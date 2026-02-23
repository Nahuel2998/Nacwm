package nacwm

import "core:log"
import "core:strings"
import X "../vendor/x11/xlib"

g_handlers := #partial [X.EventType]proc(X.XEvent) {
    .ButtonPress      = recv_button_press,
    .ClientMessage    = recv_client_message,
    .ConfigureRequest = recv_configure_request,
    .ConfigureNotify  = recv_configure_notify,
    .DestroyNotify    = recv_destroy_notify,
    .EnterNotify      = recv_enter_notify,
    .FocusIn          = recv_focus_in,
    .Expose           = recv_expose,
    .KeyPress         = recv_key_press,
    .MotionNotify     = recv_motion_notify,
    .PropertyNotify   = recv_property_notify,
    .MappingNotify    = recv_mapping_notify,
    .MapRequest       = recv_map_request,
    .MapNotify        = recv_map_notify,
    .UnmapNotify      = recv_unmap_notify,
}

setup_events :: proc() {
    attrs : X.XSetWindowAttributes

    attrs.cursor = g_cursors[.Normal]
    attrs.event_mask = {.SubstructureRedirect, .SubstructureNotify, .StructureNotify, .ButtonPress, .PointerMotion, .EnterWindow, .LeaveWindow, .PropertyChange}
    X.ChangeWindowAttributes(g_display, g_screen.root, {.CWEventMask, .CWCursor}, &attrs)

    X.SelectInput(g_display, g_screen.root, attrs.event_mask)
}

send_configure_notify :: proc(window : X.Window, pos : [2]i32, size : [2]i32, border : i32) {
    event := X.XConfigureEvent{
        type    = .ConfigureNotify,
        display = g_display,

        event  = window,
        window = window,

        x = pos.x,
        y = pos.y,
        width  = size.x,
        height = size.y,
        border_width = border,

        override_redirect = false,
    }
    X.SendEvent(g_display, window, false, {.StructureNotify}, cast(^X.XEvent)&event)
}

// Sends a message event if the window supports it
send_message :: proc(window : X.Window, protocol : X_WM_Atom) -> (supported : bool) {
    atom := g_atoms.wm[protocol]

    protocols : [^]X.Atom
    num_protocols : i32

    ok := bool(X.GetWMProtocols(g_display, window, &protocols, &num_protocols))
    if ok {
        for p in protocols[:num_protocols] {
            if p == atom {
                supported = true
                break
            }
        }
        X.Free(protocols)
    }
    if !supported do return

    event := X.XClientMessageEvent{
        type = .ClientMessage,
        message_type = g_atoms.wm[.Protocols],

        window = window,

        format = 32,
        data   = { l = { 0=cast(int)atom, 1=X.CurrentTime } },
    }
    X.SendEvent(g_display, window, false, {}, cast(^X.XEvent)&event)
    return
}

// -- Handlers
recv_key_press :: proc(event : X.XEvent) {
    event := event.xkey
    keysym := X.KeycodeToKeysym(g_display, cast(u8)event.keycode, 0)
    for binding in BINDINGS {
        if keysym      != binding.key \
        || event.state != binding.modifiers { continue }
        do_action(binding.action)
        break
    }
}

recv_configure_request :: proc(event : X.XEvent) {
    event := event.xconfigurerequest

    defer X.Sync(g_display, false)

    mask := transmute(X.WindowChangesMask)cast(i32)event.value_mask

    client_idx := client_from_window(event.window)
    if client_idx == CLIENT_NONE {
        wc := X.XWindowChanges{
            x = event.x,
            y = event.y,
            width  = event.width,
            height = event.height,
            border_width = event.border_width,
            sibling    = event.above,
            stack_mode = event.detail,
        }
        X.ConfigureWindow(g_display, event.window, mask, &wc)
        return
    }

    client := &g_clients[client_idx]
    if !client.floating {
        send_configure_notify(client.window, client.pos, client.size, client.border)
        return
    }

    when ODIN_DEBUG {
        ConfigureDebug :: struct {
            pos    : [2]i32,
            size   : [2]i32,
            border : i32,
        }
        before := ConfigureDebug{ client.pos, client.size, client.border }
    }

    if .CWX           in mask do client.pos.x  = event.x // + monitor.pos.x // NOTE: dwm adds the monitor.pos here, but really I haven't seen
    if .CWY           in mask do client.pos.y  = event.y // + monitor.pos.y //       a single window sending these as relative to monitor
    if .CWWidth       in mask do client.size.x = event.width
    if .CWHeight      in mask do client.size.y = event.height
    if .CWBorderWidth in mask do client.border = event.border_width
    client_ensure_onscreen(client)

    when ODIN_DEBUG {
        requested := ConfigureDebug{ {event.x, event.y}, {event.width, event.height}, event.border_width }
        after     := ConfigureDebug{ client.pos, client.size, client.border }
        log.debug("Configuring:", client.name, "\n  Before:   ", before, "\n  Requested:", requested, "\n  After:    ", after)
    }
    send_configure_notify(client.window, client.pos, client.size, client.border)

    if client_is_visible(client_idx) {
        X.MoveResizeWindow(g_display, client.window, client.pos.x, client.pos.y, cast(u32)client.size.x, cast(u32)client.size.y)
    }
}

