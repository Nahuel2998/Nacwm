package nacwm

import X "../vendor/x11/xlib"

REFRESH_RATE :: 165
TAG_COUNT    :: 9

MASTER_FACTOR :: 0.6
GAPS_WIDTH    :: 2 * 5

BAR_STATUS_FALLBACK :: "Now | Today "

// Windows will always be raised below this
// NOTE: More correct would be to respect _NET_WM_STATE_ABOVE,
//       but I don't want to announce I support it given it's for a single window at a time
NOTIFICATION_CLASS :: "Dunst"
// If you know your notification daemon doesn't destroy the window,
// this may be set to true to not check for NOTIFICATION_CLASS on every window
NOTIFICATION_PRESERVE :: true

STYLE :: Style{
    border = {
        width = 2,
        color = {
            .Normal   = "dim gray",
            .Selected = "dodger blue",
        },
    },
    bar = {
        height = 22,
        font   = "Cousine 9",
        tags   = {
            .Active = { 0.50, 0.60, 0.80 },
            .Used   = { 0.37, 0.37, 0.50 },
            .Unused = { 0.25, 0.25, 0.30 },
        },
        status = { 0.80, 0.80, 0.90 },
        base   = { 0.15, 0.15, 0.20 },
    },
}

SCREENSHOT :: "/home/nar/.local/bin/screenshot"
RECORD     :: "/home/nar/.local/bin/record-screen-x11"
DMENU_FONT :: "monospace:size=10"

RULES := [?]Rule{
    // class        instance   title       Spawn_Rules{tags  floating  monitor       anchor}
    { {"vesktop",   "",        ""},                   {{1},  false,    1,            .None} },
    { {"steam_app", "",        ""},                   {{},   true,     MONITOR_NONE, .None} },
    { {"",          "Toolkit", "Picture-in-Picture"}, {{},   true,     MONITOR_NONE, .Top_Right} },
}

KEY_LEFT  : X.KeySym : .XK_m
KEY_DOWN  : X.KeySym : .XK_n
KEY_UP    : X.KeySym : .XK_e
KEY_RIGHT : X.KeySym : .XK_h

