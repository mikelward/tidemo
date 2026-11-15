-- The workspaces in macOS's menu bar (SPEC.md §8): shown with no bar, or
-- with the Bar page's Position at Menu bar, and gone with the bar back.
local t = require("t")
local bar = require("tide.bar")
local brand = require("tide.brand")

-- A stand-in for whatever hs.* init.lua touches as it loads: every field
-- is a function returning the stand-in again.
local function anything()
    local any
    any = setmetatable({}, {
        __index = function()
            return any
        end,
        __call = function()
            return any
        end,
    })
    return any
end

-- hs.menubar.new hands out items that keep what they're given; `fail`
-- makes it hand out none, as macOS can.
local made = {}
local fail = false
local function new_item()
    local item = { deleted = false }
    function item:setIcon(icon, template)
        self.icon, self.template = icon, template
    end
    function item:setTooltip(s)
        self.tooltip = s
    end
    function item:setTitle(s)
        self.title = s
    end
    function item:setMenu(fn)
        self.menu = fn
    end
    function item:delete()
        self.deleted = true
    end
    made[#made + 1] = item
    return item
end

local was = _G.hs
_G.hs = setmetatable({
    menubar = {
        new = function()
            if fail then
                return nil
            end
            return new_item()
        end,
    },
}, {
    __index = function()
        return anything()
    end,
})
-- The names in the menu bar's middle, standing in for notchbar_hs: whether
-- they fit is the test's to say.
local fits = true
local strips = {}
package.loaded["tide.notchbar_hs"] = {
    new = function(_, changed)
        local strip = { stopped = false, changed = changed }
        function strip.update()
            return fits
        end
        function strip.stop()
            strip.stopped = true
        end
        strips[#strips + 1] = strip
        return strip
    end,
}
local tide = require("tide")
package.loaded["tide.notchbar_hs"] = nil

-- What sync_menubar_item reads of tide: the bar, its position, the wm and
-- the adapter.
local function fake_tide(has_bar, position)
    local self = { logs = {}, notes = {}, shown = {}, sync_menubar_item = tide.sync_menubar_item }
    self.bar = has_bar and {} or nil
    self.bar_position = position
    self.adapter = {
        logo = function(name)
            return "logo:" .. name
        end,
        log = function(s)
            self.logs[#self.logs + 1] = s
        end,
        notify = function(s)
            self.notes[#self.notes + 1] = s
        end,
    }
    self.wm = {
        bar_state = function()
            return { { name = "in", here = true }, { name = "web", occupied = true } }
        end,
        listed = function()
            return { "in", "web" }
        end,
        act = function(_, what, n)
            self.shown[#self.shown + 1] = what .. " " .. n
        end,
    }
    return self
end

t.test("with the bar at the top or bottom there's no menu bar item", function()
    made = {}
    for _, at in ipairs({ "top", "bottom" }) do
        local self = fake_tide(true, at)
        tide.sync_menubar_item(self)
        t.eq(self.menubar, nil, at)
    end
    t.eq(#made, 0)
end)

t.test("Position: Menu bar shows tide's logo and the workspaces, and a click switches", function()
    made = {}
    local self = fake_tide(true, "menubar")
    tide.sync_menubar_item(self)
    local item = self.menubar
    t.eq(item ~= nil, true, "made")
    t.eq(item.icon, "logo:" .. brand.TEMPLATE)
    t.eq(item.template, true, "tinted by macOS to suit the menu bar")
    t.eq(item.tooltip, brand.NAME)
    t.eq(item.title, "[in] web")
    local menu = item.menu()
    t.eq(#menu, 2)
    t.eq(menu[2].title, "web")
    menu[2].fn()
    t.eq(self.shown, { "show web" })
    tide.sync_menubar_item(self)
    t.eq(#made, 1, "made once, then kept")
end)

t.test("with no bar at all the workspaces show in the menu bar", function()
    made = {}
    local self = fake_tide(false, "top")
    tide.sync_menubar_item(self)
    t.eq(self.menubar ~= nil, true)
end)

t.test("the bar back removes the menu bar item", function()
    made = {}
    local self = fake_tide(true, "menubar")
    tide.sync_menubar_item(self)
    local item = self.menubar
    self.bar_position = "top"
    tide.sync_menubar_item(self)
    t.eq(self.menubar, nil)
    t.eq(item.deleted, true)
end)

t.test("an item macOS won't make is logged and said", function()
    made = {}
    fail = true
    local self = fake_tide(true, "menubar")
    tide.sync_menubar_item(self)
    fail = false
    t.eq(self.menubar, nil)
    t.eq(#self.logs, 1)
    t.eq(self.notes, { "Couldn't show the workspaces in the menu bar." })
end)

t.test("Middle of menu bar draws the names there, with no menu bar item while they fit", function()
    made, strips, fits = {}, {}, true
    local self = fake_tide(true, "menubar-middle")
    tide.sync_menubar_item(self)
    t.eq(#strips, 1, "the names drawn")
    t.eq(self.menubar, nil, "and no item")
    tide.sync_menubar_item(self)
    t.eq(#strips, 1, "drawn by the same one")
end)

t.test("names that don't fit in the middle show in the menu bar item until they do", function()
    made, strips, fits = {}, {}, false
    local self = fake_tide(true, "menubar-middle")
    tide.sync_menubar_item(self)
    t.eq(self.menubar ~= nil, true, "never lost")
    t.eq(self.menubar.title, "[in] web")
    local item = self.menubar
    fits = true
    strips[1].changed()
    t.eq(self.menubar, nil, "the front app's menus shrank")
    t.eq(item.deleted, true)
end)

t.test("leaving Middle of menu bar stops drawing the names there", function()
    made, strips, fits = {}, {}, true
    local self = fake_tide(true, "menubar-middle")
    tide.sync_menubar_item(self)
    self.bar_position = "menubar"
    tide.sync_menubar_item(self)
    t.eq(strips[1].stopped, true)
    t.eq(self.notchbar, nil)
    t.eq(self.menubar ~= nil, true, "the item on the right instead")
end)

_G.hs = was
t.done("menubar_item")