recv_configure_notify :: proc(event : X.XEvent) {
    event := event.xconfigure
    if event.window != g_screen.root do return

    changed := g_screen.size.x != event.width \
            || g_screen.size.y != event.height
    g_screen.size = { event.width, event.height }
    if !(setup_monitors() || changed) do return

    setup_bars()
    // Fixup fullscreen windows
    for &client in g_clients do if client.fullscreen {
        monitor := g_monitors[client.monitor]
        _client_resize(&client, monitor.pos, monitor.size)
    }
    // Fixup bars
    for &monitor in g_monitors {
        X.MoveResizeWindow(g_display, monitor.bar.window, monitor.pos.x, monitor.pos.y, cast(u32)monitor.size.x, cast(u32)STYLE.bar.height)
    }

    monitor_refocus()
    monitor_arrange_all()
}

recv_destroy_notify :: proc(event : X.XEvent) {
    event := event.xdestroywindow

    client_idx := client_from_window(event.window)
    client_unmanage(client_idx, true)
}

recv_enter_notify :: proc(event : X.XEvent) {
    event := event.xcrossing

    // Only accept .NotifyNormal, ignore .NotifyInferior
    // Accept all from root
    if (event.mode != .NotifyNormal || event.detail == .NotifyInferior) && event.window != g_screen.root do return

    client_idx := client_from_window(event.window)
    if client_idx != CLIENT_NONE {
        client_focus(client_idx)
    } else {
        monitor_idx := monitor_idx_from_window(event.window)
        monitor_focus(monitor_idx)
    }

    // log.debug("Entered monitor/client:", monitor_idx, "/", client_idx)
}

recv_expose :: proc(event : X.XEvent) {
    event := event.xexpose
    if event.count != 0 do return

    monitor_idx := monitor_idx_from_window(event.window, default=MONITOR_NONE)
    if monitor_idx == MONITOR_NONE do return

    log.debug("Drawing bar for monitor", monitor_idx)
    bar_draw(g_monitors[monitor_idx])
}

recv_focus_in :: proc(event : X.XEvent) {
    event := event.xfocus

    if g_selected.client == CLIENT_NONE do return

    // Force focus on the focused window
    client := g_clients[g_selected.client]
    if client.window != event.window {
        window_take_focus(client.window, !client.no_focus)
    }
}

recv_mapping_notify :: proc(event : X.XEvent) {
    event := event.xmapping

    X.RefreshKeyboardMapping(&event)
    if event.request == .MappingKeyboard {
        setup_keys()
    }
}

recv_map_notify :: proc(event : X.XEvent) {
    event := event.xmap

    if g_notification_window != X.None do return

    hints : X.XClassHint
    X.GetClassHint(g_display, event.window, &hints)
    if hints.res_class == NOTIFICATION_CLASS {
        g_notification_window = event.window
    }
    if hints.res_class != nil do X.Free(cast(rawptr)hints.res_class)
    if hints.res_name  != nil do X.Free(cast(rawptr)hints.res_name)
}

