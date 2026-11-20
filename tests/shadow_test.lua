-- Window shadows (shadow.lua, dim.layer, SPEC.md §5.7): which windows cast
-- one, from tide's appearance files, whether macOS's own stay on, and the
-- shadow tide paints round the focused window.

local t = require("t")
local shadow = require("tide.shadow")
local dim = require("tide.dim")
local json = require("json")
local fake = require("fake")
local wm_mod = require("tide.wm")

local function setup(n)
    local a = fake.new()
    for i = 1, n do
        a.add(i, {})
    end
    local wm = wm_mod.new(a, {})
    wm:sync()
    wm:retile()
    return a, wm
end

t.test("tide's defaults until a file says, the local file's over the shared one's", function()
    t.eq({ shadow.load(nil, nil, json.decode) }, { { mode = "focused", size = 16 }, {} })
    t.eq({ shadow.load('{"shadows": "all", "shadowSize": 12}', '{"shadows": "none"}', json.decode) },
        { { mode = "none", size = 12 }, {} })
end)

t.test("a bad value is said, naming the setting, and the one before it stands", function()
    local s, errors = shadow.load('{"shadows": "floating", "shadowSize": 4}', '{"shadows": "some", "shadowSize": 33}',
        json.decode)
    t.eq(s, { mode = "floating", size = 4 })
    t.eq(errors, {
        'appearance.local.json: shadows must be one of "none", "floating", "focused", "all"',
        "appearance.local.json: shadowSize must be a whole number from 0 to 32",
    })
    s, errors = shadow.load('{"shadowSize": 2.5}', "{", json.decode)
    t.eq(s, { mode = "focused", size = 16 })
    t.eq(errors, {
        "appearance.json: shadowSize must be a whole number from 0 to 32",
        "appearance.local.json isn't a JSON object",
    })
end)

-- macOS shadows every window or none.
t.test("macOS's own shadows stay on for all and floating, and go for none and focused", function()
    t.eq(shadow.macos("all"), true)
    t.eq(shadow.macos("floating"), true, "the nearest macOS allows")
    t.eq(shadow.macos("none"), false)
    t.eq(shadow.macos("focused"), false, "tide paints that one")
    t.eq(shadow.painted({ mode = "focused", size = 8 }), true)
    t.eq(shadow.painted({ mode = "focused", size = 0 }), false, "a size of 0 is none")
    t.eq(shadow.painted({ mode = "all", size = 8 }), false)
end)

t.test("a lone window casts a shadow, though it isn't dimmed", function()
    local a, wm = setup(1)
    a.focus(1)
    wm:focused(1)
    t.eq(wm:dim_scene(), nil, "not dimmed")
    local focus = wm:focus_scene()
    t.eq(focus.focused ~= nil, true)
    t.eq(focus.alone, true)
end)

local full = { x = 0, y = 0, w = 1000, h = 800 }
local win = { x = 100, y = 100, w = 400, h = 300 }

t.test("the shadow is the window's shape, shadowed, with its body cut out", function()
    local els = dim.layer(nil, { focused = win, above = {} }, full, 0.12, 10, 8)
    t.eq(#els, 2, "no dim: the shadow and the hole")
    t.eq(els[1].withShadow, true)
    t.eq(els[1].shadow.blurRadius, 8)
    t.eq(els[1].frame, win)
    t.eq(els[2].compositeRule, "destinationOut")
    t.eq(els[2].frame, win)
end)

t.test("with the dim on, the shadow sits on it, and one hole cuts both", function()
    local els = dim.layer({ focused = win, above = {} }, { focused = win, above = {} }, full, 0.12, 10, 8)
    t.eq(els[1].fillColor.alpha, 0.12, "the dim first")
    t.eq(els[2].withShadow, true)
    t.eq(els[3].compositeRule, "destinationOut")
    t.eq(#els, 3)
end)

-- A floating window in front of the focused one, over its shadow, takes
-- none of it.
t.test("a window in front of the focused one is cleared of its shadow", function()
    local front = { x = 495, y = 150, w = 200, h = 100 }
    local els = dim.layer(nil, { focused = win, above = { front } }, full, 0, 10, 8)
    local last = els[#els]
    t.eq(last.compositeRule, "copy")
    t.eq(last.fillColor.alpha, 0, "cleared, with no dim to keep")
    t.eq(last.frame, front)
end)

t.test("no shadow and no dim draws nothing, and the dim alone is as it was", function()
    t.eq(dim.layer(nil, { focused = win, above = {} }, full, 0, 10, 0), nil)
    t.eq(dim.layer(nil, nil, full, 0.12, 10, 8), nil)
    t.eq(dim.elements({ focused = win, above = {} }, full, 0.12, 10),
        dim.layer({ focused = win, above = {} }, { focused = win, above = {} }, full, 0.12, 10, 0))
end)

-- A window with a toolbar, as System Settings', is rounder on macOS 26: the
-- shadow and the hole follow its corners, so neither pokes out past them;
-- a window in front keeps the usual corners.
t.test("the shadow and the hole follow the focused window's own corners", function()
    local front = { x = 495, y = 150, w = 200, h = 100 }
    local els = dim.layer(nil, { focused = win, above = { front } }, full, 0, 16, 8, 26)
    t.eq(els[1].roundedRectRadii, { xRadius = 26, yRadius = 26 }, "the shadow")
    t.eq(els[2].roundedRectRadii, { xRadius = 26, yRadius = 26 }, "the hole")
    t.eq(els[3].roundedRectRadii, { xRadius = 16, yRadius = 16 }, "the window in front")
    t.eq(dim.layer(nil, { focused = win, above = {} }, full, 0, 16, 8)[1].roundedRectRadii,
        { xRadius = 16, yRadius = 16 }, "with no corners of its own, the usual")
end)

t.test("the focus scene names the focused window, for its corners", function()
    local a = fake.new()
    a.add(1, {})
    local wm = wm_mod.new(a, {})
    wm:sync()
    wm:retile()
    a.focus_ = 1
    wm:focused(1)
    t.eq(wm:focus_scene().id, 1)
end)

-- A dialog's corners are its app's own, so tide paints no shadow round it;
-- the dim still has its hole.
t.test("a dialog casts no painted shadow", function()
    t.eq(dim.layer(nil, { focused = win, dialog = true, above = {} }, full, 0, 16, 8), nil, "no dim, nothing")
    local els = dim.layer({ focused = win, above = {} }, { focused = win, dialog = true, above = {} }, full, 0.12, 16, 8)
    t.eq(#els, 2, "the dim and its hole")
    t.eq(els[2].compositeRule, "destinationOut")
    local a = fake.new()
    a.add(1, {})
    a.add(2, { subrole = "AXDialog", title = "Leave site?" })
    local wm = wm_mod.new(a, {})
    wm:sync()
    wm:retile()
    a.focus_ = 2
    wm:focused(2)
    t.eq(wm:focus_scene().dialog, true)
    a.focus_ = 1
    wm:focused(1)
    t.eq(wm:focus_scene().dialog, false, "a standard window")
end)

t.done("shadow")
