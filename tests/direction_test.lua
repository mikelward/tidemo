local t = require("t")
local direction = require("tilemo.direction")

local function box(x, y, w, h)
    return { x = x, y = y, w = w, h = h }
end

local function tiles(list)
    local out = {}
    for i, b in ipairs(list) do
        out[i] = { id = i, box = b }
    end
    return out
end

-- A 1920x1080 display, a bigger one to its right standing 360 px higher,
-- and a smaller one to its left, lower down.
local A = box(0, 0, 1920, 1080)
local B = box(1920, -360, 2560, 1440)
local C = box(-1280, 600, 1280, 1024)

local function id_of(hit)
    return hit and hit.id
end

t.test("on one display, the nearest window that way", function()
    local cols = tiles({ box(0, 0, 640, 1080), box(640, 0, 640, 1080), box(1280, 0, 640, 1080) })
    t.eq(id_of(direction.pick(cols[1].box, cols, 1)), 2)
    t.eq(id_of(direction.pick(cols[2].box, cols, -1)), 1)
    t.eq(id_of(direction.pick(cols[2].box, cols, 1)), 3)
    t.eq(direction.pick(cols[3].box, cols, 1), nil, "nothing right of the rightmost")
end)

t.test("a tie goes to the window first in tile order", function()
    local tall = tiles({ box(0, 0, 960, 1080), box(960, 0, 960, 540), box(960, 540, 960, 540) })
    t.eq(id_of(direction.pick(tall[3].box, tall, -1)), 1)
    t.eq(id_of(direction.pick(tall[1].box, tall, 1)), 2)
end)

t.test("at the edge, the window on the next display sharing the most height, then the nearest", function()
    local displays = {
        { uuid = "A", full = A, tiles = tiles({ box(1280, 540, 640, 540) }) },
        {
            uuid = "B",
            full = B,
            tiles = tiles({ box(1920, -360, 1280, 1440), box(3200, -360, 1280, 720), box(3200, 360, 1280, 720) }),
        },
    }
    -- The master and the lower stack window each share 540 px with it; the
    -- master's center is nearer.
    local hit, s = direction.find(box(1280, 540, 640, 540), "A", displays, 1)
    t.eq(s.uuid, "B")
    t.eq(id_of(hit), 1)
end)

t.test("sharing height beats being nearer, across an offset display", function()
    local focused = box(1280, 700, 640, 300)
    local displays = {
        { uuid = "A", full = A, tiles = tiles({ focused }) },
        { uuid = "B", full = B, tiles = tiles({ box(1920, -360, 1280, 720), box(3200, 360, 1280, 720) }) },
    }
    local hit = direction.find(focused, "A", displays, 1)
    t.eq(id_of(hit), 2, "the far window shares 300 px, the near one none")
end)

t.test("with no height shared, the nearest center, on a smaller display lower down", function()
    local focused = box(0, 0, 640, 500)
    local displays = {
        { uuid = "A", full = A, tiles = tiles({ focused }) },
        { uuid = "B", full = B, tiles = tiles({ box(1920, -360, 2560, 1440) }) },
        { uuid = "C", full = C, tiles = tiles({ box(-1280, 600, 640, 1024), box(-640, 600, 640, 1024) }) },
    }
    local hit, s = direction.find(focused, "A", displays, -1)
    t.eq(s.uuid, "C")
    t.eq(id_of(hit), 2, "its right column, nearer A")
end)

t.test("the next display is the one sharing the most height with this one", function()
    local displays = {
        { uuid = "A", full = A, tiles = {} },
        { uuid = "E", full = box(1920, 1080, 1920, 1080), tiles = tiles({ box(1920, 1080, 1920, 1080) }) },
        { uuid = "D", full = box(1920, 0, 1920, 1080), tiles = tiles({ box(1920, 0, 1920, 1080) }) },
    }
    local _, s = direction.find(A, "A", displays, 1)
    t.eq(s.uuid, "D")
end)

t.test("a display that way with no windows is still where it goes", function()
    local displays = {
        { uuid = "A", full = A, tiles = tiles({ box(0, 0, 1920, 1080) }) },
        { uuid = "B", full = B, tiles = {} },
    }
    local hit, s = direction.find(box(0, 0, 1920, 1080), "A", displays, 1)
    t.eq(hit, nil)
    t.eq(s.uuid, "B")
end)

t.test("past the last display that way, nothing", function()
    local displays = {
        { uuid = "A", full = A, tiles = tiles({ box(0, 0, 1920, 1080) }) },
        { uuid = "B", full = B, tiles = tiles({ box(1920, -360, 2560, 1440) }) },
    }
    local hit, s = direction.find(box(1920, -360, 2560, 1440), "B", displays, 1)
    t.eq(hit, nil)
    t.eq(s, nil)
end)

t.done("direction")
