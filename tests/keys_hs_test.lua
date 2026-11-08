local t = require("t")
local json = require("json")

-- Hammerspoon's event tap, timer and key codes, standing in.
local taps = {}
_G.hs = {
    eventtap = {
        event = { types = { keyDown = 10 } },
        new = function(_, fn)
            local tap = { fn = fn, on = false }
            function tap.start(self) self.on = true end
            function tap.stop(self) self.on = false end
            taps[#taps + 1] = tap
            return tap
        end,
    },
    timer = { doAfter = function() return { stop = function() end } end },
    keycodes = { map = { [17] = "t", [37] = "l" } },
}

local keys_hs = require("tide.keys_hs")

local DIR = "/home/u/.config/tide"

local function fake_tide()
    local disk = {}
    local events = {}
    local tide = { clock_dir = DIR, karabiner = true, hotkeys = {} }
    local function hotkey()
        local h = { enabled = true }
        function h.disable(self) self.enabled = false end
        function h.enable(self) self.enabled = true end
        return h
    end
    tide.adapter = {
        read = function(p) return disk[p] end,
        write_file = function(p, text) disk[p] = text; return true end,
        decode = json.decode,
        notify = function(m) events[#events + 1] = "notify: " .. m end,
        log = function(m) events[#events + 1] = "log: " .. m end,
    }
    function tide.rebind()
        -- As bind_all does: fresh hotkeys, enabled.
        tide.hotkeys = { hotkey(), hotkey() }
        events[#events + 1] = "rebind"
    end
    tide.hotkeys = { hotkey(), hotkey() }
    return tide, disk, events
end

local function all(hotkeys, on)
    for _, h in ipairs(hotkeys) do
        if h.enabled ~= on then
            return false
        end
    end
    return true
end

t.test("recording turns tide's keys off, and a key pressed gives the shortcut new keys", function()
    local tide, disk = fake_tide()
    local k = keys_hs.new(tide)
    k.load()
    k.record("lock")
    t.eq(all(tide.hotkeys, false), true, "tide's keys are off while recording")
    t.eq(k.page().recording, "lock")
    local tap = taps[#taps]
    local event = {
        getKeyCode = function() return 37 end,
        getFlags = function() return { ctrl = true, alt = true, cmd = true, shift = true } end,
    }
    t.eq(tap.fn(event), true, "the key goes to the recording")
    t.eq(tap.on, false)
    t.eq(k.page().recording, "")
    t.eq(json.decode(disk[DIR .. "/keys.local.json"]).keys, { lock = { "SUPER + SHIFT + L" } })
    t.eq(all(tide.hotkeys, true), true, "bound again, on")
end)

t.test("a change while recording stops it before binding again", function()
    local tide, _, events = fake_tide()
    local k = keys_hs.new(tide)
    k.load()
    k.record("lock")
    t.eq(all(tide.hotkeys, false), true)
    k.off("terminal")
    t.eq(k.page().recording, "", "the recording stopped")
    t.eq(taps[#taps].on, false, "and stopped listening")
    t.eq(all(tide.hotkeys, true), true, "the new hotkeys are on")
    t.eq(events[#events], "rebind")
end)

t.test("Esc stops recording and changes nothing", function()
    local tide, disk = fake_tide()
    local k = keys_hs.new(tide)
    k.load()
    k.record("lock")
    hs.keycodes.map[53] = "escape"
    taps[#taps].fn({ getKeyCode = function() return 53 end, getFlags = function() return {} end })
    t.eq(k.page().recording, "")
    t.eq(disk[DIR .. "/keys.local.json"], nil)
    t.eq(all(tide.hotkeys, true), true)
end)

t.done("keys_hs_test")
