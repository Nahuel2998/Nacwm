package nacwm

import X "../vendor/x11/xlib"

CLIENT_NONE :: Client_Index(-1)

Client_Index :: int
Client :: struct {
    monitor : Monitor_Index,

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
}
g_clients : [dynamic]Client

// Extra data for Clients that isn't commonly accessed
Client_Extra :: struct {
    // Stuff to restore after fullscreen
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
g_clients_extra : map[X.Window]Client_Extra

// Currently selected client, index into g_monitors[g_monitor_idx].clients
g_client_idx := CLIENT_NONE

client_attach :: proc(client : Client) -> Client_Index {
    append(&g_clients, client)
    return len(g_clients) - 1
}

client_detach :: proc(client_idx : Client_Index) {
    if client_idx == CLIENT_NONE do return

    delete_key(&g_clients_extra, g_clients[client_idx].window)
    unordered_remove(&g_clients, client_idx)
    // unordered_remove swaps last element for the one we just deleted
    // If we removed the last one we're fine
    if client_idx == len(g_clients) do return

    // Otherwise, fixup the indices
    client := g_clients[client_idx]
    #reverse for &idx in g_monitors[client.monitor].stack {
        if idx != len(g_clients) do continue
        idx = client_idx
        break
    }

    if g_client_idx == len(g_clients) {
        g_client_idx = client_idx
    }
}

client_stack_attach :: proc(monitor_idx : Monitor_Index, client_idx : Client_Index) {
    append(&g_monitors[monitor_idx].stack, client_idx)
}

client_stack_detach :: proc(monitor_idx : Monitor_Index, client_idx : Client_Index) {
    if client_idx == CLIENT_NONE do return

    monitor := &g_monitors[monitor_idx]
    #reverse for idx, i in monitor.stack {
        if idx != client_idx do continue
        ordered_remove(&monitor.stack, i)
        break
    }
}

client_swap :: proc(from_idx, to_idx : Client_Index) {
    if from_idx == to_idx do return

    client := g_clients[from_idx]
    g_clients[from_idx] = g_clients[to_idx]
    g_clients[to_idx]   = client

    if      g_client_idx == from_idx do g_client_idx =   to_idx
    else if g_client_idx ==   to_idx do g_client_idx = from_idx
    #reverse for &client_idx in g_monitors[client.monitor].stack {
        if      client_idx == from_idx do client_idx =   to_idx
        else if client_idx ==   to_idx do client_idx = from_idx
    }

    monitor_arrange(client.monitor)
}

// Switches focus to client_idx
// A call with CLIENT_NONE will reset focus
client_focus :: proc(client_idx : Client_Index) {
    if client_idx == g_client_idx do return

    client_unfocus()
    if client_idx == CLIENT_NONE {
        focus_reset()
        return
    }
    client := g_clients[client_idx]

    client_stack_detach(client.monitor, client_idx)
    client_stack_attach(client.monitor, client_idx)
    g_monitor_idx = client.monitor
    g_client_idx  = client_idx

    grab_buttons(client.window, true)
    X.SetWindowBorder(g_display, client.window, g_scheme[.Selected].border);
    window_take_focus(client.window, !client.no_focus)

    // TODO: Bar title? (on all paths)
}

client_unfocus :: proc() {
    if g_client_idx == CLIENT_NONE do return

    client := g_clients[g_client_idx]
    grab_buttons(client.window, false)
    X.SetWindowBorder(g_display, client.window, g_scheme[.Normal].border);

    g_client_idx = CLIENT_NONE
}

// Floats or tiles a client
client_float :: proc(client_idx : Client_Index) {
    if client_idx == CLIENT_NONE do return

    client := &g_clients[client_idx]
    if client.fullscreen || client_is_fixed(client^) do return

    client.floating = !client.floating
    if client.floating {
        client_resize(client, client.pos, client.size)
    }
    client_restack(client^)
    monitor_arrange(client.monitor)
}

// Do what I mean
client_restack :: #force_inline proc(client : Client) {
    if client.floating do client_raise(client)
    else               do client_bury( client )
}
// Raise a floating window above others
client_raise :: #force_inline proc(client : Client) {
    if !client.floating do return

    if g_notification_window != X.None {
        config := X.XWindowChanges{
            stack_mode = .Below,
            sibling    = g_notification_window,
        }
        X.ConfigureWindow(g_display, client.window, {.CWSibling, .CWStackMode}, &config)
    } else {
        X.RaiseWindow(g_display, client.window)
    }
}
// Bury a tiled window below the bar
client_bury :: #force_inline proc(client : Client) {
    if client.floating do return
    config := X.XWindowChanges{
        stack_mode = .Below,
        sibling    = g_monitors[client.monitor].bar.window,
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

    client_extra := g_clients_extra[client.window]
    client_extra.old_state = {
        floating = client.floating,
        pos      = client.pos,
        size     = client.size,
        border   = client.border,
    }
    g_clients_extra[client.window] = client_extra

    client.border     = 0
    client.floating   = true
    client.fullscreen = true
    X.ChangeProperty(g_display, client.window, g_atoms.net[.WM_State], X.XA_ATOM, 32, X.PropModeReplace, &g_atoms.net[.WM_Fullscreen], 1)

    monitor := g_monitors[monitor_idx]
    _client_resize(client, monitor.pos, monitor.size)
    client_raise(client^)
}
client_fullscreen_exit :: proc(client : ^Client, monitor_idx : Monitor_Index) {
    if !client.fullscreen do return

    _, client_extra := delete_key(&g_clients_extra, client.window)
    client.border     = client_extra.old_state.border
    client.floating   = client_extra.old_state.floating
    client.fullscreen = false
    X.ChangeProperty(g_display, client.window, g_atoms.net[.WM_State], X.XA_ATOM, 32, X.PropModeReplace, nil, 0)

    if !client.floating do client_bury(client^)
    _client_resize(client, client_extra.old_state.pos, client_extra.old_state.size)
    monitor_arrange(monitor_idx)
}

