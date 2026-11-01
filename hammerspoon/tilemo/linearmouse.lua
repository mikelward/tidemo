-- LinearMouse, which gives each mouse wheel notch the same distance, where
-- macOS's slider changes only the acceleration (SPEC.md §10): whether it's
-- there to, said in a notification, `tilemo doctor` and the settings
-- window's Mouse section (§1, §15). Pure Lua.

local M = {}

-- Homebrew's cask quits it by this.
M.BUNDLE = "com.lujjjh.LinearMouse"

-- What stops working, said the same wherever it's said.
local COST = "so a mouse wheel notch scrolls a line or so, faster as you spin it"

-- What's wrong: "missing", "stopped", or nil when it's installed and
-- running. `installed()` and `running()` ask about M.BUNDLE.
function M.problem(installed, running)
    if not installed() then
        return "missing"
    end
    if not running() then
        return "stopped"
    end
    return nil
end

-- `kind` (M.problem) said for `where`: "notice", a notification, a click
-- on which starts it when it's stopped; "doctor", tilemo doctor's line; or
-- "section", the Mouse section's line, beside the button that opens it.
function M.say(kind, where)
    if kind == "missing" then
        return "LinearMouse isn't installed, " .. COST .. ". setup-macos installs it."
    end
    if kind ~= "stopped" then
        return nil
    end
    local text = "LinearMouse isn't running, " .. COST .. "."
    if where == "notice" then
        return text .. " Click to start it, and turn on its Start at login."
    end
    if where == "doctor" then
        return text .. " Start it with LinearMouse settings, under Mouse in tide's settings,"
            .. " and turn on its Start at login."
    end
    return text
end

return M
