package nacwm

import X "vendor:x11/xlib"
import "../vendor/x11/xinerama"

Tags :: bit_set[1..=9]

MONITOR_NONE :: Monitor_Index(-1)

Monitor_Index :: int
Monitor :: struct {
    pos  : [2]i32,
    size : [2]i32,

    clients  : [dynamic]Client,
    selected : Client_Index,
    stack    : [dynamic]Client_Index,

    master_factor : f32,
    tags : Tags,

    bar : Bar,
}
g_monitors : [dynamic]Monitor

// Currently selected monitor; index into g_monitors
g_monitor_idx : Monitor_Index

setup_monitors :: proc() -> (changed : bool) {
    if xinerama.IsActive(g_display) do changed = setup_monitors_xinerama()
    else                            do changed = setup_monitors_default()

    if changed do g_monitor_idx = monitor_idx_from_window(g_screen.root, default=0)
    return
}

setup_monitors_xinerama :: proc() -> (changed : bool) {
    num_geoms : i32
    geoms := xinerama.QueryScreens(g_display, &num_geoms)
    defer X.Free(geoms)

    num_unique : int
    unique := make([]xinerama.ScreenInfo, num_geoms, allocator=context.temp_allocator)
    defer free_all(context.temp_allocator)

    for geom in geoms[:num_geoms] {
        if is_geom_unique(unique[:num_unique], geom) {
            unique[num_unique] = geom
            num_unique += 1
        }
    }

    num_mons := len(g_monitors)

    // New monitors
    reserve(&g_monitors, num_unique)
    for i := num_mons; i < num_unique; i+= 1 {
        monitor_new()
    }

    // Update existing
    for &monitor, i in g_monitors[:num_unique] {
        if monitor_update(&monitor, unique[i]) do changed = true
    }

    // Remove extra
    for _ in 0..<(num_mons - num_unique) {
        if monitor_pop() do changed = true
    }
    return
}

setup_monitors_default :: proc() -> bool {
    if len(g_monitors) == 0 do monitor_new()

    monitor := &g_monitors[0]
    if monitor.size != g_screen.size {
        monitor.size = g_screen.size
        return true
    }
    return false
}

monitor_update :: #force_inline proc(monitor : ^Monitor, geom : xinerama.ScreenInfo) -> bool {
    geom_pos  := [2]i32{ cast(i32)geom.x_org, cast(i32)geom.y_org  }
    geom_size := [2]i32{ cast(i32)geom.width, cast(i32)geom.height }
    if monitor.pos  != geom_pos  \
    || monitor.size != geom_size {
        monitor.pos  = geom_pos
        monitor.size = geom_size
        return true
    }
    return false
}

monitor_new :: proc() {
    monitor := Monitor{
        selected = CLIENT_NONE,
        tags     = {1},

        master_factor = MASTER_FACTOR,
    }
    append(&g_monitors, monitor)
}

// Free stuff allocated by monitor
monitor_delete :: proc(monitor : Monitor) {
    if monitor.bar.window != X.None {
        bar_delete(monitor.bar)
    }
    delete(monitor.clients)
}

// Remove last monitor and reattach its windows
monitor_pop :: proc() -> (changed : bool) {
    monitor := pop(&g_monitors)
    assert(len(g_monitors) > 0)

    if len(monitor.clients) > 0 do changed = true

    for client in monitor.clients {
        client_idx := client_attach(0, client)
        client_stack_attach(0, client_idx)
    }

    if g_monitor_idx >= len(g_monitors) {
        g_monitor_idx = 0
    }

    monitor_delete(monitor)
    return
}

monitor_show_hide :: proc(monitor : Monitor) {
    // Show clients top -> down
    #reverse for client_idx in monitor.stack {
        if !client_is_visible(client_idx, monitor) do continue
        client := &monitor.clients[client_idx]

        X.MoveWindow(g_display, client.window, client.pos.x, client.pos.y)

        if client.floating && !client.fullscreen {
            client_resize(client, client.pos, client.size)
        }
    }

    // Hide clients down -> top
    for client_idx in monitor.stack {
        if client_is_visible(client_idx, monitor) do continue
        client := monitor.clients[client_idx]

        client_size := client_size_real(client)
        X.MoveWindow(g_display, client.window, client_size.x * -2, client.pos.y)
    }
}

monitor_arrange :: proc(monitor_idx := g_monitor_idx) {
    monitor := g_monitors[monitor_idx]

    monitor_show_hide(monitor)
    monitor_tile(monitor)

    _ev : X.XEvent
    // Ignore enter events so focus isn't stolen by a window moving under cursor
    for X.CheckMaskEvent(g_display, {.EnterWindow}, &_ev) {}
}

monitor_arrange_all :: proc() {
    for _, monitor_idx in g_monitors {
        monitor_arrange(monitor_idx)
    }
}

// -- Utils
monitor_idx_from_rect :: proc(pos : [2]i32, size : [2]i32, default := g_monitor_idx) -> Monitor_Index {
    area : i32
    res  := default
    for monitor, i in g_monitors {
        new_area := max(0, min(pos.x + size.x, monitor.pos.x + monitor.size.x) - max(pos.x, monitor.pos.x)) \
                  * max(0, min(pos.y + size.y, monitor.pos.y + monitor.size.y) - max(pos.y, monitor.pos.y))
        if new_area > area {
            area = new_area
            res  = i
        }
    }
    return res
}

monitor_first_visible_client :: #force_inline proc(monitor : Monitor) -> Client_Index {
    #reverse for client_idx in monitor.stack {
        if client_is_visible(client_idx, monitor) do return client_idx
    }
    return CLIENT_NONE
}
