-- The wallpapers from tide's appearance files (wallpaper.lua): read as
-- tide reads them, the local file's over the shared one's, shown for the
-- mode macOS is in, and a file chosen set as tide sets one.

local t = require("t")
local wallpaper = require("tilemo.wallpaper")
local json = require("json")

local HOME = "/Users/u"

t.test("each mode's wallpaper, the local file's over the shared one's", function()
    local walls, errors = wallpaper.load('{"lightWallpaper": "~/day.jpg", "darkWallpaper": "/srv/night.png"}',
        '{"darkWallpaper": "~/Pictures/dark.heic"}', json.decode)
    t.eq(walls, { light = "~/day.jpg", dark = "~/Pictures/dark.heic" })
    t.eq(errors, {})
end)

t.test("none set, or no files, leaves macOS's own", function()
    local walls = wallpaper.load(nil, nil, json.decode)
    t.eq(walls, { light = "", dark = "" })
    t.eq(wallpaper.now(walls, true, HOME), nil)
    t.eq(wallpaper.now(wallpaper.load('{"lightWallpaper": ""}', nil, json.decode), false, HOME), nil)
end)

t.test("what's wrong with a file is said, and its good settings still count", function()
    local walls, errors = wallpaper.load('{"lightWallpaper": "day.jpg", "darkWallpaper": "~/n.png"}', "{", json.decode)
    t.eq(walls, { light = "", dark = "~/n.png" })
    t.eq(errors, {
        "appearance.json: lightWallpaper must be a file's path, such as \"~/Pictures/day.jpg\", a color such as \"#1a1d2e\", or \"\" for the default",
        "appearance.local.json isn't a JSON object",
    })
end)

t.test("a color set on tide is a setting, drawn as rrggbb", function()
    local walls, errors = wallpaper.load('{"lightWallpaper": "#1A1D2E", "darkWallpaper": "#abc"}', nil, json.decode)
    t.eq(errors, {})
    t.eq({ wallpaper.now(walls, false, HOME) }, { nil, "1a1d2e" })
    t.eq({ wallpaper.now(walls, true, HOME) }, { nil, "aabbcc" })
    t.eq(wallpaper.color_file("/x", "aabbcc"), "/x/wallpaper-aabbcc.png")
    local _, bad = wallpaper.load('{"lightWallpaper": "#12"}', nil, json.decode)
    t.eq(bad, { 'appearance.json: lightWallpaper must be a color as #rrggbb or #rgb, such as "#1a1d2e"' })
end)

t.test("the picture shown is the mode's, from ~/ as home", function()
    local walls = { light = "~/Pictures/day.jpg", dark = "/srv/night.png" }
    t.eq(wallpaper.now(walls, false, HOME), "/Users/u/Pictures/day.jpg")
    t.eq(wallpaper.now(walls, true, HOME), "/srv/night.png")
end)

t.test("a file chosen is set from ~/ when it's home's", function()
    t.eq(wallpaper.setting("/Users/u/Pictures/Day one.jpg", HOME), "~/Pictures/Day one.jpg")
    t.eq(wallpaper.setting("/Library/Desktop Pictures/Sky.heic", HOME), "/Library/Desktop Pictures/Sky.heic")
    t.eq(wallpaper.setting("/Users/uv/a.png", HOME), "/Users/uv/a.png", "not /Users/uv, which only starts like home")
    t.eq(wallpaper.setting(nil, HOME), nil)
    t.eq(wallpaper.setting("a.png", HOME), nil)
end)

t.test("the picture's URL is encoded, as macOS takes one", function()
    t.eq(wallpaper.file_url("/Users/u/Pictures/Day one.jpg"), "file:///Users/u/Pictures/Day%20one.jpg")
    t.eq(wallpaper.file_url("/srv/a+b#c?é.png"), "file:///srv/a%2Bb%23c%3F%C3%A9.png")
end)

t.test("the chooser opens where the wallpaper is, or in Pictures", function()
    t.eq(wallpaper.folder("~/Pictures/walls/day.jpg", HOME), "/Users/u/Pictures/walls")
    t.eq(wallpaper.folder("/srv/night.png", HOME), "/srv")
    t.eq(wallpaper.folder("", HOME), "/Users/u/Pictures")
end)

t.done("wallpaper")
