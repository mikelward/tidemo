-- The workspaces in the menu bar's middle (SPEC.md §8, Position: Middle of
-- menu bar): where they go, beside a notch or in the middle, and when the
-- app's menus leave no room.
local t = require("t")
local notchbar = require("tide.notchbar")
local json = require("json")

-- A 14-inch MacBook Pro's display: a 37 pt menu bar, and a notch 188 pt
-- wide in the middle.
local NOTCHED = {
    uuid = "A",
    full = { x = 0, y = 0, w = 1512, h = 982 },
    area = { x = 0, y = 37, w = 1512, h = 945 },
    notch = true,
    menu_bar = true,
}
local NOTCH = { left = 662, right = 850 }
-- A plain display to its right, with a 24 pt menu bar.
local PLAIN = {
    uuid = "B",
    full = { x = 1512, y = 0, w = 1920, h = 1080 },
    area = { x = 1512, y = 24, w = 1920, h = 1056 },
    menu_bar = true,
}

t.test("each workspace is a chip, cut as the bar cuts it, looking as it is", function()
    local chips = notchbar.chips({
        { name = "in", here = true },
        { name = "docs", occupied = true },
        { name = "web" },
        { name = "ABC-123 fix the login page", urgent = true, here = false },
    })
    t.eq(chips[1].look, "here")
    t.eq(chips[1].here, true)
    t.eq(chips[2].look, "occupied")
    t.eq(chips[3].look, "empty")
    t.eq(chips[4].look, "urgent")
    t.eq(chips[4].label, "ABC-123 fix the …")
    t.eq(chips[4].name, "ABC-123 fix the login page", "a click still names it whole")
    t.eq(notchbar.chips({ { name = "in", here = true, urgent = true } })[1].look, "urgent", "wanting attention shows over current")
end)

t.test("chips sit side by side, padded, with a small gap", function()
    local boxes, w = notchbar.layout({ 10, 20 })
    t.eq(boxes[1], { x = 0, w = 10 + 2 * notchbar.PAD })
    t.eq(boxes[2], { x = 10 + 2 * notchbar.PAD + notchbar.GAP, w = 20 + 2 * notchbar.PAD })
    t.eq(w, 30 + 4 * notchbar.PAD + notchbar.GAP)
    local _, none = notchbar.layout({})
    t.eq(none, 0)
end)

t.test("beside a notch, the names end just left of it, in the menu bar", function()
    local f = notchbar.place(NOTCHED, 120, NOTCH, 300)
    t.eq(f, { x = 662 - notchbar.MARGIN - 120, y = 0, w = 120, h = 37 })
end)

t.test("an app's menus reaching the names leave no room", function()
    local f, why = notchbar.place(NOTCHED, 120, NOTCH, 540)
    t.eq(f, nil)
    t.eq(why, "the app's menus leave no room")
    t.eq(notchbar.place(NOTCHED, 120, NOTCH, 662 - 2 * notchbar.MARGIN - 120) ~= nil, true, "just enough")
end)

t.test("without a notch, the names are centered, or moved right of the menus", function()
    local f = notchbar.place(PLAIN, 200, nil, 300)
    t.eq(f, { x = 1512 + 860, y = 0, w = 200, h = 24 })
    f = notchbar.place(PLAIN, 200, nil, 900)
    t.eq(f.x, 1512 + 900 + notchbar.MARGIN, "past the menus")
    local none, why = notchbar.place(PLAIN, 200, nil, 1100)
    t.eq(none, nil, "but not into the status items")
    t.eq(why, "the app's menus leave no room")
end)

t.test("menus that couldn't be read never let the names cover them", function()
    local f, why = notchbar.place(NOTCHED, 120, NOTCH, nil)
    t.eq(f, nil)
    t.eq(why, "the app's menus couldn't be read")
    t.eq(notchbar.place(PLAIN, 120, nil, notchbar.menus_end(nil, { PLAIN })), nil, "nor without a notch")
end)

t.test("a display with no menu bar of its own, or a hidden one, gets none", function()
    local hidden = { full = NOTCHED.full, area = NOTCHED.area, notch = true, menu_bar = false }
    local _, why = notchbar.place(hidden, 50, NOTCH, 0)
    t.eq(why, "no menu bar")
    local bare = { full = PLAIN.full, area = PLAIN.full }
    t.eq(notchbar.has_menu_bar(bare), false, "no room kept above the frame")
    t.eq(notchbar.has_menu_bar(PLAIN), true)
end)

