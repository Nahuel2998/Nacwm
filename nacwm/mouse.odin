package nacwm

import "core:log"
import X "vendor:x11/xlib"

MOUSE_MASK :: BUTTON_MASK | {.PointerMotion}

@(private="file")
GRAB_SUCCESS :: 0

client_mouse_move :: proc() {
    client_idx := g_monitors[g_monitor_idx].selected
    if client_idx == CLIENT_NONE do return

    client := &g_monitors[g_monitor_idx].clients[client_idx]
    // TODO: Do something special with fullscreen'd windows

    monitor_restack()

    grab_res := X.GrabPointer(g_display, g_screen.root, false, MOUSE_MASK, .GrabModeAsync, .GrabModeAsync, X.None, g_cursors[.Move], X.CurrentTime)
    if grab_res != GRAB_SUCCESS do return

    pointer, ok := get_root_ptr()
    if !ok do return

    last_time : X.Time

    event : X.XEvent
    old_pos := client.pos
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
            new_pos := old_pos + (event_pos - pointer)

            // TODO: Snapping

            if !client.floating do client_float(g_monitor_idx, client_idx)
            client_resize(client, new_pos, client.size)
        }
    }
    X.UngrabPointer(g_display, X.CurrentTime)

    monitor_idx := monitor_idx_from_rect(client.pos, client.size)
    if monitor_idx != g_monitor_idx {
        old_monitor_idx := g_monitor_idx
        g_monitor_idx    = monitor_idx
        client_switch_monitor(client_idx, old_monitor_idx, monitor_idx, move=false)
    }
}