recv_map_request :: proc(event : X.XEvent) {
    event := event.xmaprequest

    attrs : X.XWindowAttributes
    ok := bool(X.GetWindowAttributes(g_display, event.window, &attrs))
    if !ok || attrs.override_redirect do return

    client_idx := client_from_window(event.window)
    if client_idx != CLIENT_NONE do return

    trans_for : X.Window
    X.GetTransientForHint(g_display, event.window, &trans_for)
    window_manage(event.window, attrs, trans_for)
}

recv_motion_notify :: proc(event : X.XEvent) {
    event := event.xmotion
    if event.window != g_screen.root do return

    monitor_idx := monitor_idx_from_rect({event.x_root, event.y_root}, {1, 1})
    monitor_focus(monitor_idx)
}

recv_property_notify :: proc(event : X.XEvent) {
    event := event.xproperty

    if event.window == g_screen.root {
        switch event.atom {
        case X.XA_WM_NAME:
            bar_status_update()

        case g_atoms.nacwm[.Command]:
            strings.builder_reset(&g_ipc_command)
            ok := get_text_property_sb(g_screen.root, g_atoms.nacwm[.Command], &g_ipc_command)
            if !ok do return
            ipc_action(strings.to_string(g_ipc_command))
        }
    }
    if event.state == .PropertyDelete do return

    client_idx := client_from_window(event.window)
    if client_idx == CLIENT_NONE do return

    client := &g_clients[client_idx]
    switch event.atom {
    case X.XA_WM_TRANSIENT_FOR:
        if !client.floating do return

        trans_for : X.Window
        ok := bool(X.GetTransientForHint(g_display, event.window, &trans_for))
        if !ok do return

        managed_idx := client_from_window(trans_for)
        if managed_idx == CLIENT_NONE do return

        client.floating = true
        monitor_arrange(client.monitor)

    case X.XA_WM_NORMAL_HINTS:
        client.hints.valid = false

    case X.XA_WM_HINTS:
        client_update_wmhints(client)

    case X.XA_WM_NAME, g_atoms.net[.WM_Name]:
        client_update_name(client)

    case g_atoms.net[.WM_Window_Type]:
        client_update_type(client)
    }
}

recv_unmap_notify :: proc(event : X.XEvent) {
    event := event.xunmap

    if !NOTIFICATION_PRESERVE && event.window == g_notification_window {
        g_notification_window = X.None
    }

    client_idx := client_from_window(event.window)
    if client_idx == CLIENT_NONE do return

    if event.send_event {
        window_state_set(event.window, .WithdrawnState)
    } else {
        client_unmanage(client_idx, false)
    }
}

recv_button_press :: proc(event : X.XEvent) {
    event := event.xbutton

    click : Click_Kind
    client_idx := client_from_window(event.window)
    if client_idx != CLIENT_NONE {
        client_focus(client_idx)
    } else {
        monitor_idx := monitor_idx_from_window(event.window)
        monitor_focus(monitor_idx)
    }

    if client_idx != CLIENT_NONE {
        log.debug("allow_events")
        X.AllowEvents(g_display, .ReplayPointer, X.CurrentTime)
        click = .Client
    } else {
        log.debug("other")
        for monitor in g_monitors {
            if event.window != monitor.bar.window do continue
            if event.x <= TAG_COUNT * STYLE.bar.height {
                click = .Tag
            }
            break
        }
    }

    for binding in BUTTON_BINDINGS {
        if click        != binding.click  \
        || event.button != binding.button \
        || event.state  != binding.modifiers { continue }
        do_action(binding.action)
        break
    }
}

recv_client_message :: proc(event : X.XEvent) {
    event := event.xclient

    client_idx := client_from_window(event.window)
    if client_idx == CLIENT_NONE do return

    if event.message_type == g_atoms.net[.WM_State] {
        is_fullscreen_event := X.Atom(event.data.l[1]) == g_atoms.net[.WM_Fullscreen] \
                            || X.Atom(event.data.l[2]) == g_atoms.net[.WM_Fullscreen]
        if !is_fullscreen_event do return

        FULLSCREEN_ADD    :: 1
        FULLSCREEN_TOGGLE :: 2
        client := &g_clients[client_idx]

        on : bool
        switch event.data.l[0] {
        case FULLSCREEN_ADD:
            on = true
        case FULLSCREEN_TOGGLE:
            on = !client.fullscreen
        }
        client_fullscreen(client, client.monitor, on)
    }

    // TODO: handle urgency
}
