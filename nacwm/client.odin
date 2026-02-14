package nacwm

import X "vendor:x11/xlib"

CLIENT_NONE :: Client_Index(-1)

Client_Index :: int
Client :: struct {
    window : X.Window,
    name   : string,

    pos    : [2]i32,
    size   : [2]i32,
    border : i32,

    hints : struct {
        min : [2]i32,
        max : [2]i32,
        valid : bool,
    },

    floating : bool,
    no_focus : bool,

    tags : Tags,

    // Stuff to restore after unmanaging
    original : struct {
        border : i32,
    },
}

client_attach :: proc(monitor_idx : Monitor_Index, client : Client) -> Client_Index {
    append(&g_monitors[monitor_idx].clients, client)
    return len(g_monitors[monitor_idx].clients) - 1
}

client_detach :: proc(monitor_idx : Monitor_Index, client_idx : Client_Index) {
    if client_idx == CLIENT_NONE do return

    monitor := &g_monitors[monitor_idx]
    unordered_remove(&monitor.clients, client_idx)
    // unordered_remove swaps last element for the one we just deleted
    // If we removed the last one we're fine
    if client_idx == len(monitor.clients) do return

    // Otherwise, fixup the indices
    if monitor.selected == len(monitor.clients) {
        monitor.selected = client_idx
    }
    #reverse for &idx in monitor.stack {
        if idx != len(monitor.clients) do continue
        idx = client_idx
        break
    }
}

client_stack_attach :: proc(monitor_idx : Monitor_Index, client_idx : Client_Index) {
    append(&g_monitors[monitor_idx].stack, client_idx)
}

// NOTE: When paired with `detach`, it must be called BEFORE
client_stack_detach :: proc(monitor : ^Monitor, client_idx : Client_Index) {
    if client_idx == CLIENT_NONE do return

    #reverse for idx, i in monitor.stack {
        if idx != client_idx do continue
        ordered_remove(&monitor.stack, i)
        break
    }

    if monitor.selected == client_idx {
        monitor.selected = monitor_first_visible_client(monitor^)
    }
}

// TODO: Rather than focus/unfocus I'd like it to be focus_switch
// A call with CLIENT_NONE will focus the next visible one
client_focus :: proc(client_idx : Client_Index, monitor_idx := g_monitor_idx) {
    monitor := &g_monitors[monitor_idx]

    client_idx := client_idx
    if client_idx == CLIENT_NONE || !client_is_visible(client_idx, monitor^) {
        client_idx = monitor_first_visible_client(monitor^)
    }

    if g_monitor_idx != monitor_idx || monitor.selected != client_idx {
        client_unfocus(false)
        g_monitor_idx = monitor_idx
    }

    if client_idx == CLIENT_NONE {
        focus_reset()
        monitor.selected = CLIENT_NONE
        return
    }
    client := monitor.clients[client_idx]

    client_stack_detach(monitor, client_idx)
    client_stack_attach(monitor_idx, client_idx)
    monitor.selected = client_idx

    grab_buttons(client.window, true)
    X.SetWindowBorder(g_display, client.window, g_scheme[.Selected].border);
    window_take_focus(client.window, !client.no_focus)

    // TODO: Bars (on all paths)
}

client_unfocus :: proc($set_focus : bool) {
    client_idx := g_monitors[g_monitor_idx].selected
    if client_idx == CLIENT_NONE do return

    client := g_monitors[g_monitor_idx].clients[client_idx]
    grab_buttons(client.window, false)
    X.SetWindowBorder(g_display, client.window, g_scheme[.Normal].border);

    when set_focus do focus_reset()
}

// Floats or tiles a client
client_float :: proc(monitor_idx : Monitor_Index, client_idx : Client_Index) {
    if client_idx == CLIENT_NONE do return
    // TODO: What to do with fullscreen windows?

    client := &g_monitors[monitor_idx].clients[client_idx]
    if client_is_fixed(client^) do return

    client.floating = !client.floating
    if client.floating {
        client_resize(client, client.pos, client.size)
        X.RaiseWindow(g_display, client.window)
    }
    monitor_arrange(monitor_idx)
}

client_kill :: proc(monitor_idx : Monitor_Index, client_idx : Client_Index, kindly := true) {
    if client_idx == CLIENT_NONE do return

    window := g_monitors[monitor_idx].clients[client_idx].window
    ok := kindly && send_message(window, .Delete)
    if ok do return

    // Kindness is no longer an option
    X.GrabServer(g_display)
    X.SetErrorHandler(xerror_idc)
    X.SetCloseDownMode(g_display, .DestroyAll)
    X.KillClient(g_display, window)
    X.Sync(g_display, false)

    X.SetErrorHandler(xerror)
    X.UngrabServer(g_display)
}

