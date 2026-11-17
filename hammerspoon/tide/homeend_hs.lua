-- Home and End as on a PC, on Hammerspoon (SPEC.md §10): an event tap
-- looks at each Home and End, asks Accessibility what has focus, and in
-- a text field makes the key Command+Left or Right, the line's start or
-- end, before the app sees it. Anything else passes as it was. What it
-- decides is homeend.lua's. Not runnable outside Hammerspoon.

local homeend = require("tide.homeend")

local M = {}

-- `d`: log(text), which says what went wrong, with context;
-- nudge(pid), which has Chrome and Electron apps build their
-- accessibility, so their text fields can be told apart
-- (middlepaste_hs.lua); and prompting(), whether tide's name prompt is
-- open, whose own Home and End are hotkeys (prompt_hs.lua).
function M.new(hs, d)
    local log = d.log

    -- What has the keyboard in the app in front, as homeend.arrow wants
    -- it, the app's bundle ID, and why a read failed, if one did.
    -- Hammerspoon's own, and a terminal's, are never asked about.
    -- Accessibility's reads return nil and why rather than raise; an
    -- element with no value or no such attribute is expected, as when
    -- nothing has focus, and isn't a failure (homeend.expected).
    local function focus()
        local front = hs.application.frontmostApplication()
        local bundle = front and front:bundleID()
        if not front or homeend.OWN[bundle] then
            return bundle, nil
        end
        local pid = front:pid()
        d.nudge(pid)
        -- The app's own element, not the system-wide one: that would ask
        -- whatever has focus, which can be Hammerspoon's own prompt.
        local app = hs.axuielement.applicationElementForPID(pid)
        if not app then
            return bundle, nil, "no Accessibility element for the app in front"
        end
        local el, err = app:attributeValue("AXFocusedUIElement")
        if not el then
            return bundle, nil, not homeend.expected(err) and err or nil
        end
        local role, role_err = el:attributeValue("AXRole")
        if role == nil and not homeend.expected(role_err) then
            return bundle, nil, role_err
        end
        local ancestor, ancestor_err = el:attributeValue("AXEditableAncestor")
        if ancestor == nil and not homeend.expected(ancestor_err) then
            return bundle, nil, ancestor_err
        end
        return bundle, { role = role, editable = ancestor ~= nil }
    end

    local tap = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, function(e)
        local key = hs.keycodes.map[e:getKeyCode()]
        local flags = e:getFlags()
        if not homeend.wants(key, flags) or d.prompting() then
            return false
        end
        local ok, bundle, focused, err = pcall(focus)
        if not ok or err then
            -- The key still reaches the app, as a Mac's own Home or End.
            log("Home and End: reading what has focus failed, so " .. key .. " stays as it is: "
                .. tostring(ok and err or bundle))
            return false
        end
        local arrow = homeend.arrow(key, bundle, focused)
        if arrow then
            e:setKeyCode(hs.keycodes.map[arrow])
            e:setFlags({ cmd = true, shift = flags.shift == true })
        end
        return false
    end)
    tap:start()
    log("Home and End: started")

    return {
        stop = function()
            tap:stop()
        end,
    }
end

return M
