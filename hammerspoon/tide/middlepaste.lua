-- Middle click pastes the selection (SPEC.md §5.3), as Linux's primary
-- selection does. macOS has none, so tide reads what you select through
-- Accessibility, which leaves the clipboard alone, remembers the last, and
-- pastes it where you middle click. Pure Lua: which mouse gestures select,
-- what a middle click does, and what goes on the pasteboard for the paste.
-- middlepaste_hs.lua does it.

local M = {}

-- macos.json's switch, off unless turned on (macprefs.lua).
M.SETTING = "mouse.middleClickPaste"

-- Terminals paste their own selection on a middle click, so theirs is left
-- to them: kitty from its own buffer (conf's kitty/macos.conf), Ghostty,
-- iTerm2 and Terminal from theirs.
M.TERMINALS = {
    ["net.kovidgoyal.kitty"] = true,
    ["com.mitchellh.ghostty"] = true,
    ["com.googlecode.iterm2"] = true,
    ["com.apple.Terminal"] = true,
}

-- How far up from what's under the pointer to look for a text field: the
-- hit test can land on the text inside one.
M.DEPTH = 6

-- After a selecting gesture, before the selection is read: the app changes
-- it in its own time *(unverified on a Mac that this is long enough)*.
M.READ_AFTER = 0.1

-- After the click that places the caret, Command+V waits until the app
-- clicked is in front, looking every CLICK_SETTLE seconds, FOCUS_TRIES
-- times at most: the keystroke goes to whichever app is in front, and a
-- click takes a moment to bring one there. After Command+V, the clipboard
-- is put back RESTORE_AFTER seconds later: the app pastes in its own
-- time, so sooner would paste the old clipboard *(unverified on a Mac
-- that this is long enough in a slow app)*.
M.CLICK_SETTLE = 0.05
M.FOCUS_TRIES = 10
M.RESTORE_AFTER = 0.3

-- nspasteboard.org's mark for a copy clipboard managers should leave alone,
-- which tide's own history does (picker.lua).
M.TRANSIENT = "org.nspasteboard.TransientType"
M.TEXT = "public.utf8-plain-text"

local TEXT_ROLES = { AXTextField = true, AXTextArea = true, AXComboBox = true }

-- Roles the search stops at: past them is the window or the page, not
-- what was clicked.
local ENDS = { AXWindow = true, AXWebArea = true, AXApplication = true, AXSheet = true, AXDrawer = true }

function M.ends(role)
    return ENDS[role] == true
end

-- Whether the button and modifiers are a plain middle click. With Super
-- held it maximizes (§5.3), and with any other modifier it's the app's.
function M.plain(button, flags)
    flags = flags or {}
    return button == 2 and not (flags.cmd or flags.alt or flags.ctrl or flags.shift)
end

-- Whether what's under the pointer takes typed text. `chain` is what's
-- there and then its parents, each { role, settable }, settable when its
-- value can be set: a field that only shows text, such as a transcript,
-- isn't one to paste into.
function M.takes_text(chain)
    for i, el in ipairs(chain or {}) do
        if i > M.DEPTH or ENDS[el.role] then
            return false
        end
        if TEXT_ROLES[el.role] and el.settable == true then
            return true
        end
    end
    return false
end

-- Whether a middle click is tide's to look into, before the selection is
-- read: the setting is on, and it's on a text field outside a terminal.
-- Anything else is the app's, so a link still opens in a new tab and a tab
-- still closes. Returns false and why.
function M.wants(on, app, chain)
    if not on then
        return false, "off"
    elseif M.TERMINALS[app] then
        return false, "a terminal's own"
    elseif not M.takes_text(chain) then
        return false, "not a text field"
    end
    return true
end

-- Whether a left button coming up may have selected text: after a drag,
-- a double or triple click (`clicks`), or a click with Shift, which
-- extends a selection. A plain click selects nothing, so it costs no read.
function M.selects(dragged, clicks, flags)
    return dragged == true or (clicks or 1) >= 2 or (flags or {}).shift == true
end

-- Whether `text` is something to paste.
function M.usable(text)
    return type(text) == "string" and text ~= ""
end

-- What a middle click pastes. `remembered` is the last selection a mouse
-- gesture made, { text, pid }, or nil; `front` the pid of the app in front
-- and `live` what's selected there now. The remembered one is the newest
-- tide knows of, so it wins from another app: with focus following the
-- mouse, the app in front is the one being pasted into. In the app it came
-- from, what's selected now wins, since the keyboard may have changed it.
function M.pick(remembered, front, live)
    if remembered and remembered.pid ~= front then
        return remembered.text
    elseif M.usable(live) then
        return live
    end
    return remembered and remembered.text or nil
end

-- What goes on the pasteboard for the paste: the text, marked transient.
function M.transient(text)
    return { [M.TEXT] = text, [M.TRANSIENT] = "" }
end

-- Whether to put the clipboard back: only while the pasteboard is still as
-- tide left it. `written` is its change count after tide's write and `now`
-- its count when the paste is done; a copy made in between is newer than
-- what tide kept, so it stays.
function M.restores(written, now)
    return written ~= nil and written == now
end

-- Said when the setting is on and Hammerspoon has no Accessibility.
M.NEEDS_ACCESSIBILITY = "Middle click can't paste the selection until Hammerspoon has Accessibility:"
    .. " in System Settings, Privacy & Security, Accessibility, turn Hammerspoon on. Click here to open it."

-- Whether to say so: the setting is on and macOS says Accessibility is
-- off. Unknown (nil) says nothing.
function M.should_ask(on, accessibility)
    return on == true and accessibility == false
end

return M
