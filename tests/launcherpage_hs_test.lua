-- The dashboard launcher's webview (launcherpage_hs.lua) against a stand-in
-- hs.webview: it's made hidden as the launcher starts, and a page that
-- fails to load is made again at the next key, whether or not one was
-- pressed while it loaded.

local t = require("t")

local function stub()
    local s = { views = {}, holds = {} }
    s.hs = {
        settings = { get = function() end, set = function() end },
        inspect = function(v)
            return tostring(v)
        end,
        timer = {
            secondsSinceEpoch = function()
                return 0
            end,
        },
        drawing = { windowLevels = { modalPanel = 8 } },
        screen = {
            mainScreen = function()
                return { fullFrame = function() return { x = 0, y = 0, w = 800, h = 600 } end }
            end,
        },
        webview = {
            usercontent = {
                new = function()
                    return { setCallback = function() end }
                end,
            },
            new = function(frame)
                local v = { frame_ = frame, shown = false, deleted = false }
                local methods = {}
                function methods:navigationCallback(fn)
                    v.navigate = fn
                end
                function methods:windowCallback(fn)
                    v.window = fn
                end
                function methods:show()
                    v.shown = true
                end
                function methods:hide()
                    v.shown = false
                end
                function methods:delete()
                    v.deleted = true
                end
                function methods:hswindow() end
                -- As Hammerspoon answers a script that ran.
                function methods:evaluateJavaScript(js, done)
                    s.ran = (s.ran or 0) + 1
                    if done then
                        done(nil, { code = 0 })
                    end
                end
                setmetatable(v, {
                    __index = function(_, name)
                        return methods[name] or function() end
                    end,
                })
                s.views[#s.views + 1] = v
                return v
            end,
        },
    }
    s.tilemo = {
        adapter = {
            focused = function() end,
            log = function(line)
                s.logged = line
            end,
            after = function(_, fn)
                fn()
            end,
        },
        wm = {
            current_screen = function()
                return "uuid-1"
            end,
            screen_by_uuid = function()
                return { full = { x = 0, y = 0, w = 800, h = 600 } }
            end,
            hold = function(_, what, on)
                s.holds[what] = on
            end,
            focus_window = function() end,
        },
    }
    return s
end

local function launcher_with(s)
    _G.hs = s.hs
    package.loaded["tilemo.launcherpage_hs"] = nil
    package.loaded["tilemo.launcher_hs"] = nil
    local launcher_hs = require("tilemo.launcher_hs")
    launcher_hs.collector = function()
        return function()
            return {}
        end
    end
    launcher_hs.fetch_tabs = function() end
    return require("tilemo.launcherpage_hs").new(s.tilemo)
end

t.test("the page is made hidden as the launcher starts, and a key shows it", function()
    local s = stub()
    local page = launcher_with(s)
    t.eq(#s.views, 1)
    t.eq(s.views[1].shown, false)
    page.show("launch")
    t.eq(#s.views, 1, "no second webview")
    t.eq(s.views[1].shown, true)
    t.eq(s.holds.launcher, true)
    page.cancel()
    t.eq(s.views[1].shown, false)
    t.eq(s.views[1].deleted, false, "kept for the next key")
    t.eq(s.holds.launcher, false)
end)

t.test("a page that fails to load while open closes, and the next key makes it again", function()
    local s = stub()
    local page = launcher_with(s)
    page.show("launch")
    s.views[1].navigate("didFailProvisionalNavigation", s.views[1], nil, { code = -1009 })
    t.eq(s.views[1].deleted, true)
    t.eq(page.is_open(), false)
    t.eq(s.holds.launcher, false, "focus follows mouse comes back")
    page.show("launch")
    t.eq(#s.views, 2, "a new webview, loading the page again")
    t.eq(s.views[2].shown, true)
    t.eq(page.is_open(), true)
end)

t.test("a call the page ran isn't logged as a failure", function()
    local s = stub()
    _G.hs = s.hs
    s.hs.json = { encode = function() return "{}" end }
    s.hs.caffeinate = { get = function() return false end }
    s.tilemo.wm.listed = function() return {}, {} end
    s.tilemo.wm.bar_state = function() return {} end
    s.tilemo.wm.windows = {}
    s.tilemo.wm.screens = function() return {} end
    local page = launcher_with(s)
    s.views[1].navigate("didFinishNavigation", s.views[1])
    page.show("launch")
    t.eq(s.ran, 1, "the page was filled")
    t.eq(s.logged, nil)
    page.cancel()
end)

t.done("launcherpage_hs")
