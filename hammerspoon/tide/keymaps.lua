-- Other tiling window managers' default keys, for the settings window's
-- Start from (SPEC.md §15): tide's shell/lib/keymaps.mjs as Lua, each
-- preset mapping conf's binding names to Hyprland's key strings, with
-- Super as the modifier. ci/check_keymaps.lua, which make check-tide
-- runs, compares it with tide's file.

local M = {}

M.NAMES = { "tide", "dwm", "i3", "sway", "xmonad", "bspwm" }

M.PRESETS = {
    tide = {
        label = "tide",
        keys = {
        },
    },
    dwm = {
        label = "dwm",
        keys = {
            launcher = { "SUPER + P" },
            terminal = { "SUPER + SHIFT + Return" },
            focus_down = { "SUPER + J" },
            focus_up = { "SUPER + K" },
            add_master = { "SUPER + I" },
            remove_master = { "SUPER + D" },
            shrink_master = { "SUPER + H" },
            grow_master = { "SUPER + L" },
            swap_master = { "SUPER + Return" },
            home_or_back = { "SUPER + Tab" },
            close = { "SUPER + SHIFT + C" },
            monocle = { "SUPER + M" },
            last_layout = { "SUPER + Space" },
            float = { "SUPER + SHIFT + Space" },
            focus_left = { "SUPER + comma" },
            focus_right = { "SUPER + period" },
            move_left = { "SUPER + SHIFT + comma" },
            move_right = { "SUPER + SHIFT + period" },
            quit = { "SUPER + SHIFT + Q" },
        },
    },
    i3 = {
        label = "i3",
        keys = {
            terminal = { "SUPER + Return" },
            launcher = { "SUPER + D" },
            close = { "SUPER + SHIFT + Q" },
            focus_left = { "SUPER + J", "SUPER + Left" },
            focus_below = { "SUPER + K", "SUPER + Down" },
            focus_above = { "SUPER + L", "SUPER + Up" },
            focus_right = { "SUPER + semicolon", "SUPER + Right" },
            move_left = { "SUPER + SHIFT + J", "SUPER + SHIFT + Left" },
            move_below = { "SUPER + SHIFT + K", "SUPER + SHIFT + Down" },
            move_above = { "SUPER + SHIFT + L", "SUPER + SHIFT + Up" },
            move_right = { "SUPER + SHIFT + semicolon", "SUPER + SHIFT + Right" },
            fullscreen = { "SUPER + F" },
            float = { "SUPER + SHIFT + Space" },
            monocle = { "SUPER + W" },
            next_layout = { "SUPER + E" },
            resize_mode = { "SUPER + R" },
            quit = { "SUPER + SHIFT + E" },
            reload = { "SUPER + SHIFT + C" },
        },
    },
    sway = {
        label = "sway",
        keys = {
            terminal = { "SUPER + Return" },
            launcher = { "SUPER + D" },
            close = { "SUPER + SHIFT + Q" },
            focus_left = { "SUPER + H", "SUPER + Left" },
            focus_below = { "SUPER + J", "SUPER + Down" },
            focus_above = { "SUPER + K", "SUPER + Up" },
            focus_right = { "SUPER + L", "SUPER + Right" },
            move_left = { "SUPER + SHIFT + H", "SUPER + SHIFT + Left" },
            move_below = { "SUPER + SHIFT + J", "SUPER + SHIFT + Down" },
            move_above = { "SUPER + SHIFT + K", "SUPER + SHIFT + Up" },
            move_right = { "SUPER + SHIFT + L", "SUPER + SHIFT + Right" },
            fullscreen = { "SUPER + F" },
            float = { "SUPER + SHIFT + Space" },
            monocle = { "SUPER + W" },
            next_layout = { "SUPER + E" },
            resize_mode = { "SUPER + R" },
            quit = { "SUPER + SHIFT + E" },
            reload = { "SUPER + SHIFT + C" },
        },
    },
    xmonad = {
        label = "xmonad",
        keys = {
            terminal = { "SUPER + SHIFT + Return" },
            launcher = { "SUPER + P" },
            close = { "SUPER + SHIFT + C" },
            next_layout = { "SUPER + Space" },
            focus_down = { "SUPER + J" },
            focus_up = { "SUPER + K" },
            swap_master = { "SUPER + Return" },
            move_down = { "SUPER + SHIFT + J" },
            move_up = { "SUPER + SHIFT + K" },
            shrink_master = { "SUPER + H" },
            grow_master = { "SUPER + L" },
            float = { "SUPER + T" },
            add_master = { "SUPER + comma" },
            remove_master = { "SUPER + period" },
            quit = { "SUPER + SHIFT + Q" },
            reload = { "SUPER + Q" },
        },
    },
    bspwm = {
        label = "bspwm",
        keys = {
            terminal = { "SUPER + Return" },
            launcher = { "SUPER + Space" },
            close = { "SUPER + W" },
            quit = { "SUPER + ALT + Q" },
            reload = { "SUPER + ALT + R" },
            monocle = { "SUPER + M" },
            float = { "SUPER + S" },
            fullscreen = { "SUPER + F" },
            focus_left = { "SUPER + H" },
            focus_below = { "SUPER + J" },
            focus_above = { "SUPER + K" },
            focus_right = { "SUPER + L" },
            move_left = { "SUPER + SHIFT + H" },
            move_below = { "SUPER + SHIFT + J" },
            move_above = { "SUPER + SHIFT + K" },
            move_right = { "SUPER + SHIFT + L" },
            swap_master = { "SUPER + G" },
            previous_workspace = { "SUPER + bracketleft" },
            next_workspace = { "SUPER + bracketright" },
        },
    },
}

return M
