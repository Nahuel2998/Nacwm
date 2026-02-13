package nacwm

import X "vendor:x11/xlib"

Keybind :: struct {
    modifiers : X.InputMask,
    key       : X.KeySym,
    action    : Action,
}

Click_Kind :: enum {
    Root,
    Client,
}

BUTTON_MASK :: X.EventMask{ .ButtonPress, .ButtonRelease }
Buttonbind :: struct {
    click     : Click_Kind,
    modifiers : X.InputMask,
    button    : X.MouseButton,
    action    : Action,
}

setup_keys :: proc() {
    // TODO: Support numpad? why would I
    X.UngrabKey(g_display, X.AnyKey, {.AnyModifier}, g_screen.root)

    start, end, skip : i32
    X.DisplayKeycodes(g_display, &start, &end)
    keysyms := X.GetKeyboardMapping(g_display, cast(X.KeyCode)start, end - start + 1, &skip)
    defer X.Free(keysyms)

    for keycode in start..=end do for bind in BINDINGS {
        if bind.key != keysyms[(keycode - start) * skip] do continue
        X.GrabKey(g_display, keycode, bind.modifiers, g_screen.root, true, .GrabModeAsync, .GrabModeAsync)
    }
}

grab_buttons :: proc(window : X.Window, $focused : bool) {
    // TODO: Support numpad? why would I
    X.UngrabButton(g_display, X.AnyButton, {.AnyModifier}, window)

    when !focused do X.GrabButton(g_display, X.AnyButton, {.AnyModifier}, window, false, BUTTON_MASK, .GrabModeAsync, .GrabModeAsync, X.None, X.None)

    for bind in BUTTON_BINDINGS {
        X.GrabButton(g_display, cast(u32)bind.button, bind.modifiers, window, false, BUTTON_MASK, .GrabModeAsync, .GrabModeAsync, X.None, X.None)
    }
}
