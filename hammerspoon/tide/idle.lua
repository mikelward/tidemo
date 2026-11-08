-- tide's idle timeline on the Mac (SPEC.md §10; tide SPEC.md §10, §16):
-- after so long with no input, dim the screens, lock, turn the displays
-- off, and suspend on battery (or on AC too, if set), from tide's
-- idle.json and idle.local.json, read as tide's idle module reads them.
-- With nothing set in either, macOS's own Lock Screen settings alone time
-- it. Pure Lua: reading the idle time, and acting, are idle_hs.lua's.

local M = {}

M.SHARED_FILE = "idle.json"
M.LOCAL_FILE = "idle.local.json"

-- The steps, in the timeline's order, and the switch, as tide names them.
M.STEPS = { "dim", "lock", "displaysOff", "suspend" }
M.SWITCHES = { "suspendOnAC" }

-- tide's DEFAULT_IDLE.
M.DEFAULTS = { dim = 150, lock = 300, displaysOff = 330, suspend = 1800, suspendOnAC = false }

local KNOWN = {}
for _, k in ipairs(M.STEPS) do
    KNOWN[k] = "step"
end
for _, k in ipairs(M.SWITCHES) do
    KNOWN[k] = "switch"
end

-- One file's settings, as tide's parseIdle takes them, or nil and why, and
-- how many it sets.
local function parse(text, decode)
    local ok, t = pcall(decode, text)
    if not ok or type(t) ~= "table" or t[1] ~= nil then
        return nil, "expected an object of dim, lock, displaysOff, suspend, suspendOnAC"
    end
    local out, n = {}, 0
    for k, v in pairs(t) do
        if not KNOWN[k] then
            return nil, string.format('unknown setting "%s"; expected dim, lock, displaysOff, suspend, suspendOnAC', k)
        elseif KNOWN[k] == "switch" then
            if type(v) ~= "boolean" then
                return nil, k .. " must be true or false"
            end
        elseif type(v) ~= "number" or v ~= math.floor(v) or v <= 0 then
            return nil, k .. " must be a whole number of seconds above 0"
        end
        out[k] = v
        n = n + 1
    end
    return out, n
end

-- The timings from the two files' texts (nil for one that isn't there),
-- the local one's over the shared one's, over tide's defaults: { chosen,
-- idle, errors }. `chosen` is whether either file sets anything; a file
-- that's wrong keeps `last` (the defaults the first time), as tide's does.
function M.load(shared, own, decode, last)
    local idle, errors, chosen = {}, {}, false
    for k, v in pairs(M.DEFAULTS) do
        idle[k] = v
    end
    for _, f in ipairs({ { M.SHARED_FILE, shared }, { M.LOCAL_FILE, own } }) do
        if f[2] then
            local s, n = parse(f[2], decode)
            if not s then
                errors[#errors + 1] = f[1] .. ": " .. n
            else
                chosen = chosen or n > 0
                for k, v in pairs(s) do
                    idle[k] = v
                end
            end
        end
    end
    if #errors > 0 then
        return { chosen = last ~= nil and last.chosen or false, idle = last and last.idle or M.DEFAULTS, errors = errors }
    end
    return { chosen = chosen, idle = idle, errors = errors }
end

-- The steps due after `seconds` with no input that haven't been taken
-- since the last input (`done`), in order. `held` says what an app holds
-- awake, as macOS's power assertions do: { display } stops every step, as
-- a video playing does on tide; { system } stops suspending alone.
-- Suspending is on battery, or on AC too with suspendOnAC.
function M.due(idle, seconds, done, on_battery, held)
    held = held or {}
    local out = {}
    if held.display then
        return out
    end
    for _, step in ipairs(M.STEPS) do
        local allowed = step ~= "suspend" or ((on_battery or idle.suspendOnAC) and not held.system)
        if allowed and not done[step] and seconds >= idle[step] then
            out[#out + 1] = step
        end
    end
    return out
end

-- Staying awake when plugged in (SPEC.md §10): a Mac-only switch, off
-- unless this Mac's awake.local.json turns it on, so macOS's own idle
-- sleep doesn't take the Mac while it's on AC. The displays still turn
-- off. Its own file, not idle.local.json, because tide's parser for that
-- one (copied unchanged) takes only tide's own settings.
M.AWAKE_FILE = "awake.local.json"

-- Whether the file's text turns it on: { on, error }. No file, or one
-- that's wrong, is off; a wrong one says why.
function M.load_awake(text, decode)
    if text == nil then
        return { on = false }
    end
    local ok, t = pcall(decode, text)
    if not ok or type(t) ~= "table" or t[1] ~= nil then
        return { on = false, error = M.AWAKE_FILE .. ": expected an object of pluggedIn" }
    end
    for k, v in pairs(t) do
        if k ~= "pluggedIn" then
            return { on = false, error = string.format('%s: unknown setting "%s"; expected pluggedIn', M.AWAKE_FILE, k) }
        elseif type(v) ~= "boolean" then
            return { on = false, error = M.AWAKE_FILE .. ": pluggedIn must be true or false" }
        end
    end
    return { on = t.pluggedIn == true }
end

-- Whether to hold the Mac awake now: on, and plugged in. On battery it
-- sleeps as it would.
function M.holds_awake(on, on_battery)
    return on == true and not on_battery
end

return M
