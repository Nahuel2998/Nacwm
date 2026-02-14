package xinerama

import "core:c"
import X "vendor:x11/xlib"

ScreenInfo :: struct {
    screen_number : c.int,
    x_org         : c.short,
    y_org         : c.short,
    width         : c.short,
    height        : c.short,
}

foreign import xinerama "system:Xinerama"
@(default_calling_convention="c", link_prefix="Xinerama")
foreign xinerama {
    IsActive :: proc(display: ^X.Display) -> b32 ---
    QueryScreens :: proc(display: ^X.Display, number: ^i32) -> [^]ScreenInfo ---
}
