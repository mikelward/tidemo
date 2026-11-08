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

-- Your own app keys, apps.json: bound with tide's, ahead of them, so one
-- on tide's keys takes them; and bound again when the file changes.
t.test("your app keys bind ahead of tide's, and a wrong file is said once", function()
    local tide, disk, events = fake_tide()
    tide.adapter.bundle_of_app = function(name)
        return name == "Spotify" and "com.spotify.client" or nil
    end
    local k = keys_hs.new(tide)
    k.load()
    local before = #k.map
    disk[DIR .. "/apps.json"] = json.encode({ apps = { { keys = "SUPER + I", app = "Spotify" } } })
    events[#events + 1] = "--"
    k.load()
    t.eq(#k.map, before + 1)
    t.eq(k.map[1].key, "i")
    t.eq(k.map[1].arg.bundle, "com.spotify.client")
    t.eq(events[#events], "rebind")
    disk[DIR .. "/apps.json"] = "{\"apps\": 3}"
    k.load()
    k.load()
    local said = 0
    for _, e in ipairs(events) do
        if e:find("Your app keys are off until this is fixed: apps.json: apps should be a list", 1, true) then
            said = said + 1
        end
    end
    t.eq(said, 1)
    t.eq(#k.map, before, "a wrong file keeps none of yours")
end)

-- The settings window's app keys: added, switched to a new window and
-- removed, each written to apps.local.json and bound; what can't be one
-- is said on the page and writes nothing.
t.test("app keys from the settings window are written, bound and said on the page", function()
    local tide, disk = fake_tide()
    tide.adapter.bundle_of_app = function(name)
        return name == "Spotify" and "com.spotify.client" or nil
    end
    local k = keys_hs.new(tide)
    k.load()
    t.eq(k.add_app("Super+M", "Spotify", false), true)
    t.eq(json.decode(disk[DIR .. "/apps.local.json"]).apps, { { keys = "Super+M", app = "Spotify" } })
    t.eq(k.map[1].arg.bundle, "com.spotify.client")
    t.eq(k.page().apps.rows, { { label = "Super+M", app = "Spotify", new = false } })
    local rebinds = 0
    local rebind = tide.rebind
    tide.rebind = function()
        rebinds = rebinds + 1
        rebind()
    end
    t.eq(k.app_new(1, true), true)
    t.eq(k.page().apps.rows[1].new, true)
    t.eq(rebinds, 1, "a new window alone binds again, so the hotkey has it")
    t.eq(k.map[1].arg.new, true)
    local ok = k.add_app("Super+K", "Nope", false)
    t.eq(ok, nil)
    t.eq(k.page().apps.refused, "no app is called Nope")
    t.eq(#json.decode(disk[DIR .. "/apps.local.json"]).apps, 1, "nothing written")
    t.eq(k.remove_app(1), true)
    t.eq(k.page().apps.rows, {})
    t.eq(k.page().apps.refused, "")
    t.eq(k.remove_app(1), nil, "gone already")
end)

-- Without scripts, the Shortcuts list's rows say the app a key opens.
t.test("a row says the app its key opens without scripts' helper", function()
    local tide = fake_tide()
    tide.adapter.helper_exists = function()
        return false
    end
    tide.adapter.app_installed = function(b)
        return b == "com.apple.MobileSMS"
    end
    tide.adapter.app_name = function(b)
        return b == "com.apple.MobileSMS" and "Messages" or nil
    end
    local k = keys_hs.new(tide)
    k.load()
    local does
    for _, r in ipairs(k.page().rows) do
        if r.name == "irc" then
            does = r.does
        end
    end
    t.eq(does, "Messages")
end)

t.done("keys_hs_test")