t.test("the notch is where macOS says, or guessed in the middle", function()
    local areas = {
        { x = 0, y = 0, w = 1512, left = 662, right = 662 },
        { x = 1512, y = 0, w = 1920, left = 0, right = 0 },
    }
    t.eq(notchbar.notch_of(NOTCHED, areas), { left = 662, right = 850 })
    -- A plain display above the MacBook's, as wide and at the same x.
    local stacked = { full = { x = 0, y = -982, w = 1512, h = 982 }, area = { x = 0, y = -958, w = 1512, h = 958 }, menu_bar = true }
    t.eq(notchbar.notch_of(stacked, { areas[1], { x = 0, y = -982, w = 1512, left = 0, right = 0 } }), nil,
        "not the MacBook's notch")
    t.eq(notchbar.notch_of(PLAIN, areas), nil, "no auxiliary areas, no notch")
    local mid = 1512 / 2
    t.eq(notchbar.notch_of(NOTCHED, {}), { left = mid - notchbar.NOTCH_GUESS / 2, right = mid + notchbar.NOTCH_GUESS / 2 },
        "a notch by its room but nothing read")
    t.eq(notchbar.notch_of(PLAIN, nil), nil)
end)

t.test("the app's menus reach from the left of the display they're on", function()
    local screens = { NOTCHED, PLAIN }
    local frames = {
        { x = 1522, y = 0, w = 30, h = 24 },
        { x = 1560, y = 0, w = 60, h = 24 },
        { x = 1630, y = 0, w = 0, h = 24 },
    }
    t.eq(notchbar.menus_end(frames, screens), 1620 - 1512)
    t.eq(notchbar.menus_end({}, screens), 0, "an app with no menus")
    t.eq(notchbar.menus_end(nil, screens), nil, "menus that couldn't be read")
    -- A display above the main one, overlapping it across: the menus are
    -- on the upper one, by their y.
    local main = { full = { x = 0, y = 0, w = 1512, h = 982 } }
    local above = { full = { x = 300, y = -1080, w = 1920, h = 1080 } }
    t.eq(notchbar.menus_end({ { x = 310, y = -1080, w = 390, h = 24 } }, { main, above }), 400)
    t.eq(notchbar.menus_end({ { x = "?", w = 3 } }, screens), nil, "nothing usable")
end)

t.test("the menu bar item stays while any display can't show the names", function()
    t.eq(notchbar.enough({ "drawn", "drawn" }), true)
    t.eq(notchbar.enough({ "drawn", "full screen" }), true, "a full-screen window hides the menu bar too")
    t.eq(notchbar.enough({ "drawn", "no room" }), false, "an app's menus in the way on one")
    t.eq(notchbar.enough({ "drawn", "no menu bar" }), false, "no menu bar tide can see on one")
    t.eq(notchbar.enough({ "no menu bar" }), false, "the menu bar hidden")
    t.eq(notchbar.enough({}), false, "no displays")
end)

t.test("a click lands on the chip under it", function()
    local chips = notchbar.chips({ { name = "in", here = true }, { name = "web" } })
    local boxes = notchbar.layout({ 10, 20 })
    t.eq(notchbar.hit(chips, boxes, 1), "in")
    t.eq(notchbar.hit(chips, boxes, boxes[2].x + 1), "web")
    t.eq(notchbar.hit(chips, boxes, boxes[1].w + 0.5), nil, "between chips")
    t.eq(notchbar.hit(chips, boxes, 999), nil)
end)

local run = require("jsrun")("the notch script")
if run then
    t.test("the notch script gives each display's frame and the room either side of its notch", function()
        local fake = [[
var ObjC = { import: function () {} };
function screen(x, y, w, h, left, right) {
  return {
    frame: { origin: { x: x, y: y }, size: { width: w, height: h } },
    respondsToSelector: function () { return left !== undefined; },
    auxiliaryTopLeftArea: { size: { width: left } },
    auxiliaryTopRightArea: { size: { width: right } },
  };
}
var list = [screen(0, 0, 1512, 982, 662, 662), screen(1512, 0, 1920, 1080), screen(0, 982, 1512, 982)];
var $ = { NSScreen: { screens: { count: 3, objectAtIndex: function (i) { return list[i]; } } } };
]]
        local ok, out = run(fake .. notchbar.SCREENS_SCRIPT)
        t.eq(ok, true, out)
        local areas = json.decode(out)
        t.eq(areas, {
            { x = 0, y = 0, w = 1512, left = 662, right = 662 },
            { x = 1512, y = -98, w = 1920, left = 0, right = 0 },
            { x = 0, y = -982, w = 1512, left = 0, right = 0 },
        }, "y down from the main display's top; before macOS 12, no notch")
        t.eq(notchbar.notch_of(NOTCHED, areas), NOTCH)
    end)
end

t.done("notchbar")
