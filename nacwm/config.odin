package nacwm

import X "vendor:x11/xlib"

REFRESH_RATE  :: 165
MASTER_FACTOR :: 0.6
GAPS_WIDTH    :: 2 * 5

STYLE :: Style{
    border = {
        width = 1,
        color = {
            .Normal   = "dim gray",
            .Selected = "red",
        }
    }
}

SCREENSHOT :: "/home/nar/.local/bin/screenshot"
RECORD     :: "/home/nar/.local/bin/record-screen-x11"

RULES := [?]Rule{
    // class       instance   title                 tags  floating  monitor
    { "vesktop",   "",        "",                   {1},  false,    1            },
    { "steam_app", "",        "",                   {},   true,     MONITOR_NONE },
    { "",          "Toolkit", "Picture-in-Picture", {},   true,     MONITOR_NONE },
}

BINDINGS := [?]Keybind{
    { {.Mod4Mask},               .XK_d,      Spawn{"dmenu_run",   nil} },
    { {.Mod4Mask},               .XK_Return, Spawn{"kitty",       nil} },
    { {.Mod4Mask},               .XK_l,      Spawn{"nemo",        nil} },
    { {.Mod4Mask},               .XK_w,      Spawn{"zen-browser", nil} },

    { {},  X.KeySym(XF86.AudioRaiseVolume),  Spawn{"wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", "5%+",    nil} },
    { {},  X.KeySym(XF86.AudioLowerVolume),  Spawn{"wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", "5%-",    nil} },
    { {},  X.KeySym(XF86.AudioMute),         Spawn{"wpctl", "set-mute",   "@DEFAULT_AUDIO_SINK@", "toggle", nil} },
    { {},  X.KeySym(XF86.AudioPlay),         Spawn{"playerctl", "play-pause", nil} },
    { {},  X.KeySym(XF86.AudioNext),         Spawn{"playerctl", "next",       nil} },
    { {},  X.KeySym(XF86.AudioPrev),         Spawn{"playerctl", "previous",   nil} },
    { {},  X.KeySym(XF86.MonBrightnessUp),   Spawn{"brightnessctl", "-c", "backlight", "set", "5%+", nil} },
    { {},  X.KeySym(XF86.MonBrightnessDown), Spawn{"brightnessctl", "-c", "backlight", "set", "5%-", nil} },

    { {},                        .XK_Print,  Spawn{SCREENSHOT,    nil} },
    { {.ShiftMask},              .XK_Print,  Spawn{RECORD,        nil} },

    { {.Mod4Mask},               .XK_1,      View{1} },
    { {.Mod4Mask},               .XK_2,      View{2} },
    { {.Mod4Mask},               .XK_3,      View{3} },
    { {.Mod4Mask},               .XK_4,      View{4} },
    { {.Mod4Mask},               .XK_5,      View{5} },
    { {.Mod4Mask},               .XK_6,      View{6} },
    { {.Mod4Mask},               .XK_7,      View{7} },
    { {.Mod4Mask},               .XK_8,      View{8} },
    { {.Mod4Mask},               .XK_9,      View{9} },
    { {.Mod4Mask},               .XK_0,      ~View{} },

    { {.Mod4Mask, .ShiftMask},   .XK_1,      ToTag{1} },
    { {.Mod4Mask, .ShiftMask},   .XK_2,      ToTag{2} },
    { {.Mod4Mask, .ShiftMask},   .XK_3,      ToTag{3} },
    { {.Mod4Mask, .ShiftMask},   .XK_4,      ToTag{4} },
    { {.Mod4Mask, .ShiftMask},   .XK_5,      ToTag{5} },
    { {.Mod4Mask, .ShiftMask},   .XK_6,      ToTag{6} },
    { {.Mod4Mask, .ShiftMask},   .XK_7,      ToTag{7} },
    { {.Mod4Mask, .ShiftMask},   .XK_8,      ToTag{8} },
    { {.Mod4Mask, .ShiftMask},   .XK_9,      ToTag{9} },
    { {.Mod4Mask, .ShiftMask},   .XK_0,      ~ToTag{} },

    { {.Mod4Mask},               .XK_n,      Select{-1} },
    { {.Mod4Mask},               .XK_e,      Select{+1} },

    { {.Mod4Mask},               .XK_m,      SelectMonitor{1} },
    { {.Mod4Mask},               .XK_h,      SelectMonitor{0} },
    { {.Mod4Mask, .ShiftMask},   .XK_m,      ToMonitor{1} },
    { {.Mod4Mask, .ShiftMask},   .XK_h,      ToMonitor{0} },

    { {.Mod4Mask, .ControlMask}, .XK_m,      MasterResize{-0.05} },
    { {.Mod4Mask, .ControlMask}, .XK_h,      MasterResize{+0.05} },

    { {.Mod4Mask},               .XK_t,      Float{} },

    { {.Mod4Mask},               .XK_q,      Shoot{}     },
    { {.Mod4Mask, .ShiftMask},   .XK_q,      Shoot{true} },

    { {.Mod4Mask},               .XK_x,      Rebirth{} },
    { {.Mod4Mask, .ShiftMask},   .XK_x,      Thats{}   },
}

BUTTON_BINDINGS := [?]Buttonbind{
    { .Client, {.Mod4Mask}, .Button1, MouseMove{}   },
    { .Client, {.Mod4Mask}, .Button3, MouseResize{} },
}

/*
static const Key keys[] = {
    /* modifier                     key        function        argument */
    { MODKEY|ShiftMask,             XK_n,      zoom,           {0} },
    { MODKEY|ShiftMask,             XK_e,      zoom,           {0} },
*/

/*
    { ClkTagBar,            0,              Button1,        view,           {0} },
    { ClkTagBar,            0,              Button3,        toggleview,     {0} },
    { ClkTagBar,            MODKEY,         Button1,        tag,            {0} },
    { ClkTagBar,            MODKEY,         Button3,        toggletag,      {0} },
*/
