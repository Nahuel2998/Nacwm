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
    no_focus : bool,

    floating   : bool,
    fullscreen : bool,

    tags : Tags,

    // Stuff to restore after fullscreen
    // TODO: Maybe this could be in another array since it's very uncommon
    old_state : struct {
        floating : bool,
        pos      : [2]i32,
        size     : [2]i32,
        border   : i32,
    },

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

client_swap :: proc(from_idx, to_idx : Client_Index, monitor_idx : Monitor_Index) {
    if from_idx == to_idx do return

    monitor := &g_monitors[monitor_idx]

    client := monitor.clients[from_idx]
    monitor.clients[from_idx] = monitor.clients[to_idx]
    monitor.clients[to_idx]   = client

    if      monitor.selected == from_idx do monitor.selected = to_idx
    else if monitor.selected ==   to_idx do monitor.selected = from_idx
    #reverse for &client_idx in monitor.stack {
        if        client_idx == from_idx do client_idx = to_idx
        else if   client_idx ==   to_idx do client_idx = from_idx
    }

    monitor_arrange(monitor_idx)
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

    // TODO: Bar title (on all paths)
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

    monitor := &g_monitors[monitor_idx]
    client  := &monitor.clients[client_idx]
    if client.fullscreen || client_is_fixed(client^) do return

    client.floating = !client.floating
    if client.floating {
        client_resize(client, client.pos, client.size)
    }
    client_restack(client^, monitor^)
    monitor_arrange(monitor_idx)
}

// Do what I mean
client_restack :: #force_inline proc(client : Client, monitor : Monitor) {
    if client.floating do client_raise(client)
    else               do client_bury(client, monitor)
}
// Raise a floating window above others
client_raise :: #force_inline proc(client : Client) {
    if !client.floating do return
    X.RaiseWindow(g_display, client.window)
}
// Bury a tiled window below the bar
client_bury :: #force_inline proc(client : Client, monitor : Monitor) {
    if client.floating do return
    config := X.XWindowChanges{
        stack_mode = .Below,
        sibling    = monitor.bar.window,
    }
    X.ConfigureWindow(g_display, client.window, {.CWSibling, .CWStackMode}, &config)
}

// Enter or exit fullscreen
client_fullscreen :: proc(client : ^Client, monitor_idx : Monitor_Index, on : bool) {
    if on do client_fullscreen_enter(client, monitor_idx)
    else  do client_fullscreen_exit( client, monitor_idx )
}
client_fullscreen_enter :: proc(client : ^Client, monitor_idx : Monitor_Index) {
    if client.fullscreen do return

    X.ChangeProperty(g_display, client.window, g_atoms.net[.WM_State], X.XA_ATOM, 32, X.PropModeReplace, &g_atoms.net[.WM_Fullscreen], 1)
    client.old_state = {
        floating = client.floating,
        pos      = client.pos,
        size     = client.size,
        border   = client.border,
    }
    client.border     = 0
    client.floating   = true
    client.fullscreen = true

    monitor := g_monitors[monitor_idx]
    _client_resize(client, monitor.pos, monitor.size)
    X.RaiseWindow(g_display, client.window)
}
client_fullscreen_exit :: proc(client : ^Client, monitor_idx : Monitor_Index) {
    if !client.fullscreen do return

    X.ChangeProperty(g_display, client.window, g_atoms.net[.WM_State], X.XA_ATOM, 32, X.PropModeReplace, nil, 0)
    client.border     = client.old_state.border
    client.floating   = client.old_state.floating
    client.fullscreen = false

    _client_resize(client, client.old_state.pos, client.old_state.size)
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

// Resizes a client, minds size hints
client_resize :: proc(client : ^Client, pos : [2]i32, size : [2]i32) {
    pos, size := pos, size
    if !apply_size_hints(client, &pos, &size) do return

    _client_resize(client, pos, size)
}
// Resizes a client, doesn't mind size hints
_client_resize :: proc(client : ^Client, pos : [2]i32, size : [2]i32) {
    client.pos  = pos
    client.size = size

    wc := X.XWindowChanges{
        x            = pos.x,
        y            = pos.y,
        width        = size.x,
        height       = size.y,
        border_width = client.border,
    }
    X.ConfigureWindow(g_display, client.window, {.CWX, .CWY, .CWWidth, .CWHeight, .CWBorderWidth}, &wc)
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
    client_update_type(&client, monitor_idx)
    client_restack(client, monitor)

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

client_size_real :: #force_inline proc(client : Client) -> [2]i32 {
    return client.size + 2 * client.border
}

client_is_fixed :: #force_inline proc(client : Client) -> bool {
    return client.hints.min != {0, 0} \
        && client.hints.min == client.hints.max
}
