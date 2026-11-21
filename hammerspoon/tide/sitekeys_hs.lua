-- Site keys (SPEC.md §7.2), held as hotkeys: under the rotation, while
-- the focused window is a site of sitekeys.lua's, the keys it takes are
-- hotkeys of tide's that send the site's own instead. Like the pinned
-- window's keys (pinned_hs.lua), a hotkey can't be conditional on the
-- window, so they're enabled only while such a window has focus, checked
-- as focus and titles change, and every other window gets the keys as
-- ever. A press that finds the site gone before tide heard goes on to the
-- app, as a key posted with the hotkey off. `hs` is Hammerspoon, or a
-- stand-in.

local sitekeys = require("tide.sitekeys")

local M = {}

-- `d`: rotated(), whether Super is the Win key under the rotation;
-- front(), the bundle ID of the app in front; title(), its focused
-- window's title; log(text).
function M.new(hs, d)
    local self = { site = nil }
    local made = {}

    -- The site in front, or nil. The title is read only with a browser
    -- in front under the rotation.
    local function current()
        if not d.rotated() then
            return nil
        end
        local bundle = d.front()
        if not sitekeys.BROWSERS[bundle] then
            return nil
        end
        return sitekeys.site(bundle, d.title())
    end

    local function set(site)
        self.site = site
        for _, m in ipairs(made) do
            if sitekeys.translation(site, m.chord) then
                m.hk:enable()
            else
                m.hk:disable()
            end
        end
    end

    -- Enable the keys of the site in front, and disable the rest. Returns
    -- the site, or nil.
    function self.check()
        local ok, site = pcall(current)
        if not ok then
            d.log("site keys: couldn't read the window in front: " .. tostring(site))
            site = nil
        end
        if site ~= self.site then
            set(site)
        end
        return site
    end

    for _, k in ipairs(sitekeys.keys()) do
        local chord = sitekeys.chord(k)
        local hk
        local ok, hotkey = pcall(hs.hotkey.new, k.mods, k.key, function()
            local site = self.check()
            local to = sitekeys.translation(site, chord)
            if to then
                d.log("site keys: " .. site.name .. ": " .. chord .. " sent as " .. sitekeys.chord(to))
                hs.eventtap.keyStroke(to.mods, to.key, 0)
                return
            end
            -- Not the site any more: check() turned the hotkey off, so the
            -- key goes on to the app.
            hk:disable()
            hs.eventtap.keyStroke(k.mods, k.key, 0)
        end)
        if ok and hotkey then
            hk = hotkey
            made[#made + 1] = { chord = chord, hk = hk }
        else
            d.log("site keys: couldn't make " .. chord .. ": " .. tostring(hotkey))
        end
    end
    return self
end

return M
