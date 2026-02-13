package nacwm

import "core:log"
import X "vendor:x11/xlib"

// vendor:x11/xlib doesn't have proto.h
// These are just the ones used here
@(private="file")
XRequestCode :: enum u8 {
    ConfigureWindow   = 12,
    GrabButton        = 28,
    GrabKey           = 33,
    SetInputFocus     = 42,
    CopyArea          = 62,
    PolySegment       = 66,
    PolyFillRectangle = 70,
    PolyText8         = 74,
}

XErrorHandler :: #type proc "c" (display : ^X.Display, event : ^X.XErrorEvent) -> i32
// Default errorhandler
g_xerror_xlib : XErrorHandler

// Startup errorhandler
xerror_startup :: proc "c" (display : ^X.Display, event : ^X.XErrorEvent) -> i32 {
    context = g_context
    log.panic("There's someone here already nosvem")
}

// Ignore errorhandler
xerror_idc :: proc "c" (display : ^X.Display, event : ^X.XErrorEvent) -> i32 {
    return 0
}

// General errorhandler
xerror :: proc "c" (display : ^X.Display, event : ^X.XErrorEvent) -> i32 {
    context = g_context

    error_code := cast(X.Status)event.error_code
    if error_code == .BadWindow do return 0

    request_code := cast(XRequestCode)event.request_code
    switch request_code {
    case .SetInputFocus, .ConfigureWindow:
        if error_code == .BadMatch    do return 0

    case .PolyText8, .PolyFillRectangle, .PolySegment, .CopyArea:
        if error_code == .BadDrawable do return 0

    case .GrabButton, .GrabKey:
        if error_code == .BadAccess   do return 0
    }

    log.fatalf("XError: request_code=%d, error_code=%d", event.request_code, event.error_code);
    return g_xerror_xlib(display, event)
}

check_other_wm :: proc() {
    g_xerror_xlib = X.SetErrorHandler(xerror_startup)

    // Causes an error if another WM is running
    X.SelectInput(g_display, X.DefaultRootWindow(g_display), {.SubstructureRedirect})
    X.Sync(g_display, false)

    X.SetErrorHandler(xerror)
    X.Sync(g_display, false)
}