BINDINGS := [?]Keybind{
    { {.Mod4Mask},                           .XK_d,      Spawn{"dmenu_run", "-fn", DMENU_FONT, nil} },
    { {.Mod4Mask},                           .XK_Return, Spawn{"kitty",                        nil} },
    { {.Mod4Mask},                           .XK_l,      Spawn{"nemo",                         nil} },
    { {.Mod4Mask},                           .XK_w,      Spawn{"zen-browser",                  nil} },

    { {},              X.KeySym(XF86.AudioRaiseVolume),  Spawn{"wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", "5%+",    nil} },
    { {},              X.KeySym(XF86.AudioLowerVolume),  Spawn{"wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", "5%-",    nil} },
    { {},              X.KeySym(XF86.AudioMute),         Spawn{"wpctl", "set-mute",   "@DEFAULT_AUDIO_SINK@", "toggle", nil} },
    { {},              X.KeySym(XF86.AudioPlay),         Spawn{"playerctl", "play-pause", nil} },
    { {},              X.KeySym(XF86.AudioNext),         Spawn{"playerctl", "next",       nil} },
    { {},              X.KeySym(XF86.AudioPrev),         Spawn{"playerctl", "previous",   nil} },
    { {},              X.KeySym(XF86.MonBrightnessUp),   Spawn{"brightnessctl", "-c", "backlight", "set", "5%+", nil} },
    { {},              X.KeySym(XF86.MonBrightnessDown), Spawn{"brightnessctl", "-c", "backlight", "set", "5%-", nil} },

    { {},                                    .XK_Print,  Spawn{SCREENSHOT, nil} },
    { {           .ShiftMask},               .XK_Print,  Spawn{RECORD,     nil} },

    { {.Mod4Mask},                           .XK_1,      View{1} },
    { {.Mod4Mask},                           .XK_2,      View{2} },
    { {.Mod4Mask},                           .XK_3,      View{3} },
    { {.Mod4Mask},                           .XK_4,      View{4} },
    { {.Mod4Mask},                           .XK_5,      View{5} },
    { {.Mod4Mask},                           .XK_6,      View{6} },
    { {.Mod4Mask},                           .XK_7,      View{7} },
    { {.Mod4Mask},                           .XK_8,      View{8} },
    { {.Mod4Mask},                           .XK_9,      View{9} },
    { {.Mod4Mask},                           .XK_0,      ~View{} },

    { {.Mod4Mask,             .ControlMask}, .XK_1,      Toggle_View{1} },
    { {.Mod4Mask,             .ControlMask}, .XK_2,      Toggle_View{2} },
    { {.Mod4Mask,             .ControlMask}, .XK_3,      Toggle_View{3} },
    { {.Mod4Mask,             .ControlMask}, .XK_4,      Toggle_View{4} },
    { {.Mod4Mask,             .ControlMask}, .XK_5,      Toggle_View{5} },
    { {.Mod4Mask,             .ControlMask}, .XK_6,      Toggle_View{6} },
    { {.Mod4Mask,             .ControlMask}, .XK_7,      Toggle_View{7} },
    { {.Mod4Mask,             .ControlMask}, .XK_8,      Toggle_View{8} },
    { {.Mod4Mask,             .ControlMask}, .XK_9,      Toggle_View{9} },
    { {.Mod4Mask,             .ControlMask}, .XK_0,      ~Toggle_View{} },

    { {.Mod4Mask, .ShiftMask},               .XK_1,      To_Tag{1} },
    { {.Mod4Mask, .ShiftMask},               .XK_2,      To_Tag{2} },
    { {.Mod4Mask, .ShiftMask},               .XK_3,      To_Tag{3} },
    { {.Mod4Mask, .ShiftMask},               .XK_4,      To_Tag{4} },
    { {.Mod4Mask, .ShiftMask},               .XK_5,      To_Tag{5} },
    { {.Mod4Mask, .ShiftMask},               .XK_6,      To_Tag{6} },
    { {.Mod4Mask, .ShiftMask},               .XK_7,      To_Tag{7} },
    { {.Mod4Mask, .ShiftMask},               .XK_8,      To_Tag{8} },
    { {.Mod4Mask, .ShiftMask},               .XK_9,      To_Tag{9} },
    { {.Mod4Mask, .ShiftMask},               .XK_0,      ~To_Tag{} },

    { {.Mod4Mask, .ShiftMask, .ControlMask}, .XK_1,      Toggle_Tag{1} },
    { {.Mod4Mask, .ShiftMask, .ControlMask}, .XK_2,      Toggle_Tag{2} },
    { {.Mod4Mask, .ShiftMask, .ControlMask}, .XK_3,      Toggle_Tag{3} },
    { {.Mod4Mask, .ShiftMask, .ControlMask}, .XK_4,      Toggle_Tag{4} },
    { {.Mod4Mask, .ShiftMask, .ControlMask}, .XK_5,      Toggle_Tag{5} },
    { {.Mod4Mask, .ShiftMask, .ControlMask}, .XK_6,      Toggle_Tag{6} },
    { {.Mod4Mask, .ShiftMask, .ControlMask}, .XK_7,      Toggle_Tag{7} },
    { {.Mod4Mask, .ShiftMask, .ControlMask}, .XK_8,      Toggle_Tag{8} },
    { {.Mod4Mask, .ShiftMask, .ControlMask}, .XK_9,      Toggle_Tag{9} },
    { {.Mod4Mask, .ShiftMask, .ControlMask}, .XK_0,      ~Toggle_Tag{} },

    { {.Mod4Mask},                           KEY_DOWN,   Select{-1} },
    { {.Mod4Mask},                           KEY_UP,     Select{+1} },
    { {.Mod4Mask, .ShiftMask},               KEY_DOWN,   Swap{-1} },
    { {.Mod4Mask, .ShiftMask},               KEY_UP,     Swap{+1} },

    { {.Mod4Mask},                           KEY_LEFT,   Select_Monitor{1} },
    { {.Mod4Mask},                           KEY_RIGHT,  Select_Monitor{0} },
    { {.Mod4Mask, .ShiftMask},               KEY_LEFT,   To_Monitor{1} },
    { {.Mod4Mask, .ShiftMask},               KEY_RIGHT,  To_Monitor{0} },

    { {.Mod4Mask,             .ControlMask}, KEY_LEFT,   Master_Resize{-0.05} },
    { {.Mod4Mask,             .ControlMask}, KEY_RIGHT,  Master_Resize{+0.05} },

    { {.Mod4Mask},                           .XK_t,      Float{}  },
    { {.Mod4Mask},                           .XK_c,      Center{} },

    { {.Mod4Mask},                           .XK_q,      Shoot{}     },
    { {.Mod4Mask, .ShiftMask},               .XK_q,      Shoot{true} },

    { {.Mod4Mask},                           .XK_x,      Rebirth{} },
    { {.Mod4Mask, .ShiftMask},               .XK_x,      Thats{}   },
}

BUTTON_BINDINGS := [?]Buttonbind{
    { .Client, {.Mod4Mask},                           .Button1, Mouse_Move{}   },
    { .Client, {.Mod4Mask},                           .Button3, Mouse_Resize{} },
    { .Client, {.Mod4Mask,             .ControlMask}, .Button1, Anchor{.None} },
    { .Client, {.Mod4Mask,             .ControlMask}, .Button3, Mouse_Anchor{} },

    { .Tag,    {.Mod4Mask},                           .Button1, Mouse_View{}        },
    { .Tag,    {.Mod4Mask,             .ControlMask}, .Button1, Mouse_Toggle_View{} },
    { .Tag,    {.Mod4Mask, .ShiftMask},               .Button1, Mouse_To_Tag{}      },
    { .Tag,    {.Mod4Mask, .ShiftMask, .ControlMask}, .Button1, Mouse_Toggle_Tag{}  },
}
