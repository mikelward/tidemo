local t = require("t")
local dashboard = require("tide.dashboard")

local DIR = "hammerspoon/tide/dashboard/"

local function read(name)
    local f = assert(io.open(DIR .. name))
    local s = f:read("a")
    f:close()
    return s
end

t.test("the clocks are in tide's settings folder, under XDG_CONFIG_HOME if set", function()
    local env = { HOME = "/Users/me" }
    local getenv = function(k)
        return env[k]
    end
    t.eq(dashboard.clock_dir(getenv), "/Users/me/.config/tide")
    env.XDG_CONFIG_HOME = "/Users/me/cfg"
    t.eq(dashboard.clock_dir(getenv), "/Users/me/cfg/tide")
end)

t.test("each clocks file is its text, and one that isn't there is left out", function()
    local files = { ["/c/tide/clocks.local.json"] = "[]" }
    local got = dashboard.clock_files("/c/tide", function(p)
        return files[p]
    end)
    t.eq(got, { ["local"] = "[]" })
end)

-- The column tracks the page's stylesheet gives `selector`'s rows.
local function columns(html, selector)
    local rule = html:match(selector:gsub("[%-#%.]", "%%%0") .. "%s*(%b{})")
    local tracks = rule and rule:match("grid%-template%-columns:%s*([^;]+);")
    local n = 0
    for _ in (tracks or ""):gmatch("%S+") do
        n = n + 1
    end
    return n
end

t.test("each list's rows have a column for every part, so none wraps", function()
    local html = read("settings.html")
    -- settings_page.cjs checks each row has this many parts.
    t.eq(columns(html, ".settings #startup-list li"), 4, "a command, up, down and remove")
    t.eq(columns(html, ".settings #muted-list li"), 2, "an entry and Unmute")
    t.eq(columns(html, ".settings #karabiner-rules li"), 2, "a Karabiner rule and On or Off")
    t.eq(columns(html, ".settings #shortcut-list li"), 2, "a shortcut's keys and what it does")
    t.eq(columns(html, ".settings #shortcut-failed li"), 2, "a key that didn't register and why")
    t.eq(columns(html, ".settings #floating-list li"), 5, "an app, its title, up, down and remove")
    t.eq(columns(html, ".settings #floating-now li"), 3, "an app, its title and Always float")
    t.eq(columns(html, ".settings #ws-list-standing li"), 5, "a workspace, its note, up, down and remove")
    t.eq(columns(html, ".settings #ws-list-namePatterns li"), 5, "a pattern, its note, up, down and remove")
    t.eq(columns(html, ".settings #ws-list-inApps li"), 2, "an app and remove")
    t.eq(columns(html, ".settings .ws-pinned li"), 2, "a pinned app and remove")
    t.eq(columns(html, ".settings #setup-permissions li"), 3, "a permission, its state and Open")
    t.eq(columns(html, ".settings #setup-items li"), 3, "a tick, its title and Open")
    t.eq(columns(html, ".settings li"), 6, "a zone, its label, Bar, left, right and remove")
    -- A row that's also a choice is laid out as one, over .row's flex.
    t.eq(columns(html, ".settings .row.choice"), 4, "the Switcher's name, ‹, its value and ›")
end)

t.test("the Start at login files are tide's, in its settings folder", function()
    local files = { ["/c/tide/startup.json"] = '{"commands": []}' }
    local got = dashboard.startup_files("/c/tide", function(p)
        return files[p]
    end)
    t.eq(got, { shared = '{"commands": []}' })
end)

t.test("the Clipboard settings files are tide's, in its settings folder", function()
    local got = dashboard.clipboard_files("/c/tide", function(p)
        return p == "/c/tide/clipboard.local.json" and "{}" or nil
    end)
    t.eq(got, { ["local"] = "{}" })
end)

t.test("the Layouts settings files are tide's, in its settings folder", function()
    local got = dashboard.layout_files("/c/tide", function(p)
        return p == "/c/tide/layouts.json" and "{}" or nil
    end)
    t.eq(got, { shared = "{}" })
    t.eq(dashboard.LAYOUTS_LOCAL_FILE, "layouts.local.json")
end)

t.test("the Workspaces settings files are tide's, in its settings folder", function()
    local got = dashboard.workspace_files("/c/tide", function(p)
        return p == "/c/tide/workspaces.local.json" and "{}" or nil
    end)
    t.eq(got, { ["local"] = "{}" })
    t.eq(dashboard.WORKSPACES_LOCAL_FILE, "workspaces.local.json")
end)

