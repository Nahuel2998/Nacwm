package nacwm

import "core:fmt"
import "core:math"
import "core:strings"
import "../vendor/cairo"
import "../vendor/pango"
import X "../vendor/x11/xlib"

Bar :: struct {
    window  : X.Window,
    surface : ^cairo.surface_t,
}
g_bar_font   : ^pango.FontDescription
g_bar_status : strings.Builder

setup_bars :: proc() {
    for &monitor in g_monitors {
        if monitor.bar.window != X.None do continue
        monitor.bar = bar_create(monitor)
    }
}

setup_bar_font :: proc() {
    g_bar_font = pango.font_description_from_string(STYLE.bar.font)
}
setdown_bar_font :: proc() {
    pango.font_description_free(g_bar_font)
}

bar_create :: proc(monitor : Monitor) -> (bar : Bar) {
    attrs := X.XSetWindowAttributes{
        override_redirect = true,
        background_pixmap = X.ParentRelative,
        event_mask        = {.ButtonPress, .Exposure},
    }
    class_hint := X.XClassHint{ WM_NAME, WM_NAME }

    bar.window = X.CreateWindow(
        g_display, g_screen.root,
        monitor.pos.x, monitor.pos.y,
        cast(u32)monitor.size.x, cast(u32)STYLE.bar.height,
        0, X.DefaultDepth(g_display, g_screen.id),
        .CopyFromParent, X.DefaultVisual(g_display, g_screen.id),
        {.CWOverrideRedirect, .CWBackPixmap, .CWEventMask}, &attrs,
    )
    X.DefineCursor(g_display, bar.window, g_cursors[.Normal])
    X.MapRaised(g_display, bar.window)
    X.SetClassHint(g_display, bar.window, &class_hint)

    bar.surface = cairo.xlib_surface_create(
        g_display, bar.window, X.DefaultVisual(g_display, g_screen.id),
        monitor.size.x, STYLE.bar.height,
    )
    return
}

bar_delete :: proc(bar : Bar) {
    cairo.surface_destroy(bar.surface)
    X.UnmapWindow(g_display, bar.window)
    X.DestroyWindow(g_display, bar.window)
}

bars_draw :: proc() {
    for monitor in g_monitors {
        bar_draw(monitor)
    }
}

bar_draw :: proc(monitor : Monitor) {
    bar := monitor.bar
    cr  := cairo.create(bar.surface)
    defer {
        cairo.destroy(cr)
        cairo.surface_flush(bar.surface)
        X.Flush(g_display)
    }

    // Background
    color := STYLE.bar.base
    cairo.set_source_rgb(cr, color.r, color.g, color.g)
    cairo.paint(cr)

    // Status
    bar_status_draw(cr, monitor.size.x)

    // Tags
    has_clients : Tags
    for client in monitor.clients {
        has_clients |= client.tags
    }
    pos_x := BAR_CENTER
    BAR_CENTER :: f64(STYLE.bar.height) / 2
    for t in ~(Tags{}) {
        cairo.arc(cr, pos_x, BAR_CENTER, BAR_CENTER - 4, 0, 2 * math.PI)

        if      t in monitor.tags do color = STYLE.bar.tags[.Active]
        else if t in has_clients  do color = STYLE.bar.tags[.Used]
        else                      do color = STYLE.bar.tags[.Unused]
        cairo.set_source_rgb(cr, color.r, color.g, color.b)

        cairo.fill(cr)
        pos_x += BAR_CENTER * 2
    }
}

bar_status_draw :: proc(cr : ^cairo.cairo_t, monitor_width : i32) {
    layout := pango.cairo_create_layout(cr)
    defer     pango.unref(layout)

    color := STYLE.bar.status
    cairo.set_source_rgb(cr, color.r, color.g, color.b)
    pango.layout_set_font_description(layout, g_bar_font)
    pango.layout_set_text(layout, strings.to_cstring(&g_bar_status), -1)

    size : [2]i32
    pango.layout_get_pixel_size(layout, &size.x, &size.y)

    pos := [2]f64{
        f64(   monitor_width - size.x),
        f64(STYLE.bar.height - size.y) / 2,
    }
    cairo.move_to(cr, pos.x, pos.y)
    pango.cairo_show_layout(cr, layout)
}

bar_status_update :: proc() {
    strings.builder_reset(&g_bar_status)

    ok := get_text_property_sb(g_screen.root, X.XA_WM_NAME, &g_bar_status)
    if !ok do fmt.sbprint(&g_bar_status, BAR_STATUS_FALLBACK)

    bars_draw()
}
