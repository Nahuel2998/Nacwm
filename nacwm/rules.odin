package nacwm

import "core:strings"
import X "vendor:x11/xlib"

BROKEN :: "_broken_"

Client_Filter :: struct {
    class    : string,
    instance : string,
    title    : string,
}

Spawn_Rules :: struct {
    tags     : Tags,
    floating : bool,
    monitor  : Monitor_Index,
}
Rule :: struct {
    filter : Client_Filter,
    spawn  : Spawn_Rules,
}

client_matches :: #force_inline proc(client, filter : Client_Filter) -> bool {
    return strings.contains(client.title,    filter.title   ) \
        && strings.contains(client.class,    filter.class   ) \
        && strings.contains(client.instance, filter.instance)
}

client_apply_rules :: proc(client : ^Client) -> (monitor_idx := MONITOR_NONE) {
    hints : X.XClassHint
    X.GetClassHint(g_display, client.window, &hints)

    class    := hints.res_class != nil ? string(hints.res_class) : BROKEN
    instance := hints.res_name  != nil ? string(hints.res_name)  : BROKEN

    client_data := Client_Filter{ class, instance, client.name }
    for rule in RULES {
        if !client_matches(client_data, rule.filter) do continue

        client.floating = rule.spawn.floating
        client.tags     = rule.spawn.tags
        monitor_idx     = rule.spawn.monitor
        break
    }

    if hints.res_class != nil do X.Free(cast(rawptr)hints.res_class)
    if hints.res_name  != nil do X.Free(cast(rawptr)hints.res_name)

    if monitor_idx == CLIENT_NONE do monitor_idx = g_monitor_idx
    if client.tags == {}          do client.tags = g_monitors[monitor_idx].tags
    return
}
