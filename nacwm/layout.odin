package nacwm

import X "vendor:x11/xlib"

// TODO: Gaps
monitor_tile :: proc(monitor : Monitor) {
    num_tiled : i32
    for client, client_idx in monitor.clients {
        if client.floating || !client_is_visible(client_idx, monitor) do continue
        num_tiled += 1
    }
    if num_tiled == 0 do return

    if num_tiled == 1 {
        monitor_tile_single(monitor)
        return
    }

    i : i32
    master_width := i32(f32(monitor.size.x) * monitor.master_factor)
    stack_size   := [2]i32{ monitor.size.x  - master_width, monitor.size.y / (num_tiled - 1) }
    stack_pos    := [2]i32{ monitor.pos.x   + master_width, monitor.pos.y }
    #reverse for &client, client_idx in monitor.clients {
        if client.floating || !client_is_visible(client_idx, monitor) do continue

        if i == 0 {
            size := [2]i32{master_width, monitor.size.y} - (2 * client.border)
            client_resize(
                &client,
                monitor.pos + GAPS_WIDTH,
                size        - {
                    1.5 * GAPS_WIDTH,
                    2   * GAPS_WIDTH,
                },
            )
        }
        else {
            size := stack_size - (2 * client.border)
            if i == (num_tiled - 1) do size -= 0.5 * GAPS_WIDTH
            client_resize(
                &client,
                stack_pos + { 0.5 * GAPS_WIDTH, GAPS_WIDTH },
                size      -   1.5 * GAPS_WIDTH,
            )
            stack_pos.y += stack_size.y
        }
        i += 1
    }
}

monitor_tile_single :: proc(monitor : Monitor) {
    for &client, client_idx in monitor.clients {
        if client.floating || !client_is_visible(client_idx, monitor) do continue

        size := monitor.size - 2 * client.border
        client_resize(&client, monitor.pos + GAPS_WIDTH, size - 2 * GAPS_WIDTH)
        break
    }
}
