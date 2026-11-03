-- The Dock's badges, as the adapter reads them every two seconds for
-- attention (SPEC.md §14.2), against a stand-in Dock and app list. Reading
-- one runs on Hammerspoon's thread, so it asks only what a badge needs.

local t = require("t")

-- A Dock of `items` ({ title, label }), and the apps running, by name.
local function stub(items, running)
    local s = { walks = 0, asked = 0 }
    local function element(attrs)
        return {
            attributeValue = function(_, name)
                s.asked = s.asked + 1
                return attrs[name]
            end,
        }
    end
    local children = {}
    for _, it in ipairs(items) do
        children[#children + 1] = element({ AXTitle = it.title, AXStatusLabel = it.label })
    end
    local list = element({ AXChildren = children })
    local apps = {}
    for name, bundle in pairs(running) do
        apps[#apps + 1] = {
            name = function() return name end,
            bundleID = function() return bundle end,
        }
    end
    _G.hs = {
        axuielement = {
            systemWideElement = function()
                return { setTimeout = function() end }
            end,
            applicationElement = function()
                return element({ AXChildren = { list } })
            end,
        },
        window = {
            filter = {
                new = function()
                    return { setDefaultFilter = function() end }
                end,
            },
        },
        application = {
            get = function(hint)
                if hint == "com.apple.dock" then
                    return { name = "Dock" }
                end
                -- Not a bundle ID: Hammerspoon walks every running app.
                s.walks = s.walks + 1
                for name, bundle in pairs(running) do
                    if name == hint then
                        return { bundleID = function() return bundle end }
                    end
                end
            end,
            runningApplications = function()
                s.walks = s.walks + 1
                return apps
            end,
        },
        logger = { new = function() return { i = function() end } end },
        task = { new = function() end },
    }
    package.loaded["tilemo.hs_adapter"] = nil
    s.adapter = require("tilemo.hs_adapter").new()
    return s
end

local DOCK = {
    { title = "Finder" }, { title = "Safari" }, { title = "Mail", label = "3" }, { title = "Notes" },
    { title = "Calendar" }, { title = "Messages", label = "" }, { title = "Music" }, { title = "Trash" },
}
local RUNNING = {
    Finder = "com.apple.finder", Safari = "com.apple.Safari", Mail = "com.apple.mail", Notes = "com.apple.Notes",
    Messages = "com.apple.MobileSMS",
}

t.test("a Dock badge is read with its app", function()
    local s = stub(DOCK, RUNNING)
    t.eq(s.adapter.dock_badges(), { { app = "com.apple.mail", label = "3" } })
end)

t.test("reading the Dock walks the running apps once at most, and only for a badge", function()
    local s = stub(DOCK, RUNNING)
    s.adapter.dock_badges()
    t.eq(s.walks <= 1, true, "walked " .. s.walks .. " times")
    local quiet = stub({ { title = "Finder" }, { title = "Safari" } }, RUNNING)
    quiet.adapter.dock_badges()
    t.eq(quiet.walks, 0, "no badge, no walk")
end)

t.done("dock")
