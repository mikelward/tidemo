-- notchbar_hs.lua against a stand-in hs (SPEC.md §8, Position: Middle of
-- menu bar): what it draws, when it gives way to the menu bar item, how it
-- reads the front app's menus, and what a click on a name does.

local t = require("t")
local notchbar = require("tide.notchbar")

-- An Accessibility element: attributeValue answers from `attrs`, a name
-- with no answer giving nil and why, as hs.axuielement does.
local function el(attrs, calls)
    local e = {}
    function e:attributeValue(name)
        if calls then
            calls[#calls + 1] = name
        end
        local v = attrs[name]
        if v == nil then
            return nil, "no " .. name
        end
        return v
    end
    return e
end

-- The front app's menus: `widths` from the display's left, 10 pt in.
local function menu_bar(widths, calls)
    local items, x = {}, 10
    for i, w in ipairs(widths) do
        items[i] = el({ AXFrame = { x = x, y = 0, w = w, h = 24 } }, calls)
        x = x + w
    end
    return el({ AXChildren = items }, calls)
end

local function world()
    local w = {
        logs = {}, acts = {}, canvases = {}, changed = 0, ax_calls = {},
        style = "Light", own_front = false,
        screens = {
            {
                uuid = "A",
                full = { x = 0, y = 0, w = 1920, h = 1080 },
                area = { x = 0, y = 24, w = 1920, h = 1056 },
                menu_bar = true,
            },
        },
        workspaces = { { name = "in", here = true }, { name = "web", occupied = true } },
    }
    w.menus = menu_bar({ 60, 40, 40, 50 }, w.ax_calls)
    _G.hs = {
        host = {
            interfaceStyle = function()
                return w.style == "Dark" and "Dark" or nil
            end,
        },
        styledtext = {
            defaultFonts = { boldSystem = { name = "Bold" }, menuBar = { name = "Menu" } },
            new = function(s, attrs)
                return { s = s, attrs = attrs }
            end,
        },
        drawing = {
            -- 7 pt a character, as a stand-in for macOS's measure.
            getTextDrawingSize = function(text)
                return { w = #text.s * 7, h = 16 }
            end,
        },
        canvas = {
            windowBehaviors = { canJoinAllSpaces = 1, stationary = 16 },
            windowLevels = { status = 25, mainMenu = 24, floating = 3 },
            new = function(frame)
                local c = { frame_ = frame, drawn = 0, shown = false, deleted = false }
                function c:behavior() end
                function c:clickActivating() end
                function c:canvasMouseEvents() end
                function c:mouseCallback(fn)
                    c.click = fn
                end
                function c:level(l)
                    c.level_ = l
                end
                function c:frame(f)
                    c.frame_ = f
                end
                function c:replaceElements(els)
                    c.els = els
                    c.drawn = c.drawn + 1
                end
                function c:show()
                    c.shown = true
                end
                function c:hide()
                    c.shown = false
                end
                function c:delete()
                    c.deleted = true
                end
                w.canvases[#w.canvases + 1] = c
                return c
            end,
        },
        application = {
            frontmostApplication = function()
                if w.no_front then
                    return nil
                end
                return {}
            end,
            watcher = {
                activated = "activated",
                new = function(fn)
                    w.watch = fn
                    return {
                        start = function()
                            w.watching = true
                        end,
                        stop = function()
                            w.watching = false
                        end,
                    }
                end,
            },
        },
        axuielement = {
            applicationElement = function()
                w.ax_calls[#w.ax_calls + 1] = "app"
                return el({ AXMenuBar = w.menus }, w.ax_calls)
            end,
        },
    }
    local tide = {
        adapter = {
            log = function(s)
                w.logs[#w.logs + 1] = s
            end,
            screens = function()
                return w.screens
            end,
            -- No notch read: macOS says none.
            javascript = function()
                if w.js_fails then
                    return false, "no JXA"
                end
                return true, "[]"
            end,
            decode = function(s)
                return s == "[]" and {} or nil
            end,
            own_front = function()
                return w.own_front
            end,
        },
        wm = {
            windows = {},
            a = {
                focused = function()
                    return nil
                end,
                state = function()
                    return nil
                end,
                screens = function()
                    return w.screens
                end,
            },
            bar_state = function()
                return w.workspaces
            end,
            act = function(_, what, n)
                w.acts[#w.acts + 1] = what .. " " .. n
            end,
        },
    }
    package.loaded["tide.notchbar_hs"] = nil
    w.strip = require("tide.notchbar_hs").new(tide, function()
        w.changed = w.changed + 1
    end)
    return w
end

local function logged(w, text)
    local n = 0
    for _, s in ipairs(w.logs) do
        if s:find(text, 1, true) then
            n = n + 1
        end
    end
    return n
end

local was = _G.hs

t.test("the names are drawn over the menu bar, and that's enough", function()
    local w = world()
    t.eq(w.strip.update(), true)
    local c = w.canvases[1]
    t.eq(c.shown, true)
    t.eq(c.frame_.y, 0, "from the top of the screen")
    t.eq(c.frame_.h, 24, "as tall as the menu bar")
    t.eq(c.level_, 25, "at the status level, over a menu bar that shows")
    t.eq(c.els[2].text.s, "in")
    t.eq(c.els[1].type, "rectangle", "the current one on a pill")
    t.eq(logged(w, "started"), 1)
end)

t.test("a click on a name shows that workspace", function()
    local w = world()
    w.strip.update()
    local c = w.canvases[1]
    -- "in" is 14 pt and its padding; "web" starts after it and the gap.
    local web = 14 + 2 * notchbar.PAD + notchbar.GAP + 1
    c.click(c, "mouseDown", "_canvas_", web, 10)
    c.click(c, "mouseUp", "_canvas_", web, 10)
    c.click(c, "mouseDown", "_canvas_", 999, 10)
    t.eq(w.acts, { "show web" }, "a press on a name, once, and none off them")
end)

t.test("nothing new is drawn again on the poll", function()
    local w = world()
    w.strip.update()
    w.strip.update()
    t.eq(w.canvases[1].drawn, 1)
    w.workspaces[2].here, w.workspaces[1].here = true, nil
    w.strip.update()
    t.eq(w.canvases[1].drawn, 2, "the current one moved")
end)

t.test("menus that can't be read give way to the menu bar item, said once", function()
    local w = world()
    w.menus = el({}, w.ax_calls)
    t.eq(w.strip.update(), false)
    t.eq(w.strip.update(), false)
    t.eq(#w.canvases, 0, "nothing drawn over menus it can't see")
    t.eq(logged(w, "couldn't read the app's menus"), 1)
    t.eq(w.strip.failed.menus, "no menus: no AXChildren")
    -- Readable again: drawn, and the failure forgotten, so the same one
    -- coming back is said again.
    local good = menu_bar({ 60 }, w.ax_calls)
    w.menus = good
    t.eq(w.strip.update(), true)
    t.eq(w.strip.failed.menus, nil)
    w.menus = el({}, w.ax_calls)
    w.strip.update()
    t.eq(logged(w, "couldn't read the app's menus"), 2)
end)

t.test("a menu without a frame, or no front app, counts as unreadable", function()
    local w = world()
    w.menus = el({ AXChildren = { el({}) } })
    t.eq(w.strip.update(), false)
    t.eq(w.strip.failed.menus, "a menu without a frame: no AXFrame")
    w.no_front = true
    t.eq(w.strip.update(), false)
    t.eq(w.strip.failed.menus, "no front app")
end)

t.test("menus reaching the middle give way to the menu bar item", function()
    local w = world()
    w.menus = menu_bar({ 1200 }, w.ax_calls)
    t.eq(w.strip.update(), false)
    t.eq(#w.canvases, 0)
    t.eq(logged(w, "in the menu bar item too, as the app's menus leave no room"), 1)
end)

t.test("with Hammerspoon in front, Accessibility isn't asked about it", function()
    local w = world()
    w.own_front = true
    t.eq(w.strip.update(), false, "no menus read yet: unknown, so the item shows")
    t.eq(#w.ax_calls, 0, "not asked")
    w.own_front = false
    t.eq(w.strip.update(), true)
    local asked = #w.ax_calls
    w.own_front = true
    t.eq(w.strip.update(), true, "the last app's menus stand in")
    t.eq(#w.ax_calls, asked, "still not asked")
end)

t.test("a display with no menu bar of its own keeps the menu bar item", function()
    local w = world()
    w.screens[2] = {
        uuid = "B",
        full = { x = 1920, y = 0, w = 1920, h = 1080 },
        area = { x = 1920, y = 0, w = 1920, h = 1080 },
        menu_bar = true,
    }
    t.eq(w.strip.update(), false)
    t.eq(#w.canvases, 1, "drawn on the one that has a menu bar")
end)

t.test("a display that goes takes its strip with it, and stopping takes the rest", function()
    local w = world()
    w.strip.update()
    local c = w.canvases[1]
    local screens = w.screens
    w.screens = {}
    w.strip.update()
    t.eq(c.deleted, true)
    w.screens = screens
    w.strip.update()
    t.eq(w.watching, true)
    w.strip.stop()
    t.eq(w.canvases[2].deleted, true)
    t.eq(w.watching, false)
    t.eq(logged(w, "stopped"), 1)
end)

t.test("another app coming to the front says the room may have changed", function()
    local w = world()
    w.watch(nil, "activated")
    w.watch(nil, "deactivated")
    t.eq(w.changed, 1)
end)

t.test("a notch that can't be read is guessed, and said once", function()
    local w = world()
    w.js_fails = true
    w.strip.update()
    w.strip.update()
    t.eq(logged(w, "couldn't read where the notch is"), 1)
    t.eq(w.strip.failed.notch, "no JXA")
end)

_G.hs = was
t.done("notchbar_hs")
