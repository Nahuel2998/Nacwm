package nacwm

import X "vendor:x11/xlib"

scan_windows :: proc() {
    _w : X.Window
    windows : [^]X.Window
    num_windows : u32

    ok := bool(X.QueryTree(g_display, g_screen.root, &_w, &_w, &windows, &num_windows))
    if !ok do return

    if num_windows == 0 do return
    defer X.Free(windows)

    Transient_Window :: struct {
        trans_for : X.Window,
        window    : X.Window,
        attrs     : X.XWindowAttributes,
    }

    num_trans : int
    transients := make([]Transient_Window, num_windows, allocator=context.temp_allocator)
    defer free_all(context.temp_allocator)

    attrs : X.XWindowAttributes
    for window in windows[:num_windows] {
        ok := bool(X.GetWindowAttributes(g_display, window, &attrs))
        if !ok || attrs.override_redirect do continue

        transient := bool(X.GetTransientForHint(g_display, window, &transients[num_trans].trans_for))

        window_state, ok_state := window_state_get(window)
        if attrs.map_state == .IsViewable || (ok_state && window_state == .IconicState) {
            if transient {
                transients[num_trans].window = window
                transients[num_trans].attrs  = attrs
                num_trans += 1
            }
            else do window_manage(window, attrs)
        }
    }

    for trans in transients[:num_trans] {
        window_manage(trans.window, trans.attrs, trans.trans_for)
    }
}

window_take_focus :: proc(window : X.Window, focus : bool) {
    window := window
    if focus {
        X.SetInputFocus( g_display, window, .RevertToPointerRoot, X.CurrentTime )
        X.ChangeProperty(g_display, g_screen.root, g_atoms.net[.Active_Window], XA_WINDOW, 32, X.PropModeReplace, &window, 1)
    }
    send_message(window, .Take_Focus)
}

// -- Utils
monitor_idx_from_window :: proc(window : X.Window, default := g_monitor_idx) -> Monitor_Index {
    if window == g_screen.root {
        pos, ok := get_root_ptr()
        if ok do return monitor_idx_from_rect(pos, {1, 1}, default)
    }

    // TODO: Check for bar

    monitor_idx, client_idx := client_from_window(window)
    if client_idx != CLIENT_NONE do return monitor_idx

    return default
}

client_from_window :: proc(window : X.Window) -> (Monitor_Index, Client_Index) {
    for monitor, monitor_idx in g_monitors do for client, client_idx in monitor.clients {
        if client.window == window {
            return monitor_idx, client_idx
        }
    }
    return g_monitor_idx, CLIENT_NONE
}

window_state_get :: proc(window : X.Window) -> (X.WMHintState, bool) {
    res, ok := get_property(window, g_atoms.wm[.State], g_atoms.wm[.State], i64)
    if ok do return cast(X.WMHintState)res, true
    return {}, false
}

window_state_set :: proc(window : X.Window, state : X.WMHintState) {
    data := [2]int{ cast(int)state, X.None }
    X.ChangeProperty(g_display, window, g_atoms.wm[.State], g_atoms.wm[.State], 32, X.PropModeReplace, &data, 2)
}
