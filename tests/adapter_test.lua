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
    local seen, twice = definitions("hammerspoon/tide/hs_adapter.lua")
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
    package.loaded["tide.hs_adapter"] = nil
    require("tide.hs_adapter").watch(function()
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

t.test("tide's own windows showing, hiding and taking focus are no news to the window manager", function()
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

-- The adapter itself, against a stand-in hs: stand-in windows `ids`, which
-- the window filter watches, and `stacked`, the window server's on-screen
-- list front to back, each { id, layer, frame, pid, name } (Hammerspoon's
-- pid is 42). hs.window.orderedWindows()
-- lists only the watched windows of apps with a Dock icon, `docked` (its
-- visibleWindows() skips app:kind() 0, as Hammerspoon's own window.lua
-- does).
local function stood(ids, stacked, docked)
    local wins = {}
    for _, id in ipairs(ids) do
        wins[#wins + 1] = { id = function() return id end }
    end
    _G.hs = {
        processInfo = { processID = 42 },
        axuielement = { systemWideElement = function() return { setTimeout = function() end } end },
        task = { new = function() end },
        logger = { new = function() return { i = function() end } end },
        window = {
            filter = {
                new = function()
                    return {
                        setDefaultFilter = function() end,
                        getWindows = function() return wins end,
                    }
                end,
            },
            _orderedwinids = function()
                local out = {}
                for _, w in ipairs(stacked) do
                    out[#out + 1] = w.id
                end
                return out
            end,
            list = function()
                local out = {}
                for _, w in ipairs(stacked) do
                    local f = w.frame or { x = 0, y = 0, w = 100, h = 100 }
                    out[#out + 1] = {
                        kCGWindowNumber = w.id, kCGWindowLayer = w.layer or 0, kCGWindowAlpha = 1,
                        kCGWindowOwnerPID = w.pid or 100, kCGWindowName = w.name,
                        kCGWindowBounds = { X = f.x, Y = f.y, Width = f.w, Height = f.h },
                    }
                end
                return out
            end,
            orderedWindows = function()
                local out = {}
                for _, w in ipairs(stacked) do
                    if docked[w.id] then
                        out[#out + 1] = { id = function() return w.id end }
                    end
                end
                return out
            end,
        },
    }
    package.loaded["tide.hs_adapter"] = nil
    local a = require("tide.hs_adapter").new()
    a.windows()
    return a
end

-- A window of an app with no Dock icon (a menu bar app's settings, which
-- tiles unless a rule floats it) must still count as in front: focus
-- follows mouse reads this order to leave a tile under a float alone.
t.test("the stacking order lists the windows of apps with no Dock icon", function()
    -- 7 is a menu bar app's window, floated by a rule, in front of tile 5.
    -- 99 is the menu bar, at its own level, above the Dock's.
    local a = stood({ 5, 6, 7 }, { { id = 99, layer = 24 }, { id = 7 }, { id = 5 }, { id = 6 } },
        { [5] = true, [6] = true })
    t.eq(a.ordered(), { 7, 5, 6 })
end)

-- The window manager on the fake, with one tile, reading the stacking
-- order, and the frames of windows the fake doesn't know, through the real
-- adapter over the stand-in: `above` is the window server's list in front
-- of the tile.
local function over_tile(above)
    local fake = require("fake")
    local wm_mod = require("tide.wm")
    local a = fake.new()
    a.add(5, {})
    local wm = wm_mod.new(a, {})
    wm:sync()
    wm:retile()
    local tile = a.wins[5].frame
    local stacked = {}
    for _, w in ipairs(above(tile)) do
        stacked[#stacked + 1] = w
    end
    stacked[#stacked + 1] = { id = 5, frame = tile }
    local real = stood({ 5 }, stacked, { [5] = true })
    a.ordered = real.ordered
    local fake_state = a.state
    function a.state(id)
        return fake_state(id) or real.state(id)
    end
    return a, wm, tile
end

-- Hammerspoon's console is watched by no filter, and floats at its own
-- level. Over a tile, it's what's under the pointer, so Super+drag,
-- Super+right-drag and Super+middle-click leave the tile alone.
t.test("Hammerspoon's console over a tile stops a Super+drag from grabbing the tile", function()
    local console
    local a, wm, tile = over_tile(function(tile)
        console = { x = tile.x + 100, y = tile.y + 100, w = 400, h = 300 }
        return { { id = 77, layer = 3, pid = 42, name = "Hammerspoon Console", frame = console } }
    end)
    t.eq(a.ordered(), { 77, 5 })
    t.eq(wm:window_at(console.x + 10, console.y + 10), nil)
    t.eq(wm:grab("move", console.x + 10, console.y + 10), nil, "the drag grabs nothing")
    t.eq(wm:window_at(tile.x + 10, tile.y + 10), 5, "the tile's uncovered part is still the tile")
end)

-- tide's own drawing is click-through: the dim over the inactive
-- windows (a canvas the size of the display, with a hole where the focused
-- window is), the drag outline, the bar's tips. None of it is a window
-- over the tiles.
t.test("the dim and tide's other drawing don't stop a Super+drag from grabbing a tile", function()
    local a, wm, tile = over_tile(function(tile)
        return {
            { id = 80, layer = 1, pid = 42, frame = { x = 0, y = 0, w = 1920, h = 1080 } }, -- the dim
            { id = 81, layer = 3, pid = 42, name = "", frame = { x = tile.x, y = tile.y, w = 300, h = 300 } },
            { id = 82, layer = 0, pid = 42, name = "tide launcher", frame = tile },
        }
    end)
    t.eq(a.ordered(), { 5 })
    t.eq(wm:window_at(tile.x + 10, tile.y + 10), 5)
    local d = wm:grab("move", tile.x + 10, tile.y + 10)
    t.eq(d and d.id, 5, "the drag grabs the tile")
end)

t.test("Hammerspoon's Preferences counts as over a tile, as the console does", function()
    local a = over_tile(function(tile)
        return { { id = 78, pid = 42, name = "Hammerspoon Preferences", frame = { x = tile.x, y = tile.y, w = 300, h = 300 } } }
    end)
    t.eq(a.ordered(), { 78, 5 })
end)

-- tide's settings window, launcher and other windows of its own say
-- where they are (wm.own_window); a Super+drag over one leaves the tile
-- behind it alone.
t.test("a Super+drag over one of tide's own windows grabs nothing", function()
    local _, wm, tile = over_tile(function()
        return {}
    end)
    wm:own_window("settings", { x = tile.x, y = tile.y, w = 300, h = 300 })
    t.eq(wm:grab("move", tile.x + 10, tile.y + 10), nil)
    t.eq(wm:window_at(tile.x + 400, tile.y + 400), 5)
end)

-- A new window of a running app (the launcher's, Cmd+Return): `app`
-- records what's done to a stand-in Chrome, whose New Window works while
-- it's behind unless `menu_fails`.
local function new_window(menu_fails)
    local a = stood({}, {}, {})
    local did = {}
    local chrome = {
        findMenuItem = function() return { enabled = true } end,
        selectMenuItem = function()
            did[#did + 1] = "New Window"
            return not menu_fails
        end,
        activate = function()
            did[#did + 1] = "activate"
            return true
        end,
        bundleID = function() return "com.google.Chrome" end,
    }
    hs.application = { get = function() return chrome end }
    hs.eventtap = { keyStroke = function() did[#did + 1] = "Cmd+N" end }
    a.launch({ bundle = "com.google.Chrome" }, true, {})
    return did
end

t.test("a new window of a running app doesn't bring its other windows forward first", function()
    t.eq(new_window(false), { "New Window" })
end)

t.test("if New Window can't be chosen while it's behind, the app comes forward to choose it", function()
    t.eq(new_window(true), { "New Window", "activate", "New Window", "Cmd+N" })
end)

-- The mouse tap, against a stand-in hs.eventtap: `fire(kind, button,
-- flags, mark)` hands it an event and gives back whether it swallowed it.
local function tapped(h)
    local handler
    local saved = hs.eventtap
    local types = {}
    for _, k in ipairs({ "leftMouseDown", "leftMouseDragged", "leftMouseUp", "rightMouseDown", "rightMouseDragged",
        "rightMouseUp", "otherMouseDown", "otherMouseUp" }) do
        types[k] = k
    end
    hs.eventtap = {
        event = {
            types = types,
            properties = { mouseEventButtonNumber = "button", eventSourceUserData = "mark", mouseEventClickState = "clicks" },
        },
        new = function(_, fn)
            handler = fn
            return { start = function() end }
        end,
    }
    package.loaded["tide.hs_adapter"] = nil
    require("tide.hs_adapter").mouse(function(flags)
        return flags.alt == true
    end, h)
    hs.eventtap = saved
    return function(kind, button, flags, mark)
        local props = { button = button, mark = mark or 0, clicks = 1 }
        return handler({
            getType = function() return kind end,
            location = function() return { x = 1, y = 2 } end,
            getFlags = function() return flags or {} end,
            getProperty = function(_, k) return props[k] end,
        })
    end
end

t.test("tide's own paste click into kitty passes its mouse tap untouched", function()
    local middlepaste = require("tide.middlepaste")
    local pastes = 0
    local fire = tapped({
        paste = function()
            pastes = pastes + 1
            return true
        end,
        clicked = function() end,
    })
    t.eq(fire("otherMouseDown", 2, {}), true, "a plain middle click tide pastes is swallowed")
    t.eq(fire("otherMouseDown", 2, middlepaste.KITTY_PASTE, middlepaste.MARK), false)
    t.eq(fire("otherMouseUp", 2, middlepaste.KITTY_PASTE, middlepaste.MARK), false, "not taken for the real release")
    t.eq(fire("otherMouseUp", 2, {}), true, "the real release is still swallowed")
    t.eq(pastes, 1)
end)

t.done("adapter")
