-- Your keys for tide's named bindings (SPEC.md §15), as tide's Keyboard
-- shortcuts keep them (tide SPEC.md §16): keys.json and keys.local.json in
-- tide's folder, { "preset": "dwm", "keys": { "terminal": ["SUPER + D"],
-- "lock": [] } }, the preset you started from (keymaps.lua) and a
-- binding's keys in place of the preset's, none turning it off. One file
-- serves both desktops, so keys are Hyprland's strings, "SUPER + SHIFT +
-- Return", which this file turns into keys.lua's { key, shift } and back.
-- A Mac binding is Super plus a key, with Shift or not: keys with Ctrl or
-- Alt too, or without Super, can't be one here, and are said so.

local keymaps = require("tide.keymaps")
local mute = require("tide.mute")

local M = {}

M.FILE = "keys.json"
M.LOCAL_FILE = "keys.local.json"
-- As tide's MAX_KEYS and conf's MAX_KEYS_PER_BIND.
M.MAX_KEYS = 8
M.NO_KEYS = { preset = "tide", keys = {} }

-- XKB's key names, as Hyprland's strings give them, and Hammerspoon's for
-- the same key. A PC keyboard's Insert arrives as Help and its Print as
-- F13 (SPEC.md §7.2).
local XKB_TO_HS = {
    Return = "return", Space = "space", Tab = "tab", BackSpace = "delete", Delete = "forwarddelete",
    Insert = "help", Print = "f13", Page_Up = "pageup", Prior = "pageup", Page_Down = "pagedown",
    Next = "pagedown", Home = "home", End = "end", Up = "up", Down = "down", Left = "left", Right = "right",
    Escape = "escape",
    period = ".", comma = ",", grave = "`", backslash = "\\", slash = "/", equal = "=", minus = "-",
    semicolon = ";", apostrophe = "'", bracketleft = "[", bracketright = "]",
}
local HS_TO_XKB = {}
for xkb, hs in pairs(XKB_TO_HS) do
    if xkb ~= "Prior" and xkb ~= "Next" then
        HS_TO_XKB[hs] = xkb
    end
end

