package nacwm

import "core:log"
import X "vendor:x11/xlib"

Cursor_Type :: enum {
    Normal,
    Resize,
    Move,
}
g_cursors : [Cursor_Type]X.Cursor

Color_Scheme :: struct {
    border : uint,  // X.XColor.pixel
}
Color_Scheme_Type :: enum {
    Normal,
    Selected,
}
g_scheme : [Color_Scheme_Type]Color_Scheme

Style :: struct {
    border : struct {
        width : i32,
        color : [Color_Scheme_Type]cstring,
    }
}

setup_cursors :: proc() {
    g_cursors[.Normal] = X.CreateFontCursor(g_display, .XC_left_ptr)
    g_cursors[.Resize] = X.CreateFontCursor(g_display, .XC_sizing)
    g_cursors[.Move]   = X.CreateFontCursor(g_display, .XC_fleur)
}

setdown_cursors :: proc() {
    for cursor in g_cursors do X.FreeCursor(g_display, cursor)
}

setup_colors :: proc() {
    colormap := X.DefaultColormap(g_display, g_screen.id)

    for color_name, i in STYLE.border.color {
        screen, exact : X.XColor
        ok := bool(X.AllocNamedColor(g_display, colormap, color_name, &screen, &exact))
        if !ok do log.panic("Failed to alloc color:", color_name)

        g_scheme[i].border = screen.pixel
    }
}

setdown_colors :: proc() {
    colormap := X.DefaultColormap(g_display, g_screen.id)

    pixels : [len(g_scheme)]uint
    for scheme, i in g_scheme {
        pixels[i] = scheme.border
    }
    X.FreeColors(g_display, colormap, auto_cast &pixels, len(pixels), 0)
}