client_switch_monitor :: proc(client_idx : Client_Index, old_monitor_idx, new_monitor_idx : Monitor_Index, $move : bool) {
    if client_idx      == CLIENT_NONE \
    || old_monitor_idx == new_monitor_idx { return }

    old_monitor := &g_monitors[old_monitor_idx]
    client      := old_monitor.clients[client_idx]

    client_unfocus(true)
    client_stack_detach(old_monitor, client_idx)
    client_detach(old_monitor_idx, client_idx)

    new_monitor := g_monitors[new_monitor_idx]
    client.tags  = new_monitor.tags
    when move {
        if client.floating {
            offset := new_monitor.pos - old_monitor.pos
            client.pos += offset
        }
    }

    new_client_idx := client_attach(new_monitor_idx, client)
    client_stack_attach(new_monitor_idx, new_client_idx)

    // TODO: Consider whether focus should follow client moved
    client_focus(CLIENT_NONE)
    monitor_arrange_all()
}

client_resize :: proc(client : ^Client, pos : [2]i32, size : [2]i32) {
    pos, size := pos, size
    if !apply_size_hints(client, &pos, &size) do return

    client.pos  = pos
    client.size = size

    wc := X.XWindowChanges{
        x      = pos.x,
        y      = pos.y,
        width  = size.x,
        height = size.y,
    }
    X.ConfigureWindow(g_display, client.window, {.CWX, .CWY, .CWWidth, .CWHeight}, &wc)
    send_configure_notify(client.window, pos, size, client.border)

    X.Sync(g_display, false)
}

window_manage :: proc(window : X.Window, attrs : X.XWindowAttributes, transient_for : X.Window = X.None) {
    client := Client{}

    client.window = window

    client.pos.x  = attrs.x
    client.pos.y  = attrs.y
    client.size.x = attrs.width
    client.size.y = attrs.height

    client.border = STYLE.border.width
    client.original.border = attrs.border_width

    client_update_name(&client)

    monitor_idx := MONITOR_NONE
    if transient_for != X.None {
        new_monitor_idx, client_idx := client_from_window(transient_for)
        if client_idx != CLIENT_NONE {
            // Inherit tags and monitor
            client.tags = g_monitors[new_monitor_idx].clients[client_idx].tags
            monitor_idx = new_monitor_idx
        }
    }
    if monitor_idx == MONITOR_NONE {
        monitor_idx = client_apply_rules(&client)
    }
    monitor := g_monitors[monitor_idx]

    client_ensure_onscreen(&client, monitor)

    changes : X.XWindowChanges
    changes.border_width = client.border
    X.ConfigureWindow(g_display, client.window, {.CWBorderWidth}, &changes)
    X.SetWindowBorder(g_display, client.window, g_scheme[.Normal].border);
    send_configure_notify(client.window, client.pos, client.size, client.border)

    client_update_sizehints(&client)
    client_update_wmhints(&client)

    X.SelectInput(g_display, window, {.EnterWindow, .FocusChange, .PropertyChange, .StructureNotify})
    grab_buttons(window, false)

    if !client.floating {
        client.floating = transient_for != X.None || client_is_fixed(client)
    }
    client_update_type(&client)
    if client.floating {
        X.RaiseWindow(g_display, client.window)
    }

    client_idx := client_attach(monitor_idx, client)
    client_stack_attach(monitor_idx, client_idx)

    X.ChangeProperty(g_display, g_screen.root, g_atoms.net[.Client_List], XA_WINDOW, 32, X.PropModeAppend, &client.window, 1)
    window_state_set(client.window, .NormalState)

    monitor_arrange(monitor_idx)
    X.MapWindow(g_display, client.window)
    client_focus(CLIENT_NONE)
}

client_unmanage :: proc(monitor_idx : Monitor_Index, client_idx : Client_Index, $destroyed : bool) {
    if client_idx == CLIENT_NONE do return

    monitor := &g_monitors[monitor_idx]
    client  := monitor.clients[client_idx]

    delete(client.name)
    client_stack_detach(monitor, client_idx)
    client_detach(monitor_idx, client_idx)

    when !destroyed {
        X.GrabServer(g_display)
        X.SetErrorHandler(xerror_idc)
        X.SelectInput(g_display, client.window, {})

        wc := X.XWindowChanges{ border_width = client.original.border }
        X.ConfigureWindow(g_display, client.window, {.CWBorderWidth}, &wc)

        X.UngrabButton(g_display, X.AnyButton, {.AnyModifier}, client.window)
        window_state_set(client.window, .WithdrawnState)
        X.Sync(g_display, false)

        X.SetErrorHandler(xerror)
        X.UngrabServer(g_display)
    }

    client_focus(CLIENT_NONE)
    update_client_list()
    monitor_arrange(monitor_idx)
}

// -- Utils
client_ensure_onscreen :: proc(client : ^Client, monitor : Monitor) {
    client_size := client_size_real(client^)

    // br -> Bottom_Right
    client_br  :=  client.pos +  client_size
    monitor_br := monitor.pos + monitor.size
    if client_br.x > monitor_br.x {
        client.pos.x = monitor_br.x - client_size.x
    }
    if client_br.y > monitor_br.y {
        client.pos.y = monitor_br.y - client_size.y
    }
    client.pos.x = max(client.pos.x, monitor.pos.x)
    client.pos.y = max(client.pos.y, monitor.pos.y)
}

client_is_visible :: #force_inline proc(client_idx : Client_Index, monitor : Monitor) -> bool {
    assert(client_idx >= 0)
    client := monitor.clients[client_idx]
    return card(client.tags & monitor.tags) > 0
}
