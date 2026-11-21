-- Site keys (SPEC.md §7.2): under setup-macos's rotation, a PC keyboard's
-- keys for a web app, where Karabiner can't tell one site from another.
-- A site is told by its browser window's title ending, as Google Docs
-- ends "<name> - Google Docs"; each lists the keys it turns into others,
-- as Hammerspoon names them. Pure Lua: sitekeys_hs.lua holds the keys.

local launcher = require("tide.launcher")

local M = {}

-- The browsers whose window titles are read: the Chromium ones the
-- launcher asks for tabs (launcher.BROWSERS), Chrome and Brave, whose
-- window title is the tab's *(unverified on a Mac for Brave)*.
M.BROWSERS = {}
for _, b in ipairs(launcher.BROWSERS) do
    if b.chromium then
        M.BROWSERS[b.bundle] = true
    end
end

-- Google's editors share their keys *(unverified: support.google.com
-- wasn't reachable to check them)*. Physical Ctrl+H, a PC's find and
-- replace, arrives as Cmd+Y with conf's Karabiner rule for Chrome's
-- History, or Cmd+H without it; the Mac's find and replace is
-- Cmd+Shift+H. Physical Alt+/, a PC's search the menus, arrives as
-- Ctrl+/; the Mac's is Option+/.
local GOOGLE = {
    { from = { mods = { "cmd" }, key = "y" }, to = { mods = { "cmd", "shift" }, key = "h" } },
    { from = { mods = { "cmd" }, key = "h" }, to = { mods = { "cmd", "shift" }, key = "h" } },
    { from = { mods = { "ctrl" }, key = "/" }, to = { mods = { "alt" }, key = "/" } },
}

M.SITES = {
    { name = "Google Docs", suffix = " - Google Docs", keys = GOOGLE },
    { name = "Google Sheets", suffix = " - Google Sheets", keys = GOOGLE },
    { name = "Google Slides", suffix = " - Google Slides", keys = GOOGLE },
}

-- Whether the rotation is on: Karabiner running with tide's rule
-- (`ready`, keys.karabiner_ready), and that rule the Win key's (`super`,
-- karabiner.lua's super()). With Super on left Option, or plain Option,
-- a Mac's keys are its own, so no site's are changed; and while Karabiner
-- isn't running, nothing swaps physical Ctrl into Command (SPEC.md §7.1).
function M.rotated(ready, super)
    return ready == true and super == "win"
end

-- A key as "cmd+shift+h", for matching and the log.
function M.chord(k)
    return table.concat(k.mods, "+") .. "+" .. k.key
end

-- The site whose window app `bundle`'s title names, or nil.
function M.site(bundle, title)
    if not M.BROWSERS[bundle] or type(title) ~= "string" then
        return nil
    end
    for _, site in ipairs(M.SITES) do
        if #title > #site.suffix and title:sub(-#site.suffix) == site.suffix then
            return site
        end
    end
    return nil
end

-- What `site` sends for the key `chord`, or nil when it's the page's.
function M.translation(site, chord)
    for _, k in ipairs(site and site.keys or {}) do
        if M.chord(k.from) == chord then
            return k.to
        end
    end
    return nil
end

-- Every key some site takes, each once, in the table's order.
function M.keys()
    local out, seen = {}, {}
    for _, site in ipairs(M.SITES) do
        for _, k in ipairs(site.keys) do
            local c = M.chord(k.from)
            if not seen[c] then
                seen[c] = true
                out[#out + 1] = k.from
            end
        end
    end
    return out
end

return M
