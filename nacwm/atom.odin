package nacwm

import "core:c"
import "core:c/libc"
import "core:strings"
import X "vendor:x11/xlib"

WM_NAME :: "nacwm"

XA_WINDOW :: X.Atom(33)
XA_STRING :: X.Atom(31)

X_WM_Atom :: enum {
    Protocols,
    Delete,
    State,
    Take_Focus,
}
X_Net_Atom :: enum {
    Active_Window,
    Supported,
    WM_Name,
    WM_State,
    WM_Check,
    WM_Fullscreen,
    WM_Window_Type,
    WM_Window_Type_Dialog,
    Client_List,
}
g_atoms : struct {
    wm  : [X_WM_Atom]X.Atom,
    net : [X_Net_Atom]X.Atom,
}

g_wmcheckwin : X.Window

// TODO: Actually check which of these are unused
setup_atoms :: proc() {
    g_atoms = {
        wm  = {
            .Protocols  = X.InternAtom(g_display, "WM_PROTOCOLS",     false),
            .Delete     = X.InternAtom(g_display, "WM_DELETE_WINDOW", false),
            .State      = X.InternAtom(g_display, "WM_STATE",         false),
            .Take_Focus = X.InternAtom(g_display, "WM_TAKE_FOCUS",    false),
        },
        net = {
            .Active_Window         = X.InternAtom(g_display, "_NET_ACTIVE_WINDOW",         false),
            .Supported             = X.InternAtom(g_display, "_NET_SUPPORTED",             false),
            .WM_Name               = X.InternAtom(g_display, "_NET_WM_NAME",               false),
            .WM_State              = X.InternAtom(g_display, "_NET_WM_STATE",              false),
            .WM_Check              = X.InternAtom(g_display, "_NET_SUPPORTING_WM_CHECK",   false),
            .WM_Fullscreen         = X.InternAtom(g_display, "_NET_WM_STATE_FULLSCREEN",   false),
            .WM_Window_Type        = X.InternAtom(g_display, "_NET_WM_WINDOW_TYPE",        false),
            .WM_Window_Type_Dialog = X.InternAtom(g_display, "_NET_WM_WINDOW_TYPE_DIALOG", false),
            .Client_List           = X.InternAtom(g_display, "_NET_CLIENT_LIST",           false),
        },
    }
}

setup_wmhints :: proc() {
    utf8str := X.InternAtom(g_display, "UTF8_STRING", false)

    wm_name := WM_NAME
    g_wmcheckwin = X.CreateSimpleWindow(g_display, g_screen.root, 0, 0, 1, 1, 0, 0, 0)
    X.ChangeProperty(g_display, g_wmcheckwin,  g_atoms.net[.WM_Name],     utf8str,  8, X.PropModeReplace, raw_data(wm_name), len(WM_NAME))
    X.ChangeProperty(g_display, g_wmcheckwin,  g_atoms.net[.WM_Check],  XA_WINDOW, 32, X.PropModeReplace, &g_wmcheckwin, 1)
    X.ChangeProperty(g_display, g_screen.root, g_atoms.net[.WM_Check],  XA_WINDOW, 32, X.PropModeReplace, &g_wmcheckwin, 1)

    // -- EWMH
    X.ChangeProperty(g_display, g_screen.root, g_atoms.net[.Supported], X.XA_ATOM, 32, X.PropModeReplace, &g_atoms.net, len(g_atoms.net))
    X.DeleteProperty(g_display, g_screen.root, g_atoms.net[.Client_List])
}

client_update_type :: proc(client : ^Client, monitor_idx : Monitor_Index) {
    window := client.window

    wintype, ok_wintype := get_property(window, g_atoms.net[.WM_Window_Type], X.XA_ATOM, X.Atom)
    if ok_wintype && wintype == g_atoms.net[.WM_Window_Type_Dialog] {
        client.floating = true
    }

    state, ok_state := get_property(window, g_atoms.net[.WM_State], X.XA_ATOM, X.Atom)
    if ok_state && state == g_atoms.net[.WM_Fullscreen] {
        client_fullscreen(client, monitor_idx, true)
    }
}

client_update_wmhints :: proc(client : ^Client) {
    hints := X.GetWMHints(g_display, client.window)
    if hints == nil do return
    defer X.Free(hints)

    // TODO: Urgency hint

    if card(hints.flags & {.InputHint}) > 0 {
        client.no_focus = !bool(hints.input)
    } else {
        client.no_focus = false
    }
}

