-- middlepaste_hs.lua against a stand-in hs: what Accessibility says is
-- under the pointer and selected, a pasteboard, posted events and timers
-- run by hand.

local t = require("t")
local middlepaste = require("tide.middlepaste")
local middlepaste_hs = require("tide.middlepaste_hs")

local TEXT = "public.utf8-plain-text"

local function copy(tbl)
    local out = {}
    for k, v in pairs(tbl) do
        out[k] = v
    end
    return out
end

-- An accessibility element.
local function el(attrs)
    local e = { attrs = attrs }
    function e:attributeValue(name)
        return attrs[name]
    end
    function e:isAttributeSettable(name)
        return (attrs.settable or {})[name] == true
    end
    function e:setAttributeValue(name, value)
        attrs.set = attrs.set or {}
        attrs.set[#attrs.set + 1] = name .. "=" .. tostring(value)
    end
    function e:pid()
        return attrs.pid
    end
    return e
end

-- A text field in the app `pid`, inside a window.
local function field(pid)
    local window = el({ AXRole = "AXWindow", pid = pid })
    return el({ AXRole = "AXTextField", settable = { AXValue = true }, AXParent = window, pid = pid })
end

-- What's focused in the app in front, with `text` selected.
local function focused(text, subrole)
    return el({ AXRole = "AXTextArea", AXSelectedText = text, AXSubrole = subrole })
end

local function world()
    local w = {
        timers = {}, events = {}, logs = {}, notes = {}, asks = 0,
        board = { [TEXT] = "the clipboard" }, count = 10,
        bundles = { [1] = "com.example.editor", [2] = "com.example.notes" },
        apps = {}, front = 1, access = true,
    }
    local hs = {
        timer = {
            doAfter = function(seconds, fn)
                local timer = { seconds = seconds }
                function timer.fn()
                    timer.fired = true
                    fn()
                end
                function timer:stop()
                    timer.stopped = true
                end
                w.timers[#w.timers + 1] = timer
                return timer
            end,
        },
        pasteboard = {
            readAllData = function()
                return copy(w.board)
            end,
            writeAllData = function(data)
                w.count = w.count + 1
                -- `refuse` is how many writes fail, each emptying the board.
                if (w.refuse or 0) > 0 then
                    w.refuse = w.refuse - 1
                    w.board = {}
                    return false
                end
                w.board = copy(data)
                return true
            end,
            clearContents = function()
                w.count = w.count + 1
                w.board = {}
            end,
            changeCount = function()
                return w.count
            end,
        },
        eventtap = {
            event = {
                types = { leftMouseDown = "down", leftMouseUp = "up" },
                newMouseEvent = function(kind, p)
                    return {
                        post = function()
                            w.events[#w.events + 1] = kind .. " " .. p.x .. "," .. p.y
                            -- A click brings the app clicked to the front,
                            -- unless `w.stays` keeps another there.
                            if kind == "down" and w.under and not w.stays then
                                w.front = w.under:pid()
                            end
                        end,
                    }
                end,
            },
            keyStroke = function(mods, key)
                if w.key_fails then
                    error("no keystroke")
                end
                -- What the app pastes is what's on the pasteboard now.
                w.events[#w.events + 1] = table.concat(mods, "+") .. "+" .. key .. " pastes " .. tostring(w.board[TEXT])
            end,
        },
        axuielement = {
            systemWideElement = function()
                return el({ AXFocusedUIElement = w.focused })
            end,
            applicationElementForPID = function(pid)
                w.apps[pid] = w.apps[pid] or { asked = 0 }
                local app = w.apps[pid]
                local e = el({ settable = { AXManualAccessibility = app.electron }, pid = pid })
                -- The app's own hit test: only what's in this app.
                function e:elementAtPosition()
                    return w.under and w.under:pid() == pid and w.under or nil
                end
                function e:setAttributeValue(name, value)
                    app.set = app.set or {}
                    app.set[#app.set + 1] = name .. "=" .. tostring(value)
                end
                local value = e.attributeValue
                function e:attributeValue(name)
                    if name == "AXRole" then
                        app.asked = app.asked + 1
                    end
                    return value(self, name)
                end
                return e
            end,
        },
        application = {
            applicationForPID = function(pid)
                return {
                    bundleID = function()
                        return w.bundles[pid]
                    end,
                }
            end,
            frontmostApplication = function()
                return {
                    pid = function()
                        return w.front
                    end,
                }
            end,
        },
    }
    w.paste = middlepaste_hs.new(hs, {
        log = function(text)
            w.logs[#w.logs + 1] = text
        end,
        accessibility = function(ask)
            if ask then
                w.asks = w.asks + 1
            end
            return w.access
        end,
        notify = function(text, fn)
            w.notes[#w.notes + 1] = { text = text, fn = fn }
        end,
        open_accessibility = function()
            w.opened = (w.opened or 0) + 1
        end,
        -- The window manager's answer: by frames, so tide's dim layer over
        -- a window doesn't hide it. `w.window` is the pid, or what's under
        -- the point's.
        window_pid = function()
            if w.window ~= nil then
                return w.window or nil
            end
            return w.under and w.under:pid()
        end,
    })
    -- Run the timers still due, and those they start, in the order started.
    function w.run()
        local i = 1
        while w.timers[i] do
            if not w.timers[i].stopped and not w.timers[i].fired then
                w.timers[i].fn()
            end
            i = i + 1
        end
        w.timers = {}
    end
    -- Select `text` in the app `pid` with the mouse.
    function w.select(text, pid)
        w.front = pid
        w.focused = focused(text)
        w.paste.selected()
        w.run()
    end
    return w
end

t.test("off, a middle click is the app's, and nothing is read", function()
    local w = world()
    w.under, w.focused = field(2), focused("words")
    t.eq(w.paste.click(5, 6), false)
    w.paste.selected()
    t.eq(#w.timers, 0)
    t.eq(w.apps, {})
end)

t.test("a selection made with the mouse is pasted into another app's text field, and the clipboard comes back", function()
    local w = world()
    w.paste.set(true)
    w.select("picked words", 1)
    -- Focus follows the mouse: the app pasted into is in front by now.
    w.front, w.focused, w.under = 2, focused(""), field(2)
    t.eq(w.paste.click(300, 400), true, "the click is taken")
    t.eq(w.events, {}, "nothing until the click's event is done with")
    w.run()
    t.eq(w.events, { "down 300,400", "up 300,400", "cmd+v pastes picked words" })
    t.eq(w.board, { [TEXT] = "the clipboard" })
    t.eq(w.logs, {})
end)

t.test("the selection is never on the pasteboard unmarked", function()
    local w = world()
    w.paste.set(true)
    w.select("picked words", 1)
    w.under = field(2)
    w.paste.click(1, 1)
    w.timers[1].fn()
    t.eq(w.board[TEXT], "picked words")
    t.eq(w.board[middlepaste.TRANSIENT], "", "marked for clipboard managers to skip")
end)

t.test("the settle and restore delays are the ones the spec names", function()
    local w = world()
    w.paste.set(true)
    w.select("picked words", 1)
    w.under = field(2)
    w.paste.click(1, 1)
    w.timers[1].fn()
    t.eq(w.timers[2].seconds, middlepaste.CLICK_SETTLE)
    w.timers[2].fn()
    t.eq(w.timers[3].seconds, middlepaste.RESTORE_AFTER)
end)

t.test("something copied during the paste stays on the clipboard", function()
    local w = world()
    w.paste.set(true)
    w.select("picked words", 1)
    w.under = field(2)
    w.paste.click(1, 1)
    w.timers[1].fn()
    w.timers[2].fn()
    w.board, w.count = { [TEXT] = "copied just now" }, w.count + 1
    w.timers[3].fn()
    t.eq(w.board, { [TEXT] = "copied just now" })
    t.eq(#w.logs, 1)
    t.eq(w.logs[1]:find("copied during the paste", 1, true) ~= nil, true)
end)

t.test("an empty clipboard is empty again afterwards", function()
    local w = world()
    w.board = {}
    w.paste.set(true)
    w.select("picked words", 1)
    w.under = field(2)
    w.paste.click(1, 1)
    w.run()
    t.eq(w.board, {})
end)

t.test("a second paste before the first is done still gives the real clipboard back", function()
    local w = world()
    w.paste.set(true)
    w.select("picked words", 1)
    w.under = field(2)
    w.paste.click(1, 1)
    w.timers[1].fn()
    w.timers[2].fn()
    -- The first paste's restore is pending, with the selection on the
    -- pasteboard.
    w.paste.click(2, 2)
    w.run()
    t.eq(w.board, { [TEXT] = "the clipboard" })
end)

t.test("Command+V waits for the app clicked to come to the front", function()
    local w = world()
    w.paste.set(true)
    w.select("picked words", 1)
    w.under, w.stays = field(2), true
    w.paste.click(1, 1)
    w.timers[1].fn()
    w.timers[2].fn()
    t.eq(w.events, { "down 1,1", "up 1,1" }, "not yet: another app is in front")
    w.front = 2
    w.run()
    t.eq(w.events[3], "cmd+v pastes picked words")
    t.eq(w.board, { [TEXT] = "the clipboard" })
end)

t.test("with another app in front for good, nothing is pasted there, and the clipboard comes back", function()
    local w = world()
    w.paste.set(true)
    w.select("picked words", 1)
    -- Focus follows the mouse on to a terminal after the click.
    w.under, w.stays = field(2), true
    w.paste.click(1, 1)
    w.front = 3
    w.run()
    t.eq(w.events, { "down 1,1", "up 1,1" })
    t.eq(w.board, { [TEXT] = "the clipboard" })
    t.eq(w.logs[1]:find("didn't come to the front", 1, true) ~= nil, true)
end)

t.test("something copied between two overlapping pastes is what the clipboard ends with", function()
    local w = world()
    w.paste.set(true)
    w.select("picked words", 1)
    w.under = field(2)
    w.paste.click(1, 1)
    w.timers[1].fn()
    w.timers[2].fn()
    w.board, w.count = { [TEXT] = "copied just now" }, w.count + 1
    -- The second paste starts before the first one's restore is due.
    w.paste.click(2, 2)
    w.timers[4].fn()
    w.run()
    t.eq(w.events[#w.events], "cmd+v pastes picked words")
    t.eq(w.board, { [TEXT] = "copied just now" })
end)

t.test("the selection is read from where it was made, though another app is in front by then", function()
    local w = world()
    w.paste.set(true)
    w.front, w.focused = 1, focused("picked words")
    w.paste.selected()
    -- Focus follows the mouse into another window before the read.
    w.front, w.focused, w.under = 2, focused(""), field(2)
    w.run()
    t.eq(w.paste.click(1, 1), true)
    w.run()
    t.eq(w.events[3], "cmd+v pastes picked words")
end)

t.test("a click on a link, or in a terminal, is left to the app", function()
    local w = world()
    w.paste.set(true)
    w.select("picked words", 1)
    w.under = el({ AXRole = "AXLink", pid = 2, AXParent = el({ AXRole = "AXWebArea", pid = 2 }) })
    t.eq(w.paste.click(1, 1), false)
    w.bundles[2] = "net.kovidgoyal.kitty"
    w.under = field(2)
    t.eq(w.paste.click(1, 1), false)
    w.run()
    t.eq(w.events, {})
    t.eq(w.board, { [TEXT] = "the clipboard" })
end)

t.test("a click where tide knows no window, or over one of its own, is left alone, unasked", function()
    local w = world()
    w.paste.set(true)
    w.select("picked words", 1)
    w.under, w.window = field(2), false
    t.eq(w.paste.click(1, 1), false)
    t.eq(w.apps[2], nil, "nothing was asked about what's there")
end)

t.test("with nothing selected, a middle click is the app's", function()
    local w = world()
    w.paste.set(true)
    w.under, w.focused = field(1), focused("")
    t.eq(w.paste.click(1, 1), false)
    w.focused = nil
    t.eq(w.paste.click(1, 1), false)
    t.eq(#w.timers, 0)
end)

t.test("a selection made with the keyboard is pasted in its own app", function()
    local w = world()
    w.paste.set(true)
    w.under, w.focused = field(1), focused("typed selection")
    t.eq(w.paste.click(1, 1), true)
    w.run()
    t.eq(w.events[3], "cmd+v pastes typed selection")
end)

t.test("clicking away keeps the last selection, as on Linux", function()
    local w = world()
    w.paste.set(true)
    w.select("picked words", 1)
    w.select("", 1)
    w.under = field(2)
    t.eq(w.paste.click(1, 1), true)
    w.run()
    t.eq(w.events[3], "cmd+v pastes picked words")
end)

t.test("a password field's selection is never read", function()
    local w = world()
    w.paste.set(true)
    w.front, w.focused = 1, focused("hunter2", "AXSecureTextField")
    w.paste.selected()
    w.run()
    w.under = field(1)
    t.eq(w.paste.click(1, 1), false)
    t.eq(#w.timers, 0)
end)

t.test("turning the setting off forgets the selection", function()
    local w = world()
    w.paste.set(true)
    w.select("picked words", 1)
    w.paste.set(false)
    w.paste.set(true)
    w.front, w.focused, w.under = 2, focused(""), field(2)
    t.eq(w.paste.click(1, 1), false)
end)

t.test("each app is asked for its accessibility once, and an Electron app has it switched on", function()
    local w = world()
    w.apps[2] = { asked = 0, electron = true }
    w.paste.set(true)
    w.select("picked words", 1)
    w.under = field(2)
    w.paste.click(1, 1)
    w.paste.click(1, 1)
    w.run()
    t.eq(w.apps[1].asked, 1, "Chrome builds its tree when asked its role")
    t.eq(w.apps[2].asked, 1)
    t.eq(w.apps[2].set, { "AXManualAccessibility=true" })
    t.eq(w.apps[1].set, nil, "an app without the attribute has nothing set")
end)

t.test("a keystroke that fails is logged, and the clipboard still comes back", function()
    local w = world()
    w.key_fails = true
    w.paste.set(true)
    w.select("picked words", 1)
    w.under = field(2)
    w.paste.click(1, 1)
    w.run()
    t.eq(w.board, { [TEXT] = "the clipboard" })
    t.eq(#w.logs, 1)
    t.eq(w.logs[1]:find("Command+V failed", 1, true) ~= nil, true)
end)

t.test("a pasteboard that refuses the selection pastes nothing, and the clipboard comes back", function()
    local w = world()
    w.paste.set(true)
    w.select("picked words", 1)
    w.under = field(2)
    w.refuse = 1
    w.paste.click(1, 1)
    w.run()
    t.eq(w.events, {})
    t.eq(w.board, { [TEXT] = "the clipboard" })
    t.eq(w.logs[1]:find("nothing is pasted", 1, true) ~= nil, true)
end)

t.test("stopping mid-paste puts the clipboard back at once", function()
    local w = world()
    w.paste.set(true)
    w.select("picked words", 1)
    w.under = field(2)
    w.paste.click(1, 1)
    w.timers[1].fn()
    t.eq(w.board[TEXT], "picked words")
    w.paste.stop()
    t.eq(w.board, { [TEXT] = "the clipboard" })
    w.run()
    t.eq(w.events, { "down 1,1", "up 1,1" }, "and Command+V isn't sent")
end)

t.test("turned on without Accessibility, macOS asks and a notification opens the list, once", function()
    local w = world()
    w.access = false
    w.paste.set(true)
    w.paste.set(true)
    t.eq(w.asks, 1)
    t.eq(#w.notes, 1)
    t.eq(w.notes[1].text, middlepaste.NEEDS_ACCESSIBILITY)
    w.notes[1].fn()
    t.eq(w.opened, 1)
    -- Off and on again says it again; with Accessibility, nothing.
    w.paste.set(false)
    w.paste.set(true)
    t.eq(#w.notes, 2)
    w.access = true
    w.paste.set(false)
    w.paste.set(true)
    t.eq(#w.notes, 2)
    t.eq(w.asks, 2)
end)

t.done("middlepaste_hs")
