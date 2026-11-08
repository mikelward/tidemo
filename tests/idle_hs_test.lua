-- tide's idle timeline through Hammerspoon (idle_hs.lua), against a
-- stand-in macOS: idle time, power assertions, the battery, and a clock the
-- test fires. Each step acts once; input lifts the dim and starts again.

local t = require("t")
local json = require("json")

local function stub(files)
    local s = { idle = 0, did = {}, timers = {}, logged = {}, veils = 0, battery = true, assertions = {}, set = {} }
    _G.hs = {
        json = { decode = json.decode },
        host = {
            idleTime = function()
                return s.idle
            end,
        },
        battery = {
            powerSource = function()
                return s.battery and "Battery Power" or "AC Power"
            end,
            watcher = {
                new = function(fn)
                    s.power_changed = fn
                    -- Hammerspoon stops a watcher Lua collects.
                    return setmetatable({ start = function() end }, {
                        __gc = function()
                            s.watcher_collected = true
                        end,
                    })
                end,
            },
        },
        caffeinate = {
            currentAssertions = function()
                return s.assertions
            end,
            set = function(kind, on)
                s.set[#s.set + 1] = kind .. " " .. tostring(on)
            end,
            lockScreen = function()
                s.did[#s.did + 1] = "lock"
            end,
            systemSleep = function()
                s.did[#s.did + 1] = "suspend"
            end,
        },
        screen = {
            allScreens = function()
                return { { fullFrame = function() return { x = 0, y = 0, w = 100, h = 100 } end } }
            end,
        },
        canvas = {
            windowLevels = { screenSaver = 1000 },
            new = function()
                s.veils = s.veils + 1
                local v = {}
                for _, m in ipairs({ "appendElements", "level", "behavior", "show" }) do
                    v[m] = function() end
                end
                function v.delete()
                    s.veils = s.veils - 1
                end
                return v
            end,
        },
    }
    local tide = {
        idle_files = files,
        adapter = {
            log = function(line)
                s.logged[#s.logged + 1] = line
            end,
            run = function(path, args)
                s.did[#s.did + 1] = path .. " " .. table.concat(args, " ")
                return true
            end,
            after = function(seconds, fn)
                local timer = { seconds = seconds, fn = fn }
                function timer.stop()
                    timer.stopped = true
                end
                s.timers[#s.timers + 1] = timer
                return timer
            end,
        },
    }
    package.loaded["tide.idle_hs"] = nil
    s.idler = require("tide.idle_hs").new(tide)
    s.tide = tide
    -- The clock's next look, `seconds` with no input by then.
    function s.look(seconds)
        s.idle = seconds
        s.timers[#s.timers].fn()
    end
    return s
end

local SET = { shared = '{"dim": 30, "lock": 60, "displaysOff": 90, "suspend": 120}' }

t.test("with nothing set, nothing runs", function()
    local s = stub({})
    t.eq(#s.timers, 0)
    t.eq(s.idler.running(), false)
end)

t.test("the timeline, step by step, each once", function()
    local s = stub(SET)
    t.eq(s.timers[1].seconds, 5)
    s.look(30)
    t.eq(s.veils, 1, "dimmed")
    t.eq(s.timers[#s.timers].seconds, 1, "looked at every second while dimmed")
    s.look(31)
    t.eq(s.veils, 1, "once")
    s.look(95)
    t.eq(s.did, { "lock", "/usr/bin/pmset displaysleepnow" })
    s.look(120)
    t.eq(s.did[3], "suspend")
end)

t.test("input lifts the dim and starts the timeline again", function()
    local s = stub(SET)
    s.look(40)
    t.eq(s.veils, 1)
    s.look(2)
    t.eq(s.veils, 0, "lifted")
    s.look(35)
    t.eq(s.veils, 1, "and dims again")
end)

t.test("a video playing holds it all; on AC there's no sleep", function()
    local s = stub(SET)
    -- As IOPMCopyAssertionsByProcess gives them: by process ID, each a list.
    s.assertions = { [4242] = { { AssertType = "PreventUserIdleDisplaySleep", AssertName = "Video" } } }
    s.look(200)
    t.eq(s.did, {})
    t.eq(s.veils, 0)
    s.assertions = {}
    s.battery = false
    s.look(201)
    t.eq(s.did, { "lock", "/usr/bin/pmset displaysleepnow" })
end)

t.test("a download holds the sleep alone", function()
    local s = stub(SET)
    s.assertions = { [77] = { { AssertType = "PreventUserIdleSystemSleep", AssertName = "Download" } } }
    s.look(200)
    t.eq(s.did, { "lock", "/usr/bin/pmset displaysleepnow" })
end)

t.test("switched off and on again, the timeline starts afresh", function()
    local s = stub(SET)
    s.look(70)
    t.eq(s.did, { "lock" })
    s.tide.idle_files = {}
    s.idler.reload()
    s.tide.idle_files = SET
    s.idler.reload()
    s.look(75)
    t.eq(s.did, { "lock", "lock" }, "the lock again, not skipped")
end)

t.test("taking the settings out stops it, and lifts a dim", function()
    local s = stub(SET)
    s.look(40)
    s.tide.idle_files = {}
    s.idler.reload()
    t.eq(s.veils, 0)
    t.eq(s.timers[#s.timers].stopped, true)
    t.eq(s.idler.running(), false)
end)

t.test("with nothing set, the Mac isn't held awake", function()
    local s = stub({})
    s.battery = false
    s.power_changed()
    t.eq(s.set, {})
    t.eq(s.idler.holding(), false)
end)

t.test("staying awake holds the Mac on AC and lets go on battery", function()
    local s = stub({ awake = '{"pluggedIn": true}' })
    t.eq(s.set, {}, "on battery, nothing held")
    s.battery = false
    s.power_changed()
    t.eq(s.set, { "systemIdle true" })
    s.power_changed()
    t.eq(#s.set, 1, "once")
    s.battery = true
    s.power_changed()
    t.eq(s.set, { "systemIdle true", "systemIdle false" })
end)

-- Regression: the watcher was a local nothing kept, so Lua collected it,
-- which stops it, and plugging in no longer held the Mac awake.
t.test("the power watcher lives as long as the timeline", function()
    local s = stub({ awake = '{"pluggedIn": true}' })
    collectgarbage("collect")
    collectgarbage("collect")
    t.eq(s.watcher_collected, nil)
end)

t.test("turning it off lets go at once", function()
    local s = stub({ awake = '{"pluggedIn": true}' })
    s.battery = false
    s.power_changed()
    s.tide.idle_files = {}
    s.idler.reload()
    t.eq(s.set, { "systemIdle true", "systemIdle false" })
end)

t.test("unplugged, the timeline lets go before it looks, so it can still sleep", function()
    local s = stub({ shared = SET.shared, awake = '{"pluggedIn": true}' })
    s.battery = false
    s.power_changed()
    s.battery = true
    -- No watcher event yet: the look itself lets go.
    s.look(200)
    t.eq(s.set[#s.set], "systemIdle false")
    t.eq(s.did[#s.did], "suspend")
end)

t.test("a file that's wrong is logged and leaves it off", function()
    local s = stub({ awake = '{"pluggedIn": "yes"}' })
    s.battery = false
    s.power_changed()
    t.eq(s.set, {})
    t.eq(s.logged, { "idle: awake.local.json: pluggedIn must be true or false" })
end)

t.done("idle_hs")
