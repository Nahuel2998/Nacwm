package nacwm

import X "vendor:x11/xlib"

MOUSE_MASK :: BUTTON_MASK | {.PointerMotion}

@(private="file")
GRAB_SUCCESS :: 0

Mouse_Action :: enum {
    Move,
    Resize,
}

client_mouse_action :: proc($action : Mouse_Action) {
    client_idx := g_monitors[g_monitor_idx].selected
    if client_idx == CLIENT_NONE do return

    client := &g_monitors[g_monitor_idx].clients[client_idx]
    if client.fullscreen do return

    monitor_restack()

    grab_res := X.GrabPointer(g_display, g_screen.root, false, MOUSE_MASK, .GrabModeAsync, .GrabModeAsync, X.None, g_cursors[.Move], X.CurrentTime)
    if grab_res != GRAB_SUCCESS do return

    pointer, ok := get_root_ptr()
    if !ok do return

    last_time : X.Time

    event : X.XEvent
    old_pos := client.pos
    when action == .Resize {
        old_size := client_size_real(client^)
        center   := client.pos + old_size / 2
        left_side := pointer.x < center.x
        top_side  := pointer.y < center.y
    }
    out: for {
        X.MaskEvent(g_display, MOUSE_MASK | {.Exposure, .SubstructureRedirect}, &event)

        #partial switch event.type {
        case .ButtonRelease: break out

        case .ConfigureRequest, .Expose, .MapRequest:
            g_handlers[event.type](event)

        case .MotionNotify:
            event := event.xmotion

            if event.time - last_time <= 1000 / REFRESH_RATE do continue
            last_time = event.time

            event_pos := [2]i32{ event.x, event.y }
            new_pos   := client.pos
            new_size  := client.size
            delta     := event_pos - pointer
            when action == .Move {
                new_pos = old_pos + delta
                // TODO: Snapping
            }
            else { // Resize
                if left_side {
                    new_pos.x = old_pos.x + delta.x
                    delta.x *= -1
                }
                if top_side {
                    new_pos.y = old_pos.y + delta.y
                    delta.y *= -1
                }
                new_size = old_size + delta
            }

            if !client.floating do client_float(g_monitor_idx, client_idx)
            client_resize(client, new_pos, new_size)
        }
    }
    X.UngrabPointer(g_display, X.CurrentTime)

    when action == .Resize {
        _ev : X.XEvent
        // Ignore EnterNotify events caused by this
        for X.CheckMaskEvent(g_display, {.EnterWindow}, &_ev) {}
    }

    monitor_idx := monitor_idx_from_rect(client.pos, client.size)
    if monitor_idx != g_monitor_idx {
        old_monitor_idx := g_monitor_idx
        g_monitor_idx    = monitor_idx
        client_switch_monitor(client_idx, old_monitor_idx, monitor_idx, move=false)
    }
}