client_kill :: proc(client_idx : Client_Index, kindly := true) {
    if client_idx == CLIENT_NONE do return

    window := g_clients[client_idx].window
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

// FIXME: Client doesn't always go to the master area
client_switch_monitor :: proc(client_idx : Client_Index, new_monitor_idx : Monitor_Index, $move : bool, $follow : bool) {
    if client_idx == CLIENT_NONE do return

    client := &g_clients[client_idx]
    if client.monitor == new_monitor_idx do return

    client_stack_detach(client.monitor,  client_idx)
    client_stack_attach(new_monitor_idx, client_idx)

    new_monitor := g_monitors[new_monitor_idx]
    client.tags  = new_monitor.tags
    when move {
        if client.floating {
            old_monitor := g_monitors[client.monitor]
            offset := new_monitor.pos - old_monitor.pos
            client.pos += offset
        }
    }
    client.monitor = new_monitor_idx

    if client_idx == g_client_idx {
        when follow do g_monitor_idx = client.monitor
        else        do monitor_refocus()
    }
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

window_manage :: proc(window : X.Window, attrs : X.XWindowAttributes, transient_for : X.Window = X.None, restore := Restart_Window_Data{}) {
    client := Client{}

    client.monitor = MONITOR_NONE
    client.window  = window

    client.pos.x  = attrs.x
    client.pos.y  = attrs.y
    client.size.x = attrs.width
    client.size.y = attrs.height

    client.border = STYLE.border.width
    g_clients_extra[client.window] = { original = { border = attrs.border_width } }

    client_update_name(&client)

    if restore.window == client.window {
        client.tags     = transmute(Tags)restore.data.tags
        client.monitor  = restore.data.monitor
        client.floating = restore.data.floating
    }
    else if transient_for != X.None {
        client_idx := client_from_window(transient_for)
        if client_idx != CLIENT_NONE {
            parent := g_clients[client_idx]
            // Inherit tags and monitor
            client.tags    = parent.tags
            client.monitor = parent.monitor
        }
    }
    if client.monitor == MONITOR_NONE {
        client_apply_rules(&client)
    }

    client_ensure_onscreen(&client)

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
    client_restack(client)

    client_idx := client_attach(client)
    client_stack_attach(client.monitor, client_idx)

    X.ChangeProperty(g_display, g_screen.root, g_atoms.net[.Client_List], X.XA_WINDOW, 32, X.PropModeAppend, &client.window, 1)
    window_state_set(client.window, .NormalState)

    monitor_arrange(client.monitor)
    X.MapWindow(g_display, client.window)
    if client.monitor == g_monitor_idx {
        monitor_refocus()
    }
}

client_unmanage :: proc(client_idx : Client_Index, $destroyed : bool) {
    if client_idx == CLIENT_NONE do return

    client := g_clients[client_idx]
    client_extra := g_clients_extra[client.window]
    _ = client_extra // Used when !destroyed

    delete(client.name)
    client_stack_detach(client.monitor, client_idx)
    client_detach(client_idx)

    when !destroyed {
        X.GrabServer(g_display)
        X.SetErrorHandler(xerror_idc)
        X.SelectInput(g_display, client.window, {})

        wc := X.XWindowChanges{ border_width = client_extra.original.border }
        X.ConfigureWindow(g_display, client.window, {.CWBorderWidth}, &wc)

        X.UngrabButton(g_display, X.AnyButton, {.AnyModifier}, client.window)
        window_state_set(client.window, .WithdrawnState)
        X.Sync(g_display, false)

        X.SetErrorHandler(xerror)
        X.UngrabServer(g_display)
    }

    if client_idx == g_client_idx {
        g_client_idx = CLIENT_NONE
        monitor_refocus()
    }
    update_client_list()
    monitor_arrange(client.monitor)
}

// -- Utils
client_ensure_onscreen :: proc(client : ^Client) {
    client_size := client_size_real(client^)
    monitor := g_monitors[client.monitor]

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

client_is_visible :: #force_inline proc(client_idx : Client_Index) -> bool {
    assert(client_idx != CLIENT_NONE)
    client := g_clients[client_idx]
    return card(client.tags & g_monitors[client.monitor].tags) > 0
}

client_is_visible_in_monitor :: #force_inline proc(client_idx : Client_Index, monitor : Monitor) -> bool {
    assert(client_idx != CLIENT_NONE)
    client := g_clients[client_idx]
    if client.monitor != monitor.index do return false
    return card(client.tags & monitor.tags) > 0
}

client_size_real :: #force_inline proc(client : Client) -> [2]i32 {
    return client.size + 2 * client.border
}

client_is_fixed :: #force_inline proc(client : Client) -> bool {
    return client.hints.min != {0, 0} \
        && client.hints.min == client.hints.max
}
