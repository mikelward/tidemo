-- The desktop picture from tide's wallpapers, light and dark (SPEC.md §10;
-- wallpaper.lua): set on every display for the mode macOS is in, again as
-- the mode changes, a display comes, or the settings do. With none set
-- for the mode, macOS's own picture stays. And the settings window's file
-- chooser for one, and its grid of the wallpapers installed.

local wallpaper = require("tide.wallpaper")
local wallgrid = require("tide.wallgrid")
local imagesize = require("tide.imagesize")

local M = {}

-- `tide` is the started tide module: its clock_dir (tide's settings
-- folder) and adapter.
function M.new(tide)
    local self = {}
    local home = os.getenv("HOME") or ""
    local reported = ""

    -- The wallpapers set, and each mode's position (wallpaper.load's).
    local function walls()
        local dir = tide.clock_dir
        local read = tide.adapter.read
        local w, errors, positions = wallpaper.load(read(dir .. "/" .. wallpaper.SHARED_FILE),
            read(dir .. "/" .. wallpaper.LOCAL_FILE), hs.json.decode)
        local text = table.concat(errors, "; ")
        if text ~= "" and text ~= reported then
            tide.adapter.log("wallpaper: " .. text)
        end
        reported = text
        return w, positions
    end

    local function dark()
        return hs.host.interfaceStyle() == "Dark"
    end

    -- Where a color's picture is drawn: a folder of tide's own, kept
    -- across restarts, since macOS shows the file itself.
    local colors = home .. "/Library/Application Support/tide"

    -- The picture for color `hex`, drawn once: a small square of it, which
    -- macOS stretches to fill each display. Nil, logged, if it can't be:
    -- tried again at each change, but said once for each color.
    local said = {}
    local function drawn(hex)
        local path = wallpaper.color_file(colors, hex)
        if hs.fs.attributes(path, "mode") == "file" then
            return path
        end
        hs.fs.mkdir(colors)
        local ok, saved = pcall(function()
            local c = hs.canvas.new({ x = 0, y = 0, w = 64, h = 64 })
            c:appendElements({ type = "rectangle", action = "fill", fillColor = { hex = "#" .. hex, alpha = 1 } })
            local image = c:imageFromCanvas()
            c:delete()
            return image and image:saveToFile(path)
        end)
        if not ok or not saved then
            if not said[hex] then
                said[hex] = true
                tide.adapter.log("wallpaper: couldn't draw #" .. hex .. " to " .. path .. ": " .. tostring(saved)
                    .. "; the desktop picture stays as it is")
            end
            return nil
        end
        return path
    end

    -- Set the mode's picture, placed as its position says, on every display
    -- that doesn't show it so yet. A color's square is filled.
    function self.apply()
        local w, positions = walls()
        local is_dark = dark()
        local path, hex = wallpaper.now(w, is_dark, home)
        local placement = wallpaper.placement(positions[is_dark and "dark" or "light"])
        if hex then
            path = drawn(hex)
            placement = wallpaper.placement("fill")
        end
        if not path then
            return
        end
        if hs.fs.attributes(path, "mode") ~= "file" then
            tide.adapter.log("wallpaper: no file at " .. path .. "; the desktop picture stays as it is")
            return
        end
        -- Through JXA, as hs.screen:desktopImageURL can't say how to place
        -- it (wallpaper.desktop_script).
        local ok, out = tide.adapter.javascript(wallpaper.desktop_script(wallpaper.file_url(path), placement))
        if not ok then
            tide.adapter.log("wallpaper: couldn't set " .. path .. ": " .. tostring(out))
            return
        end
        local decoded, refused = pcall(hs.json.decode, out)
        if not decoded or type(refused) ~= "table" then
            tide.adapter.log("wallpaper: setting " .. path .. " gave back " .. tostring(out))
            return
        end
        for _, why in ipairs(refused) do
            tide.adapter.log("wallpaper: macOS didn't set " .. path .. " on a display: " .. tostring(why))
        end
    end

    -- The chooser for `key`'s wallpaper (wallpaper.KEYS), macOS's own file
    -- dialog, offering images, where it is now. Returns the setting for
    -- the file chosen, or nil for a cancel.
    function self.pick(key)
        local mode = key == wallpaper.KEYS.dark and "dark" or "light"
        local folder = wallpaper.folder((walls())[mode], home)
        local chosen = hs.dialog.chooseFileOrFolder("Choose the " .. mode .. " wallpaper", folder, true, false, false,
            { "public.image" })
        local path = chosen and (chosen["1"] or chosen[1])
        return wallpaper.setting(path, home)
    end

    -- hs.fs as wallgrid.walk takes it: a folder's names, and what a path
    -- is, through links.
    local files = {
        dir = function(path)
            local ok, iter, obj = pcall(hs.fs.dir, path)
            if not ok or not iter then
                return nil, ok and obj or iter
            end
            local names = {}
            for name in iter, obj do
                names[#names + 1] = name
            end
            return names
        end,
        kind = function(path)
            return hs.fs.attributes(path, "mode")
        end,
    }

    -- Each picture's thumbnail as a data: URL, kept for the session, so
    -- the grid opens at once the second time; and its size, when its
    -- header didn't say.
    local thumbs = {}
    local THUMB_W, THUMB_H = 320, 200
    local function thumbnail(path)
        local source = path
        for _, p in ipairs(wallgrid.thumbnail_sources(path)) do
            if hs.fs.attributes(p, "mode") == "file" then
                source = p
                break
            end
        end
        local ok, got = pcall(function()
            local image = hs.image.imageFromPath(source)
            if not image then
                return nil
            end
            local size = image:size()
            local box = wallgrid.thumb_size(size.w, size.h, THUMB_W, THUMB_H)
            return { url = image:setSize(box, true):encodeAsURLString(false, "JPEG"), width = size.w, height = size.h }
        end)
        if not ok or not got or type(got.url) ~= "string" then
            tide.adapter.log("wallpaper grid: couldn't draw a thumbnail of " .. path .. ": "
                .. tostring(ok and "macOS couldn't read it" or got))
            return nil
        end
        return got
    end

    -- The wallpaper grid's pictures (wallgrid.lua): `list` gets them at
    -- once, { images, screens, problems }, each image with its size from
    -- its header (0 for none) and its thumbnail if it's been drawn; then
    -- `thumb` gets each thumbnail not yet drawn, { path, url, width,
    -- height }, one a tick, until the grid closes or opens again.
    local generation = 0
    function self.gallery(list, thumb)
        generation = generation + 1
        local mine = generation
        local found, problems = wallgrid.walk(wallgrid.folders(home), files)
        for _, p in ipairs(problems) do
            tide.adapter.log("wallpaper grid: " .. p)
        end
        local images = wallgrid.images(found, home, wallpaper.setting)
        for _, img in ipairs(images) do
            local w, h = imagesize.read(img.path)
            img.width, img.height = w or 0, h or 0
            img.thumb = thumbs[img.path] and thumbs[img.path].url or nil
        end
        local frames = {}
        for _, s in ipairs(hs.screen.allScreens()) do
            local f = s:fullFrame()
            frames[#frames + 1] = { w = f.w, h = f.h }
        end
        list({ images = images, screens = wallgrid.screens(frames), problems = problems })
        local i = 0
        local function next_thumb()
            if mine ~= generation then
                return
            end
            i = i + 1
            local img = images[i]
            if not img then
                return
            end
            if thumbs[img.path] == nil then
                local got = thumbnail(img.path)
                -- One that can't be drawn isn't tried, or said, again.
                thumbs[img.path] = got or false
                if got then
                    thumb({ path = img.path, url = got.url, width = got.width, height = got.height })
                end
            end
            tide.adapter.after(0, next_thumb)
        end
        next_thumb()
    end

    -- The grid closed: no more thumbnails for it.
    function self.gallery_closed()
        generation = generation + 1
    end

    -- Kept, as Hammerspoon stops one that's collected.
    self.theme_watch = hs.distributednotifications.new(function()
        self.apply()
    end, "AppleInterfaceThemeChangedNotification")
    self.theme_watch:start()
    self.screen_watch = hs.screen.watcher.new(function()
        self.apply()
    end)
    self.screen_watch:start()
    self.apply()
    return self
end

return M
