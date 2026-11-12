-- Caps Lock sending F18, which tide takes as Compose (SPEC.md §10), set by
-- tide itself when macos.json's keyboard.capsLockCompose is on, and taken
-- out again when it's turned off. Off unless turned on: it changes a key
-- outside window management. macOS keeps one key mapping for
-- every keyboard (hidutil's UserKeyMapping), so tide adds Caps Lock's to
-- what's there, keeping, say, setup-macos's modifier rotation, and sets it
-- again as it starts and after a wake or a keyboard plugged in: the
-- mapping doesn't survive a restart. One that already maps Caps Lock,
-- to F18 or anything else, is yours and left alone. Pure Lua: running
-- hidutil is the caller's.

local M = {}

M.HIDUTIL = "/usr/bin/hidutil"
-- The setting, in macos.json and macos.local.json (macprefs.lua).
M.SETTING = "keyboard.capsLockCompose"
-- HID usage IDs: page 7 (keyboard), Caps Lock 0x39 and F18 0x6D.
M.CAPS_LOCK = 0x700000039
M.F18 = 0x70000006D
-- The PC keyboard type (macos.json's keyboard.type "pc"): the three keys
-- left of the space bar, Ctrl, Win and Alt, act as Command, Option and
-- Control, so Ctrl+C copies as on Linux; the right side the same. A PC
-- keyboard's Ctrl, Win and Alt are left Control (E0), Command (E3) and
-- Option (E2); a Mac keyboard's control, option and command are swapped
-- into those first, by tide's Karabiner rule (karabiner.lua).
M.TYPE = "keyboard.type"
-- The entries tide added, in hs.settings, so a reload takes out only those.
M.OWNED_KEY = "tide.keymap_owned"
M.ROTATION = {
    { src = 0x7000000E0, dst = 0x7000000E3 },
    { src = 0x7000000E3, dst = 0x7000000E2 },
    { src = 0x7000000E2, dst = 0x7000000E0 },
    { src = 0x7000000E4, dst = 0x7000000E7 },
    { src = 0x7000000E7, dst = 0x7000000E6 },
    { src = 0x7000000E6, dst = 0x7000000E4 },
}

-- hidutil's `property --get UserKeyMapping` output as a list of
-- { src, dst }, or nil and why. It prints "(null)" for none, or an
-- NSArray's description: entries of HIDKeyboardModifierMappingSrc and
-- HIDKeyboardModifierMappingDst, in decimal, in either order.
function M.parse(out)
    if type(out) ~= "string" then
        return nil, "no output"
    end
    local text = out:match("^%s*(.-)%s*$")
    if text == "" or text == "(null)" then
        return {}
    end
    if not text:match("^%(") then
        return nil, "not a list: " .. text:sub(1, 80)
    end
    local list = {}
    for entry in text:gmatch("{(.-)}") do
        local src = entry:match("HIDKeyboardModifierMappingSrc%s*=%s*(%d+)")
        local dst = entry:match("HIDKeyboardModifierMappingDst%s*=%s*(%d+)")
        if not src or not dst then
            return nil, "an entry without a source and destination: " .. entry:gsub("%s+", " ")
        end
        list[#list + 1] = { src = math.tointeger(tonumber(src)), dst = math.tointeger(tonumber(dst)) }
    end
    return list
end

-- The mapping with Caps Lock sending F18 added, or nil when there's
-- nothing to do: Caps Lock is mapped already.
function M.with_compose(list)
    for _, m in ipairs(list) do
        if m.src == M.CAPS_LOCK then
            return nil
        end
    end
    local out = {}
    for i, m in ipairs(list) do
        out[i] = m
    end
    out[#out + 1] = { src = M.CAPS_LOCK, dst = M.F18 }
    return out
end

-- The mapping without Caps Lock sending F18, or nil when there's nothing
-- to do: Caps Lock isn't mapped, or is mapped to something else, which is
-- yours.
function M.without_compose(list)
    local out, found = {}, false
    for _, m in ipairs(list) do
        if m.src == M.CAPS_LOCK and m.dst == M.F18 then
            found = true
        else
            out[#out + 1] = m
        end
    end
    return found and out or nil
end

-- `list` as the JSON `hidutil property --set` takes, in hex as Apple's
-- examples write it.
function M.json(list)
    local parts = {}
    for i, m in ipairs(list) do
        parts[i] = string.format('{"HIDKeyboardModifierMappingSrc":0x%X,"HIDKeyboardModifierMappingDst":0x%X}',
            m.src, m.dst)
    end
    return '{"UserKeyMapping":[' .. table.concat(parts, ",") .. "]}"
end

-- Reads the mapping with `run(path, args, done(code, err, out))` and sets
-- it to `change(list)`, unless that's nil. `log` says what went wrong, and
-- `done(changed)`, if given, is called at the end.
local function update(run, log, change, done)
    done = done or function() end
    local started = run(M.HIDUTIL, { "property", "--get", "UserKeyMapping" }, function(code, err, out)
        if code ~= 0 then
            log("capslock: hidutil --get exited " .. tostring(code) .. ": " .. tostring(err))
            return done(false)
        end
        local list, why = M.parse(out)
        if not list then
            log("capslock: couldn't read the key mapping, so Caps Lock is left as it is: " .. why)
            return done(false)
        end
        local new = change(list)
        if not new then
            return done(false)
        end
        local ok = run(M.HIDUTIL, { "property", "--set", M.json(new) }, function(scode, serr)
            if scode ~= 0 then
                log("capslock: hidutil --set exited " .. tostring(scode) .. ": " .. tostring(serr))
                return done(false)
            end
            done(true)
        end)
        if not ok then
            log("capslock: couldn't run " .. M.HIDUTIL .. " to set the key mapping")
            done(false)
        end
    end)
    if not started then
        log("capslock: couldn't run " .. M.HIDUTIL .. " to read the key mapping")
        done(false)
    end
end

-- Adds Caps Lock sending F18 to the mapping, when Caps Lock isn't in it.
function M.apply(run, log, done)
    update(run, log, M.with_compose, done)
end

-- Takes Caps Lock sending F18 out of the mapping, leaving the rest.
function M.remove(run, log, done)
    update(run, log, M.without_compose, done)
end

-- An entry as a key for the set of the ones tide added.
local function key(m)
    return string.format("%X:%X", m.src, m.dst)
end
M.key = key

-- `list` with what tide manages brought to `want` ({ caps, pc }): each
-- wanted entry added where its key isn't mapped yet, and each unwanted one
-- that tide added (`owned`, a set of M.key) taken out, so a mapping that
-- was never tide's is left alone, the same one included. Returns the new
-- list, the entries added and the ones taken out, or nil when nothing
-- changes.
function M.desired(list, want, owned)
    local wanted = {}
    if want.caps then
        wanted[#wanted + 1] = { src = M.CAPS_LOCK, dst = M.F18 }
    end
    if want.pc then
        for _, e in ipairs(M.ROTATION) do
            wanted[#wanted + 1] = e
        end
    end
    local is_wanted = {}
    for _, e in ipairs(wanted) do
        is_wanted[key(e)] = true
    end
    local out, added, dropped = {}, {}, {}
    for _, m in ipairs(list) do
        if owned[key(m)] and not is_wanted[key(m)] then
            dropped[#dropped + 1] = m
        else
            out[#out + 1] = m
        end
    end
    for _, e in ipairs(wanted) do
        local mapped = false
        for _, m in ipairs(out) do
            if m.src == e.src then
                mapped = true
            end
        end
        if not mapped then
            out[#out + 1] = { src = e.src, dst = e.dst }
            added[#added + 1] = e
        end
    end
    if #added == 0 and #dropped == 0 then
        return nil
    end
    return out, added, dropped
end

-- The mapping brought to the settings, `want` ({ caps, pc }): what's on
-- added each time, as tide starts, after a wake and as the files change,
-- since the mapping doesn't last a restart; what's turned off taken out,
-- where tide added it. `state` keeps `owned`, the entries tide added, given
-- to `state.save` after each change so a reload keeps them; and one change
-- runs at a time, a later `want` waiting for it, so an earlier one can't
-- write over it.
function M.follow(state, want, run, log)
    state.owned = state.owned or {}
    state.want = want
    if state.busy then
        state.again = true
        return
    end
    state.busy = true
    local function go()
        local w = state.want
        local added, dropped
        update(run, log, function(list)
            local out, a, d = M.desired(list, w, state.owned)
            added, dropped = a, d
            return out
        end, function(changed)
            if changed then
                for _, e in ipairs(added) do
                    state.owned[key(e)] = true
                end
                for _, e in ipairs(dropped) do
                    state.owned[key(e)] = nil
                end
                if state.save then
                    state.save(state.owned)
                end
            end
            if state.again then
                state.again = false
                go()
            else
                state.busy = false
            end
        end)
    end
    go()
end

return M
