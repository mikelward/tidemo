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
        -- The menu bar's setting, as `defaults read` answers: by default
        -- it isn't set, so defaults fails.
        execute = function()
            s.asked = (s.asked or 0) + 1
            if s.hides == nil then
                return "", nil
            end
            return s.hides and "1\n" or "0\n", true
        end,
        -- NSScreen's notch areas (notchbar.SCREENS_SCRIPT), as JSON, or
        -- an error when `s.areas` is false.
        osascript = {
            javascript = function()
                s.scripts = (s.scripts or 0) + 1
                if s.areas == false then
                    return false, nil, { OSAScriptErrorMessageKey = "not allowed" }
                end
                return true, s.areas or "[]"
            end,
        },
        json = {
            decode = function(text)
                local f = assert(load("return " .. text:gsub("%[", "{"):gsub("%]", "}"):gsub('"(%w+)":', "%1=")))
                return f()
            end,
        },
        timer = {
            doAfter = function(_, fn)
                s.idle = fn
                return { stop = function() end }
            end,
        },
        logger = { new = function() return { i = function() end } end },
        inspect = tostring,
        task = { new = function() end },
    }
    package.loaded["tide.hs_adapter"] = nil
    s.adapter = require("tide.hs_adapter").new()
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
    local module = require("tide.hs_adapter")
    module.watch(function()
        seen = #s.adapter.screens()
    end, function() end, function() end, function() end, function() end, function() end)
    s.adapter.screens()
    s.screens = { LEFT, RIGHT }
    watch()
    t.eq(seen, 2)
end)

t.test("the menu bar's setting is read once, even when it was never set", function()
    for _, hides in ipairs({ false, true }) do
        local s = stub({ LEFT })
        s.hides = hides or nil
        t.eq(s.adapter.screens()[1].notch, hides)
        s.settle()
        t.eq(s.adapter.screens()[1].notch, hides)
        t.eq(s.asked, 1, "asked once with it " .. (hides and "set" or "unset"))
    end
end)

t.test("the menu bar's setting is read again when the displays change", function()
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
    require("tide.hs_adapter").watch(function()
        seen = s.adapter.screens()[1]
    end, function() end, function() end, function() end, function() end, function() end)
    s.hides = true
    t.eq(s.adapter.screens()[1].menu_bar, false, "hidden: nothing to cover")
    s.settle()
    -- Set to Never in System Settings: the menu bar's strip comes back.
    s.hides = false
    watch()
    t.eq(seen.menu_bar, true, "covered, without a reload")
    t.eq(s.asked, 2)
end)

-- An external display whose menu bar keeps more than 30 px, as a notched
-- display's does.
local TALL = { uuid = "T", frame = { x = 1440, y = 33, w = 2560, h = 1407 }, full = { x = 1440, y = 0, w = 2560, h = 1440 } }

t.test("a display has a notch when macOS says so, not by its menu bar's height", function()
    local s = stub({ LEFT, TALL })
    s.areas = '[{"x":0,"y":0,"w":1440,"left":600,"right":600},{"x":1440,"y":0,"w":2560,"left":0,"right":0}]'
    local list = s.adapter.screens()
    t.eq(list[1].notch, true, "the built-in display, with only 25 px kept")
    t.eq(list[2].notch, false, "the external one, with 33")
end)

t.test("where macOS can't say, the menu bar's height decides", function()
    local s = stub({ TALL })
    s.areas = false
    t.eq(s.adapter.screens()[1].notch, true)
end)

t.test("the notch areas are read once, and again when the displays change", function()
    local s = stub({ TALL })
    local watch
    hs.screen.watcher = {
        new = function(fn)
            watch = fn
            return { start = function() end }
        end,
    }
    hs.window.filter.ignoreAlways = {}
    require("tide.hs_adapter").watch(function()
        s.adapter.screens()
    end, function() end, function() end, function() end, function() end, function() end)
    s.adapter.screens()
    s.settle()
    s.adapter.screens()
    t.eq(s.scripts, 1)
    watch()
    t.eq(s.scripts, 2)
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
