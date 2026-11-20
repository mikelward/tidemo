-- The dim on Hammerspoon (SPEC.md §5.6; dim.lua): one hs.canvas per
-- display, over the windows and under the bar, the tray, panels, menus and
-- the Dock, that the pointer clicks through. It paints the focused window's
-- shadow too, when tide's appearance says only that one casts one, with
-- macOS's own shadows off (§5.7; shadow.lua). Not runnable outside
-- Hammerspoon.

local dim = require("tide.dim")
local shadow = require("tide.shadow")

local M = {}

-- Over normal windows (level 0) and under floating ones (3), where the
-- bar, the tray, picture-in-picture and apps' panels sit *(unverified for
-- every app's panel)*.
M.LEVEL = 1
-- Events come in bursts, a drag's moves most of all: one redraw for each.
M.DEBOUNCE = 0.03

-- `tide` is the started tide module: its wm, adapter and clock_dir.
function M.new(tide)
    local self = { canvases = {}, drawn = {} }
    local a = tide.adapter
    local strength = dim.STRENGTH
    local major = hs.host.operatingSystemVersion().major
    local radius = dim.radius(major)
    local reported = ""
    local pending
    -- The shadows set, and whether macOS draws its own, as tide last set it
    -- (nil: not yet).
    local shadows = { mode = shadow.DEFAULT, size = shadow.SIZE }
    local macos_shadows

    -- macOS's own shadows on or off, for every window. setShadows is an
    -- undocumented call of Hammerspoon's *(unverified on macOS 26)*.
    local function set_macos(on)
        if on == macos_shadows then
            return
        end
        local ok, err = pcall(hs.window.setShadows, on)
        if ok then
            macos_shadows = on
            a.log("shadows: macOS's own " .. (on and "on" or "off"))
        else
            a.log("shadows: couldn't turn macOS's own " .. (on and "on" or "off") .. ": " .. tostring(err))
        end
    end

    -- The strength from tide's appearance files, again as they change.
    function self.load()
        local dir = tide.clock_dir
        local errors
        strength, errors = dim.load(a.read(dir .. "/" .. dim.SHARED_FILE), a.read(dir .. "/" .. dim.LOCAL_FILE),
            hs.json.decode)
        local shadow_errors
        shadows, shadow_errors = shadow.load(a.read(dir .. "/" .. shadow.SHARED_FILE),
            a.read(dir .. "/" .. shadow.LOCAL_FILE), hs.json.decode)
        for _, e in ipairs(shadow_errors) do
            errors[#errors + 1] = e
        end
        local text = table.concat(errors, "; ")
        if text ~= "" and text ~= reported then
            a.log("dim: " .. text)
        end
        reported = text
        set_macos(shadow.macos(shadows.mode))
    end

    local function drop(uuid)
        if self.canvases[uuid] then
            self.canvases[uuid]:delete()
        end
        self.canvases[uuid] = nil
        self.drawn[uuid] = nil
    end

    local function draw()
        local ok, err = pcall(function()
            local scene = tide.wm:dim_scene()
            local focus = shadow.painted(shadows) and tide.wm:focus_scene() or nil
            local size = shadow.painted(shadows) and shadows.size or 0
            -- The focused window's own corners, rounder with a toolbar.
            local id = (focus and focus.id) or (scene and scene.id)
            local own = id and a.has_toolbar and dim.radius(major, a.has_toolbar(id)) or radius
            local seen = {}
            for _, s in ipairs(tide.wm:screens()) do
                seen[s.uuid] = true
                local els = dim.layer(scene, focus, s.full, strength, radius, size, own)
                local key = els and hs.inspect(els) .. hs.inspect(s.full)
                if not els then
                    drop(s.uuid)
                elseif key ~= self.drawn[s.uuid] then
                    local c = self.canvases[s.uuid]
                    if not c then
                        c = hs.canvas.new(s.full)
                        c:level(M.LEVEL)
                        c:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces + hs.canvas.windowBehaviors.stationary)
                        self.canvases[s.uuid] = c
                    else
                        c:frame(s.full)
                    end
                    c:replaceElements(els)
                    c:show()
                    self.drawn[s.uuid] = key
                end
            end
            for uuid in pairs(self.canvases) do
                if not seen[uuid] then
                    drop(uuid)
                end
            end
        end)
        if not ok then
            a.log("dim: couldn't draw: " .. tostring(err))
        end
    end

    -- Something the dim shows may have changed: focus, a window's frame, the
    -- stacking or the displays.
    function self.update()
        if pending then
            return
        end
        pending = a.after(M.DEBOUNCE, function()
            pending = nil
            draw()
        end)
    end

    -- Focus moving to another app, Hammerspoon's own windows among them,
    -- which the window watchers leave out (hs_adapter.watch).
    self.apps = hs.application.watcher.new(function(_, event)
        if event == hs.application.watcher.activated then
            self.update()
        end
    end)
    self.apps:start()

    function self.stop()
        self.apps:stop()
        for uuid in pairs(self.canvases) do
            drop(uuid)
        end
        -- macOS's shadows back as tide found them: on.
        set_macos(true)
    end

    self.load()
    return self
end

return M
