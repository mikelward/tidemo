-- The wallpaper grid's pictures (wallgrid.lua): the folders walked, each
-- picture's light or dark and collection, as tide for Linux's grid has
-- them, against a stand-in file system.

local t = require("t")
local wallgrid = require("tide.wallgrid")
local wallpaper = require("tide.wallpaper")

local HOME = "/Users/u"

-- A file system from `tree`: a folder is a table of its entries, a file
-- true, a link to nothing false, and a folder that can't be read "locked".
local function fs(tree)
    local function at(path)
        local node = tree
        for part in path:gmatch("[^/]+") do
            if type(node) ~= "table" then
                return nil
            end
            node = node[part]
        end
        return node
    end
    return {
        dir = function(path)
            local node = at(path)
            if node == "locked" then
                return nil, "Permission denied"
            end
            if type(node) ~= "table" then
                return nil, "No such file or directory"
            end
            local names = {}
            for name in pairs(node) do
                names[#names + 1] = name
            end
            return names
        end,
        kind = function(path)
            local node = at(path)
            if node == true then
                return "file"
            elseif type(node) == "table" or node == "locked" then
                return "directory"
            end
            return nil
        end,
    }
end

local TREE = {
    System = { Library = { ["Desktop Pictures"] = {
        ["Sonoma.heic"] = true,
        ["Sequoia Sunrise.heic"] = true,
        ["Hello Metallic Blue.madesktop"] = true,
        [".thumbnails"] = { ["Sonoma.heic"] = true },
        ["Solid Colors"] = { ["Stone.png"] = true, ["Teal.png"] = true },
        ["Ignored.txt"] = true,
    } } },
    Users = { u = { Pictures = {
        ["Photos Library.photoslibrary"] = { ["deep.jpg"] = true },
        Wallpapers = {
            ["city-day.jpg"] = true,
            ["city-night.jpg"] = true,
            ["lone-night.jpg"] = true,
            ["gone.jpg"] = false,
            Locked = "locked",
            ["A"] = { ["B"] = { ["C"] = { ["too-deep.jpg"] = true }, ["deep-enough.png"] = true } },
        },
    } } },
}

t.test("it walks macOS's folder, this Mac's and yours, passing over what isn't a picture", function()
    local found, problems = wallgrid.walk(wallgrid.folders(HOME), fs(TREE))
    t.eq(found, {
        "/System/Library/Desktop Pictures/Sequoia Sunrise.heic",
        "/System/Library/Desktop Pictures/Solid Colors/Stone.png",
        "/System/Library/Desktop Pictures/Solid Colors/Teal.png",
        "/System/Library/Desktop Pictures/Sonoma.heic",
        "/Users/u/Pictures/Wallpapers/A/B/deep-enough.png",
        "/Users/u/Pictures/Wallpapers/city-day.jpg",
        "/Users/u/Pictures/Wallpapers/city-night.jpg",
        "/Users/u/Pictures/Wallpapers/lone-night.jpg",
    }, "no aerial, hidden thumbnail, photo library, or picture too deep")
    t.eq(problems, {
        "couldn't read /Users/u/Pictures/Wallpapers/Locked: Permission denied",
        "passed over /Users/u/Pictures/Wallpapers/gone.jpg: a link to nothing, or gone",
    }, "/Library/Desktop Pictures isn't there, which isn't one")
end)

t.test("each picture's collection: macOS's, its subfolder's, this Mac's, or yours", function()
    t.eq(wallgrid.collection("/System/Library/Desktop Pictures/Sonoma.heic", HOME), "macOS")
    t.eq(wallgrid.collection("/System/Library/Desktop Pictures/Solid Colors/Teal.png", HOME), "Solid Colors")
    t.eq(wallgrid.collection("/Library/Desktop Pictures/Company.jpg", HOME), "This Mac")
    t.eq(wallgrid.collection("/Users/u/Pictures/Wallpapers/a/b.jpg", HOME), "Yours")
    t.eq(wallgrid.collection("/Users/u/Desktop/b.jpg", HOME), "Other")
end)

t.test("a light and dark pair shows for its mode; anything else for either", function()
    local modes = wallgrid.modes({
        "/w/city-day.jpg", "/w/city-night.jpg", "/w/lone-night.jpg",
        "/w/Big Sur Light.heic", "/w/Big Sur Dark.heic",
        "/w/adwaita-l.jpg", "/w/adwaita-d.jpg", "/w/warty-final-ubuntu-light-3840x2160.png",
        "/w/warty-final-ubuntu-dimmed-3840x2160.png", "/w/Sonoma.heic",
    })
    t.eq(modes["/w/city-day.jpg"], "light")
    t.eq(modes["/w/city-night.jpg"], "dark")
    t.eq(modes["/w/lone-night.jpg"], "", "no partner")
    t.eq(modes["/w/Big Sur Light.heic"], "light", "a space before the word, as macOS names them")
    t.eq(modes["/w/Big Sur Dark.heic"], "dark")
    t.eq(modes["/w/adwaita-l.jpg"], "light")
    t.eq(modes["/w/adwaita-d.jpg"], "dark")
    t.eq(modes["/w/warty-final-ubuntu-dimmed-3840x2160.png"], "dark", "a size at the end aside")
    t.eq(modes["/w/Sonoma.heic"], "", "a dynamic wallpaper changes by itself")
end)

t.test("the grid's pictures, by name, each with what choosing it sets", function()
    local images = wallgrid.images({
        "/Users/u/Pictures/Wallpapers/city-night.jpg",
        "/System/Library/Desktop Pictures/Sonoma.heic",
        "/Users/u/Pictures/Wallpapers/city-day.jpg",
    }, HOME, wallpaper.setting)
    t.eq(images, {
        { path = "/Users/u/Pictures/Wallpapers/city-day.jpg", name = "city-day", mode = "light", collection = "Yours",
            setting = "~/Pictures/Wallpapers/city-day.jpg" },
        { path = "/Users/u/Pictures/Wallpapers/city-night.jpg", name = "city-night", mode = "dark", collection = "Yours",
            setting = "~/Pictures/Wallpapers/city-night.jpg" },
        { path = "/System/Library/Desktop Pictures/Sonoma.heic", name = "Sonoma", mode = "", collection = "macOS",
            setting = "/System/Library/Desktop Pictures/Sonoma.heic" },
    })
end)

t.test("a thumbnail comes from macOS's own smaller copy first", function()
    t.eq(wallgrid.thumbnail_sources("/System/Library/Desktop Pictures/Sonoma.heic"), {
        "/System/Library/Desktop Pictures/.thumbnails/Sonoma.heic",
        "/System/Library/Desktop Pictures/.thumbnails/Sonoma.png",
        "/System/Library/Desktop Pictures/.thumbnails/Sonoma.jpg",
    })
end)

t.test("a thumbnail keeps its picture's shape, within its box", function()
    t.eq(wallgrid.thumb_size(6016, 6016, 320, 200), { w = 200, h = 200 })
    t.eq(wallgrid.thumb_size(5120, 2880, 320, 200), { w = 320, h = 180 })
    t.eq(wallgrid.thumb_size(100, 50, 320, 200), { w = 100, h = 50 }, "never larger than it is")
    t.eq(wallgrid.thumb_size(nil, nil, 320, 200), { w = 320, h = 200 })
end)

t.test("the displays' sizes, each once", function()
    t.eq(wallgrid.screens({ { w = 1512, h = 982 }, { w = 2560, h = 1440 }, { w = 2560, h = 1440 } }),
        { { width = 1512, height = 982 }, { width = 2560, height = 1440 } })
end)

t.done("wallgrid")
