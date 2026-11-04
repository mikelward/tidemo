-- The Displays page's displays (displays.lua), through hs.screen: each one's
-- modes, where it is, whether it's the main one, and its brightness.

local displays = require("tilemo.displays")

local M = {}

-- `tilemo` is the started tilemo module: its adapter. `changed()` is
-- called as a display comes, goes or changes, for the page to redraw.
function M.new(tilemo, changed)
    local self = {}
    local log = tilemo.adapter.log

    local function frame(s)
        local f = s:fullFrame()
        return { x = f.x, y = f.y, w = f.w, h = f.h }
    end

    local function find(uuid)
        for _, s in ipairs(hs.screen.allScreens() or {}) do
            if s:getUUID() == uuid then
                return s
            end
        end
    end

    function self.state()
        local primary = hs.screen.primaryScreen()
        local main = primary and primary:getUUID()
        local readings = {}
        for _, s in ipairs(hs.screen.allScreens() or {}) do
            local brightness = s:getBrightness()
            readings[#readings + 1] = {
                uuid = s:getUUID(),
                name = s:name(),
                main = s:getUUID() == main,
                frame = frame(s),
                mode = s:currentMode(),
                modes = s:availableModes(),
                brightness = type(brightness) == "number" and brightness or nil,
            }
        end
        return displays.state(readings)
    end

    local function missing(uuid)
        log("displays: no display " .. tostring(uuid) .. " now")
    end

    self.act = {
        -- Only a size macOS lists for the display, at the scale it's at.
        set_size = function(uuid, w, h)
            local s = find(uuid)
            if not s then
                return missing(uuid)
            end
            local mode = s:currentMode()
            for _, m in ipairs(displays.sizes(s:availableModes(), mode and mode.scale)) do
                if m.w == w and m.h == h then
                    if not s:setMode(m.w, m.h, m.scale, m.freq, m.depth) then
                        log("displays: macOS didn't set " .. tostring(s:name()) .. " to " .. w .. "x" .. h)
                    end
                    return
                end
            end
            log("displays: " .. tostring(s:name()) .. " has no " .. w .. "x" .. h .. " at its scale")
        end,
        place = function(uuid, place)
            local s, main = find(uuid), hs.screen.primaryScreen()
            if not s or not main then
                return missing(uuid)
            end
            if s:getUUID() == main:getUUID() then
                return
            end
            local x, y = displays.origin(place, frame(s), frame(main))
            if x and not s:setOrigin(x, y) then
                log("displays: macOS didn't move " .. tostring(s:name()) .. " " .. place)
            end
        end,
        make_main = function(uuid)
            local s = find(uuid)
            if not s then
                return missing(uuid)
            end
            if not s:setPrimary() then
                log("displays: macOS didn't make " .. tostring(s:name()) .. " the main display")
            end
        end,
        set_brightness = function(uuid, level)
            local s = find(uuid)
            if not s then
                return missing(uuid)
            end
            if not s:setBrightness(level / 100) then
                log("displays: macOS didn't set " .. tostring(s:name()) .. "'s brightness")
            end
        end,
    }

    -- A message from the settings page, if it's one of the Displays page's.
    function self.handle(body)
        return displays.handle(body, self.act)
    end

    -- Kept, as Hammerspoon stops one that's collected.
    self.watch = hs.screen.watcher.new(function()
        changed()
    end)
    self.watch:start()

    return self
end

return M
