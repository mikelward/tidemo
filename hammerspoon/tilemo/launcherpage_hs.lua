-- The dashboard launcher on Hammerspoon (SPEC.md §9.2): tileco's launcher
-- page, with launcherpage.lua's stand-ins for Chrome, in a borderless
-- hs.webview over the display you're on, in place of the hs.chooser
-- switcher. It runs only with start()'s `launcher = "dashboard"`. Its rows
-- are the switcher's (launcher_hs.collector), and choosing one runs it as
-- the switcher does (launcher_hs.run). The page is made once and loaded as
-- tilemo starts, then shown and hidden: making a webview and loading the
-- page on each key took most of the time it took to open. Not runnable
-- outside Hammerspoon.

local brand = require("tilemo.brand")
local dashboard = require("tilemo.dashboard")
local launcher_hs = require("tilemo.launcher_hs")
local launcherpage = require("tilemo.launcherpage")
local names = require("tilemo.names")
local saved = require("tilemo.saved")
local wm_mod = require("tilemo.wm")

local M = {}

local DIR = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") .. "/dashboard/"

local function read(name)
    local f, err = io.open(DIR .. name)
    if not f then
        error("tide: can't read the dashboard launcher's " .. name .. ": " .. tostring(err))
    end
    local text = f:read("a")
    f:close()
    return text
end

-- Built once at start, so a missing or unreadable file is an error then,
-- not on the first press of a key.
local function build()
    local sources = {}
    for _, name in ipairs(launcherpage.MODULES) do
        sources[name] = read(name)
    end
    return dashboard.page(read("launcherpage.html"), read("launcher.css"), sources, launcherpage.MODULES)
end

