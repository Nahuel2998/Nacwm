package nacwm

import "core:strings"
import X "../vendor/x11/xlib"

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
    anchor   : Quadrant,
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

client_apply_rules :: proc(client : ^Client) {
    hints : X.XClassHint
    X.GetClassHint(g_display, client.window, &hints)

    class    := hints.res_class != nil ? string(hints.res_class) : BROKEN
    instance := hints.res_name  != nil ? string(hints.res_name)  : BROKEN

    client_data := Client_Filter{ class, instance, client.name }
    for rule in RULES {
        if !client_matches(client_data, rule.filter) do continue

        client.floating = rule.spawn.floating
        client.tags     = rule.spawn.tags
        client.monitor  = rule.spawn.monitor
        client.anchor   = rule.spawn.anchor
        break
    }

    if hints.res_class != nil do X.Free(cast(rawptr)hints.res_class)
    if hints.res_name  != nil do X.Free(cast(rawptr)hints.res_name)

    if client.monitor == CLIENT_NONE do client.monitor = g_selected.monitor
    if client.tags    == {}          do client.tags    = g_monitors[client.monitor].tags
    return
}
