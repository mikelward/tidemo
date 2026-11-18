-- clickaway_hs.lua against a stand-in hs: a mouse button going down
-- outside a popup closes it, once, on the next turn; one inside it doesn't;
-- one on a bar gives the focus back; and the open that same click asks for
-- is dropped.

local t = require("t")
local clickaway = require("tide.clickaway_hs")

local function world()
    local w = { clock = 100, later = {}, logs = {}, closed = {}, taps = 0 }
    w.hs = {
        eventtap = {
            event = { types = { leftMouseDown = 1, rightMouseDown = 3, otherMouseDown = 25 } },
            new = function(types, fn)
                w.taps = w.taps + 1
                w.types = types
                local tap = {}
                function tap:start()
                    w.running = tap
                end
                function tap:stop()
                    if w.running == tap then
                        w.running = nil
                    end
                end
                w.fn = fn
                return tap
            end,
        },
    }
    w.away = clickaway.new(w.hs, {
        after = function(_, fn)
            w.later[#w.later + 1] = fn
        end,
        now = function()
            return w.clock
        end,
        log = function(line)
            w.logs[#w.logs + 1] = line
        end,
        bars = function()
            return { { x = 0, y = 0, w = 1920, h = 30 } }
        end,
    })
    function w.click(x, y)
        if not w.running then
            return nil
        end
        return w.fn({
            location = function()
                return { x = x, y = y }
            end,
        })
    end
    function w.turn()
        local fns = w.later
        w.later = {}
        for _, fn in ipairs(fns) do
            fn()
        end
    end
    function w.open()
        w.away.start({ { x = 1500, y = 30, w = 300, h = 200 } }, function(refocus)
            w.closed[#w.closed + 1] = refocus
        end)
    end
    return w
end

t.test("a click inside the popup leaves it open and passes on", function()
    local w = world()
    w.open()
    t.eq(w.click(1600, 100), false)
    w.turn()
    t.eq(w.closed, {})
    t.eq(w.running ~= nil, true)
end)

t.test("a click elsewhere closes it on the next turn, once, and passes on", function()
    local w = world()
    w.open()
    t.eq(w.click(500, 500), false)
    t.eq(w.closed, {}, "not from the tap's own callback")
    t.eq(w.running, nil, "the tap stops")
    w.turn()
    t.eq(w.closed, { false }, "the focus goes where you clicked")
    t.eq(w.click(600, 600), nil)
end)

t.test("every mouse button counts", function()
    local w = world()
    w.open()
    t.eq(w.types, { 1, 3, 25 })
end)

t.test("a click on a bar gives the focus back to the window you were in", function()
    local w = world()
    w.open()
    w.click(100, 10)
    w.turn()
    t.eq(w.closed, { true })
end)

t.test("the open that same click asks for is dropped, and a later one isn't", function()
    local w = world()
    t.eq(w.away.reopening(), false)
    w.open()
    w.click(1700, 10)
    w.turn()
    t.eq(w.away.reopening(), true)
    w.clock = w.clock + clickaway.GRACE
    t.eq(w.away.reopening(), false)
end)

t.test("closing it another way stops watching", function()
    local w = world()
    w.open()
    w.away.stop()
    t.eq(w.running, nil)
    t.eq(w.away.reopening(), false)
end)

t.test("opening it again replaces the tap", function()
    local w = world()
    w.open()
    w.open()
    t.eq(w.taps, 2)
    w.click(500, 500)
    w.turn()
    t.eq(w.closed, { false })
end)

t.test("a tap that can't start is logged, and the popup still opens", function()
    local w = world()
    w.hs.eventtap.new = function()
        error("no Accessibility")
    end
    w.open()
    t.eq(#w.logs, 1)
    t.eq(w.logs[1]:find("clickaway: watching for a click outside", 1, true) ~= nil, true)
end)

t.done("clickaway_hs_test")
