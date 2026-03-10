package nacwm

import "core:os"
import "core:sys/posix"
import "core:strings"
import X "../vendor/x11/xlib"

Restart_Monitor_Data :: [2]uint // { master_factor : f32, tags : Tags }
Restart_Window_Data  :: struct {
    window   : X.Window,
    data     : bit_field u32 {
        monitor  : Monitor_Index  | 8,
        tags     : u16 /* Tags */ | 16,
        floating : bool           | 1,
        anchor   : Quadrant       | 3,
    },
}
#assert(size_of(Restart_Window_Data) == size_of([2]uint))

g_restart := false

restart :: proc() {
    monitors_save()
    clients_save()
    argv := make([]cstring, len(os.args) + 1)
    for arg, i in os.args {
        argv[i] = strings.clone_to_cstring(arg)
    }
    posix.execvp(argv[0], raw_data(argv))
}

clients_save :: proc() {
    window_data := make([]Restart_Window_Data, len(g_clients), context.temp_allocator)
    defer free_all(context.temp_allocator)

    for client, i in g_clients {
        window_data[i] = {
            client.window,
            {
                monitor  = client.monitor,
                tags     = transmute(u16)client.tags,
                floating = client.floating,
                anchor   = client.anchor,
            },
        }
    }

    count := ( size_of(Restart_Window_Data) / size_of(uint) ) * len(window_data)
    X.ChangeProperty(g_display, g_screen.root, g_atoms.nacwm[.Window_Data], g_atoms.nacwm[.Window_Data], 32, X.PropModeReplace, raw_data(window_data), cast(i32)count)
    X.Flush(g_display)
}

monitors_save :: proc() {
    monitor_data := make([]Restart_Monitor_Data, len(g_monitors), context.temp_allocator)
    defer free_all(context.temp_allocator)

    for monitor, i in g_monitors {
        monitor_data[i] = {
            cast(uint)( transmute(u32)monitor.master_factor ),
            cast(uint)( transmute(u16)monitor.tags ),
        }
    }

    count := ( size_of(Restart_Monitor_Data) / size_of(uint) ) * len(monitor_data)
    X.ChangeProperty(g_display, g_screen.root, g_atoms.nacwm[.Monitor_Data], g_atoms.nacwm[.Monitor_Data], 32, X.PropModeReplace, raw_data(monitor_data), cast(i32)count)
    X.Flush(g_display)
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

monitors_restore :: proc() {
    data, num_items, ok := get_property_data(g_screen.root, g_atoms.nacwm[.Monitor_Data], g_atoms.nacwm[.Monitor_Data], 32 * 2, true) // Get up to 32 monitors because why more
    if !ok do return
    defer X.Free(data)

    if num_items == 0 do return

    monitor_datas := cast([^]Restart_Monitor_Data)data
    for monitor_data, i in monitor_datas[:num_items / (size_of(Restart_Monitor_Data) / size_of(uint))] {
        g_monitors[i].master_factor = transmute(f32)(  cast(u32)monitor_data[0] )
        g_monitors[i].tags          = transmute(Tags)( cast(u16)monitor_data[1] )
    }
}
