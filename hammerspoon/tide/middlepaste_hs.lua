-- Middle click pastes the selection, on Hammerspoon (SPEC.md §5.3). The
-- mouse tap (hs_adapter.mouse) calls selected() after a gesture that may
-- have selected text, and hands each plain middle click to click(), which
-- says whether it took it. What they decide is middlepaste.lua's.
--
-- Reading the selection is Accessibility's AXSelectedText, so nothing is
-- copied; the last one is kept in memory only. Pasting is: the clipboard
-- kept, the text put there marked transient, a click where you clicked to
-- place the caret, Command+V, and the clipboard put back. Not runnable
-- outside Hammerspoon.

local middlepaste = require("tide.middlepaste")

local M = {}

-- `d`: log(text), which says what went wrong, with context;
-- accessibility(ask), whether Hammerspoon has Accessibility, nil when it
-- can't be told, having macOS ask for it with `ask`; notify(text, fn), a
-- notification that calls fn when clicked; open_accessibility(), which
-- opens Privacy & Security's Accessibility list; and window_pid(x, y),
-- the pid of the app whose window is at a point, nil where there's none
-- or it's one of tide's own.
function M.new(hs, d)
    local self = {}
    local log = d.log
    local on = false
    -- Whether the notification about Accessibility has been sent, so it's
    -- said once each time the setting is turned on without it.
    local asked = false
    -- The last selection a mouse gesture made: { text, pid }.
    local remembered
    -- A paste under way: the clipboard as it was before, the pasteboard's
    -- change count after tide's write, and the timer that puts it back.
    local held, written, restore_timer
    -- Apps asked for their accessibility, by pid.
    local nudged = {}

    local function try(what, fn, ...)
        local r = table.pack(pcall(fn, ...))
        if not r[1] then
            log("middle click paste: " .. what .. " failed: " .. tostring(r[2]))
            return nil
        end
        return table.unpack(r, 2, r.n)
    end

    -- Chrome builds its accessibility tree only once something asks its
    -- application element's role, and an Electron app once
    -- AXManualAccessibility is set on it (chrome_browser_application_mac.mm,
    -- electron_application.mm); until then neither says what's selected or
    -- what's a text field. So tide asks each app once, the first time a
    -- selection or a middle click involves it. Other apps don't have the
    -- attribute, and nothing is set.
    local function nudge(pid)
        if not pid or nudged[pid] then
            return
        end
        nudged[pid] = true
        try("asking an app for its accessibility", function()
            local app = hs.axuielement.applicationElementForPID(pid)
            if not app then
                return
            end
            app:attributeValue("AXRole")
            if app:isAttributeSettable("AXManualAccessibility") == true then
                app:setAttributeValue("AXManualAccessibility", true)
            end
        end)
    end

    -- What's under x, y and its parents, as middlepaste.takes_text wants
    -- them, with the app's pid and bundle ID. The app is the one whose
    -- window tide knows is there, and the hit test is that app's own:
    -- the system-wide one lands on tide's dim layer over a window that
    -- isn't focused (§5.6), and Hammerspoon can't ask itself.
    local function at(x, y)
        local chain = {}
        local pid = d.window_pid(x, y)
        local app_el = pid and hs.axuielement.applicationElementForPID(pid)
        local el = app_el and app_el:elementAtPosition(x, y)
        while el and #chain < middlepaste.DEPTH do
            local role = el:attributeValue("AXRole")
            chain[#chain + 1] = { role = role, settable = el:isAttributeSettable("AXValue") == true }
            if middlepaste.ends(role) then
                break
            end
            el = el:attributeValue("AXParent")
        end
        local app = pid and hs.application.applicationForPID(pid)
        return chain, pid, app and app:bundleID()
    end

    -- What has the keyboard in the app in front, and that app's pid.
    local function focus()
        local front = hs.application.frontmostApplication()
        return hs.axuielement.systemWideElement():attributeValue("AXFocusedUIElement"), front and front:pid()
    end

    -- What's selected in `focused`. A password field's is never read.
    local function selected_in(focused)
        if not focused or focused:attributeValue("AXSubrole") == "AXSecureTextField" then
            return nil
        end
        return focused:attributeValue("AXSelectedText")
    end

    -- Put the clipboard back, unless something was copied since.
    local function restore()
        restore_timer = nil
        local kept, count = held, written
        held, written = nil, nil
        if kept == nil then
            return
        end
        if not middlepaste.restores(count, hs.pasteboard.changeCount()) then
            -- On purpose: a copy made since is newer than what tide kept.
            log("middle click paste: something was copied during the paste, so the clipboard stays as it is now")
            return
        end
        try("putting the clipboard back", function()
            if next(kept) == nil then
                hs.pasteboard.clearContents()
            elseif not hs.pasteboard.writeAllData(kept) then
                log("middle click paste: couldn't put the clipboard back")
            end
        end)
    end

    local function paste(text, x, y, target)
        -- A paste already under way holds the real clipboard: keep that
        -- one, not the text tide put there.
        if restore_timer then
            restore_timer:stop()
            restore_timer = nil
        end
        -- Unless something was copied since tide's write: that's the
        -- clipboard now, and what goes back.
        if held ~= nil and not middlepaste.restores(written, hs.pasteboard.changeCount()) then
            held = nil
        end
        if held == nil then
            held = try("reading the clipboard", hs.pasteboard.readAllData)
            if held == nil then
                return
            end
        end
        local wrote = try("writing the selection", function()
            return hs.pasteboard.writeAllData(middlepaste.transient(text))
        end)
        -- Counted even after a write that failed part way, which may have
        -- emptied the pasteboard: the clipboard still goes back.
        written = hs.pasteboard.changeCount()
        if not wrote then
            log("middle click paste: couldn't put the selection on the pasteboard, so nothing is pasted")
            restore()
            return
        end
        -- The click places the caret, and gives the window focus.
        try("clicking", function()
            local t = hs.eventtap.event.types
            local p = { x = x, y = y }
            hs.eventtap.event.newMouseEvent(t.leftMouseDown, p):post()
            hs.eventtap.event.newMouseEvent(t.leftMouseUp, p):post()
        end)
        -- Command+V goes to the app in front, so only once that's the app
        -- clicked: the click takes a moment to bring it there, and with
        -- focus following the mouse the pointer may have moved on to
        -- another window, a terminal's even.
        local tries = 0
        local function send()
            tries = tries + 1
            local front = try("reading the app in front", hs.application.frontmostApplication)
            if front and front:pid() == target then
                try("Command+V", hs.eventtap.keyStroke, { "cmd" }, "v", 0)
                restore_timer = hs.timer.doAfter(middlepaste.RESTORE_AFTER, restore)
            elseif tries < middlepaste.FOCUS_TRIES then
                restore_timer = hs.timer.doAfter(middlepaste.CLICK_SETTLE, send)
            else
                log("middle click paste: the app clicked didn't come to the front, so nothing is pasted")
                restore()
            end
        end
        restore_timer = hs.timer.doAfter(middlepaste.CLICK_SETTLE, send)
    end

    -- Follow the setting. Turned on without Accessibility, nothing can be
    -- read or pasted: macOS asks for it, and a notification says where to
    -- turn it on, opening the list when clicked.
    function self.set(value)
        on = value == true
        if not on then
            remembered = nil
        end
        if not middlepaste.should_ask(on, d.accessibility()) then
            asked = false
        elseif not asked then
            asked = true
            d.accessibility(true)
            d.notify(middlepaste.NEEDS_ACCESSIBILITY, d.open_accessibility)
        end
    end

    -- A mouse gesture that may have selected text just ended: remember
    -- what's selected, once the app has caught up. What had the keyboard
    -- is taken now, and read then: with focus following the mouse, another
    -- app may be in front by then. Nothing selected keeps the last one, as
    -- a click elsewhere keeps Linux's.
    function self.selected()
        if not on then
            return
        end
        local focused, pid = try("reading what's focused", focus)
        nudge(pid)
        hs.timer.doAfter(middlepaste.READ_AFTER, function()
            local text = try("reading the selection", selected_in, focused)
            if middlepaste.usable(text) then
                remembered = { text = text, pid = pid }
            end
        end)
    end

    -- A plain middle click at x, y. True when tide pastes, so the tap
    -- swallows the click; false leaves it to the app.
    function self.click(x, y)
        if not on then
            return false
        end
        local chain, pid, bundle = try("reading what's under the pointer", at, x, y)
        nudge(pid)
        if not middlepaste.wants(on, bundle, chain) then
            return false
        end
        local focused, front = try("reading what's focused", focus)
        nudge(front)
        local live = try("reading the selection", selected_in, focused)
        local text = middlepaste.pick(remembered, front, live)
        if not middlepaste.usable(text) then
            return false
        end
        -- Once this event is done with, so the clicks can't cross.
        hs.timer.doAfter(0, function()
            paste(text, x, y, pid)
        end)
        return true
    end

    -- Stop, putting the clipboard back now if a paste is under way.
    function self.stop()
        on, remembered = false, nil
        if restore_timer then
            restore_timer:stop()
        end
        restore()
    end

    return self
end

return M
