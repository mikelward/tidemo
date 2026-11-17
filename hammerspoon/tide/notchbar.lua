-- The workspaces drawn in the menu bar's middle (SPEC.md §8, Position:
-- Middle of menu bar): where they go on each display, what each chip says
-- and looks like, and which one a click is on. Free of Hammerspoon, so it
-- runs in the tests; notchbar_hs.lua draws it.

local bar = require("tide.bar")

local M = {}

-- Room kept clear of the app's menus and of the notch, in points.
M.MARGIN = 12
-- A chip's padding either side of its name, and the gap between chips.
M.PAD = 7
M.GAP = 2
-- The name's size, as the menu bar's own (13 pt).
M.TEXT_SIZE = 13
-- Without a notch, how far across the menu bar the names may reach: the
-- status items take the rest *(a guess; macOS gives no way to read where
-- they start)*.
M.PLAIN_REACH = 0.62
-- A notch's width when macOS doesn't say, centered *(a guess from the
-- 14-inch MacBook Pro's, about 190 pt)*.
M.NOTCH_GUESS = 200

-- The chips for `ws`, the workspaces in bar order, each { name, here,
-- occupied, urgent }: each one's label, cut as the bar cuts names, and its
-- look: "here", "urgent", "occupied" or "empty".
function M.chips(ws)
    local out = {}
    for _, w in ipairs(ws or {}) do
        local look = (w.urgent and "urgent") or (w.here and "here") or (w.occupied and "occupied") or "empty"
        out[#out + 1] = { name = w.name, label = bar.short(w.name), look = look, here = w.here or false }
    end
    return out
end

-- Each chip's x and width, from the left of the strip, for label widths
-- `widths` (as macOS measures them), and the whole strip's width.
function M.layout(widths)
    local boxes, x = {}, 0
    for i, w in ipairs(widths) do
        if i > 1 then
            x = x + M.GAP
        end
        boxes[i] = { x = x, w = w + 2 * M.PAD }
        x = x + boxes[i].w
    end
    return boxes, x
end

-- Whether display `s` (the adapter's: area, full) has a menu bar of its
-- own showing: macOS keeps room for one above its frame.
function M.has_menu_bar(s)
    return s.full ~= nil and s.area ~= nil and s.area.y > s.full.y and s.menu_bar ~= false
end

-- Where on display `s` the strip of width `w` goes, or nil and why when
-- it doesn't fit. `notch` is { left, right }, the notch's edges in screen
-- points, or nil for none. `menus_end` is how far the app's menus reach
-- from the display's left, or nil when unknown, which never fits: the
-- names mustn't cover menus they can't see.
--
-- Beside a notch, the strip ends just left of it, so the names sit by the
-- notch with the app's menus to their left. Without one, it's centered,
-- moved right of the menus if they reach that far, and no further across
-- than M.PLAIN_REACH.
function M.place(s, w, notch, menus_end)
    if not M.has_menu_bar(s) then
        return nil, "no menu bar"
    end
    if menus_end == nil then
        return nil, "the app's menus couldn't be read"
    end
    local full = s.full
    local h = s.area.y - full.y
    local start = full.x + menus_end + M.MARGIN
    local x
    if notch then
        x = notch.left - M.MARGIN - w
    else
        x = math.max(full.x + (full.w - w) / 2, start)
        if x + w > full.x + full.w * M.PLAIN_REACH then
            return nil, "the app's menus leave no room"
        end
    end
    if x < start then
        return nil, "the app's menus leave no room"
    end
    return { x = math.floor(x), y = full.y, w = math.ceil(w), h = h }
end

-- Display `s`'s notch from the JSON `areas` notchbar_hs reads from
-- NSScreen (M.SCREENS_SCRIPT): the entry whose x, y and width match the
-- display's, since stacked displays can share x and width, its notch between the two auxiliary areas. A display that
-- has a notch by its room (`s.notch`) but no entry gets M.NOTCH_GUESS,
-- centered. Returns { left, right } in screen points, or nil.
function M.notch_of(s, areas)
    if bar.notch_in(s.full, areas) then
        local a = bar.screen_area(s.full, areas)
        return { left = s.full.x + a.left, right = s.full.x + a.w - a.right }
    end
    if s.notch then
        local mid = s.full.x + s.full.w / 2
        return { left = mid - M.NOTCH_GUESS / 2, right = mid + M.NOTCH_GUESS / 2 }
    end
    return nil
end

-- JavaScript for JXA (hs.osascript.javascript), through its ObjC bridge:
-- each display's x, y (down from the main display's top, as
-- Hammerspoon's) and width, and the widths of the menu bar's areas
-- either side of its notch (auxiliaryTopLeftArea and
-- auxiliaryTopRightArea, macOS 12 and later), 0 without a notch. Gives
-- JSON.
M.SCREENS_SCRIPT = [[
ObjC.import('AppKit');
(function () {
  const out = [];
  const screens = $.NSScreen.screens;
  // NSScreen's y runs up from the main display's bottom; Hammerspoon's
  // runs down from its top.
  const mainHeight = screens.objectAtIndex(0).frame.size.height;
  for (let i = 0; i < screens.count; i++) {
    const s = screens.objectAtIndex(i);
    const f = s.frame;
    const y = mainHeight - (f.origin.y + f.size.height);
    let left = 0, right = 0;
    if (s.respondsToSelector('auxiliaryTopLeftArea')) {
      left = s.auxiliaryTopLeftArea.size.width;
      right = s.auxiliaryTopRightArea.size.width;
    }
    out.push({ x: f.origin.x, y: y, w: f.size.width, left: left, right: right });
  }
  return JSON.stringify(out);
})()]]

-- How far the app's menus reach from their display's left, from the
-- frames of the front app's menu bar items (AXMenuBar's children, each
-- { x, y, w, h }) and the displays' full frames: the furthest right edge,
-- less the left of the display the first item is on, by its x and y, since
-- stacked displays share x. 0 for an app with no
-- menus; nil when `frames` is nil (they couldn't be read) or none of them
-- is a frame.
function M.menus_end(frames, screens)
    if frames == nil then
        return nil
    end
    if #frames == 0 then
        return 0
    end
    local first, right
    for _, f in ipairs(frames or {}) do
        if type(f) == "table" and tonumber(f.x) and tonumber(f.w) and f.w > 0 then
            first = first or f
            right = math.max(right or f.x + f.w, f.x + f.w)
        end
    end
    if not first then
        return nil
    end
    for _, s in ipairs(screens or {}) do
        local full = s.full
        if full and first.x >= full.x and first.x < full.x + full.w
            and (tonumber(first.y) or full.y) >= full.y and (tonumber(first.y) or full.y) < full.y + full.h then
            return right - full.x
        end
    end
    return right
end

-- Whether the names drawn in the middle are enough on their own, from
-- what happened on each display: "drawn", "full screen" (hidden under a
-- full-screen window, as the bar is), "no room" or "no menu bar". Any
-- display where they couldn't show, for want of room or of a menu bar
-- tide can see, keeps the menu bar item, as does drawing on none.
function M.enough(outcomes)
    local shown = false
    for _, o in ipairs(outcomes) do
        if o == "no room" or o == "no menu bar" then
            return false
        end
        if o == "drawn" or o == "full screen" then
            shown = true
        end
    end
    return shown
end

-- The workspace a click at `x`, from the strip's left, is on, or nil.
function M.hit(chips, boxes, x)
    for i, b in ipairs(boxes) do
        if x >= b.x and x < b.x + b.w then
            return chips[i] and chips[i].name
        end
    end
    return nil
end

return M
