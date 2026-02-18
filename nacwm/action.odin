package nacwm

import "core:sys/posix"
import "core:log"
import X "../vendor/x11/xlib"

Action :: union {
    Rebirth,
    Thats,
    Spawn,
    View,
    SelectMonitor,
    Select,
    Move,
    ToTag,
    ToMonitor,
    Float,
    Center,
    Shoot,
    MouseMove,
    MouseResize,
    MasterResize,
}

Rebirth :: distinct struct{ }
Thats   :: distinct struct{ }
Spawn :: distinct []cstring
View  :: distinct Tags
SelectMonitor :: distinct struct{ target : Monitor_Index }
Select        :: distinct struct{ delta : i8 }
Move      :: distinct struct{ delta : i8 }
ToTag     :: distinct Tags
ToMonitor :: distinct struct{ target : Monitor_Index }
Float     :: distinct struct{ }
Center    :: distinct struct{ }
Shoot     :: distinct struct{ unkindly : bool }
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
        monitor_refocus()
        monitor_arrange(g_monitor_idx)
        bar_draw(monitor^)

    case Select:
        if g_client_idx == CLIENT_NONE do return

        client := g_clients[g_client_idx]
        if client.fullscreen do return

        monitor := g_monitors[g_monitor_idx]
        client_idx := monitor_nth_matching_client(monitor, g_client_idx, a.delta, client_is_visible_in_monitor)
        client_focus(client_idx)

    case Move:
        if g_client_idx == CLIENT_NONE do return

        client := g_clients[g_client_idx]
        if client.floating do return

        monitor := g_monitors[client.monitor]
        client_idx := monitor_nth_matching_client(
            monitor,
            g_client_idx,
            a.delta,
            proc(idx : Client_Index, mon : Monitor) -> bool {
                clt := g_clients[idx]
                return client_is_visible_in_monitor(idx, mon) && !clt.floating
            },
        )
        client_swap(g_client_idx, client_idx)

    case SelectMonitor:
        monitor_focus(a.target)

    case ToTag:
        if g_client_idx == CLIENT_NONE do return

        g_clients[g_client_idx].tags = cast(Tags)a
        monitor_refocus()
        monitor_arrange(g_monitor_idx)
        bar_draw(g_monitors[g_monitor_idx])

    case ToMonitor:
        if a.target >= len(g_monitors) do return

        client_switch_monitor(g_client_idx, a.target, move=true, follow=false)

    case Float:
        client_float(g_client_idx)

    case Center:
        if g_client_idx == CLIENT_NONE do return

        client := &g_clients[g_client_idx]
        if !client.floating do return

        monitor := g_monitors[client.monitor]
        pos := monitor.pos + (monitor.size - client.size) / 2
        client_resize(client, pos, client.size)

    case Shoot:
        client_kill(g_client_idx, !a.unkindly)

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
