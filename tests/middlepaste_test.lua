local t = require("t")
local middlepaste = require("tide.middlepaste")

local FIELD = { { role = "AXTextField", settable = true }, { role = "AXGroup" }, { role = "AXWindow" } }

t.test("only a plain middle click pastes: Super's maximizes, and other modifiers are the app's", function()
    t.eq(middlepaste.plain(2, {}), true)
    t.eq(middlepaste.plain(2, nil), true)
    t.eq(middlepaste.plain(2, { cmd = true, alt = true, ctrl = true }), false, "Super from Karabiner")
    t.eq(middlepaste.plain(2, { alt = true }), false)
    t.eq(middlepaste.plain(2, { shift = true }), false)
    t.eq(middlepaste.plain(3, {}), false, "a side button")
end)

t.test("a text field takes text, found from the text inside it too", function()
    t.eq(middlepaste.takes_text(FIELD), true)
    t.eq(middlepaste.takes_text({ { role = "AXStaticText" }, { role = "AXTextArea", settable = true } }), true)
    t.eq(middlepaste.takes_text({ { role = "AXComboBox", settable = true } }), true)
end)

t.test("a link, a tab, a page's text and a field that only shows text don't take it", function()
    t.eq(middlepaste.takes_text({ { role = "AXLink" }, { role = "AXGroup" }, { role = "AXWebArea" } }), false)
    t.eq(middlepaste.takes_text({ { role = "AXRadioButton" }, { role = "AXTabGroup" }, { role = "AXWindow" } }), false)
    t.eq(middlepaste.takes_text({ { role = "AXTextArea", settable = false }, { role = "AXWindow" } }), false, "a transcript")
    t.eq(middlepaste.takes_text({ { role = "AXStaticText" }, { role = "AXWebArea" }, { role = "AXTextArea", settable = true } }),
        false, "nothing past the page")
    t.eq(middlepaste.takes_text({}), false)
    t.eq(middlepaste.takes_text(nil), false, "nothing read")
    local deep = {}
    for i = 1, middlepaste.DEPTH do
        deep[i] = { role = "AXGroup" }
    end
    deep[#deep + 1] = { role = "AXTextField", settable = true }
    t.eq(middlepaste.takes_text(deep), false, "too far up to be what was clicked")
end)

t.test("a middle click is tide's only with the setting on, on a text field, outside a terminal", function()
    t.eq(middlepaste.wants(true, "com.apple.TextEdit", FIELD), true)
    t.eq({ middlepaste.wants(false, "com.apple.TextEdit", FIELD) }, { false, "off" })
    t.eq({ middlepaste.wants(true, "com.google.Chrome", { { role = "AXLink" } }) }, { false, "not a text field" })
    for _, app in ipairs({ "net.kovidgoyal.kitty", "com.mitchellh.ghostty", "com.googlecode.iterm2", "com.apple.Terminal" }) do
        t.eq({ middlepaste.wants(true, app, FIELD) }, { false, "a terminal's own" }, app)
    end
    t.eq(middlepaste.wants(true, nil, FIELD), true, "an app with no bundle ID")
end)

t.test("a drag, a double click and a Shift click may select; a plain click doesn't", function()
    t.eq(middlepaste.selects(true, 1, {}), true)
    t.eq(middlepaste.selects(false, 2, {}), true)
    t.eq(middlepaste.selects(false, 3, {}), true)
    t.eq(middlepaste.selects(false, 1, { shift = true }), true)
    t.eq(middlepaste.selects(false, 1, {}), false)
    t.eq(middlepaste.selects(false, nil, nil), false)
end)

t.test("the last selection made with the mouse is pasted into another app", function()
    local r = { text = "from A", pid = 1 }
    t.eq(middlepaste.pick(r, 2, nil), "from A")
    t.eq(middlepaste.pick(r, 2, "B's older selection"), "from A", "the app in front is the one pasted into")
end)

t.test("in the app it came from, what's selected now wins, and the last one stays once it's gone", function()
    local r = { text = "from A", pid = 1 }
    t.eq(middlepaste.pick(r, 1, "from A, extended"), "from A, extended")
    t.eq(middlepaste.pick(r, 1, ""), "from A")
    t.eq(middlepaste.pick(r, 1, nil), "from A")
end)

t.test("with nothing remembered, what's selected in front is pasted, or nothing", function()
    t.eq(middlepaste.pick(nil, 1, "typed selection"), "typed selection")
    t.eq(middlepaste.pick(nil, 1, ""), nil)
    t.eq(middlepaste.pick(nil, 1, nil), nil)
    t.eq(middlepaste.usable(""), false)
    t.eq(middlepaste.usable(nil), false)
    t.eq(middlepaste.usable(" "), true, "a space is a selection")
end)

t.test("the text goes on the pasteboard marked transient, which the clipboard history skips", function()
    local picker = require("tide.picker")
    local data = middlepaste.transient("hello")
    t.eq(data["public.utf8-plain-text"], "hello")
    local types = {}
    for uti in pairs(data) do
        types[#types + 1] = uti
    end
    t.eq(picker.keep(types), false)
end)

t.test("the clipboard goes back only while the pasteboard is as tide left it", function()
    t.eq(middlepaste.restores(7, 7), true)
    t.eq(middlepaste.restores(7, 8), false, "a copy made during the paste stays")
    t.eq(middlepaste.restores(nil, 7), false)
end)

t.test("Accessibility is asked for only with the setting on and macOS saying it's off", function()
    t.eq(middlepaste.should_ask(true, false), true)
    t.eq(middlepaste.should_ask(true, true), false)
    t.eq(middlepaste.should_ask(true, nil), false, "unknown says nothing")
    t.eq(middlepaste.should_ask(false, false), false)
    t.eq(middlepaste.NEEDS_ACCESSIBILITY:find("Privacy & Security, Accessibility", 1, true) ~= nil, true, "says where")
end)

t.done("middlepaste")
