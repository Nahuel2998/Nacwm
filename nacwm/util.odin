package nacwm

import X "vendor:x11/xlib"
import "../vendor/x11/xinerama"

is_geom_unique :: proc(seen : []xinerama.ScreenInfo, geom : xinerama.ScreenInfo) -> bool {
    for other in seen {
        if geom.x_org  == other.x_org  \
        && geom.y_org  == other.y_org  \
        && geom.width  == other.width  \
        && geom.height == other.height {
            return false
        }
    }
    return true
}

get_root_ptr :: proc() -> (pos: [2]i32, ok : b32) {
    _i : i32
    _m : X.KeyMask
    _w : X.Window
    ok = X.QueryPointer(g_display, g_screen.root, &_w, &_w, &pos.x, &pos.y, &_i, &_i, &_m)
    return
}

// Returns focus to the root window, marking no window as active
focus_reset :: proc() {
    X.SetInputFocus( g_display, g_screen.root, .RevertToPointerRoot, X.CurrentTime)
    X.DeleteProperty(g_display, g_screen.root, g_atoms.net[.Active_Window])
}

// Edit pos and size following hints
// Returns whether something changed
apply_size_hints :: proc(client : ^Client, pos : ^[2]i32, size : ^[2]i32) -> bool {
    size.x = max(1, size.x)
    size.y = max(1, size.y)

    client_size := client_size_real(client^)

    // TODO: Differ between automatic and interact
    if pos.x > g_screen.size.x do pos.x = g_screen.size.x - client_size.x
    if pos.y > g_screen.size.y do pos.y = g_screen.size.y - client_size.y
    if pos.x + size.x < 0      do pos.x = 0
    if pos.y + size.y < 0      do pos.y = 0

    if client.floating {
        if !client.hints.valid do client_update_sizehints(client)

        // TODO: Base/increment calculations

        if client.hints.min.x != 0 do size.x = max(size.x, client.hints.min.x)
        if client.hints.min.y != 0 do size.y = max(size.y, client.hints.min.y)
        if client.hints.max.x != 0 do size.x = min(size.x, client.hints.max.x)
        if client.hints.max.y != 0 do size.y = min(size.y, client.hints.max.y)
    }

    return pos^ != client.pos || size^ != client.size
}

client_size_real :: #force_inline proc(client : Client) -> [2]i32 {
    return client.size + 2 * client.border
}

client_is_fixed :: #force_inline proc(client : Client) -> bool {
    return client.hints.min != {0, 0} \
        && client.hints.min == client.hints.max
}
