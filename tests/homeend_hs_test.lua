-- homeend_hs.lua against a stand-in hs: an event tap fed key events by
-- hand, an app in front, and what Accessibility says has focus there.

local t = require("t")
local homeend_hs = require("tide.homeend_hs")

local CODES = { home = 115, ["end"] = 119, left = 123, right = 124, a = 0 }
local NAMES = {}
for name, code in pairs(CODES) do
    NAMES[code] = name
end

local function world()
    local w = { logs = {}, nudged = {}, asked = 0, front = { bundle = "com.google.Chrome", pid = 7 } }
    local keycodes = { map = {} }
    for name, code in pairs(CODES) do
        keycodes.map[name] = code
        keycodes.map[code] = name
    end
    local hs = {
        keycodes = keycodes,
        eventtap = {
            event = { types = { keyDown = 10 } },
            new = function(types, fn)
                w.types = types
                w.fn = fn
                return {
                    start = function()
                        w.started = true
                    end,
                    stop = function()
                        w.stopped = true
                    end,
                }
            end,
        },
        application = {
            frontmostApplication = function()
                local f = w.front
                if not f then
                    return nil
                end
                return {
                    bundleID = function()
                        return f.bundle
                    end,
                    pid = function()
                        return f.pid
                    end,
                }
            end,
        },
        axuielement = {
            applicationElementForPID = function(pid)
                return {
                    attributeValue = function(_, name)
                        w.asked = w.asked + 1
                        if w.fail then
                            error("timed out")
                        end
                        t.eq(name, "AXFocusedUIElement")
                        t.eq(pid, w.front.pid)
                        local f = w.focused
                        if not f then
                            -- As Accessibility says it, nil and why.
                            return nil, w.focus_err
                        end
                        return {
                            attributeValue = function(_, attr)
                                if f[attr] == nil then
                                    return nil, (w.attr_errs or {})[attr]
                                end
                                return f[attr]
                            end,
                        }
                    end,
                }
            end,
        },
    }
    w.h = homeend_hs.new(hs, {
        log = function(text)
            w.logs[#w.logs + 1] = text
        end,
        nudge = function(pid)
            w.nudged[#w.nudged + 1] = pid
        end,
        prompting = function()
            return w.prompting == true
        end,
    })
    -- A key going down: what the app gets, as "key" with its modifiers,
    -- or nil when the tap swallowed it.
    function w.press(key, flags)
        local ev = { code = CODES[key], flags = flags or {} }
        function ev.getKeyCode()
            return ev.code
        end
        function ev.getFlags()
            return ev.flags
        end
        function ev.setKeyCode(_, code)
            ev.code = code
        end
        function ev.setFlags(_, f)
            ev.flags = f
        end
        if w.fn(ev) then
            return nil
        end
        local mods = {}
        for _, m in ipairs({ "cmd", "alt", "ctrl", "shift" }) do
            if ev.flags[m] then
                mods[#mods + 1] = m
            end
        end
        mods[#mods + 1] = NAMES[ev.code]
        return table.concat(mods, "+")
    end
    return w
end

t.test("it watches keys going down from the start, and says it started", function()
    local w = world()
    t.eq(w.types, { 10 })
    t.eq(w.started, true)
    t.eq(w.logs, { "Home and End: started" })
    w.h.stop()
    t.eq(w.stopped, true)
end)

t.test("in a text field, Home and End are Command+Left and Right", function()
    local w = world()
    w.focused = { AXRole = "AXTextField" }
    t.eq(w.press("home"), "cmd+left")
    t.eq(w.press("end"), "cmd+right")
    t.eq(w.nudged, { 7, 7 })
end)

t.test("Shift+Home and End select to there", function()
    local w = world()
    w.focused = { AXRole = "AXTextArea" }
    t.eq(w.press("home", { shift = true }), "cmd+shift+left")
    t.eq(w.press("end", { shift = true }), "cmd+shift+right")
end)

t.test("a MacBook's Fn+Left, Home with Fn, is Command+Left too, without Fn", function()
    local w = world()
    w.focused = { AXRole = "AXTextField" }
    t.eq(w.press("home", { fn = true }), "cmd+left")
end)

t.test("a contenteditable on a page counts as a text field", function()
    local w = world()
    w.focused = { AXRole = "AXGroup", AXEditableAncestor = {} }
    t.eq(w.press("home"), "cmd+left")
end)

-- The bug: Command+Left on a page is Back.
t.test("on a page, Home and End stay themselves, scrolling it, not going Back", function()
    local w = world()
    w.focused = { AXRole = "AXWebArea" }
    t.eq(w.press("home"), "home")
    t.eq(w.press("end", { shift = true }), "shift+end")
    w.focused = nil
    t.eq(w.press("home"), "home")
end)

t.test("terminals keep their Home and End, unasked", function()
    local w = world()
    w.front = { bundle = "net.kovidgoyal.kitty", pid = 9 }
    w.focused = { AXRole = "AXTextArea" }
    t.eq(w.press("home"), "home")
    t.eq(w.asked, 0)
    t.eq(w.nudged, {})
end)

t.test("Hammerspoon, and tide's open name prompt, keep theirs, unasked", function()
    local w = world()
    w.focused = { AXRole = "AXTextField" }
    w.front = { bundle = "org.hammerspoon.Hammerspoon", pid = 3 }
    t.eq(w.press("home"), "home")
    w.front = { bundle = "com.google.Chrome", pid = 7 }
    w.prompting = true
    t.eq(w.press("end"), "end")
    t.eq(w.asked, 0)
end)

t.test("other keys, and Home with Command or Control, pass unasked", function()
    local w = world()
    w.focused = { AXRole = "AXTextField" }
    t.eq(w.press("a"), "a")
    t.eq(w.press("home", { cmd = true }), "cmd+home")
    t.eq(w.press("end", { ctrl = true }), "ctrl+end")
    t.eq(w.asked, 0)
end)

t.test("with no app in front the key stays as it is", function()
    local w = world()
    w.front = nil
    t.eq(w.press("home"), "home")
end)

t.test("a failed read leaves the key as it is, and says why", function()
    local w = world()
    w.fail = true
    t.eq(w.press("home"), "home")
    t.eq(#w.logs, 2)
    t.eq(w.logs[2]:find("^Home and End: reading what has focus failed, so home stays as it is: .*timed out") ~= nil,
        true, w.logs[2])
end)

-- Accessibility's reads return nil and why rather than raise.
t.test("a read that times out leaves the key as it is, and says why", function()
    local w = world()
    w.focus_err = "kAXErrorCannotComplete (-25204)"
    t.eq(w.press("end"), "end")
    t.eq(w.logs[2], "Home and End: reading what has focus failed, so end stays as it is: kAXErrorCannotComplete (-25204)")
end)

t.test("a role that can't be read leaves the key as it is, and says why", function()
    local w = world()
    w.focused = {}
    w.attr_errs = { AXRole = "kAXErrorInvalidUIElement (-25202)" }
    t.eq(w.press("home"), "home")
    t.eq(w.logs[2], "Home and End: reading what has focus failed, so home stays as it is: kAXErrorInvalidUIElement (-25202)")
end)

t.test("nothing focused, or no editable ancestor, isn't a failure", function()
    local w = world()
    w.focus_err = "kAXErrorNoValue (-25212)"
    t.eq(w.press("home"), "home")
    w.focused = { AXRole = "AXTextField" }
    w.attr_errs = { AXEditableAncestor = "kAXErrorAttributeUnsupported (-25205)" }
    t.eq(w.press("home"), "cmd+left")
    t.eq(w.logs, { "Home and End: started" })
end)

t.done("homeend_hs_test")
