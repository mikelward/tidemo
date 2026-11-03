-- The displays, as the adapter reads them for the bar, the tray and the
-- window manager, against stand-in screens. Reading them takes 20 ms or
-- more a time, so one pass of work, up to Hammerspoon's next idle moment,
-- reads them once.

local t = require("t")

-- The adapter, over `screens` ({ uuid, frame, full }), with the timer
-- Hammerspoon runs once it's idle held in `s.idle`.
local function stub(screens)
    local s = { reads = 0, screens = screens }
    _G.hs = {
        processInfo = { processID = 42 },
        axuielement = {
            systemWideElement = function()
                return { setTimeout = function() end }
            end,
        },
        window = {
            filter = {
                new = function()
                    return { setDefaultFilter = function() end, subscribe = function() end }
                end,
            },
        },
        screen = {
            allScreens = function()
                s.reads = s.reads + 1
                local out = {}
                for i, sc in ipairs(s.screens) do
                    out[i] = {
                        getUUID = function() return sc.uuid end,
                        frame = function() return sc.frame end,
                        fullFrame = function() return sc.full end,
                    }
                end
                return out
            end,
        },
        -- The menu bar isn't set to hide.
        execute = function()
            return "0\n", true
        end,
        timer = {
            doAfter = function(_, fn)
                s.idle = fn
                return { stop = function() end }
            end,
        },
        logger = { new = function() return { i = function() end } end },
        task = { new = function() end },
    }
    package.loaded["tilemo.hs_adapter"] = nil
    s.adapter = require("tilemo.hs_adapter").new()
    -- Hammerspoon is idle: what's waiting for it runs.
    function s.settle()
        local fn = s.idle
        s.idle = nil
        if fn then
            fn()
        end
    end
    return s
end

local LEFT = { uuid = "L", frame = { x = 0, y = 25, w = 1440, h = 875 }, full = { x = 0, y = 0, w = 1440, h = 900 } }
local RIGHT = { uuid = "R", frame = { x = 1440, y = 0, w = 1920, h = 1080 }, full = { x = 1440, y = 0, w = 1920, h = 1080 } }

t.test("the displays are read once in a pass, however often they're asked for", function()
    local s = stub({ RIGHT, LEFT })
    local first = s.adapter.screens()
    s.adapter.screens()
    s.adapter.screens()
    t.eq(s.reads, 1)
    t.eq(first[1].uuid, "L", "left to right")
    t.eq(first[1].area, { x = 0, y = 25, w = 1440, h = 875 })
    t.eq(first[2].full, { x = 1440, y = 0, w = 1920, h = 1080 })
    t.eq(first[1].notch, false)
end)

t.test("once Hammerspoon is idle, the next ask reads them again", function()
    local s = stub({ LEFT })
    s.adapter.screens()
    s.settle()
    s.screens = { LEFT, RIGHT }
    t.eq(#s.adapter.screens(), 2)
    t.eq(s.reads, 2)
end)

t.test("a display coming or going is read at once, as macOS says so", function()
    local s = stub({ LEFT })
    local watch
    hs.screen.watcher = {
        new = function(fn)
            watch = fn
            return { start = function() end }
        end,
    }
    hs.window.filter.ignoreAlways = {}
    local seen
    local module = require("tilemo.hs_adapter")
    module.watch(function()
        seen = #s.adapter.screens()
    end, function() end, function() end, function() end, function() end, function() end)
    s.adapter.screens()
    s.screens = { LEFT, RIGHT }
    watch()
    t.eq(seen, 2)
end)

t.test("a caller changing its list changes no one else's", function()
    local s = stub({ LEFT })
    local mine = s.adapter.screens()
    mine[1].area.h = 1
    table.insert(mine, 1, { uuid = "X" })
    local theirs = s.adapter.screens()
    t.eq(#theirs, 1)
    t.eq(theirs[1].area.h, 875)
end)

t.done("screens")
