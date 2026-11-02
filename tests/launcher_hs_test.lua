-- The chooser switcher (launcher_hs.lua) against a stand-in hs.chooser
-- that, as Hammerspoon's, can't be touched once deleted: the settings
-- window deletes it to switch launchers while a browser may still be
-- listing its tabs.

local t = require("t")

local function stub()
    local s = { tabs = {} }
    local methods = {}
    local visible = false
    local on_choice
    function methods:isVisible()
        return visible
    end
    function methods:show()
        visible = true
    end
    function methods:cancel()
        visible = false
        on_choice(nil)
    end
    function methods:query()
        return ""
    end
    function methods:delete()
        -- As libchooser.m's: the userdata loses its metatable.
        setmetatable(self, nil)
    end
    s.hs = {
        settings = {
            get = function() end,
            set = function() end,
        },
        chooser = {
            new = function(fn)
                on_choice = fn
                local c = setmetatable({}, {
                    __index = function(_, name)
                        return methods[name] or function() end
                    end,
                })
                s.chooser = c
                return c
            end,
        },
        hotkey = {
            bind = function()
                return { delete = function() end }
            end,
        },
        host = {
            interfaceStyle = function() end,
        },
    }
    s.tilemo = {
        adapter = {
            focused = function() end,
            log = function() end,
        },
        wm = {
            hold = function() end,
            focus_window = function() end,
            note_tabs = function()
                s.noted = true
            end,
        },
    }
    return s
end

local function launcher_with(s)
    _G.hs = s.hs
    package.loaded["tilemo.launcher_hs"] = nil
    local launcher_hs = require("tilemo.launcher_hs")
    launcher_hs.collector = function()
        return function()
            return {}
        end
    end
    launcher_hs.fetch_tabs = function(_, done)
        s.tabs[#s.tabs + 1] = done
    end
    return launcher_hs.new(s.tilemo)
end

t.test("a browser's tabs that answer after the switcher is deleted are dropped", function()
    local s = stub()
    local launcher = launcher_with(s)
    launcher.show("launch")
    t.eq(launcher.is_open(), true)
    launcher.delete()
    local ok, err = pcall(s.tabs[1], { { title = "Docs", url = "https://example.com/" } })
    t.eq(ok, true, tostring(err))
    t.eq(s.noted, nil, "the tabs aren't noted for a deleted switcher")
end)

t.test("a browser's tabs that answer while the switcher's open join it", function()
    local s = stub()
    local launcher = launcher_with(s)
    launcher.show("launch")
    s.tabs[1]({ { title = "Docs", url = "https://example.com/" } })
    t.eq(s.noted, true)
    launcher.cancel()
end)

t.done("launcher_hs")