client_update_sizehints :: proc(client : ^Client) {
    _sh   : X.SizeHints
    hints : X.XSizeHints
    ok := bool(X.GetWMNormalHints(g_display, client.window, &hints, &_sh))
    if !ok do hints.flags = {}

    // TODO: Handle basesize

    client.hints = {}
    if       .PMinSize in hints.flags do client.hints.min = { hints.min_width,  hints.min_height  }
    else if .PBaseSize in hints.flags do client.hints.min = { hints.base_width, hints.base_height }

    if       .PMaxSize in hints.flags do client.hints.max = { hints.max_width,  hints.max_height  }

    // TODO: Handle aspect
    client.hints.valid = true
}

client_update_name :: proc(client : ^Client) {
    name : string
    ok   : bool
    get_name: {
        name, ok = get_text_property(client.window, g_atoms.net[.WM_Name])
        if ok do break get_name

        name, ok = get_text_property(client.window, X.XA_WM_NAME)
        if ok do break get_name
    }
    if len(name) == 0 {
        if ok do delete(name)
        name = strings.clone(BROKEN)
    }

    if len(client.name) != 0 {
        delete(client.name)
    }
    client.name = name
}

// TODO: Consider keeping track of this somewhere
update_client_list :: proc() {
    num_clients : int
    for monitor in g_monitors {
        num_clients += len(monitor.clients)
    }

    if num_clients == 0 {
        X.DeleteProperty(g_display, g_screen.root, g_atoms.net[.Client_List])
        return
    }

    clients := make([]X.Window, num_clients, allocator=context.temp_allocator)
    defer free_all(context.temp_allocator)

    i : int
    for monitor in g_monitors do for client in monitor.clients {
        clients[i] = client.window
        i += 1
    }
    X.ChangeProperty(g_display, g_screen.root, g_atoms.net[.Client_List], XA_WINDOW, 32, X.PropModeReplace, raw_data(clients), cast(i32)num_clients)
}

// -- Utils
get_property :: proc(window : X.Window, prop : X.Atom, x_type : X.Atom, $type : typeid) -> (type, bool) {
    _a : X.Atom
    _i : c.int
    _ul, num_items : c.ulong
    data : rawptr

    status := X.GetWindowProperty(g_display, window, prop, 0, size_of(type)/size_of(i32), false, x_type, &_a, &_i, &num_items, &_ul, &data)
    if status != 0 || data == nil do return {}, false
    defer X.Free(data)

    if num_items == 0 do return {}, true

    res := cast(^type)data
    return res^, true
}

// TODO: Do I really need more than a fixed buffer size?
get_text_property :: proc(window : X.Window, atom : X.Atom) -> (string, bool) {
    prop : X.XTextProperty
    ok := bool(X.GetTextProperty(g_display, window, &prop, atom))
    if !ok || prop.nitems == 0 do return "", false
    defer X.Free(prop.value)

    if prop.encoding == XA_STRING {
        return strings.clone_from_cstring(cstring(prop.value)), true
    }

    list : [^]cstring
    num_elems : i32
    if XmbTextPropertyToTextList(g_display, &prop, &list, &num_elems) >= cast(i32)X.Status.Success \
    && num_elems > 0 {
        defer XFreeStringList(list)
        if list[0] != nil {
            return strings.clone_from_cstring(cstring(list[0])), true
        }
    }
    return "", false
}

get_text_property_buf :: proc(window : X.Window, atom : X.Atom, buf : []u8) -> bool {
    prop : X.XTextProperty
    ok := bool(X.GetTextProperty(g_display, window, &prop, atom))
    if !ok || prop.nitems == 0 do return false
    defer X.Free(prop.value)

    if prop.encoding == XA_STRING {
        libc.strncpy(raw_data(buf), cstring(prop.value), len(buf) - 1)
        return true
    }

    list : [^]cstring
    num_elems : i32
    if XmbTextPropertyToTextList(g_display, &prop, &list, &num_elems) >= cast(i32)X.Status.Success \
    && num_elems > 0 {
        defer XFreeStringList(list)
        if list[0] != nil {
            libc.strncpy(raw_data(buf), cstring(list[0]), len(buf) - 1)
            return true
        }
    }
    return false
}

// -- Bindings
foreign import xlib "system:X11"
@(default_calling_convention="c")
foreign xlib {
    XmbTextPropertyToTextList :: proc(
        display : ^X.Display,
        text_prop : ^X.XTextProperty,
        list_return : ^[^]cstring,
        count_return : ^i32,
        ) -> i32 ---

    XFreeStringList :: proc(
        list : [^]cstring,
        ) ---
}
