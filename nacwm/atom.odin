package nacwm

import "core:fmt"
import "core:log"
import "core:strings"
import X "../vendor/x11/xlib"

WM_NAME :: "nacwm"

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
Nacwm_Atom :: enum {
    Window_Data,
}
g_atoms : struct {
    wm    : [X_WM_Atom]X.Atom,
    net   : [X_Net_Atom]X.Atom,
    nacwm : [Nacwm_Atom]X.Atom,
}

g_wmcheckwin : X.Window

setup_atoms :: proc() {
    g_atoms = {
        wm  = {
            .Protocols  = X.InternAtom(g_display, "WM_PROTOCOLS",     false),
            .Delete     = X.InternAtom(g_display, "WM_DELETE_WINDOW", false),
            .State      = X.InternAtom(g_display, "WM_STATE",         false),
            .Take_Focus = X.InternAtom(g_display, "WM_TAKE_FOCUS",    false),
        },
        net = { // -- EWMH
            .Client_List           = X.InternAtom(g_display, "_NET_CLIENT_LIST",           false),
            .Active_Window         = X.InternAtom(g_display, "_NET_ACTIVE_WINDOW",         false),
            .Supported             = X.InternAtom(g_display, "_NET_SUPPORTED",             false),
            .WM_Name               = X.InternAtom(g_display, "_NET_WM_NAME",               false),
            .WM_State              = X.InternAtom(g_display, "_NET_WM_STATE",              false),
            .WM_Check              = X.InternAtom(g_display, "_NET_SUPPORTING_WM_CHECK",   false),
            .WM_Fullscreen         = X.InternAtom(g_display, "_NET_WM_STATE_FULLSCREEN",   false),
            .WM_Window_Type        = X.InternAtom(g_display, "_NET_WM_WINDOW_TYPE",        false),
            .WM_Window_Type_Dialog = X.InternAtom(g_display, "_NET_WM_WINDOW_TYPE_DIALOG", false),
        },
        nacwm = {
            .Window_Data = X.InternAtom(g_display, "_NACWM_WINDOW_DATA", false),
        },
    }
}

setup_wmhints :: proc() {
    utf8str := X.InternAtom(g_display, "UTF8_STRING", false)

    wm_name := WM_NAME
    g_wmcheckwin = X.CreateSimpleWindow(g_display, g_screen.root, 0, 0, 1, 1, 0, 0, 0)
    X.ChangeProperty(g_display, g_wmcheckwin,  g_atoms.net[.WM_Name],      utf8str,  8, X.PropModeReplace, raw_data(wm_name), len(WM_NAME))
    X.ChangeProperty(g_display, g_wmcheckwin,  g_atoms.net[.WM_Check], X.XA_WINDOW, 32, X.PropModeReplace, &g_wmcheckwin, 1)
    X.ChangeProperty(g_display, g_screen.root, g_atoms.net[.WM_Check], X.XA_WINDOW, 32, X.PropModeReplace, &g_wmcheckwin, 1)

    X.ChangeProperty(g_display, g_screen.root, g_atoms.net[.Supported],  X.XA_ATOM, 32, X.PropModeReplace, &g_atoms.net, len(g_atoms.net))
    X.DeleteProperty(g_display, g_screen.root, g_atoms.net[.Client_List])
}

client_update_type :: proc(client : ^Client) {
    window := client.window

    wintype, ok_wintype := get_property(window, g_atoms.net[.WM_Window_Type], X.XA_ATOM, X.Atom, 1, false)
    if ok_wintype && wintype == g_atoms.net[.WM_Window_Type_Dialog] {
        client.floating = true
    }

    state, ok_state := get_property(window, g_atoms.net[.WM_State], X.XA_ATOM, X.Atom, 1, false)
    if ok_state && state == g_atoms.net[.WM_Fullscreen] {
        client_fullscreen(client, client.monitor, true)
    }
}

