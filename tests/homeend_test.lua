local t = require("t")
local homeend = require("tide.homeend")

local FIELD = { role = "AXTextField", editable = false }
local PAGE = { role = "AXWebArea", editable = false }

t.test("Home and End in a text field go to the line's start and end", function()
    t.eq(homeend.arrow("home", "com.google.Chrome", FIELD), "left")
    t.eq(homeend.arrow("end", "com.google.Chrome", FIELD), "right")
    t.eq(homeend.arrow("home", "com.apple.TextEdit", { role = "AXTextArea" }), "left")
    t.eq(homeend.arrow("end", "com.apple.Safari", { role = "AXComboBox" }), "right")
end)

t.test("a web page's contenteditable counts as a text field", function()
    t.eq(homeend.arrow("home", "com.google.Chrome", { role = "AXGroup", editable = true }), "left")
end)

-- Command+Left there is Back: the keys stay themselves, and scroll.
t.test("on a page, or with nothing focused, Home and End stay as they are", function()
    t.eq(homeend.arrow("home", "com.google.Chrome", PAGE), nil)
    t.eq(homeend.arrow("end", "com.apple.Safari", PAGE), nil)
    t.eq(homeend.arrow("home", "com.apple.finder", nil), nil)
end)

t.test("terminals and Hammerspoon keep their own Home and End", function()
    for _, bundle in ipairs({ "net.kovidgoyal.kitty", "com.mitchellh.ghostty", "com.apple.Terminal",
        "com.googlecode.iterm2", "org.hammerspoon.Hammerspoon" }) do
        t.eq(homeend.arrow("home", bundle, { role = "AXTextArea" }), nil, bundle)
    end
end)

t.test("Home and End alone, with Shift or with Fn are looked at", function()
    t.eq(homeend.wants("home", {}), true)
    t.eq(homeend.wants("end", { shift = true }), true)
    t.eq(homeend.wants("home", { fn = true }), true)
    t.eq(homeend.wants("home", nil), true)
end)

-- Ctrl+Home is Karabiner's, as Command+Up; the rest are the app's.
t.test("Home and End with Command, Option or Control, and other keys, aren't", function()
    t.eq(homeend.wants("home", { cmd = true }), false)
    t.eq(homeend.wants("end", { alt = true }), false)
    t.eq(homeend.wants("home", { ctrl = true }), false)
    t.eq(homeend.wants("left", {}), false)
    t.eq(homeend.wants(nil, {}), false)
end)

t.test("no value and an unsupported attribute are expected; other errors aren't", function()
    t.eq(homeend.expected(nil), true)
    t.eq(homeend.expected("kAXErrorNoValue (-25212)"), true)
    t.eq(homeend.expected("kAXErrorAttributeUnsupported (-25205)"), true)
    t.eq(homeend.expected("kAXErrorCannotComplete (-25204)"), false)
    t.eq(homeend.expected("kAXErrorInvalidUIElement (-25202)"), false)
end)

t.done("homeend_test")
