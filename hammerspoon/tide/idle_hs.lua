-- tide's idle timeline on the Mac (idle.lua), through Hammerspoon: the
-- idle time from hs.host.idleTime, looked at every few seconds, and each
-- step: a dark veil over every display for the dim, macOS's lock, the
-- displays off (`pmset displaysleepnow`), and sleep. Input lifts the dim
-- and starts the timeline again. And, when this Mac's awake.local.json
-- turns it on, a system-idle power assertion while plugged in, so macOS's
-- own idle sleep doesn't take the Mac; it's let go on battery.

local idle = require("tide.idle")

local M = {}

-- Seconds between looks, and while dimmed, so input lifts it at once.
M.EVERY = 5
M.DIMMED_EVERY = 1
-- How dark the dim is.
M.DIM_ALPHA = 0.5

-- `tide` is the started tide module: its idle_files and adapter (log,
-- after, run).
function M.new(tide)
    local self = {}
    local a = tide.adapter
    local loaded
    local done = {}
    local last = 0
    local timer
    local veils
    local said
    local awake = { on = false }
    local holding = false
    local said_awake

    local function undim()
        for _, v in ipairs(veils or {}) do
            v:delete()
        end
        veils = nil
    end

    local function dim()
        undim()
        veils = {}
        for _, s in ipairs(hs.screen.allScreens()) do
            local v = hs.canvas.new(s:fullFrame())
            v:appendElements({ type = "rectangle", action = "fill", fillColor = { black = 1, alpha = M.DIM_ALPHA } })
            v:level(hs.canvas.windowLevels.screenSaver)
            v:behavior({ "canJoinAllSpaces", "stationary" })
            v:show()
            veils[#veils + 1] = v
        end
    end

    -- macOS's power assertion types that keep the display, or only the
    -- system, awake.
    local DISPLAY = { PreventUserIdleDisplaySleep = true, NoDisplaySleepAssertion = true }
    local SYSTEM = { PreventUserIdleSystemSleep = true, NoIdleSleepAssertion = true }

    -- What apps hold awake now, from macOS's power assertions: by process
    -- ID, each a list of records with its AssertType, as
    -- IOPMCopyAssertionsByProcess gives them.
    local function held()
        local out = { display = false, system = false }
        for _, records in pairs(hs.caffeinate.currentAssertions() or {}) do
            for _, r in pairs(type(records) == "table" and records or {}) do
                local kind = type(r) == "table" and r.AssertType
                if DISPLAY[kind] then
                    out.display = true
                elseif SYSTEM[kind] then
                    out.system = true
                end
            end
        end
        return out
    end

    local ACT = {
        dim = dim,
        lock = function()
            hs.caffeinate.lockScreen()
        end,
        displaysOff = function()
            if not a.run("/usr/bin/pmset", { "displaysleepnow" }, function(code, err)
                if code ~= 0 then
                    a.log("idle: pmset displaysleepnow exited " .. tostring(code) .. ": " .. tostring(err))
                end
            end) then
                a.log("idle: couldn't run pmset displaysleepnow")
            end
        end,
        suspend = function()
            hs.caffeinate.systemSleep()
        end,
    }

    -- Hold the Mac awake, or let it go, as the switch and the power
    -- source say. tide's own assertion then counts as holding the system
    -- awake, so the timeline doesn't sleep on AC either; on battery it's
    -- gone before held() looks.
    local function sync_awake()
        local want = idle.holds_awake(awake.on, hs.battery.powerSource() == "Battery Power")
        if want == holding then
            return
        end
        local ok, err = pcall(hs.caffeinate.set, "systemIdle", want)
        if not ok then
            a.log("idle: couldn't " .. (want and "hold" or "let go of") .. " the Mac awake: " .. tostring(err))
            return
        end
        holding = want
    end

    -- Kept on self: Hammerspoon stops a watcher Lua collects, and with the
    -- timeline off nothing else notices the Mac being plugged in.
    self.power_watcher = hs.battery.watcher.new(sync_awake)
    self.power_watcher:start()

    local function look()
        timer = nil
        sync_awake()
        local seconds = hs.host.idleTime()
        if seconds < last then
            done = {}
            undim()
        end
        last = seconds
        local on_battery = hs.battery.powerSource() == "Battery Power"
        for _, step in ipairs(idle.due(loaded.idle, seconds, done, on_battery, held())) do
            done[step] = true
            local ok, err = pcall(ACT[step])
            if not ok then
                a.log("idle: couldn't " .. step .. ": " .. tostring(err))
            end
        end
        timer = a.after(veils and M.DIMMED_EVERY or M.EVERY, look)
    end

    -- tide's idle files, read again: the timeline starts, changes or stops.
    function self.reload()
        local files = tide.idle_files or {}
        loaded = idle.load(files.shared, files["local"], hs.json.decode, loaded)
        local why = #loaded.errors > 0 and table.concat(loaded.errors, "; ") or nil
        if why ~= said and why then
            a.log("idle: " .. why)
        end
        said = why
        awake = idle.load_awake(files.awake, hs.json.decode)
        if awake.error ~= said_awake and awake.error then
            a.log("idle: " .. awake.error)
        end
        said_awake = awake.error
        sync_awake()
        if loaded.chosen and not timer then
            -- Started afresh: what an earlier run did is no longer done.
            done = {}
            last = hs.host.idleTime()
            timer = a.after(M.EVERY, look)
        elseif not loaded.chosen then
            if timer then
                timer.stop()
                timer = nil
            end
            undim()
        end
    end

    -- What's held awake now, for CI's smoke test.
    self.held = held

    -- Whether tide holds the Mac awake now, for the tests.
    function self.holding()
        return holding
    end

    -- Whether tide's timeline runs, for the page.
    function self.running()
        return loaded ~= nil and loaded.chosen
    end

    self.reload()
    return self
end

return M
