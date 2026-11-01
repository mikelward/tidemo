local t = require("t")
local checklist = require("tilemo.checklist")
local links = require("tilemo.links")

local function by_id(list)
    local out = {}
    for _, x in ipairs(list) do
        out[x.id] = x
    end
    return out
end

t.test("every permission and item opens a System Settings pane", function()
    for _, list in ipairs({ checklist.PERMISSIONS, checklist.ITEMS }) do
        for _, x in ipairs(list) do
            t.eq(links.PANES[x.link] ~= nil, true, x.id .. " opens nothing")
            t.eq(x.ref:match("^§%d") ~= nil, true, x.id .. " names no section")
        end
    end
end)

t.test("Accessibility is on or off as macOS says, and can't be told unasked", function()
    t.eq(checklist.permission_state("accessibility", { accessibility = true }), "on")
    t.eq(checklist.permission_state("accessibility", { accessibility = false }), "off")
    t.eq(checklist.permission_state("accessibility", {}), "unknown")
end)

t.test("Input Monitoring isn't needed with Karabiner, and can't be read without", function()
    t.eq(checklist.permission_state("input_monitoring", { karabiner = true }), "not_needed")
    t.eq(checklist.permission_state("input_monitoring", { karabiner = false }), "unknown")
end)

t.test("Screen Recording is never needed, and Automation can't be read", function()
    t.eq(checklist.permission_state("screen_recording", { accessibility = true }), "not_needed")
    t.eq(checklist.permission_state("automation", { accessibility = true, karabiner = true }), "unknown")
end)

t.test("the page gives each permission its state's label, and each item its tick", function()
    local page = checklist.page({ accessibility = false, karabiner = true }, { "lock", "minimize" })
    local perms = by_id(page.permissions)
    t.eq(perms.accessibility.state, "off")
    t.eq(perms.accessibility.label, "Off")
    t.eq(perms.input_monitoring.label, "Not needed")
    t.eq(perms.automation.label, "Can't tell")
    t.eq(perms.accessibility.link, "privacy_accessibility")
    local items = by_id(page.items)
    t.eq(items.lock.done, true)
    t.eq(items.minimize.done, true)
    t.eq(items.mission_control.done, false)
    t.eq(page.left, #checklist.ITEMS - 2)
    t.eq(#page.permissions, #checklist.PERMISSIONS)
    t.eq(#page.items, #checklist.ITEMS)
end)

t.test("only ticks for items that still exist count, once each, in the items' order", function()
    t.eq(checklist.progress({ "lock", "gone", "mission_control", "lock" }), { done = { "mission_control", "lock" }, left = #checklist.ITEMS - 2 })
    t.eq(checklist.progress(nil), { done = {}, left = #checklist.ITEMS })
    t.eq(checklist.progress("junk"), { done = {}, left = #checklist.ITEMS })
end)

t.test("a tick adds an item and an untick takes it out, keeping the rest", function()
    local list = checklist.ticked({ "lock" }, "tiling", true)
    t.eq(list, { "lock", "tiling" })
    t.eq(checklist.ticked(list, "lock", false), { "tiling" })
    t.eq(checklist.ticked({ "lock" }, "lock", true), { "lock" }, "ticked twice is once")
end)

t.test("a tick for an item the checklist doesn't have is refused", function()
    local list, why = checklist.ticked({ "lock" }, "accessibility", true)
    t.eq(list, nil)
    t.eq(why:find("no item accessibility", 1, true) ~= nil, true)
    t.eq((checklist.ticked({}, nil, true)), nil)
end)

t.test("tilemo doctor names Accessibility only when it's off", function()
    t.eq(#checklist.doctor({ accessibility = false }), 1)
    t.eq(checklist.doctor({ accessibility = false })[1]:find("Accessibility is off", 1, true) ~= nil, true)
    t.eq(checklist.doctor({ accessibility = true }), {})
    t.eq(checklist.doctor({}), {}, "unknown isn't a problem to report")
end)

t.done("checklist")
