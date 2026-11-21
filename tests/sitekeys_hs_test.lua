-- sitekeys_hs.lua against a stand-in hs: hotkeys made, enabled or not,
-- the keys posted, and the app, window title and Super key in a table.

local t = require("t")
local sitekeys_hs = require("tide.sitekeys_hs")

local CHROME = "com.google.Chrome"

-- A stand-in for Hammerspoon's hotkeys, as workspace_settings_test's.
local function fake_hs()
    local s = { made = {}, strokes = {} }
    s.hotkey = {
        new = function(mods, key, fn)
            if s.refuse == key then
                error("no such key")
            end
            local k = { mods = table.concat(mods, "+"), key = key, fn = fn, on = false }
            function k:enable()
                k.on = true
                return k
            end
            function k:disable()
                k.on = false
                return k
            end
            s.made[#s.made + 1] = k
            return k
        end,
    }
    s.eventtap = {
        keyStroke = function(mods, key)
            s.strokes[#s.strokes + 1] = table.concat(mods, "+") .. "+" .. key
        end,
    }
    function s.held()
        local out = {}
        for _, k in ipairs(s.made) do
            if k.on then
                out[#out + 1] = k.mods .. "+" .. k.key
            end
        end
        return out
    end
    -- A press of `chord`: the hotkey's, if one holds it, else the app's.
    function s.press(chord)
        for _, k in ipairs(s.made) do
            if k.on and k.mods .. "+" .. k.key == chord then
                k.fn()
                return "tide"
            end
        end
        return "app"
    end
    return s
end

-- The world tide sees: the Super key in use, the app in front and its
-- focused window's title, and the log.
local function setup(w)
    w = w or {}
    w.super = w.super or "win"
    w.front = w.front or CHROME
    w.logs = {}
    local hs = fake_hs()
    if w.refuse then
        hs.refuse = w.refuse
    end
    local keys = sitekeys_hs.new(hs, {
        rotated = function()
            return w.super == "win"
        end,
        front = function()
            if w.front_error then
                error(w.front_error, 0)
            end
            return w.front
        end,
        title = function()
            w.asked = (w.asked or 0) + 1
            return w.title
        end,
        log = function(text)
            w.logs[#w.logs + 1] = text
        end,
    })
    return hs, keys, w
end

local ALL = { "cmd+y", "cmd+h", "ctrl+/" }

t.test("nothing is held until a Google Docs window has focus", function()
    local hs, keys, w = setup({ title = "Inbox - Gmail" })
    t.eq(hs.held(), {})
    keys.check()
    t.eq(hs.held(), {})
    w.title = "Trip plan - Google Docs"
    keys.check()
    t.eq(hs.held(), ALL)
end)

t.test("a title change, as a tab switch makes, enables and disables them", function()
    local hs, keys, w = setup({ title = "Budget - Google Sheets" })
    keys.check()
    t.eq(hs.held(), ALL)
    w.title = "My Drive - Google Drive"
    keys.check()
    t.eq(hs.held(), {}, "Drive's tab")
    t.eq(hs.press("cmd+y"), "app")
    w.title = "Kickoff - Google Slides"
    keys.check()
    t.eq(hs.held(), ALL)
end)

t.test("another app in front gets the keys as ever", function()
    local hs, keys, w = setup({ title = "Trip plan - Google Docs" })
    keys.check()
    w.front = "com.apple.TextEdit"
    keys.check()
    t.eq(hs.held(), {})
    for _, chord in ipairs(ALL) do
        t.eq(hs.press(chord), "app", chord)
    end
    w.front = "com.apple.Safari"
    keys.check()
    t.eq(hs.held(), {}, "Safari isn't one of the browsers")
end)

t.test("the keys sent: Cmd+Y and Cmd+H find and replace, Ctrl+/ searches the menus", function()
    local hs, keys = setup({ title = "Trip plan - Google Docs" })
    keys.check()
    for _, chord in ipairs(ALL) do
        t.eq(hs.press(chord), "tide", chord)
    end
    t.eq(hs.strokes, { "cmd+shift+h", "cmd+shift+h", "alt+/" })
    t.eq(hs.held(), ALL, "still held after")
end)

t.test("the log names the site and keys", function()
    local w = { title = "Secret merger - Google Docs" }
    local hs, keys = setup(w)
    keys.check()
    hs.press("cmd+y")
    hs.press("ctrl+/")
    t.eq(w.logs, {
        "site keys: Google Docs: cmd+y sent as cmd+shift+h",
        "site keys: Google Docs: ctrl+/ sent as alt+/",
    })
    for _, line in ipairs(w.logs) do
        t.eq(line:find("Secret", 1, true), nil, "no title in the log")
    end
end)

t.test("with Super on left Option or plain Option, nothing is held or asked", function()
    for _, super in ipairs({ "option", "none" }) do
        local hs, keys, w = setup({ super = super, title = "Trip plan - Google Docs" })
        keys.check()
        t.eq(hs.held(), {}, super)
        t.eq(w.asked, nil, super .. ": the title isn't read")
        for _, chord in ipairs(ALL) do
            t.eq(hs.press(chord), "app", super .. ": " .. chord)
        end
        t.eq(hs.strokes, {}, super)
    end
end)

t.test("the Super key changing away from Win lets them go at the next check", function()
    local hs, keys, w = setup({ title = "Trip plan - Google Docs" })
    keys.check()
    t.eq(hs.held(), ALL)
    w.super = "option"
    keys.check()
    t.eq(hs.held(), {})
end)

t.test("a press that finds focus moved on goes to the app, with the hotkeys off", function()
    local hs, keys, w = setup({ title = "Trip plan - Google Docs" })
    keys.check()
    -- Focus moves to TextEdit, unheard, and Cmd+H comes first.
    w.front = "com.apple.TextEdit"
    t.eq(hs.press("cmd+h"), "tide")
    t.eq(hs.strokes, { "cmd+h" }, "posted on unchanged")
    t.eq(hs.held(), {})
    t.eq(w.logs, {})
end)

t.test("the title isn't read unless a browser is in front", function()
    local _, keys, w = setup({ front = "com.apple.TextEdit", title = "x - Google Docs" })
    keys.check()
    t.eq(w.asked, nil)
end)

t.test("a hotkey that can't be made is logged, and the rest still work", function()
    local hs, keys, w = setup({ refuse = "/", title = "Trip plan - Google Docs" })
    keys.check()
    t.eq(hs.held(), { "cmd+y", "cmd+h" })
    t.eq(#w.logs, 1)
    t.eq(w.logs[1]:find("couldn't make ctrl+/", 1, true) ~= nil, true, w.logs[1])
end)

t.test("a failed read of the window in front is logged, and holds nothing", function()
    local hs, keys, w = setup({ title = "Trip plan - Google Docs" })
    keys.check()
    t.eq(hs.held(), ALL)
    -- An Accessibility read can raise.
    w.front_error = "timed out"
    keys.check()
    t.eq(hs.held(), {})
    t.eq(w.logs, { "site keys: couldn't read the window in front: timed out" })
end)

t.done("sitekeys_hs")
