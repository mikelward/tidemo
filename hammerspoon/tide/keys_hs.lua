-- Your keys on Hammerspoon (SPEC.md §15): reading keys.json and
-- keys.local.json (shortcuts.lua) into the keys tide binds, the settings
-- window's edits, and recording a shortcut's new keys. Runs against `hs`;
-- what it decides is shortcuts.lua's, which the tests cover.

local keys = require("tide.keys")
local shortcuts = require("tide.shortcuts")
local keymaps = require("tide.keymaps")
local mute = require("tide.mute")

local M = {}

-- How long a recording waits for a key before giving Hammerspoon's keys
-- back, as tide's does.
M.RECORD_SECONDS = 15

-- `tide` is the started tide module: its adapter, clock_dir, hotkeys,
-- karabiner, settings, and `rebind`, which binds keys.bindings again.
function M.new(tide)
    local self = {
        state = shortcuts.NO_KEYS,
        map = keys.named_map(),
        rows = {},
        recording = "",
        pending = nil,
        refused = "",
        error = nil,
    }
    local a = tide.adapter
    local reported_file, reported_problems

    local function rows_now()
        self.rows = shortcuts.rows(keys.named_map(), self.map, self.state, keys.does)
    end

    -- Read the files and bind what they say. A file that's wrong is said
    -- once, naming it, and the last good keys stay; so are keys that
    -- couldn't be had.
    function self.load()
        local state, err = shortcuts.load(tide.clock_dir, a.read, a.decode)
        if state then
            self.state, self.error = state, nil
            reported_file = nil
        else
            self.error = err
            if err ~= reported_file then
                reported_file = err
                a.notify("The shortcuts stay as they were: " .. err)
            end
        end
        local map, problems = shortcuts.apply(keys.named_map(), self.state)
        -- Any file in the folder changing reads this again; the keys are
        -- bound again only when they've changed.
        local parts = {}
        for i, b in ipairs(map) do
            parts[i] = tostring(b.name) .. "=" .. (b.shift and "shift+" or "") .. b.key
        end
        local signature = table.concat(parts, " ")
        local changed = signature ~= self.signature
        self.signature = signature
        self.map = map
        local said = table.concat(problems, "; ")
        if said ~= "" and said ~= reported_problems then
            a.notify("Some shortcuts couldn't have their keys: " .. said)
        end
        reported_problems = said
        rows_now()
        if changed then
            -- Binding again makes the hotkeys afresh, enabled, so a
            -- recording, whose hotkeys are off, stops first.
            if self.recording ~= "" and self.stop then
                self.stop()
            end
            tide.rebind()
        end
    end

    local function refresh()
        if tide.settings then
            tide.settings.refresh()
        end
    end

    -- One of shortcuts.lua's edits, written to keys.local.json and bound at
    -- once rather than when the folder's watcher fires. Keys another
    -- shortcut has wait in `pending` for the page's Swap.
    function self.edit(fn, pending)
        local new, why = shortcuts.edit(tide.clock_dir, a.read, a.decode, mute.quote, a.write_file, fn)
        if type(why) == "table" and why.clash then
            self.pending = { name = pending.name, keys = pending.keys, clash = why.clash }
            self.refused = ""
            refresh()
            return true
        end
        self.pending = nil
        if not new then
            self.refused = tostring(why)
            refresh()
            return nil, why
        end
        self.refused = ""
        self.load()
        refresh()
        return true
    end

    -- Keys tide's unnamed bindings have, as shortcuts.lua compares them.
    local function fixed_chords()
        local out = {}
        for _, b in ipairs(keys.named_map()) do
            if not b.name then
                out[(b.shift and "shift+" or "") .. b.key] = true
            end
        end
        return out
    end

    function self.give(name, hypr, swap)
        return self.edit(function(state)
            return shortcuts.with_keys(state, keys.named_map(), self.rows, name, hypr, swap, fixed_chords())
        end, { name = name, keys = hypr })
    end

    function self.swap()
        local p = self.pending
        if not p then
            return true
        end
        return self.give(p.name, p.keys, true)
    end

    function self.reset(name)
        return self.edit(function(state)
            return shortcuts.with_default(state, name, keys.named_map())
        end)
    end

    function self.off(name)
        return self.edit(function(state)
            return shortcuts.with_off(state, name)
        end)
    end

    function self.start_from(preset)
        self.stop()
        return self.edit(function(state)
            return shortcuts.with_preset(state, preset)
        end)
    end

    function self.cancel()
        self.pending = nil
        refresh()
    end

    local tap, timer

    -- Gives Hammerspoon's keys back and stops listening.
    function self.stop()
        if tap then
            tap:stop()
            tap = nil
        end
        if timer then
            timer:stop()
            timer = nil
        end
        if self.recording ~= "" then
            self.recording = ""
            for _, h in ipairs(tide.hotkeys or {}) do
                h:enable()
            end
            refresh()
        end
    end

    -- Records `name`'s new keys: tide's own keys are off until a key is
    -- pressed, Esc is, or the time runs out, so the keys pressed reach
    -- this, not the bindings.
    function self.record(name)
        self.stop()
        self.pending, self.refused = nil, ""
        self.recording = name
        for _, h in ipairs(tide.hotkeys or {}) do
            h:disable()
        end
        tap = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, function(event)
            local key = hs.keycodes.map[event:getKeyCode()]
            local r = shortcuts.recorded(event:getFlags(), key, tide.karabiner)
            if r.wait then
                return true
            end
            local recording = self.recording
            self.stop()
            if r.keys then
                local ok, why = self.give(recording, r.keys, false)
                if not ok then
                    a.log("shortcuts: " .. tostring(why))
                end
            elseif r.error then
                self.refused = r.error
                refresh()
            end
            -- The key went to the recording, not the app.
            return true
        end)
        tap:start()
        timer = hs.timer.doAfter(M.RECORD_SECONDS, self.stop)
        refresh()
    end

    -- The settings window's Shortcuts state, for update().
    function self.page()
        local presets = {}
        for i, n in ipairs(keymaps.NAMES) do
            presets[i] = { value = n, label = keymaps.PRESETS[n].label }
        end
        local rows = {}
        for i, r in ipairs(self.rows) do
            local labels = {}
            for j, k in ipairs(r.keys) do
                local mac = shortcuts.from_hypr(k)
                labels[j] = mac and keys.keys_label(mac, {}, true) or k
            end
            rows[i] = { name = r.name, does = r.does, label = #labels == 0 and "Off" or table.concat(labels, " or "),
                off = #labels == 0, changed = r.changed }
        end
        local pending = self.pending
        if pending then
            local mac = shortcuts.from_hypr(pending.keys)
            pending = { label = mac and keys.keys_label(mac, {}, true) or pending.keys, does = pending.clash.does }
        end
        return {
            rows = rows,
            preset = self.state.preset,
            presets = presets,
            own = next(self.state.keys) ~= nil,
            recording = self.recording,
            pending = pending,
            refused = self.refused,
            error = self.error or "",
        }
    end

    return self
end

return M
