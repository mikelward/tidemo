-- Middle click pastes the selection (SPEC.md §5.3), as Linux's primary
-- selection does. macOS has none, so tide reads what you select through
-- Accessibility, which leaves the clipboard alone, remembers the last, and
-- pastes it where you middle click. Pure Lua: which mouse gestures select,
-- what a middle click does, and what goes on the pasteboard for the paste.
-- middlepaste_hs.lua does it.

local M = {}

-- macos.json's switch, off unless turned on (macprefs.lua).
M.SETTING = "mouse.middleClickPaste"

-- kitty shares the one selection: tide reads what's selected there over
-- its remote control socket, and pastes into it with a click conf's
-- kitty/macos.conf maps to pasting the clipboard (M.KITTY_PASTE).
M.KITTY = "net.kovidgoyal.kitty"

-- The modifiers on the middle click tide sends kitty to paste, which conf's
-- kitty/macos.conf maps to paste_from_clipboard, grabbed or not. Neither
-- is Super, so the click doesn't maximize.
M.KITTY_PASTE = { ctrl = true, shift = true }

-- What tide marks the events it posts with (eventSourceUserData), so its
-- own mouse tap lets them through untouched.
M.MARK = 0x7469646d

-- The terminals, each sharing the one selection its own way, how a
-- middle click pastes another app's selection into it:
-- - "kitty": tide sends kitty's paste click (M.KITTY_PASTE).
-- - "pasteboard": Ghostty pastes its selection pasteboard, M.GHOSTTY_BOARD,
--   so tide writes the text there and lets the click through.
-- - "clipboard": iTerm2's middle click pastes the clipboard, and it copies
--   each selection there, so tide lends it the clipboard until the
--   button comes up.
-- - "keys": Terminal can't be told what to paste, so tide takes the click,
--   focuses the window and sends Command+V.
-- What's selected in each is read through Accessibility, and kitty over its
-- socket.
M.TERMINALS = {
    ["net.kovidgoyal.kitty"] = "kitty",
    ["com.mitchellh.ghostty"] = "pasteboard",
    ["com.googlecode.iterm2"] = "clipboard",
    ["com.apple.Terminal"] = "keys",
}

-- Ghostty's selection pasteboard: its copy-on-select writes there, and its
-- middle click pastes it (its NSPasteboard+Extension.swift).
M.GHOSTTY_BOARD = "com.mitchellh.ghostty.selection"

-- iTerm2 copies each selection to the clipboard, so after a selecting
-- gesture there with Accessibility saying nothing, a clipboard that
-- changed since the button went down holds it.
M.ITERM = "com.googlecode.iterm2"

-- How long the clipboard is lent to iTerm2 when its button never comes up.
M.LEND_AT_MOST = 5

-- How far up from what's under the pointer to look for a text field: the
-- hit test can land on the text inside one.
M.DEPTH = 6

-- After a selecting gesture, before the selection is read: the app changes
-- it in its own time *(unverified on a Mac that this is long enough)*.
M.READ_AFTER = 0.1

-- After the click that places the caret, Command+V waits until the app
-- and window clicked are in front (M.ready), looking every CLICK_SETTLE seconds, FOCUS_TRIES
-- times at most: the keystroke goes to whichever app is in front, and a
-- click takes a moment to bring one there. After Command+V, the clipboard
-- is put back RESTORE_AFTER seconds later: the app pastes in its own
-- time, so sooner would paste the old clipboard *(unverified on a Mac
-- that this is long enough in a slow app)*.
M.CLICK_SETTLE = 0.05

-- Whether Command+V can go now: the app in front (`front_pid`) is the one
-- clicked (`pid`), and, where tide knows the window clicked (`win`), it's
-- the one focused (`front_win`). Two windows of one app are both in front
-- with it, so the app alone isn't enough: before the click moves the
-- focus, the keystroke would paste into the other window.
function M.ready(front_pid, front_win, pid, win)
    return front_pid ~= nil and front_pid == pid and (win == nil or front_win == win)
end
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
-- read: the setting is on, and it's on a text field, or anywhere in a
-- terminal. Anything else is the app's, so a link still opens in a new tab
-- and a tab still closes. Returns false and why.
function M.wants(on, app, chain)
    if not on then
        return false, "off"
    elseif M.TERMINALS[app] then
        return true
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

-- What a middle click in a terminal (`pid`) pastes: the last selection,
-- when it came from another app. The terminal's own is left to it, which
-- pastes it itself, so a program that has the mouse there, such as vim,
-- still gets its middle click.
function M.into_terminal(remembered, pid)
    if remembered and remembered.pid ~= pid and M.usable(remembered.text) then
        return remembered.text
    end
    return nil
end

-- kitty's selection, from `kitten @ get-text --extent=selection`'s output,
-- which ends in a newline it adds; nil for none.
function M.kitty_text(out)
    if type(out) ~= "string" then
        return nil
    end
    local text = out:gsub("\n$", "")
    if text == "" then
        return nil
    end
    return text
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
