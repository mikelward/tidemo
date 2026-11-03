-- hs_adapter.lua can't run outside Hammerspoon, but one thing about it can
-- be checked here: its constructor defines each function once. A second
-- definition of a name replaces the first for every caller, as a helper
-- opener once took the place of the launcher's open_app(path, env).

local t = require("t")

local function definitions(path)
    local f = assert(io.open(path))
    local seen, twice = {}, {}
    local n = 0
    for line in f:lines() do
        n = n + 1
        local code = line:gsub("%-%-.*$", "")
        local name = code:match("^%s*function%s+a%.([%w_]+)%s*%(") or code:match("^%s*a%.([%w_]+)%s*=%s*function")
        if name then
            if seen[name] then
                twice[#twice + 1] = name .. " (lines " .. seen[name] .. " and " .. n .. ")"
            else
                seen[name] = n
            end
        end
    end
    f:close()
    return seen, twice
end

t.test("the adapter defines each of its functions once", function()
    local seen, twice = definitions("hammerspoon/tilemo/hs_adapter.lua")
    t.eq(next(seen) ~= nil, true, "found the adapter's functions")
    t.eq(twice, {})
end)

-- The window filter's events, against a stand-in hs.window.filter: a
-- stand-in window of `pid` titled `title`.
local function watched()
    local s = { changes = 0, focused = {} }
    local subs = {}
    _G.hs = {
        processInfo = { processID = 42 },
        window = {
            filter = {
                ignoreAlways = {},
                windowCreated = "created", windowDestroyed = "destroyed", windowHidden = "hidden",
                windowUnhidden = "unhidden", windowFullscreened = "fullscreened",
                windowUnfullscreened = "unfullscreened", windowFocused = "focused", windowMoved = "moved",
                windowMinimized = "minimized", windowUnminimized = "unminimized",
                windowTitleChanged = "retitled",
                new = function()
                    return {
                        setDefaultFilter = function() end,
                        subscribe = function(_, events, fn)
                            for _, e in ipairs(type(events) == "table" and events or { events }) do
                                subs[e] = fn
                            end
                        end,
                    }
                end,
            },
        },
        screen = { watcher = { new = function() return { start = function() end } end } },
    }
    package.loaded["tilemo.hs_adapter"] = nil
    require("tilemo.hs_adapter").watch(function()
        s.changes = s.changes + 1
    end, function(id)
        s.focused[#s.focused + 1] = id
    end, function() end, function() end, function() end, function() end)
    function s.fire(event, pid, title, id)
        subs[event]({
            pid = function() return pid end,
            title = function() return title end,
            id = function() return id end,
        }, "app", event)
    end
    return s
end

t.test("tilemo's own windows showing, hiding and taking focus are no news to the window manager", function()
    local s = watched()
    s.fire("created", 42, "tide launcher", 1)
    s.fire("destroyed", 42, "tide launcher", 1)
    s.fire("focused", 42, "tide launcher", 1)
    -- The switcher is an hs.chooser, with no title.
    s.fire("focused", 42, "", 2)
    t.eq(s.changes, 0)
    t.eq(s.focused, {})
end)

t.test("the window filters never look at Hammerspoon's own windows at all", function()
    watched()
    t.eq(hs.window.filter.ignoreAlways.Hammerspoon, true)
end)

t.test("other apps' windows still are", function()
    local s = watched()
    s.fire("created", 7, "tide launcher", 4)
    s.fire("focused", 7, "Notes", 5)
    t.eq(s.changes, 1)
    t.eq(s.focused, { 5 })
end)

t.done("adapter")
