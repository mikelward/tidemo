-- Left and right between windows and displays (SPEC.md §7.2): which window
-- Super+Left and Right select, and where Super+Shift+Left and Right move
-- the window. Pure geometry on { x, y, w, h } boxes, so it tests with
-- made-up displays.
--
-- One rule picks both a window and a display: of the boxes on that side,
-- the one with the most vertical overlap with where you are, then the one
-- whose center is nearest, then the first listed. "On that side" means its
-- center is left (d < 0) or right (d > 0) of yours.

local M = {}

local function center(b)
    return b.x + b.w / 2, b.y + b.h / 2
end

-- How many pixels of height two boxes share.
function M.overlap(a, b)
    return math.max(0, math.min(a.y + a.h, b.y + b.h) - math.max(a.y, b.y))
end

-- Whether box `b` is on side `d` of box `from`.
function M.beside(from, b, d)
    local fx = center(from)
    local bx = center(b)
    return d < 0 and bx < fx or d > 0 and bx > fx
end

-- Of `items`, each { box = ... } plus whatever the caller keeps, the one
-- the rule picks against `from`, or nil with none.
function M.nearest(from, items)
    local fx, fy = center(from)
    local best, best_overlap, best_dist
    for _, it in ipairs(items) do
        local o = M.overlap(from, it.box)
        local x, y = center(it.box)
        local dist = (x - fx) ^ 2 + (y - fy) ^ 2
        if not best or o > best_overlap or (o == best_overlap and dist < best_dist) then
            best, best_overlap, best_dist = it, o, dist
        end
    end
    return best
end

-- The same, of the items on side `d` of `from` only.
function M.pick(from, items, d)
    local side = {}
    for _, it in ipairs(items) do
        if M.beside(from, it.box, d) then
            side[#side + 1] = it
        end
    end
    return M.nearest(from, side)
end

-- Where Super+Left or Right goes from `box` on display `here`. `displays`
-- is every display, each { uuid, full, tiles }, its tiles each { id, box },
-- in tile order. Returns the tile picked and its display: on this display
-- if one is that way; at its edge, on the next display that way, picked
-- against `box` as well; nil for the tile if that display has none; nil
-- for both with no display that way.
function M.find(box, here, displays, d)
    local cur
    for _, s in ipairs(displays) do
        if s.uuid == here then
            cur = s
        end
    end
    if not cur then
        return nil
    end
    local hit = M.pick(box, cur.tiles, d)
    if hit then
        return hit, cur
    end
    local others = {}
    for _, s in ipairs(displays) do
        if s.uuid ~= here then
            others[#others + 1] = { box = s.full, display = s }
        end
    end
    local next_one = M.pick(cur.full, others, d)
    if not next_one then
        return nil
    end
    local s = next_one.display
    -- That display is the side test: a tile there that's offset back past
    -- `box`'s center still counts.
    return M.nearest(box, s.tiles), s
end

return M
