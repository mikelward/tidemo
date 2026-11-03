-- The desktop picture from tide's wallpapers (wallpaper_hs.lua), against
-- stand-in displays, files and macOS's appearance: set on every display
-- for the mode it's in, again as the mode changes or a display comes, and
-- left alone with none set; and macOS's file dialog for choosing one.

local t = require("t")
local json = require("json")

local HOME = os.getenv("HOME") or ""

-- tilemo's world: `files` by path (tide's settings folder is /c/tide),
-- the pictures that exist, macOS's mode, and the dialog's answer.
local function stub(opts)
    local s = { logged = {}, set = {}, dark = opts.dark or false, chooser = opts.chooser }
    s.screens = {}
    -- A display, showing `url`.
    function s.add_screen(url)
        local i = #s.screens + 1
        local scr = { url = url or "file:///System/Library/Desktop%20Pictures/Sonoma.heic" }
        function scr.desktopImageURL(self, set)
            if set == nil then
                return self.url
            end
            self.url = set
            s.set[#s.set + 1] = { i, set }
        end
        s.screens[i] = scr
    end
    for _ = 1, opts.screens or 1 do
        s.add_screen()
    end
    _G.hs = {
        json = { decode = json.decode },
        host = {
            interfaceStyle = function()
                return s.dark and "Dark" or nil
            end,
        },
        fs = {
            attributes = function(path, what)
                t.eq(what, "mode")
                return (opts.pictures or {})[path] and "file" or nil
            end,
        },
        screen = {
            allScreens = function()
                return s.screens
            end,
            watcher = {
                new = function(fn)
                    s.screen_changed = fn
                    return { start = function() end }
                end,
            },
        },
        distributednotifications = {
            new = function(fn, name)
                t.eq(name, "AppleInterfaceThemeChangedNotification")
                s.theme_changed = fn
                return { start = function() end }
            end,
        },
        dialog = {
            chooseFileOrFolder = function(message, folder, files, dirs, many, types)
                s.asked = { message = message, folder = folder, files = files, dirs = dirs, many = many, types = types }
                return s.chooser
            end,
        },
    }
    local tilemo = {
        clock_dir = "/c/tide",
        adapter = {
            read = function(path)
                return (opts.files or {})[path]
            end,
            log = function(text)
                s.logged[#s.logged + 1] = text
            end,
        },
    }
    package.loaded["tilemo.wallpaper_hs"] = nil
    s.wall = require("tilemo.wallpaper_hs").new(tilemo)
    return s
end

local FILES = { ["/c/tide/appearance.json"] = '{"lightWallpaper": "/srv/day one.jpg", "darkWallpaper": "/srv/night.png"}' }
local PICTURES = { ["/srv/day one.jpg"] = true, ["/srv/night.png"] = true }

t.test("every display shows the wallpaper for the mode macOS is in", function()
    local s = stub({ files = FILES, pictures = PICTURES, screens = 2 })
    t.eq(s.set, { { 1, "file:///srv/day%20one.jpg" }, { 2, "file:///srv/day%20one.jpg" } })
end)

t.test("turning dark shows the dark one, and a new display gets it too", function()
    local s = stub({ files = FILES, pictures = PICTURES })
    s.dark = true
    s.theme_changed()
    t.eq(s.screens[1].url, "file:///srv/night.png")
    s.add_screen("file:///other.png")
    s.set = {}
    s.screen_changed()
    t.eq(s.set, { { 2, "file:///srv/night.png" } }, "only the display that didn't show it")
end)

t.test("with none set, or no such file, macOS's own picture stays", function()
    local s = stub({ files = {}, pictures = PICTURES })
    t.eq(s.set, {})
    local gone = stub({ files = FILES, pictures = {} })
    t.eq(gone.set, {})
    t.eq(gone.logged, { "wallpaper: no file at /srv/day one.jpg; the desktop picture stays as it is" })
end)

t.test("choosing opens macOS's dialog, offering images, where the wallpaper is", function()
    local s = stub({ files = FILES, pictures = PICTURES, chooser = { ["1"] = HOME .. "/Pictures/Dusk.heic" } })
    t.eq(s.wall.pick("darkWallpaper"), "~/Pictures/Dusk.heic")
    t.eq(s.asked, { message = "Choose the dark wallpaper", folder = "/srv", files = true, dirs = false, many = false,
        types = { "public.image" } })
end)

t.test("a cancel chooses nothing", function()
    local s = stub({ files = FILES, pictures = PICTURES })
    t.eq(s.wall.pick("lightWallpaper"), nil)
end)

t.done("wallpaper_hs")
