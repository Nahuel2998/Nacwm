package nacwm

import "core:strings"
import X "vendor:x11/xlib"

BROKEN :: "_broken_"

Rule :: struct {
    class    : string,
    instance : string,
    title    : string,
    tags     : Tags,
    floating : bool,
    monitor  : Monitor_Index,
}

client_apply_rules :: proc(client : ^Client) -> (monitor_idx := MONITOR_NONE) {
    hints : X.XClassHint
    X.GetClassHint(g_display, client.window, &hints)

    class    := hints.res_class != nil ? string(hints.res_class) : BROKEN
    instance := hints.res_name  != nil ? string(hints.res_name)  : BROKEN

    for rule in RULES {
        if !strings.contains(client.name, rule.title   ) \
        || !strings.contains(class,       rule.class   ) \
        || !strings.contains(instance,    rule.instance) { continue }

        client.floating = rule.floating
        client.tags     = rule.tags
        monitor_idx     = rule.monitor
        break
    }

    if hints.res_class != nil do X.Free(cast(rawptr)hints.res_class)
    if hints.res_name  != nil do X.Free(cast(rawptr)hints.res_name)

    if monitor_idx == CLIENT_NONE do monitor_idx = g_monitor_idx
    if client.tags == {}          do client.tags = g_monitors[monitor_idx].tags
    return
}
