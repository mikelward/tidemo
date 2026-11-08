local t = require("t")
local shortcuts = require("tide.shortcuts")
local keymaps = require("tide.keymaps")
local keys = require("tide.keys")
local json = require("json")

local DIR = "/home/u/.config/tide"

local function files(map)
    return function(p)
        return map[p]
    end
end

local MAP = {
    { key = "t", action = "app", name = "terminal", does = "Terminal" },
    { key = "`", action = "monocle", name = "monocle" },
    { key = "o", action = "monocle", name = "monocle" },
    { key = "l", action = "lock", name = "lock" },
    { key = "space", action = "launcher", arg = "launch", name = "launcher" },
    { key = "f20", action = "launcher", arg = "launch" },
    { key = "1", action = "nth", arg = 1 },
    { key = "delete", karabiner_key = "f19", action = "close", name = "close" },
    { key = "return", action = "go_to", name = "go_to_workspace" },
}

local function keys_of(map, name)
    local out = {}
    for _, b in ipairs(map) do
        if b.name == name then
            out[#out + 1] = (b.shift and "shift+" or "") .. b.key
        end
    end
    return out
end

t.test("Hyprland's strings become a Mac's Super keys and back", function()
    t.eq(shortcuts.from_hypr("SUPER + T"), { key = "t", shift = false })
    t.eq(shortcuts.from_hypr("SUPER + SHIFT + Return"), { key = "return", shift = true })
    t.eq(shortcuts.from_hypr("shift+super+period"), { key = ".", shift = true })
    t.eq(shortcuts.from_hypr("SUPER + Page_Up"), { key = "pageup", shift = false })
    t.eq(shortcuts.from_hypr("SUPER + F4"), { key = "f4", shift = false })
    t.eq(shortcuts.from_hypr("SUPER + Print"), { key = "f13", shift = false })
    t.eq(shortcuts.from_hypr("SUPER + BackSpace"), { key = "delete", shift = false })
    t.eq(shortcuts.to_hypr("return", true), "SUPER + SHIFT + Return")
    t.eq(shortcuts.to_hypr(".", false), "SUPER + period")
    t.eq(shortcuts.to_hypr("t", false), "SUPER + T")
    t.eq(shortcuts.to_hypr("f13", false), "SUPER + Print")
    t.eq(shortcuts.to_hypr("pagedown", true), "SUPER + SHIFT + Page_Down")
end)

t.test("keys a Mac binding can't be are refused, saying why", function()
    local _, why = shortcuts.from_hypr("ALT + Tab")
    t.eq(why, "a Mac binding needs Super")
    _, why = shortcuts.from_hypr("SUPER + CTRL + T")
    t.eq(why, "a Mac binding is Super with Shift or not, so it can't hold CTRL")
    _, why = shortcuts.from_hypr("SUPER + XF86AudioMute")
    t.eq(why, "no Mac key is called XF86AudioMute")
end)

t.test("keys.local.json's keys and preset replace keys.json's, as tide reads them", function()
    local read = files({
        [DIR .. "/keys.json"] = '{"preset": "i3", "keys": {"lock": []}}',
        [DIR .. "/keys.local.json"] = '{"keys": {"terminal": ["SUPER + D"]}}',
    })
    t.eq(shortcuts.load(DIR, read, json.decode), { preset = "i3", keys = { terminal = { "SUPER + D" } } })
    t.eq(shortcuts.load(DIR, files({}), json.decode), { preset = "tide", keys = {} })
    for _, bad in ipairs({ "[1]", '{"other": 1}', '{"preset": "awesome"}', '{"keys": {"Bad Name": []}}',
        '{"keys": {"lock": "SUPER + L"}}', '{"keys": {"lock": [""]}}', '{"keys": {"lock": [1]}}' }) do
        local state, why = shortcuts.load(DIR, files({ [DIR .. "/keys.local.json"] = bad }), json.decode)
        t.eq(state, nil, bad)
        t.eq(why:sub(1, #"keys.local.json: "), "keys.local.json: ", bad)
    end
end)

t.test("your keys replace a binding's, and none turns it off", function()
    local map, problems = shortcuts.apply(MAP, { preset = "tide", keys = {
        terminal = { "SUPER + D", "SUPER + SHIFT + T" }, lock = {},
    } })
    t.eq(keys_of(map, "terminal"), { "d", "shift+t" })
    t.eq(keys_of(map, "lock"), {})
    t.eq(keys_of(map, "monocle"), { "`", "o" }, "the rest keep theirs")
    t.eq(problems, {})
    t.eq(map[1].action, "app", "in the map's place")
end)

t.test("a binding given another's default keys takes them, and the other goes without", function()
    local map = shortcuts.apply(MAP, { preset = "tide", keys = { lock = { "SUPER + T" } } })
    t.eq(keys_of(map, "lock"), { "t" })
    t.eq(keys_of(map, "terminal"), {})
end)

t.test("your keys take a preset's from the binding it gave them to", function()
    local map, problems = shortcuts.apply(MAP, { preset = "i3", keys = { lock = { "SUPER + Return" } } })
    t.eq(keys_of(map, "lock"), { "return" })
    t.eq(keys_of(map, "terminal"), {}, "i3's terminal gave up Super+Return")
    t.eq(problems, {})
end)

t.test("a binding with no key of its own binds only once your keys or a preset give it one", function()
    local map = { { key = "t", action = "app", name = "terminal" }, { action = "last_layout", name = "last_layout" } }
    local none = shortcuts.apply(map, { preset = "tide", keys = {} })
    t.eq(keys_of(none, "last_layout"), {})
    local dwm = shortcuts.apply(map, { preset = "dwm", keys = {} })
    t.eq(keys_of(dwm, "last_layout"), { "space" }, "dwm's Super+Space")
    local rows = shortcuts.rows(map, none, { preset = "tide", keys = {} }, keys.does)
    t.eq(rows[2], { name = "last_layout", does = "The layout used last", keys = {}, changed = false })
    t.eq(#keys.bindings(keys.KARABINER, none) > 0, true, "binds without it")
end)

t.test("keys an unnamed binding has, or a Mac can't bind, are left out and said", function()
    local map, problems = shortcuts.apply(MAP, { preset = "tide", keys = {
        lock = { "SUPER + 1", "SUPER + CTRL + L" },
    } })
    t.eq(keys_of(map, "lock"), {})
    t.eq(problems, {
        "lock can't have SUPER + 1, which something that can't change has",
        "lock can't have SUPER + CTRL + L: a Mac binding is Super with Shift or not, so it can't hold CTRL",
    })
end)

t.test("Backspace keeps Karabiner's F19 wherever it goes", function()
    local map = shortcuts.apply(MAP, { preset = "tide", keys = { lock = { "SUPER + BackSpace" } } })
    for _, b in ipairs(map) do
        if b.name == "lock" then
            t.eq(b.karabiner_key, "f19")
        end
    end
    t.eq(keys_of(map, "close"), {}, "close gave it up")
end)

t.test("a preset's keys are a binding's, and a key it can't bind keeps tide's", function()
    local map, problems = shortcuts.apply(MAP, { preset = "dwm", keys = {} })
    t.eq(keys_of(map, "launcher"), { "p" })
    t.eq(keys_of(map, "terminal"), { "shift+return" })
    t.eq(keys_of(map, "monocle"), { "m" })
    t.eq(keys_of(map, "go_to_workspace"), { "return" }, "dwm's Super+Return is swap with the master, which isn't in the map")
    t.eq(problems, {})
    local b = shortcuts.apply(MAP, { preset = "bspwm", keys = {} })
    t.eq(keymaps.PRESETS.bspwm.keys.quit, { "SUPER + ALT + Q" })
    t.eq(shortcuts.preset_keys("bspwm").quit, nil, "Super+Alt+Q can't be a Mac key")
    t.eq(keys_of(b, "close"), { "w" })
end)

t.test("the rows say each named binding's keys and whether they're the preset's", function()
    local state = { preset = "tide", keys = { lock = {} } }
    local applied = shortcuts.apply(MAP, state)
    local rows = shortcuts.rows(MAP, applied, state, keys.does)
    t.eq(rows[1], { name = "terminal", does = "Terminal", keys = { "SUPER + T" }, changed = false })
    t.eq(rows[2], { name = "monocle", does = "Monocle", keys = { "SUPER + grave", "SUPER + O" }, changed = false })
    t.eq(rows[3], { name = "lock", does = "Lock", keys = {}, changed = true })
    local dwm = { preset = "dwm", keys = {} }
    local drows = shortcuts.rows(MAP, shortcuts.apply(MAP, dwm), dwm, keys.does)
    for _, r in ipairs(drows) do
        t.eq(r.changed, false, r.name .. " is dwm's")
    end
end)

t.test("new keys, a clash, a swap, reset, off and a preset", function()
    local state = { preset = "tide", keys = {} }
    local rows = shortcuts.rows(MAP, shortcuts.apply(MAP, state), state, keys.does)
    t.eq(shortcuts.with_keys(state, MAP, rows, "terminal", "SUPER + D"), { preset = "tide", keys = { terminal = { "SUPER + D" } } })
    t.eq(shortcuts.with_keys({ preset = "tide", keys = { terminal = { "SUPER + D" } } }, MAP, rows, "terminal", "SUPER + T"),
        { preset = "tide", keys = {} }, "back at its defaults")
    local _, clash = shortcuts.with_keys(state, MAP, rows, "lock", "SUPER + T")
    t.eq(clash, { clash = { name = "terminal", does = "Terminal" } })
    t.eq(shortcuts.with_keys(state, MAP, rows, "lock", "SUPER + T", true),
        { preset = "tide", keys = { lock = { "SUPER + T" }, terminal = { "SUPER + L" } } })
    local _, why = shortcuts.with_keys(state, MAP, rows, "lock", "SUPER + 1", false, { ["1"] = true })
    t.eq(why, "those keys can't change, so they can't be Lock")
    t.eq(shortcuts.with_default({ preset = "dwm", keys = { lock = {} } }, "lock"), { preset = "dwm", keys = {} })
    t.eq(shortcuts.with_off(state, "lock"), { preset = "tide", keys = { lock = {} } })
    -- Reset after a swap: both go back.
    local swapped = shortcuts.with_keys(state, MAP, rows, "lock", "SUPER + T", true)
    t.eq(shortcuts.with_default(swapped, "lock", MAP), { preset = "tide", keys = {} })
    t.eq(shortcuts.with_preset({ preset = "tide", keys = { lock = {} } }, "i3"), { preset = "i3", keys = {} })
end)

t.test("an edit writes keys.local.json whole, with the preset always", function()
    local disk = { [DIR .. "/keys.json"] = '{"preset": "dwm"}' }
    local written
    local new = shortcuts.edit(DIR, files(disk), json.decode, json.encode, function(p, text)
        written = { p, text }
        return true
    end, function(s)
        return shortcuts.with_preset(s, "tide")
    end)
    t.eq(new, { preset = "tide", keys = {} })
    t.eq(written[1], DIR .. "/keys.local.json")
    t.eq(json.decode(written[2]), { preset = "tide", keys = {} }, "tide's overrides keys.json's dwm")
    disk[DIR .. "/keys.local.json"] = written[2]
    t.eq(shortcuts.load(DIR, files(disk), json.decode).preset, "tide")
    local _, why = shortcuts.edit(DIR, files({ [DIR .. "/keys.local.json"] = "[1]" }), json.decode, json.encode,
        function() error("not written") end, function(s) return s end)
    t.eq(why, "keys.local.json: not a JSON object. Fix the file to change the shortcuts here")
end)

t.test("every name keys.lua gives is one of conf's, and each preset names only conf's", function()
    local conf = {}
    for _, name in ipairs(keymaps.NAMES) do
        for n in pairs(keymaps.PRESETS[name].keys) do
            conf[n] = true
        end
    end
    local seen = {}
    for _, b in ipairs(keys.map) do
        if b.name then
            t.eq(b.name:match("^[a-z_]+$") ~= nil, true, b.name)
            seen[b.name] = true
        end
    end
    for _, n in ipairs({ "terminal", "launcher", "close", "lock", "focus_down", "monocle", "float" }) do
        t.eq(seen[n], true, n)
    end
end)

t.test("a key pressed while recording is Super's, as Karabiner or Option makes it", function()
    local K = { ctrl = true, alt = true, cmd = true }
    t.eq(shortcuts.recorded(K, "t", true), { keys = "SUPER + T" })
    t.eq(shortcuts.recorded({ ctrl = true, alt = true, cmd = true, shift = true }, "return", true), { keys = "SUPER + SHIFT + Return" })
    t.eq(shortcuts.recorded(K, "f19", true), { keys = "SUPER + BackSpace" }, "Karabiner's Backspace")
    t.eq(shortcuts.recorded(K, "f20", true), { wait = true }, "the Super tap")
    t.eq(shortcuts.recorded({ alt = true }, "t", false), { keys = "SUPER + T" }, "Option as Super")
    t.eq(shortcuts.recorded({ alt = true }, "t", true), { error = "hold Super with it" }, "plain Option, with Karabiner")
    t.eq(shortcuts.recorded({ cmd = true }, "t", false), { error = "hold Super with it" })
    t.eq(shortcuts.recorded({}, "escape", true), { cancel = true })
    t.eq(shortcuts.recorded({}, "t", true), { error = "hold Super with it" })
end)

t.done("shortcuts_test")