-- `tilemo` is the started tilemo module: its wm and adapter. The same
-- interface as launcher_hs.new's: show(tab), toggle(), is_open(), scope(),
-- set_scope(), row(), cancel().
function M.new(tilemo)
    local self = { tilemo = tilemo, recency = saved.get(hs.settings, launcher_hs.RECENCY_KEY, launcher_hs.OLD_RECENCY_KEY) or {} }
    local page = build()
    local view, before, uuid, scope
    -- The page has started, so tilemo.open can fill it; it's showing; and
    -- what to do once it has started, when a key came first.
    local loaded, visible, pending = false, false, nil
    local by_id, collect, found_tabs = {}, nil, {}

    local function log_js(what)
        return function(_, err)
            if dashboard.js_failed(err) then
                tilemo.adapter.log("dashboard launcher: " .. what .. ": " .. hs.inspect(err))
            end
        end
    end

    -- Hidden, not deleted: the next open shows it again.
    local function close(refocus)
        if not visible then
            return
        end
        visible = false
        pending = nil
        self.opened = nil
        tilemo.wm:hold("launcher", false)
        if view then
            view:hide()
        end
        if refocus and before then
            tilemo.wm:focus_window(before)
        end
    end

    -- The page's feed: the rows found so far, with what's around them.
    local function feed()
        local items = collect(found_tabs)
        by_id = {}
        for _, item in ipairs(items) do
            by_id[item.id] = item
        end
        return hs.json.encode(launcherpage.feed(items, {
            recency = self.recency,
            view = launcherpage.view(tilemo.wm, uuid),
            keep_awake = hs.caffeinate.get("displayIdle") and true or false,
            clock_files = tilemo.clock_files,
            good_clocks = tilemo.good_clocks,
        }))
    end

    local function push(call)
        if view and loaded then
            view:evaluateJavaScript(call, log_js(call:match("^[%w.]+")))
        end
    end

    local function handle(body)
        local m = launcherpage.message(body)
        if m.kind == "row" then
            local item = by_id[m.value]
            -- Out of the page before the row runs: it may focus a window.
            close(false)
            if item then
                launcher_hs.run(tilemo, self.recency, item, false)
            else
                tilemo.adapter.log("dashboard launcher: no row " .. m.value)
            end
        elseif m.kind == "workspace" then
            local name = m.value
            if names.unsafe(wm_mod.clean_name(name) or "") then
                tilemo.adapter.notify(names.UNSAFE_MESSAGE)
                return
            end
            local n = tilemo.wm:canonical(name)
            if n and not tilemo.wm:shown(n) then
                local on = uuid
                close(false)
                -- Made if it's new, as the name prompt makes one.
                tilemo.wm:show(n, on, true)
            else
                close(true)
            end
        elseif m.kind == "settings" then
            close(false)
            tilemo.wm:act("settings", m.value)
        elseif m.kind == "keep_awake" then
            -- The bar's cup: the page stays open, and shows it.
            tilemo.presenter.toggle_keep_awake()
            if visible then
                push("tilemo.update(" .. feed() .. ")")
            end
        elseif m.kind == "browser" then
            close(false)
            local b = launcherpage.browser_key()
            if b then
                tilemo.wm:act("app", b.spec)
            end
        elseif m.kind == "reload" then
            hs.reload()
        elseif m.kind == "close" then
            close(true)
        elseif m.kind == "clock_errors" then
            tilemo.report_clock_errors(m.value)
        elseif m.kind == "good_clocks" then
            tilemo.keep_good_clocks(m.value)
        else
            tilemo.adapter.log("dashboard launcher: a message it doesn't know: " .. tostring(m.value))
        end
    end

    local content = hs.webview.usercontent.new("tilemo")
    content:setCallback(function(msg)
        local body = msg.body or {}
        -- Out of the page's own callback before deleting the page.
        tilemo.adapter.after(0, function()
            handle(body)
        end)
    end)

    -- The webview, made hidden, over `frame`, with the page loading in it.
    local function make(frame)
        loaded = false
        view = hs.webview.new(frame, { developerExtrasEnabled = false }, content)
        view:windowStyle({ "borderless" })
        -- A title for the rules to see: tilemo leaves its own windows alone.
        view:windowTitle(brand.title("launcher"))
        view:level(hs.drawing.windowLevels.modalPanel)
        -- On the Space you're on, and over a full-screen app *(unverified on
        -- a Mac; TODO.md)*.
        local ok, err = pcall(view.behaviorAsLabels, view, { "moveToActiveSpace", "fullScreenAuxiliary" })
        if not ok then
            tilemo.adapter.log("dashboard launcher: its Spaces behavior: " .. tostring(err))
        end
        view:allowTextEntry(true)
        local mine = view
        view:navigationCallback(function(action, _, _, failure)
            if view ~= mine then
                return
            end
            if action == "didFinishNavigation" then
                loaded = true
                local go = pending
                pending = nil
                if go then
                    go()
                end
            elseif action == "didFailNavigation" or action == "didFailProvisionalNavigation" then
                -- Closed if a key opened it meanwhile, and made again at the
                -- next key.
                tilemo.adapter.log("dashboard launcher: the page didn't load: " .. hs.inspect(failure))
                close(false)
                view = nil
                loaded = false
                mine:delete()
            end
        end)
        view:windowCallback(function(action, _, focused)
            if view ~= mine then
                return
            end
            -- Clicking away closes it, as the page itself does on blur.
            if action == "focusChange" and focused == false then
                close(false)
            elseif action == "closing" then
                -- Closed from outside: made again at the next open.
                view = nil
                loaded = false
                close(false)
            end
        end)
        view:html(page)
    end

    -- Open on tab `tab` (Launch if none), as the switcher does. A switcher
    -- key pressed while it's open closes it if it's on that key's scope,
    -- and otherwise moves there (SPEC.md §9).
    function self.show(tab)
        local want = launcherpage.page_scope(tab)
        if visible then
            scope = want
            push(string.format("tilemo.press(%q)", want))
            return
        end
        before = tilemo.adapter.focused()
        uuid = tilemo.wm:current_screen()
        local s = tilemo.wm:screen_by_uuid(uuid)
        if not s then
            tilemo.adapter.log("dashboard launcher: no display to show it on")
            return
        end
        scope = want
        collect = launcher_hs.collector(tilemo)
        found_tabs = {}
        if view then
            view:frame(s.full)
        else
            make(s.full)
        end
        -- Filled now if the page has started, else as soon as it has.
        local function fill()
            push(string.format("tilemo.open(%s, %q)", feed(), scope))
        end
        if loaded then
            fill()
        else
            pending = fill
        end
        -- Browser tabs join the windows as each browser answers.
        local opened = {}
        self.opened = opened
        launcher_hs.fetch_tabs(tilemo, function(list)
            if self.opened ~= opened then
                return
            end
            for _, t in ipairs(list) do
                found_tabs[#found_tabs + 1] = t
            end
            tilemo.wm:note_tabs(list)
            push("tilemo.update(" .. feed() .. ")")
        end)
        visible = true
        view:show()
        tilemo.wm:hold("launcher", true)
        local w = view:hswindow()
        if w then
            w:focus()
        end
    end

    -- The bar's logo: closes it, or opens it on Launch.
    function self.toggle()
        if visible then
            close(true)
        else
            self.show("launch")
        end
    end

    function self.is_open()
        return visible
    end

    -- The scope it was last asked for; Tab on the page moves without
    -- saying.
    function self.scope()
        return scope
    end

    function self.set_scope(s)
        if visible then
            scope = launcherpage.page_scope(s)
            push(string.format("tilemo.turn(%q)", scope))
        end
    end

    -- The page's rows aren't Lua's to read: CI's smoke test reads the
    -- chooser's.
    function self.row()
        return nil
    end

    function self.cancel()
        close(true)
    end

    -- Done with, as the settings window switches launchers: the page goes.
    function self.delete()
        close(false)
        if view then
            local v = view
            view = nil
            loaded = false
            v:delete()
        end
    end

    -- Whether the page has started, and what it answers to `js`, for CI's
    -- smoke test: done(result, err) runs after anything pushed before it.
    function self.ready()
        return loaded
    end
    function self.evaluate(js, done)
        if not (view and loaded) then
            done(nil, "the page hasn't started")
            return
        end
        view:evaluateJavaScript(js, done)
    end

    -- Made and loaded now, hidden, so the first key finds it ready.
    local s = tilemo.wm:screen_by_uuid(tilemo.wm:current_screen())
    make(s and s.full or hs.screen.mainScreen():fullFrame())

    return self
end

return M