t.test("a tide module copied unchanged finds another by tide's name for it", function()
    local js = dashboard.bundle({
        ["tide-clocks.js"] = "export const X = 1;",
        ["tide-startup.js"] = 'import { X } from "./clocks.mjs";\nexport const Y = X;',
    }, { "tide-clocks.js", "tide-startup.js" })
    t.eq(js:find('modules["./clocks.mjs"] = modules["./tide-clocks.js"];', 1, true) ~= nil, true)
    t.eq(js:find('modules["./clocks.mjs"]', 1, true) < js:find("const Y", 1, true), true, "registered before it's needed")
end)

t.test("every page in the sidebar, and every icon button, has its icon drawn", function()
    local html = read("settings.html")
    local js = read("settings-page.js")
    local drawn = {}
    for name in html:gmatch('%[data%-icon="([%w_-]+)"%]%s*{%s*%-%-icon:') do
        -- One rule each: a second would draw over a page's own.
        t.eq(drawn[name], nil, "a second icon named " .. name)
        drawn[name] = true
    end
    for _, sec in ipairs(require("tide.launcher").SETTINGS_SECTIONS) do
        if not sec.page then
            t.eq(drawn[sec.id], true, "the sidebar's " .. sec.id)
        end
    end
    local glyphs = js:match("const ICONS = (%b{})")
    t.eq(glyphs ~= nil, true, "settings-page.js's ICONS")
    for name in glyphs:gmatch('"([%w_-]+)"') do
        if not name:match("^%W") then
            t.eq(drawn[name], true, "a button's " .. name)
        end
    end
    for name in html:gmatch('<[^>]- data%-icon="([%w_-]+)"') do
        t.eq(drawn[name], true, "the page's " .. name)
    end
    t.eq(drawn.open, true, "a section's buttons")
end)

t.test("the settings page builds, and changes the clocks as tide's page does", function()
    local sources = {}
    for _, name in ipairs(dashboard.SETTINGS_MODULES) do
        sources[name] = read(name)
    end
    local html = dashboard.page(read("settings.html"), read("launcher.css"), sources, dashboard.SETTINGS_MODULES)
    t.eq(html:find("/*TIDE_", 1, true), nil)
    t.eq(html:find('id="add-zone"', 1, true) ~= nil, true)
    t.eq(html:find('id="add-command"', 1, true) ~= nil, true)
    t.eq(html:find('id="clipboard-history"', 1, true) ~= nil, true)
    for _, id in ipairs({ "clocks", "layouts", "workspaces", "startup", "clipboard", "muted", "floating" }) do
        t.eq(html:find('<h1 id="' .. id .. '"', 1, true) ~= nil, true, "a section to reveal: " .. id)
    end
    local node = io.popen("command -v node"):read("l")
    if not node then
        if os.getenv("TIDE_NEED_NODE") then
            error("node is needed to check the settings page")
        end
        print("SKIP the settings page's changes: no node")
        return
    end
    local path = os.tmpname()
    local f = assert(io.open(path, "w"))
    f:write(dashboard.bundle(sources, dashboard.SETTINGS_MODULES))
    f:close()
    local p = io.popen("TZ=Europe/Dublin node tests/settings_page.cjs " .. path .. " 2>&1")
    local out = p:read("a")
    local ok = p:close()
    os.remove(path)
    if not ok then
        error(out)
    end
end)

