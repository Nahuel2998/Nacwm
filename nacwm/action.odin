package nacwm

import "core:sys/posix"
import "core:log"
import X "vendor:x11/xlib"

Action :: union {
    Rebirth,
    Thats,
    Spawn,
    View,
    Shoot,
    Select,
    SelectMonitor,
    ToTag,
    ToMonitor,
    Float,
    MouseMove,
    MouseResize,
    MasterResize,
}

Rebirth :: distinct struct{ }
Thats   :: distinct struct{ }
Spawn :: distinct []cstring
View  :: distinct Tags
Shoot :: distinct struct{ unkindly : bool }
Select        :: distinct struct{ delta : i8 }
SelectMonitor :: distinct struct{ target : Monitor_Index }
ToTag     :: distinct Tags
ToMonitor :: distinct struct{ target : Monitor_Index }
Float     :: distinct struct{ }
MouseMove   :: distinct struct{ }
MouseResize :: distinct struct{ }
MasterResize :: distinct struct{ delta : f32 }

// Checks whether there's something wrong in the bindings config
verify_bindings :: proc() {
    for binding in BINDINGS {
        #partial switch a in binding.action {
        case Spawn:
            if a[len(a) - 1] != nil do log.panic("Spawn{", a, "} doesn't end with `nil`. It should")

        case ToMonitor:
            if a.target < 0 do log.panic(a, "can't be negative. Target must be a Monitor_Index")
        case SelectMonitor:
            if a.target < 0 do log.panic(a, "can't be negative. Target must be a Monitor_Index")

        case MasterResize:
            if a.delta < -1 || a.delta > 1 do log.panic(a, "must be a float in range -1..1")

        case Select:
            if a.delta == 0 do log.panic(a, "must be anything but 0")
        }
    }
}

do_action :: proc(action : Action) {
    switch a in action {
    case Rebirth:
        g_restart = true
        g_running = false

    case Thats:
        g_running = false

    case Spawn:
        if posix.fork() != 0 do return

        if g_display != nil {
            connection := X.ConnectionNumber(g_display)
            posix.close( cast(posix.FD)connection )
        }
        posix.setsid()

        // Reset ignored signals
        sa : posix.sigaction_t
        posix.sigemptyset(&sa.sa_mask)
        sa.sa_flags   = {}
        sa.sa_handler = auto_cast posix.SIG_DFL
        posix.sigaction(.SIGCHLD, &sa, nil)

        posix.execvp(a[0], raw_data(a))
        log.panic("Failed to run command:", a)

    case View:
        monitor := &g_monitors[g_monitor_idx]
        monitor.tags = cast(Tags)a
        client_focus(CLIENT_NONE)
        monitor_arrange(g_monitor_idx)
        bar_draw(monitor^)

    case Shoot:
        client_idx := g_monitors[g_monitor_idx].selected
        client_kill(g_monitor_idx, client_idx, !a.unkindly)

    case Select:
        monitor    := g_monitors[g_monitor_idx]
        client_idx := monitor.selected
        if client_idx == CLIENT_NONE do return

        client := monitor.clients[client_idx]
        if client.fullscreen do return

        incr  := int(0 < a.delta) - int(a.delta < 0)
        until := abs(a.delta)
        for {
            client_idx += incr
            client_idx %= len(monitor.clients)
            if client_idx < 0 do client_idx += len(monitor.clients)

            if client_is_visible(client_idx, monitor) do until -= 1
            if until == 0 do break
        }
        client_focus(client_idx)

    case SelectMonitor:
        if g_monitor_idx == a.target do return

        client_unfocus(false)
        g_monitor_idx = a.target
        client_focus(CLIENT_NONE)

    case ToTag:
        monitor := &g_monitors[g_monitor_idx]
        client_idx := monitor.selected
        if client_idx == CLIENT_NONE do return

        monitor.clients[client_idx].tags = cast(Tags)a
        client_focus(CLIENT_NONE)
        monitor_arrange(g_monitor_idx)
        bar_draw(monitor^)

    case ToMonitor:
        if a.target >= len(g_monitors) do return

        client_idx := g_monitors[g_monitor_idx].selected
        client_switch_monitor(client_idx, g_monitor_idx, a.target, move=true)

    case Float:
        client_idx := g_monitors[g_monitor_idx].selected
        client_float(g_monitor_idx, client_idx)

    case MouseMove:
        client_mouse_action(.Move)

    case MouseResize:
        client_mouse_action(.Resize)

    case MasterResize:
        monitor    := &g_monitors[g_monitor_idx]
        new_factor := monitor.master_factor + a.delta
        if new_factor < 0.05 || new_factor > 0.95 do return

        monitor.master_factor = new_factor
        monitor_tile(monitor^)
    }
}
