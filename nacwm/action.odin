package nacwm

import "core:sys/posix"
import "core:log"
import X "vendor:x11/xlib"

PREV :: -1
NEXT :: +1

Action :: union {
    Rebirth,
    Thats,
    Spawn,
    View,
    Shoot,
    // Select,
    ToTag,
    ToMonitor,
    Float,
    MouseMove,
}

Rebirth   :: distinct struct{ }
Thats     :: distinct struct{ }
Spawn     :: distinct []cstring
View      :: distinct Tags
Shoot     :: distinct struct{ unkindly : bool }
// Select :: distinct struct{ delta : i8 }
ToTag     :: distinct Tags
ToMonitor :: distinct struct{ target : Monitor_Index }
Float     :: distinct struct{ }
MouseMove :: distinct struct{ }

// Checks whether there's something wrong in the bindings config
verify_bindings :: proc() {
    for binding in BINDINGS {
        #partial switch a in binding.action {
        case Spawn:
            if a[len(a) - 1] != nil do log.panic("Spawn{", a, "} doesn't end with `nil`. It should.")

        case ToMonitor:
            if a.target < 0 do log.panic(a, "can't be negative. Target must be a Monitor_Index")
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
        g_monitors[g_monitor_idx].tags = cast(Tags)a
        client_focus(CLIENT_NONE)
        monitor_arrange(g_monitor_idx)

    case Shoot:
        client_idx := g_monitors[g_monitor_idx].selected
        client_kill(g_monitor_idx, client_idx, !a.unkindly)

    case ToTag:
        client_idx := g_monitors[g_monitor_idx].selected
        if client_idx == CLIENT_NONE do return

        g_monitors[g_monitor_idx].clients[client_idx].tags = cast(Tags)a
        client_focus(CLIENT_NONE)
        monitor_arrange(g_monitor_idx)

    case ToMonitor:
        if a.target >= len(g_monitors) do return

        client_idx := g_monitors[g_monitor_idx].selected
        client_switch_monitor(client_idx, g_monitor_idx, a.target)

    case Float:
        client_idx := g_monitors[g_monitor_idx].selected
        client_float(g_monitor_idx, client_idx)

    case MouseMove:
        client_mouse_move()
    }
}