client_update_wmhints :: proc(client : ^Client) {
    hints := X.GetWMHints(g_display, client.window)
    if hints == nil do return
    defer X.Free(hints)

    // TODO: Urgency hint

    if .InputHint in hints.flags do client.no_focus = !bool(hints.input)
    else                         do client.no_focus = false
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
    num_clients := cast(i32)len(g_clients)
    if num_clients == 0 {
        X.DeleteProperty(g_display, g_screen.root, g_atoms.net[.Client_List])
        return
    }

    clients := make([]X.Window, num_clients, allocator=context.temp_allocator)
    defer free_all(context.temp_allocator)

    i : int
    for client in g_clients {
        clients[i] = client.window
        i += 1
    }
    X.ChangeProperty(g_display, g_screen.root, g_atoms.net[.Client_List], X.XA_WINDOW, 32, X.PropModeReplace, raw_data(clients), num_clients)
}

clients_save :: proc() {
    window_data := make([]Restart_Window_Data, len(g_clients), context.temp_allocator)
    for client, i in g_clients {
        window_data[i] = {
            client.window,
            {
                monitor  = client.monitor,
                tags     = transmute(u16)client.tags,
                floating = client.floating,
            },
        }
    }
    count := ( size_of(Restart_Window_Data) / size_of(uint) ) * len(window_data)
    X.ChangeProperty(g_display, g_screen.root, g_atoms.nacwm[.Window_Data], g_atoms.nacwm[.Window_Data], 32, X.PropModeReplace, raw_data(window_data), cast(i32)count)
    X.Flush(g_display)
    free_all(context.temp_allocator)
}

@(require_results)
clients_load :: proc(allocator := context.allocator) -> ([]Restart_Window_Data, bool) {
    data, num_items, ok := get_property_data(g_screen.root, g_atoms.nacwm[.Window_Data], g_atoms.nacwm[.Window_Data], 512 * 2, true) // Get up to 512 clients because why more
    if !ok do return nil, false
    defer X.Free(data)

    if num_items == 0 do return nil, false

    num_window_data := num_items / (size_of(Restart_Window_Data) / size_of(uint))
    raw_window_data := cast([^]Restart_Window_Data)data

    res := make([]Restart_Window_Data, num_window_data, allocator)
    for &window_data, i in res {
        window_data = raw_window_data[i]
    }
    return res, true
}

// -- Utils
get_property :: proc(window : X.Window, prop : X.Atom, x_type : X.Atom, $type : typeid, $length : int, $delete : b32) -> (type, bool) {
    data, num_items, ok := get_property_data(window, prop, x_type, length, delete)
    if !ok do return {}, false
    defer X.Free(data)

    if num_items == 0 do return {}, true

    res := cast(^type)data
    return res^, true
}

get_property_data :: proc(window : X.Window, prop : X.Atom, x_type : X.Atom, $length : int, $delete : b32) -> (rawptr, uint, bool) {
    _a : X.Atom
    _i : i32
    bytes_after, num_items : uint
    data : rawptr

    status := X.GetWindowProperty(g_display, window, prop, 0, length, delete, x_type, &_a, &_i, &num_items, &bytes_after, &data)
    if bytes_after > 0 do log.warn("Read of property", prop, "with length", length, "resulted in", bytes_after, "bytes_after")

    if status != 0 || data == nil do return data, 0, false

    return data, num_items, true
}

get_text_property :: proc(window : X.Window, atom : X.Atom) -> (string, bool) {
    buf : strings.Builder
    ok := get_text_property_sb(window, atom, &buf)
    return strings.to_string(buf), ok
}

// NOTE: This appends to the sb, maybe clear it first
get_text_property_sb :: proc(window : X.Window, atom : X.Atom, buf : ^strings.Builder) -> bool {
    prop : X.XTextProperty
    ok := bool(X.GetTextProperty(g_display, window, &prop, atom))
    if !ok || prop.nitems == 0 do return false
    defer X.Free(prop.value)

    if prop.encoding == X.XA_STRING {
        fmt.sbprint(buf, cstring(prop.value))
        return true
    }

    list : [^]cstring
    num_elems : i32
    if X.mbTextPropertyToTextList(g_display, &prop, &list, &num_elems) >= cast(i32)X.Status.Success \
    && num_elems > 0 {
        defer X.FreeStringList(list)
        if list[0] != nil {
            fmt.sbprint(buf, cstring(list[0]))
            return true
        }
    }
    return false
}
