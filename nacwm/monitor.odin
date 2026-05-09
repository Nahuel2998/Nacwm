package nacwm

import X "../vendor/x11/xlib"
import "../vendor/x11/xinerama"

Tags :: bit_set[1..=TAG_COUNT]

MONITOR_NONE :: Monitor_Index(-1)

Monitor_Index :: int
Monitor :: struct {
    index : Monitor_Index,

    pos  : [2]i32,
    size : [2]i32,

    stack : [dynamic]Client_Index,

    master_factor : f32,
    tags : Tags,

    bar : Bar,
}
g_monitors : [dynamic]Monitor

setup_monitors :: proc() -> (changed : bool) {
    if xinerama.IsActive(g_display) do changed = setup_monitors_xinerama()
    else                            do changed = setup_monitors_default()

    if changed {
        g_selected.monitor = monitor_idx_from_window(g_screen.root, default=Monitor_Index(0))
    }
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
        index = len(g_monitors),
        tags  = {1},
        master_factor = MASTER_FACTOR,
    }
    append(&g_monitors, monitor)
}

// Free stuff allocated by monitor
monitor_delete :: proc(monitor : Monitor) {
    if monitor.bar.window != X.None {
        bar_delete(monitor.bar)
    }
}

// Remove last monitor and reattach its windows
monitor_pop :: proc() -> (changed : bool) {
    monitor := pop(&g_monitors)
    assert(len(g_monitors) > 0)

    for client in g_clients {
        if client.monitor != len(g_monitors) do continue
        client := client
        changed = true

        client.monitor = Monitor_Index(0)
        client_idx := client_attach(client)
        client_stack_attach(client.monitor, client_idx)
    }

    if g_selected.monitor >= len(g_monitors) {
        g_selected.monitor = Monitor_Index(0)
    }

    monitor_delete(monitor)
    return
}

monitor_show_hide :: proc(monitor : Monitor) {
    // Show clients top -> down
    #reverse for client_idx in monitor.stack {
        if !client_is_visible_in_monitor(client_idx, monitor) do continue
        client := &g_clients[client_idx]

        X.MoveWindow(g_display, client.window, client.pos.x, client.pos.y)

        if client.floating && !client.fullscreen {
            client_resize(client, client.pos, client.size)
        }
    }

    // Hide clients down -> top
    for client_idx in monitor.stack {
        if client_is_visible_in_monitor(client_idx, monitor) do continue
        client := g_clients[client_idx]

        client_size := client_size_real(client)
        X.MoveWindow(g_display, client.window, client_size.x * -2, client.pos.y)
    }
}

monitor_arrange :: proc(monitor_idx := g_selected.monitor) {
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

// Switch focus to another monitor
monitor_focus :: proc(monitor_idx : Monitor_Index) {
    if monitor_idx == g_selected.monitor do return

    g_selected.monitor = monitor_idx
    monitor_refocus()
}

// Refocus the currently focused monitor
monitor_refocus :: proc() {
    monitor    := g_monitors[g_selected.monitor]
    client_idx := monitor_first_visible_client(monitor)
    client_focus(client_idx)
}

// -- Utils
monitor_idx_from_rect :: proc(pos : [2]i32, size : [2]i32, default := g_selected.monitor) -> Monitor_Index {
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
        if client_is_visible_in_monitor(client_idx, monitor) do return client_idx
    }
    return CLIENT_NONE
}

monitor_tags_set :: proc(monitor_idx : Monitor_Index, tags : Tags, $toggle : bool) {
    if monitor_idx == MONITOR_NONE do return
    monitor_idx := monitor_idx

    if !monitor_has_tags(monitor_idx, tags) {
        new_monitor := monitor_with_tags(tags)
        if new_monitor == MONITOR_NONE do return

        if monitor_idx == g_selected.monitor {
            when !toggle { // Toggling becoming a move to another monitor would be quite counter-intuitive
                g_selected.monitor = new_monitor
            }
        }
        monitor_idx = new_monitor
    }
    monitor := &g_monitors[monitor_idx]

    new_tags : Tags
    when toggle do new_tags = tags ~ monitor.tags
    else        do new_tags = tags
    if new_tags == {} do return

    monitor.tags = new_tags

    if monitor_idx == g_selected.monitor {
        monitor_refocus()
    }
    monitor_arrange(monitor_idx)
    bar_draw(monitor^)
}

monitor_with_tags :: #force_inline proc(tags : Tags) -> Monitor_Index {
    for idx in 0..<len(g_monitors) {
        if monitor_has_tags(idx, tags) do return idx
    }
    return MONITOR_NONE
}

monitor_has_tags :: #force_inline proc(monitor_idx : Monitor_Index, tags : Tags) -> bool {
    return monitor_idx >= len(MONITOR_TAGS) \
        || tags - MONITOR_TAGS[monitor_idx] == {}
}