t.test("a launcher switch that fails says why, and the log keeps it", function()
    local settings_hs = require("tide.settings_hs")
    local logged = {}
    local tide = {
        adapter = {
            log = function(line)
                logged[#logged + 1] = line
            end,
        },
        set_launcher = function()
            return nil, "can't read the dashboard launcher's launcherpage.html"
        end,
    }
    local ok, why = settings_hs.switch_launcher(tide, "dashboard")
    t.eq(ok, nil)
    t.eq(why, "can't read the dashboard launcher's launcherpage.html")
    t.eq(logged, { "settings: couldn't switch the launcher to dashboard: can't read the dashboard launcher's launcherpage.html" })
    tide.set_launcher = nil
    ok, why = settings_hs.switch_launcher(tide, "dashboard")
    t.eq(why, "this tide can't switch launchers")
    tide.set_launcher = function()
        return true
    end
    t.eq(settings_hs.switch_launcher(tide, "chooser"), true)
    t.eq(#logged, 2)
end)

-- The Super key: tide binds its keys again at once, not at the next
-- Karabiner check, and a choice that fails says why and changes nothing.
t.test("a Super key choice rebinds tide's keys at once, and a failed one says why", function()
    local settings_hs = require("tide.settings_hs")
    local logged, rechecks, asked = {}, 0, {}
    local tide = {
        adapter = {
            log = function(line)
                logged[#logged + 1] = line
            end,
        },
        karabiner_rules = {
            set_super = function(value)
                asked[#asked + 1] = value
                if value == "capslock" then
                    return nil, "there's no Super key called capslock"
                end
                return true
            end,
        },
        recheck_super = function()
            rechecks = rechecks + 1
        end,
    }
    t.eq(settings_hs.choose_super(tide, "none"), true)
    t.eq(rechecks, 1)
    local ok, why = settings_hs.choose_super(tide, "capslock")
    t.eq(ok, nil)
    t.eq(why, "there's no Super key called capslock")
    t.eq(rechecks, 1, "a failed choice binds nothing again")
    t.eq(logged, { "settings: couldn't make capslock the Super key: there's no Super key called capslock" })
    t.eq(asked, { "none", "capslock" })
    tide.karabiner_rules = nil
    ok, why = settings_hs.choose_super(tide, "win")
    t.eq(why, "tide can't switch Karabiner's rules on this Mac")
end)

-- The Bar page's Position row: kept in hs.settings, and the bars and windows follow at
-- once, with no reload.
t.test("a Bar choice is kept and places the bars and tiles again at once", function()
    local settings_hs = require("tide.settings_hs")
    local bar = require("tide.bar")
    local checklist = require("tide.checklist")
    local stored, did, logged, said = {}, {}, {}, {}
    local dock = { side = "bottom", hides = false }
    local tide = {
        adapter = {
            log = function(line)
                logged[#logged + 1] = line
            end,
            notify = function(text)
                said[#said + 1] = text
            end,
            dock = function()
                return dock
            end,
        },
        wm = {
            bar_position = "top",
            bar_floor = { A = 68 },
            retile = function()
                did[#did + 1] = "retile"
            end,
        },
        bar = {
            update = function()
                did[#did + 1] = "place"
            end,
        },
    }
    local store = {
        set = function(k, v)
            stored[k] = v
        end,
    }
    t.eq(settings_hs.choose_bar_position(tide, "bottom", store), true)
    t.eq(stored[bar.POSITION_KEY], "bottom")
    t.eq(tide.bar_position, "bottom")
    t.eq(tide.wm.bar_position, "bottom")
    t.eq(tide.wm.bar_floor, {}, "a floor is for the top")
    t.eq(did, { "place", "retile" })
    t.eq(said, {}, "a Dock shown at the bottom is fine")
    dock.hides = true
    settings_hs.choose_bar_position(tide, "bottom", store)
    t.eq(said, { checklist.DOCK_NOTICE }, "one that hides there slides over the bar")
    local ok, why = settings_hs.choose_bar_position(tide, "left", store)
    t.eq(ok, nil)
    t.eq(why, "the bar can't go along left")
    t.eq(stored[bar.POSITION_KEY], "bottom", "nothing changed")
    t.eq(logged, { "settings: the bar can't go along left" })
end)

t.test("the Bar page's icons are kept whole and drawn at once", function()
    local settings_hs = require("tide.settings_hs")
    local bar = require("tide.bar")
    local stored, logged, drawn = {}, {}, 0
    local tide = {
        adapter = {
            log = function(text)
                logged[#logged + 1] = text
            end,
        },
        bar = {
            update = function()
                drawn = drawn + 1
            end,
        },
    }
    local store = {
        set = function(k, v)
            stored[k] = v
        end,
    }
    t.eq(settings_hs.choose_bar_icons(tide, { { id = "tray", shown = true }, { id = "bogus" } }, store), true)
    local kept = stored[bar.ICONS_KEY]
    t.eq(#kept, #bar.ICONS, "every icon, once")
    local want = {}
    for i, e in ipairs(bar.icon_list({ { id = "tray", shown = true } })) do
        want[i] = { id = e.id, shown = e.shown }
    end
    t.eq(kept, want, "made whole as the bar makes it, other apps' icons on")
    t.eq(tide.bar_icons, kept)
    t.eq(drawn, 1)
    local ok, why = settings_hs.choose_bar_icons(tide, "battery", store)
    t.eq(ok, nil)
    t.eq(why, "the bar's icons aren't a list: battery")
    t.eq(stored[bar.ICONS_KEY], kept, "nothing changed")
    t.eq(logged, { "settings: the bar's icons aren't a list: battery" })
end)

t.test("the wallpaper grid reaches the page with its lists as lists, empty or not", function()
    local settings_hs = require("tide.settings_hs")
    local json = require("json")
    local was = _G.hs
    _G.hs = { json = { encode = json.encode } }
    local text = settings_hs.encode_gallery({ images = {}, screens = { { width = 1512, height = 982 } },
        problems = { 'couldn\'t read "x"' } })
    _G.hs = was
    t.eq(json.decode(text), { images = {}, screens = { { width = 1512, height = 982 } }, problems = { 'couldn\'t read "x"' } })
    t.eq(text:find('"images":[]', 1, true) ~= nil, true, text)
end)

t.done("settings")