-- A Hyprland key string as a Mac binding, { key, shift }, or nil and why.
function M.from_hypr(keys)
    local parts = {}
    for part in tostring(keys):gmatch("[^+]+") do
        part = part:match("^%s*(.-)%s*$")
        if part ~= "" then
            parts[#parts + 1] = part
        end
    end
    local key = table.remove(parts)
    if not key then
        return nil, "no key"
    end
    local super, shift, other = false, false, nil
    for _, m in ipairs(parts) do
        local u = m:upper()
        if u == "SUPER" or u == "MOD4" or u == "WIN" or u == "LOGO" or u == "META" then
            super = true
        elseif u == "SHIFT" then
            shift = true
        else
            other = other or m
        end
    end
    if not super then
        return nil, "a Mac binding needs Super"
    end
    if other then
        return nil, "a Mac binding is Super with Shift or not, so it can't hold " .. other
    end
    local hs_key = XKB_TO_HS[key]
    if not hs_key then
        local f = key:match("^[Ff](%d+)$")
        if f then
            hs_key = "f" .. f
        elseif key:match("^%w$") then
            hs_key = key:lower()
        else
            return nil, "no Mac key is called " .. key
        end
    end
    return { key = hs_key, shift = shift }
end

-- A Mac binding's keys as Hyprland's string: "SUPER + SHIFT + Return".
function M.to_hypr(key, shift)
    local name = HS_TO_XKB[key]
    if not name then
        local f = key:match("^f(%d+)$")
        name = f and ("F" .. f) or (#key == 1 and key:upper() or key)
    end
    return "SUPER + " .. (shift and "SHIFT + " or "") .. name
end

-- A key pressed while a shortcut records (keys_hs.lua): `flags` as
-- hs.eventtap gives them, `key` Hammerspoon's name for it on this layout,
-- `karabiner` whether Super is Karabiner's chord or plain Option (keys.lua).
-- Returns { keys } as Hyprland's string, { cancel } for Esc, { wait } for
-- the Super tap, or { error }.
function M.recorded(flags, key, karabiner)
    flags = flags or {}
    local super
    if karabiner then
        super = flags.ctrl and flags.alt and flags.cmd
    else
        super = flags.alt and not flags.ctrl and not flags.cmd
    end
    if key == "escape" and not super then
        return { cancel = true }
    end
    if not key or key == "" then
        return { error = "that key can't be a shortcut" }
    end
    if super and key == "f20" then
        -- Karabiner's Super tap, on its way to a chord.
        return { wait = true }
    end
    if not super then
        return { error = "hold Super with it" }
    end
    -- Karabiner sends Win+Backspace as F19 (keys.lua's close).
    if karabiner and key == "f19" then
        key = "delete"
    end
    if key == "escape" then
        return { error = "Esc stops recording, so it can't be a shortcut" }
    end
    return { keys = M.to_hypr(key, flags.shift and true or false) }
end

-- Two bindings' keys as one string to compare.
local function chord(b)
    return (b.shift and "shift+" or "") .. b.key
end

-- Two lists of Hyprland strings are the same keys, in order.
local function same_keys(a, b)
    if #a ~= #b then
        return false
    end
    for i = 1, #a do
        local x, y = M.from_hypr(a[i]), M.from_hypr(b[i])
        if not x or not y or chord(x) ~= chord(y) then
            return false
        end
    end
    return true
end

local function is_name(n)
    return type(n) == "string" and n:match("^[a-z][a-z0-9_]*$") ~= nil
end

-- One file's settings, from its decoded JSON: { preset, keys }, each nil
-- when the file doesn't set it, or nil and why.
function M.parse(v, file)
    if type(v) ~= "table" or (next(v) ~= nil and mute.is_list(v)) then
        return nil, file .. ": not a JSON object"
    end
    for k in pairs(v) do
        if k ~= "keys" and k ~= "preset" then
            return nil, file .. ": unknown setting " .. tostring(k)
        end
    end
    local out = {}
    if v.preset ~= nil then
        if type(v.preset) ~= "string" or not keymaps.PRESETS[v.preset] then
            return nil, file .. ": preset should be one of " .. table.concat(keymaps.NAMES, ", ")
        end
        out.preset = v.preset
    end
    if v.keys ~= nil then
        if type(v.keys) ~= "table" or (next(v.keys) ~= nil and mute.is_list(v.keys)) then
            return nil, file .. ": keys should be an object of names"
        end
        out.keys = {}
        for name, list in pairs(v.keys) do
            if not is_name(name) then
                return nil, file .. ": " .. tostring(name) .. " isn't a binding's name"
            end
            if type(list) ~= "table" or (next(list) ~= nil and not mute.is_list(list)) then
                return nil, file .. ": " .. name .. " should list its keys"
            end
            if #list > M.MAX_KEYS then
                return nil, string.format("%s: %s lists %d keys, more than %d", file, name, #list, M.MAX_KEYS)
            end
            local keys = {}
            for i, k in ipairs(list) do
                if type(k) ~= "string" or not k:match("%S") or k:match('[%c"\\]') then
                    return nil, string.format("%s: %s[%d] isn't keys", file, name, i)
                end
                keys[i] = k:match("^%s*(.-)%s*$")
            end
            out.keys[name] = keys
        end
    end
    return out
end

-- Your keys from both files, as tide reads them: keys.local.json's keys
-- replace keys.json's whole, and so does its preset. { preset, keys }, or
-- nil and why.
function M.load(dir, read, decode)
    local state = { preset = "tide", keys = {} }
    for _, name in ipairs({ M.FILE, M.LOCAL_FILE }) do
        local text = read(dir .. "/" .. name)
        if text and text:match("%S") then
            local v, err = M.parse(decode(text), name)
            if not v then
                return nil, err
            end
            state = { preset = v.preset or state.preset, keys = v.keys or state.keys }
        end
    end
    return state
end

-- A preset's keys a Mac can bind, by name. One whose keys it can't
-- (bspwm's Super+Alt+Q) is left out, keeping tide's keys, rather than
-- turning the binding off.
function M.preset_keys(preset)
    local out = {}
    for name, keys in pairs(keymaps.PRESETS[preset].keys) do
        local ok = {}
        for _, k in ipairs(keys) do
            if M.from_hypr(k) then
                ok[#ok + 1] = k
            end
        end
        if #ok > 0 then
            out[name] = ok
        end
    end
    return out
end

-- The keys to bind, by name: the preset's, with yours over them.
function M.merged(state)
    local out = {}
    for name, keys in pairs(M.preset_keys(state.preset)) do
        out[name] = keys
    end
    for name, keys in pairs(state.keys) do
        out[name] = keys
    end
    return out
end

-- keys.lua's map with `state`'s keys, and what couldn't be: a named
-- binding given keys there takes them first, in the map's place of its
-- first entry, so a default that wants the same keys gives them up, as
-- conf does. Keys a Mac can't bind, an unnamed binding has, or another
-- given binding has, are left out, each said in `problems`. A name the map
-- doesn't have, for a binding only Linux has, is left alone.
function M.apply(map, state)
    local given = M.merged(state)
    local problems = {}
    local fixed, by_name, first = {}, {}, {}
    for i, b in ipairs(map) do
        if b.name then
            by_name[b.name] = by_name[b.name] or {}
            table.insert(by_name[b.name], b)
            first[b.name] = first[b.name] or i
        elseif b.key then
            fixed[chord(b)] = true
        end
    end
    local taken = {}
    local replacement = {}
    -- Given keys: yours, then the preset's, each in the map's order, so
    -- yours take keys from the preset's and the first to want keys has
    -- them.
    local passes = {}
    for i, b in ipairs(map) do
        if b.name and first[b.name] == i and given[b.name] then
            table.insert(passes, { i = i, b = b, yours = state.keys[b.name] ~= nil })
        end
    end
    table.sort(passes, function(x, y)
        if x.yours ~= y.yours then
            return x.yours
        end
        return x.i < y.i
    end)
    for _, p in ipairs(passes) do
        local b, name = p.b, p.b.name
        do
            local out = {}
            for _, k in ipairs(given[name]) do
                local mac, why = M.from_hypr(k)
                if not mac then
                    problems[#problems + 1] = name .. " can't have " .. k .. ": " .. why
                elseif fixed[chord(mac)] or taken[chord(mac)] then
                    -- A preset's key that yours took is no problem.
                    if p.yours then
                        problems[#problems + 1] = name .. " can't have " .. k .. ", which "
                            .. (taken[chord(mac)] or "something that can't change") .. " has"
                    end
                else
                    taken[chord(mac)] = name
                    local copy = {}
                    for kk, v in pairs(b) do
                        copy[kk] = v
                    end
                    copy.key, copy.shift, copy.karabiner_key = mac.key, mac.shift, nil
                    -- Backspace as Karabiner sends it (keys.lua's close).
                    if mac.key == "delete" then
                        copy.karabiner_key = "f19"
                    end
                    out[#out + 1] = copy
                end
            end
            replacement[name] = out
        end
    end
    local result = {}
    for i, b in ipairs(map) do
        local name = b.name
        if not name then
            result[#result + 1] = b
        elseif replacement[name] then
            if first[name] == i then
                for _, r in ipairs(replacement[name]) do
                    result[#result + 1] = r
                end
            end
        elseif b.key and not taken[chord(b)] then
            result[#result + 1] = b
        end
    end
    return result, problems
end

-- Each named binding's keys before yours, by name, as Hyprland strings:
-- the preset's for one it names, else the map's own, less the keys the
-- preset gives others here (a name only Linux has takes nothing, as
-- M.apply binds nothing for it).
function M.preset_defaults(map, preset)
    local given = M.preset_keys(preset)
    local here = {}
    for _, b in ipairs(map) do
        if b.name then
            here[b.name] = true
        end
    end
    local taken = {}
    for name, list in pairs(given) do
        for _, k in ipairs(here[name] and list or {}) do
            local mac = M.from_hypr(k)
            if mac then
                taken[chord(mac)] = true
            end
        end
    end
    local out = {}
    for _, b in ipairs(map) do
        if b.name then
            if given[b.name] then
                out[b.name] = given[b.name]
            else
                out[b.name] = out[b.name] or {}
                if b.key and not taken[chord(b)] then
                    table.insert(out[b.name], M.to_hypr(b.key, b.shift))
                end
            end
        end
    end
    return out
end

-- The settings window's named rows, in the map's order: { name, does,
-- keys (Hyprland strings, as bound), changed (from the preset's) }.
-- `applied` is M.apply's map, `does` keys.does.
function M.rows(map, applied, state, does)
    local defaults = M.preset_defaults(map, state.preset)
    local now, order, what = {}, {}, {}
    for _, b in ipairs(map) do
        if b.name and not what[b.name] then
            order[#order + 1] = b.name
            what[b.name] = does(b)
            now[b.name] = {}
        end
    end
    for _, b in ipairs(applied) do
        if b.name then
            table.insert(now[b.name], M.to_hypr(b.key, b.shift))
        end
    end
    local out = {}
    for _, name in ipairs(order) do
        out[#out + 1] = {
            name = name,
            does = what[name],
            keys = now[name],
            changed = not same_keys(now[name], defaults[name]),
        }
    end
    return out
end

-- The edits, each on a state and returning the new one, or nil and why,
-- or nil and { clash = { name, does } }. `rows` is M.rows', the keys as
-- bound now.
local function set_or_default(keys, name, defaults, list)
    if same_keys(list, defaults[name] or {}) then
        keys[name] = nil
    else
        keys[name] = list
    end
end

local function copy_keys(state)
    local keys = {}
    for k, v in pairs(state.keys) do
        keys[k] = v
    end
    return keys
end

-- `name` given `keys` alone. Keys another named binding has are a clash,
-- unless `swap`, which gives that one `name`'s old keys. `fixed_chords`
-- are keys.lua's unnamed bindings' keys, as "shift+key".
function M.with_keys(state, map, rows, name, keys, swap, fixed_chords)
    local target
    for _, r in ipairs(rows) do
        if r.name == name then
            target = r
        end
    end
    if not target then
        return nil, "no shortcut is called " .. tostring(name)
    end
    local mac, why = M.from_hypr(keys)
    if not mac then
        return nil, why
    end
    if (fixed_chords or {})[chord(mac)] then
        return nil, "those keys can't change, so they can't be " .. target.does
    end
    local defaults = M.preset_defaults(map, state.preset)
    local out = copy_keys(state)
    for _, r in ipairs(rows) do
        if r.name ~= name then
            for _, k in ipairs(r.keys) do
                local other = M.from_hypr(k)
                if other and chord(other) == chord(mac) then
                    if not swap then
                        return nil, { clash = { name = r.name, does = r.does } }
                    end
                    local given = {}
                    for _, list in ipairs({ r.keys, target.keys }) do
                        for _, kk in ipairs(list) do
                            local x = M.from_hypr(kk)
                            if x and chord(x) ~= chord(mac) and #given < M.MAX_KEYS then
                                given[#given + 1] = kk
                            end
                        end
                    end
                    set_or_default(out, r.name, defaults, given)
                end
            end
        end
    end
    set_or_default(out, name, defaults, { keys })
    return { preset = state.preset, keys = out }
end

-- `name` back at its preset's keys. Another binding you gave those keys,
-- by a swap say, gives them up, as M.apply binds yours first; one left
-- with none goes back to its own preset's, so Reset undoes a swap.
function M.with_default(state, name, map)
    local keys = copy_keys(state)
    keys[name] = nil
    local defaults = M.preset_defaults(map or {}, state.preset)
    local wanted = {}
    for _, k in ipairs(defaults[name] or {}) do
        local mac = M.from_hypr(k)
        if mac then
            wanted[chord(mac)] = true
        end
    end
    local others = {}
    for other in pairs(keys) do
        others[#others + 1] = other
    end
    for _, other in ipairs(others) do
        local list, kept, hit = keys[other], {}, false
        for _, k in ipairs(list) do
            local mac = M.from_hypr(k)
            if mac and wanted[chord(mac)] then
                hit = true
            else
                kept[#kept + 1] = k
            end
        end
        if hit then
            if #kept == 0 then
                keys[other] = nil
            else
                set_or_default(keys, other, defaults, kept)
            end
        end
    end
    return { preset = state.preset, keys = keys }
end

function M.with_off(state, name)
    local keys = copy_keys(state)
    keys[name] = {}
    return { preset = state.preset, keys = keys }
end

function M.with_preset(_, preset)
    if not keymaps.PRESETS[preset] then
        return nil, "no preset is called " .. tostring(preset)
    end
    return { preset = preset, keys = {} }
end

-- keys.local.json's text for `state`, keeping any other key the file has,
-- with the preset always, so tide's own overrides another in keys.json.
function M.text(state, old, quote)
    local names = {}
    for name in pairs(state.keys) do
        names[#names + 1] = name
    end
    table.sort(names)
    local rows = {}
    for _, name in ipairs(names) do
        local list = {}
        for i, k in ipairs(state.keys[name]) do
            list[i] = quote(k)
        end
        rows[#rows + 1] = "    " .. quote(name) .. ": [" .. table.concat(list, ", ") .. "]"
    end
    local keys = #rows == 0 and "{}" or ("{\n" .. table.concat(rows, ",\n") .. "\n  }")
    local parts = { '  "preset": ' .. quote(state.preset), '  "keys": ' .. keys }
    -- Keys the file has that this one doesn't know are kept, as given.
    local others = {}
    for k in pairs(old or {}) do
        if k ~= "preset" and k ~= "keys" then
            others[#others + 1] = k
        end
    end
    if #others > 0 then
        return nil, M.LOCAL_FILE .. " has settings tide doesn't know (" .. table.concat(others, ", ")
            .. "); fix the file by hand"
    end
    return "{\n" .. table.concat(parts, ",\n") .. "\n}\n"
end

-- Apply `fn`, one of the edits, to the keys in effect, and write
-- keys.local.json whole. Returns the new state, or nil and why (a string,
-- or { clash }), writing nothing.
function M.edit(dir, read, decode, quote, write, fn)
    local state, err = M.load(dir, read, decode)
    if not state then
        return nil, err .. ". Fix the file to change the shortcuts here"
    end
    local new, why = fn(state)
    if not new then
        return nil, why
    end
    local path = dir .. "/" .. M.LOCAL_FILE
    local raw = read(path)
    local old = raw and raw:match("%S") and decode(raw) or {}
    local text, terr = M.text(new, old, quote)
    if not text then
        return nil, terr
    end
    local ok, werr = write(path, text)
    if not ok then
        return nil, "couldn't write " .. path .. ": " .. tostring(werr)
    end
    return new
end

return M
