package nacwm

import "base:runtime"
import "core:log"
import "core:sys/posix"
import X "../vendor/x11/xlib"

g_display : ^X.Display

Screen_Info :: struct {
    id   : i32,
    size : [2]i32,
    root : X.Window,
}
g_screen : Screen_Info

Selected :: struct {
    monitor : Monitor_Index,
    client  : Client_Index,
}
g_selected := Selected{ 0, CLIENT_NONE }
g_running  := true

g_context : runtime.Context

main :: proc() {
    context.logger = log.create_console_logger(.Debug when ODIN_DEBUG else .Info)
    g_context = context

    verify_bindings()

    g_display = X.OpenDisplay(nil)
    if g_display == nil do log.panic("Failed to open display")
    defer X.CloseDisplay(g_display)

    // Exits if another WM is running
    check_other_wm()

    setup()
    defer setdown()

    scan_windows()
    run()

    // FIXME: If we restart(), setdown() isn't called; is this right?
    //        Currently it causes floating windows to spawn leftmost
    if g_restart do restart()
}

run :: proc() {
    X.Sync(g_display, false)

    event : X.XEvent
    for g_running {
        X.NextEvent(g_display, &event)
        if cast(i32)event.type > cast(i32)X.EventType.GenericEvent {
            // Cairo seems to cause event 65
            log.info("Received event outside valid range:", cast(i32)event.type)
            continue
        }

        handler := g_handlers[event.type]
        if handler != nil do handler(event)
    }
}

setup :: proc() {
    setup_signals()

    setup_screen()
    setup_atoms()
    setup_wmhints()

    setup_monitors()
    monitors_restore()

    setup_cursors()
    setup_colors()

    setup_bar_font()
    setup_bars()
    bar_status_update()

    setup_events()
    setup_keys()

    // Warp pointer to center of main monitor
    assert(len(g_monitors) > 0)
    monitor := g_monitors[0]
    pos     := monitor.pos + monitor.size / 2
    X.WarpPointer(g_display, X.None, g_screen.root, 0, 0, 0, 0, pos.x, pos.y)

    focus_reset()
}

setdown :: proc() {
    for _, idx in g_monitors {
        // Since hiding windows moves them offscreen, we make all tags visible
        // Just so the next windowmanager (likely us, too) doesn't freak out
        monitor_tags_set(idx, ~{}, false)
    }
    for client_idx in 0..<len(g_clients) {
        client_unmanage(client_idx, false)
    }

    X.UngrabKey(g_display, X.AnyKey, {.AnyModifier}, g_screen.root)

    for monitor in g_monitors do monitor_delete(monitor)
    X.DestroyWindow(g_display, g_wmcheckwin)

    setdown_cursors()
    setdown_colors()
    setdown_bar_font()

    X.Sync(g_display, false)
    focus_reset()
}

setup_signals :: proc() {
    // Don't turn children into zombies
    sa : posix.sigaction_t
    posix.sigemptyset(&sa.sa_mask)
    sa.sa_flags   = {.NOCLDSTOP, .NOCLDWAIT, .RESTART}
    sa.sa_handler = auto_cast posix.SIG_IGN
    posix.sigaction(.SIGCHLD, &sa, nil)

    // Clean up zombies from .xinitrc
    for posix.waitpid(-1, nil, {.NOHANG}) > 0 { }
}

setup_screen :: proc() {
    g_screen.id     = X.DefaultScreen( g_display )
    g_screen.size.x = X.DisplayWidth(  g_display, g_screen.id )
    g_screen.size.y = X.DisplayHeight( g_display, g_screen.id )
    g_screen.root   = X.RootWindow(    g_display, g_screen.id )
}
