-- Home and End as on a PC (SPEC.md §10): in a text field they go to the
-- line's start and end, and elsewhere they're the keys themselves, so a
-- page scrolls to its top and bottom. A Mac's own Home and End only
-- scroll, and Command+Left, the line's start, is Back in a browser
-- whenever no text field has focus; so tide looks at what has focus
-- before choosing. Karabiner can't, which is why it isn't conf's rule.
-- Pure Lua: what a key becomes. homeend_hs.lua does it.

local middlepaste = require("tide.middlepaste")

local M = {}

-- What each key becomes in a text field: Command with the arrow.
M.ARROWS = { home = "left", ["end"] = "right" }

-- Roles that take a caret. Chrome's contenteditable has an
-- AXEditableAncestor instead of one of these.
M.TEXT_ROLES = { AXTextField = true, AXTextArea = true, AXComboBox = true }

-- Apps whose Home and End are their own: terminals send the keys on to
-- the shell, and Hammerspoon can't ask itself what has focus (its name
-- prompt binds Home and End itself, prompt_hs.lua).
M.OWN = { ["org.hammerspoon.Hammerspoon"] = true }
for bundle in pairs(middlepaste.TERMINALS) do
    M.OWN[bundle] = true
end

-- Whether `focused`, { role, editable }, takes a caret. `editable` is
-- whether it has an AXEditableAncestor.
function M.is_text(focused)
    return focused ~= nil and (M.TEXT_ROLES[focused.role] == true or focused.editable == true)
end

-- Whether a key press is one to look at: Home or End, alone or with
-- Shift. Fn, which a MacBook's Fn+Left sends Home with, doesn't count.
-- Anything else, Ctrl+Home included, is Karabiner's or the app's.
function M.wants(key, flags)
    if not M.ARROWS[key] then
        return false
    end
    flags = flags or {}
    return not (flags.cmd or flags.alt or flags.ctrl)
end

-- Accessibility's errors that only mean there's nothing there: no value
-- (kAXErrorNoValue, as when nothing has focus) and an attribute the
-- element doesn't have (kAXErrorAttributeUnsupported). Hammerspoon's
-- message names the code.
M.EXPECTED_ERRORS = { "-25212", "-25205", "no value", "unsupported" }

-- Whether `err`, an Accessibility read's error or nil, is only that.
function M.expected(err)
    if err == nil then
        return true
    end
    local text = tostring(err):lower()
    for _, e in ipairs(M.EXPECTED_ERRORS) do
        if text:find(e, 1, true) then
            return true
        end
    end
    return false
end

-- What `key` becomes in the app `bundle` with `focused` (is_text's)
-- having the keyboard: nil to leave it as it is, else the arrow, sent
-- with Command, and Shift if it was held, to select to there.
function M.arrow(key, bundle, focused)
    if M.OWN[bundle] or not M.is_text(focused) then
        return nil
    end
    return M.ARROWS[key]
end

return M
