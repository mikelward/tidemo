-- The workspaces in the menu bar's middle on Hammerspoon (SPEC.md §8,
-- Position: Middle of menu bar): notchbar.lua's strip as an hs.canvas per
-- display, over the menu bar just left of a notch, or in the middle
-- without one. Not runnable outside Hammerspoon.

local notchbar = require("tide.notchbar")
local bar = require("tide.bar")

local M = {}

local function colors()
    local dark = hs.host.interfaceStyle() == "Dark"
    local fg = dark and { white = 0.95, alpha = 1 } or { white = 0.08, alpha = 1 }
    return {
        here = fg,
        occupied = fg,
        empty = dark and { white = 0.95, alpha = 0.45 } or { white = 0.08, alpha = 0.45 },
        urgent = { red = 1, green = 0.62, blue = 0.04, alpha = 1 },
        pill = dark and { white = 1, alpha = 0.2 } or { white = 0, alpha = 0.12 },
    }
end

local function font(here)
    local f = here and hs.styledtext.defaultFonts.boldSystem or hs.styledtext.defaultFonts.menuBar
    return { name = f.name, size = notchbar.TEXT_SIZE }
end

-- `tide` is the started tide module: its wm and adapter. `changed` is
-- called when what fits may have changed (the front app or its menus), for
-- tide to show or hide the menu bar item it falls back on.
function M.new(tide, changed)
    local self = { canvases = {}, failed = {} }
    local log = tide.adapter.log

    -- Log a lasting failure once, and again only once it changes.
    local function once(what, err)
        if self.failed[what] ~= tostring(err) then
            self.failed[what] = tostring(err)
            log("menu bar workspaces: " .. what .. ": " .. tostring(err))
        end
    end

    -- Each display's notch, from NSScreen, read again only when the
    -- displays change.
    local areas, areas_key
    local function notch_areas(screens)
        local parts = {}
        for _, s in ipairs(screens) do
            parts[#parts + 1] = string.format("%s:%g,%g", s.uuid, s.full.x, s.full.w)
        end
        local key = table.concat(parts, ";")
        if key ~= areas_key then
            areas_key = key
            local ok, out = tide.adapter.javascript(notchbar.SCREENS_SCRIPT)
            local decoded = ok and tide.adapter.decode(out)
            if type(decoded) == "table" then
                areas = decoded
                self.failed.notch = nil
            else
                areas = {}
                once("couldn't read where the notch is, so it's guessed", ok and "not JSON" or out)
            end
        end
        return areas
    end

    -- The front app's menu bar items' frames, or nil when they can't be
    -- read. hs.axuielement's calls return nil and why rather than raise,
    -- so each is checked: unknown menus mustn't read as none, or the names
    -- would cover them.
    local last_frames
    local function menu_frames()
        -- Asking Accessibility about Hammerspoon from its own thread waits
        -- out a timeout (hs_adapter's a.focused), so with tide's launcher,
        -- Settings or the console in front, the last app's menus stand in:
        -- Hammerspoon's own few menus are rarely wider. Before any, they're
        -- unknown, and the menu bar item shows.
        if tide.adapter.own_front and tide.adapter.own_front() then
            return last_frames
        end
        local ok, frames, err = pcall(function()
            local app = hs.application.frontmostApplication()
            if not app then
                return nil, "no front app"
            end
            local el = hs.axuielement.applicationElement(app)
            if not el then
                return nil, "no Accessibility element for the front app"
            end
            local mb, why = el:attributeValue("AXMenuBar")
            if not mb then
                return nil, "no menu bar: " .. tostring(why)
            end
            local items
            items, why = mb:attributeValue("AXChildren")
            if type(items) ~= "table" then
                return nil, "no menus: " .. tostring(why)
            end
            local out = {}
            for _, item in ipairs(items) do
                local f
                f, why = item:attributeValue("AXFrame")
                if type(f) ~= "table" then
                    return nil, "a menu without a frame: " .. tostring(why)
                end
                out[#out + 1] = { x = f.x, y = f.y, w = f.w, h = f.h }
            end
            return out
        end)
        if not ok then
            err = frames
            frames = nil
        end
        if not frames then
            once("couldn't read the app's menus, so the names show in the menu bar item", err)
            return nil
        end
        self.failed.menus = nil
        last_frames = frames
        return frames
    end

    local function hide(uuid)
        local c = self.canvases[uuid]
        if c and c.shown then
            c.canvas:hide()
            c.shown = false
        end
    end

    local function draw(s, frame, chips, boxes, look)
        local c = self.canvases[s.uuid]
        if not c then
            local canvas = hs.canvas.new(frame)
            canvas:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces + hs.canvas.windowBehaviors.stationary)
            canvas:clickActivating(false)
            canvas:canvasMouseEvents(true, false, false, false)
            c = { canvas = canvas, shown = false }
            canvas:mouseCallback(function(_, message, _, x)
                if message == "mouseDown" then
                    local n = notchbar.hit(c.chips, c.boxes, x)
                    if n then
                        tide.wm:act("show", n)
                    end
                end
            end)
            self.canvases[s.uuid] = c
        end
        c.chips, c.boxes = chips, boxes
        -- Nothing new to draw, every two seconds (init.lua's poll).
        local parts = { frame.x, frame.y, frame.w, frame.h, look.here.white }
        for _, chip in ipairs(chips) do
            parts[#parts + 1] = chip.label .. "/" .. chip.look
        end
        local key = table.concat(parts, "|")
        if c.key == key and c.shown then
            return
        end
        c.key = key
        local level = bar.level(s, "top")
        if c.level ~= level then
            c.level = level
            c.canvas:level(hs.canvas.windowLevels[level])
        end
        c.canvas:frame(frame)
        local els = {}
        local pill_h = math.max(0, math.min(22, frame.h - 6))
        for i, chip in ipairs(chips) do
            local b = boxes[i]
            if chip.here then
                els[#els + 1] = {
                    type = "rectangle",
                    action = "fill",
                    fillColor = look.pill,
                    roundedRectRadii = { xRadius = 6, yRadius = 6 },
                    frame = { x = b.x, y = (frame.h - pill_h) / 2, w = b.w, h = pill_h },
                }
            end
            local text = hs.styledtext.new(chip.label, { font = font(chip.here), color = look[chip.look] })
            local size = hs.drawing.getTextDrawingSize(text)
            els[#els + 1] = {
                type = "text",
                text = text,
                frame = { x = b.x + notchbar.PAD, y = (frame.h - size.h) / 2, w = b.w - notchbar.PAD + 2, h = size.h + 2 },
            }
        end
        c.canvas:replaceElements(els)
        if not c.shown then
            c.canvas:show()
            c.shown = true
        end
    end

    -- Draw the strip on each display with a menu bar showing. Returns
    -- whether that's enough on its own (notchbar.enough); otherwise tide
    -- shows the menu bar item as well.
    function self.update()
        local screens = tide.adapter.screens()
        local chips = notchbar.chips(tide.wm:bar_state())
        local look = colors()
        local widths = {}
        for i, chip in ipairs(chips) do
            local size = hs.drawing.getTextDrawingSize(hs.styledtext.new(chip.label, { font = font(chip.here) }))
            widths[i] = math.ceil(size.w)
        end
        local boxes, w = notchbar.layout(widths)
        local menus_end = notchbar.menus_end(menu_frames(), screens)
        local outcomes, present = {}, {}
        for _, s in ipairs(screens) do
            present[s.uuid] = true
            if not notchbar.has_menu_bar(s) then
                hide(s.uuid)
                outcomes[#outcomes + 1] = "no menu bar"
            elseif bar.hidden(tide.wm, s.uuid) then
                hide(s.uuid)
                outcomes[#outcomes + 1] = "full screen"
            else
                local frame, why = notchbar.place(s, w, notchbar.notch_of(s, notch_areas(screens)), menus_end)
                if frame then
                    draw(s, frame, chips, boxes, look)
                    outcomes[#outcomes + 1] = "drawn"
                else
                    hide(s.uuid)
                    outcomes[#outcomes + 1] = "no room"
                    if self.why ~= why then
                        self.why = why
                        log("menu bar workspaces: in the menu bar item too, as " .. why)
                    end
                end
            end
        end
        local enough = notchbar.enough(outcomes)
        if enough then
            self.why = nil
        end
        for uuid, c in pairs(self.canvases) do
            if not present[uuid] then
                c.canvas:delete()
                self.canvases[uuid] = nil
            end
        end
        return enough
    end

    -- The front app's menus differ, so the room does.
    self.apps = hs.application.watcher.new(function(_, event)
        if event == hs.application.watcher.activated then
            changed()
        end
    end)
    self.apps:start()

    function self.stop()
        if self.apps then
            self.apps:stop()
            self.apps = nil
        end
        for uuid, c in pairs(self.canvases) do
            c.canvas:delete()
            self.canvases[uuid] = nil
        end
        log("menu bar workspaces: stopped")
    end

    log("menu bar workspaces: started")
    return self
end

return M
