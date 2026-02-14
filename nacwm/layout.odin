package nacwm

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

    monitor_pos  := [2]i32{ monitor.pos.x,  monitor.pos.y  + STYLE.bar.height }
    monitor_size := [2]i32{ monitor.size.x, monitor.size.y - STYLE.bar.height }

    i : i32
    master_width := i32(f32(monitor_size.x) * monitor.master_factor)
    stack_size   := [2]i32{ monitor_size.x  - master_width, monitor_size.y / (num_tiled - 1) }
    stack_pos    := [2]i32{ monitor_pos.x   + master_width, monitor_pos.y }
    #reverse for &client, client_idx in monitor.clients {
        if client.floating || !client_is_visible(client_idx, monitor) do continue

        if i == 0 {
            size := [2]i32{master_width, monitor_size.y} - (2 * client.border)
            client_resize(
                &client,
                monitor_pos + GAPS_WIDTH,
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
    monitor_pos  := [2]i32{ monitor.pos.x,  monitor.pos.y  + STYLE.bar.height }
    monitor_size := [2]i32{ monitor.size.x, monitor.size.y - STYLE.bar.height }
    for &client, client_idx in monitor.clients {
        if client.floating || !client_is_visible(client_idx, monitor) do continue

        size := monitor_size - 2 * client.border
        client_resize(&client, monitor_pos + GAPS_WIDTH, size - 2 * GAPS_WIDTH)
        break
    }
}
