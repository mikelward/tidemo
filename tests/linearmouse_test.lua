local t = require("t")
local linearmouse = require("tilemo.linearmouse")

local function yes()
    return true
end
local function no()
    return false
end

t.test("LinearMouse installed and running is no problem", function()
    t.eq(linearmouse.problem(yes, yes), nil)
end)

t.test("LinearMouse not installed is missing, whatever's running", function()
    t.eq(linearmouse.problem(no, yes), "missing")
    t.eq(linearmouse.problem(no, no), "missing")
end)

t.test("LinearMouse installed but not running is stopped", function()
    t.eq(linearmouse.problem(yes, no), "stopped")
end)

t.test("each problem says what stops working", function()
    for _, kind in ipairs({ "missing", "stopped" }) do
        for _, where in ipairs({ "notice", "doctor", "section" }) do
            local text = linearmouse.say(kind, where)
            t.eq((text:find("wheel notch scrolls a line or so", 1, true)) and true or false, true, kind .. " " .. where .. ": " .. text)
        end
    end
end)

t.test("missing says setup-macos installs it", function()
    t.eq((linearmouse.say("missing", "notice"):find("setup-macos installs it", 1, true)) and true or false, true)
end)

t.test("stopped says how to start it, for where it's said", function()
    t.eq((linearmouse.say("stopped", "notice"):find("Click to start it", 1, true)) and true or false, true)
    t.eq((linearmouse.say("stopped", "doctor"):find("LinearMouse settings, under Mouse", 1, true)) and true or false, true)
    -- The section has the button beside it, so it only says what's wrong.
    t.eq(linearmouse.say("stopped", "section"),
        "LinearMouse isn't running, so a mouse wheel notch scrolls a line or so, faster as you spin it.")
end)

t.test("no problem says nothing", function()
    t.eq(linearmouse.say(nil, "section"), nil)
end)

t.done("linearmouse")
