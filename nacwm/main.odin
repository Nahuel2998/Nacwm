package nacwm

import "base:runtime"
import "core:os"
import "core:log"
import "core:strings"
import "core:sys/posix"
import X "vendor:x11/xlib"

g_display : ^X.Display

Screen_Info :: struct {
    id : i32,
    size : [2]i32,
    root : X.Window,
}
g_screen : Screen_Info

g_context : runtime.Context

g_restart := false
g_running := true

main :: proc() {
    context.logger = log.create_console_logger()
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

    if g_restart {
        argv := make([]cstring, len(os.args) + 1)
        for arg, i in os.args {
            argv[i] = strings.clone_to_cstring(arg)
        }
        posix.execvp(argv[0], raw_data(argv))
    }
}

run :: proc() {
    X.Sync(g_display, false)

    event : X.XEvent
    for g_running {
        X.NextEvent(g_display, &event)

        handler := g_handlers[event.type]
        if handler != nil do handler(event)
    }
}

setup :: proc() {
    setup_signals()

    setup_screen()
    setup_monitors()

    setup_atoms()
    setup_wmhints()

    setup_cursors()
    setup_colors()

    setup_events()
    setup_keys()

    focus_reset()
}

setdown :: proc() {
    do_action(~View{})
    for monitor, monitor_idx in g_monitors do for client_idx in 0..<len(monitor.clients) {
        client_unmanage(monitor_idx, client_idx, false)
    }

    X.UngrabKey(g_display, X.AnyKey, {.AnyModifier}, g_screen.root)

    for monitor in g_monitors do monitor_delete(monitor)
    X.DestroyWindow(g_display, g_wmcheckwin)

    setdown_cursors()
    setdown_colors()

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
