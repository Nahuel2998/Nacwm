package nacwm

import "core:strings"
import "core:strconv"

g_ipc_command : strings.Builder

ipc_action :: proc(command : string) {
    start, ok := word_start(command)
    if !ok do return

    end := word_end(command, start)

    arg, has_arg := word_start(command, end)
    switch command[start:end] {
    case "rebirth":
        do_action(Rebirth{})

    case "thats":
        do_action(Thats{})

    case "view": if !has_arg do return
        tags := parse_tags(command, arg)
        do_action(View(tags))

    case "select": if !has_arg do return
        delta, ok_delta := strconv.parse_int(command[arg:], 10)
        if !ok_delta || delta == 0 do return
        do_action(Select{cast(i8)delta})

    case "swap": if !has_arg do return
        delta, ok_delta := strconv.parse_int(command[arg:], 10)
        if !ok_delta || delta == 0 do return
        do_action(Swap{cast(i8)delta})

    case "select-monitor": if !has_arg do return
        monitor_idx, ok_mon := strconv.parse_int(command[arg:], 10)
        if !ok_mon || monitor_idx < 0 do return
        do_action(Select_Monitor{monitor_idx})

    case "to-tag": if !has_arg do return
        tags := parse_tags(command, arg)
        do_action(To_Tag(tags))

    case "to-monitor": if !has_arg do return
        monitor_idx, ok_mon := strconv.parse_int(command[arg:], 10)
        if !ok_mon || monitor_idx < 0 do return
        do_action(To_Monitor{monitor_idx})

    case "float":
        do_action(Float{})

    case "center":
        do_action(Center{})

    case "shoot":
        unkindly := has_arg && command[arg] == '1'
        do_action(Shoot{unkindly})

    case "master-resize": if !has_arg do return
        delta, ok_delta := strconv.parse_f32(command[arg:])
        if !ok_delta || delta < -1 || delta > 1 do return
        do_action(Master_Resize{delta})
    }
}

@(private="file")
word_start :: proc(command : string, start := 0) -> (int, bool) {
    if start == len(command) do return -1, false

    i := start
    for command[i] == ' ' {
        i += 1
        if i == len(command) do return -1, false
    }
    return i, true
}

@(private="file")
word_end :: proc(command : string, start := 0) -> int {
    i := start
    for i < len(command) && command[i] != ' ' do i += 1
    return i
}

@(private="file")
parse_tags :: proc(command : string, arg : int) -> Tags {
    arg  := arg
    tags := Tags{}
    for t in ~(Tags{}) {
        if command[arg] == '1' do tags |= {t}
        arg += 1
        if arg == len(command) do break
    }
    return tags
}
