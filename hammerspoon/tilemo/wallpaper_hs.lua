-- The desktop picture from tide's wallpapers, light and dark (SPEC.md §10;
-- wallpaper.lua): set on every display for the mode macOS is in, again as
-- the mode changes, a display comes, or the settings do. With none set
-- for the mode, macOS's own picture stays. And the settings window's file
-- chooser for one.

local wallpaper = require("tilemo.wallpaper")

local M = {}

-- `tilemo` is the started tilemo module: its clock_dir (tide's settings
-- folder) and adapter.
function M.new(tilemo)
    local self = {}
    local home = os.getenv("HOME") or ""
    local reported = ""

    local function walls()
        local dir = tilemo.clock_dir
        local read = tilemo.adapter.read
        local w, errors = wallpaper.load(read(dir .. "/" .. wallpaper.SHARED_FILE), read(dir .. "/" .. wallpaper.LOCAL_FILE),
            hs.json.decode)
        local text = table.concat(errors, "; ")
        if text ~= "" and text ~= reported then
            tilemo.adapter.log("wallpaper: " .. text)
        end
        reported = text
        return w
    end

    local function dark()
        return hs.host.interfaceStyle() == "Dark"
    end

    -- Set the mode's picture on every display that doesn't show it yet.
    local said_color = ""
    function self.apply()
        local w = walls()
        local set = w[dark() and "dark" or "light"]
        if wallpaper.is_color(set) then
            -- Said once for each color, not at every display or mode change.
            if set ~= said_color then
                tilemo.adapter.log("wallpaper: " .. set .. " is a color, which tide shows but a Mac can't set; the desktop picture stays as it is")
                said_color = set
            end
            return
        end
        local path = wallpaper.now(w, dark(), home)
        if not path then
            return
        end
        if hs.fs.attributes(path, "mode") ~= "file" then
            tilemo.adapter.log("wallpaper: no file at " .. path .. "; the desktop picture stays as it is")
            return
        end
        local url = wallpaper.file_url(path)
        for _, s in ipairs(hs.screen.allScreens()) do
            local ok, err = pcall(function()
                if s:desktopImageURL() ~= url then
                    s:desktopImageURL(url)
                end
            end)
            if not ok then
                tilemo.adapter.log("wallpaper: couldn't set " .. path .. ": " .. tostring(err))
            end
        end
    end

    -- The chooser for `key`'s wallpaper (wallpaper.KEYS), macOS's own file
    -- dialog, offering images, where it is now. Returns the setting for
    -- the file chosen, or nil for a cancel.
    function self.pick(key)
        local mode = key == wallpaper.KEYS.dark and "dark" or "light"
        local folder = wallpaper.folder(walls()[mode], home)
        local chosen = hs.dialog.chooseFileOrFolder("Choose the " .. mode .. " wallpaper", folder, true, false, false,
            { "public.image" })
        local path = chosen and (chosen["1"] or chosen[1])
        return wallpaper.setting(path, home)
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
