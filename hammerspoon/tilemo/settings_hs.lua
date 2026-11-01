-- tilemo's settings window on Hammerspoon (SPEC.md §15): a section for each
-- of tide's pages, dashboard.lua's settings page in an hs.webview. It writes
-- tide's clocks.local.json, layouts.local.json, startup.local.json and
-- clipboard.local.json, and tilemo hands the files back once they change on
-- disk, so the page shows what the bar and the next login do. What tilemo
-- can't change itself, a section's buttons open (links.lua). Not runnable
-- outside Hammerspoon.

local brand = require("tilemo.brand")
local dashboard = require("tilemo.dashboard")
local layout = require("tilemo.layout")
local mute = require("tilemo.mute")
local picker = require("tilemo.picker")
local floating = require("tilemo.floating")
local links = require("tilemo.links")
local linearmouse = require("tilemo.linearmouse")

local M = {}

-- `list` as a JSON array, each item by `encode`, so an empty one is [].
function M.list(list, encode)
    local out = {}
    for i, v in ipairs(list or {}) do
        out[i] = encode(v)
    end
    return "[" .. table.concat(out, ",") .. "]"
end

-- A Floating fill-in (floating.prefill) as JSON, its `about` rows a list.
function M.encode_fill(fill)
    local about = fill.about
    local copy = {}
    for k, v in pairs(fill) do
        copy[k] = v
    end
    copy.about = "__about__"
    return (hs.json.encode(copy):gsub('"__about__"', function()
        return M.list(about, hs.json.encode)
    end))
end

local DIR = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") .. "/dashboard/"

local function read(name)
    local f, err = io.open(DIR .. name)
    if not f then
        error("tide: can't read the settings page's " .. name .. ": " .. tostring(err))
    end
    local text = f:read("a")
    f:close()
    return text
end

-- Built once at start, so a missing or unreadable file is an error then.
local function build()
    local sources = {}
    for _, name in ipairs(dashboard.SETTINGS_MODULES) do
        sources[name] = read(name)
    end
    return dashboard.page(read("settings.html"), read("launcher.css"), sources, dashboard.SETTINGS_MODULES)
end

-- One of the Floating section's messages, { floatAdd = { app, title } },
-- { floatMove = { index, app, title, step } } or { floatRemove = { index,
-- app, title } }, through `floats` (floating_hs.new). Returns true, or nil
-- and why.
function M.float_edit(floats, body)
    if not floats then
        return nil, "the float rules aren't loaded"
    end
    local str = function(v)
        return type(v) == "string" and v or ""
    end
    local int = function(v)
        return math.tointeger(v) or 0
    end
    if body.floatAdd then
        local m = body.floatAdd
        return floats.edit(function(list)
            return floating.with(list, str(m.app), str(m.title))
        end)
    elseif body.floatMove then
        local m = body.floatMove
        return floats.edit(function(list)
            return floating.moved(list, int(m.index), str(m.app), str(m.title), int(m.step) < 0 and -1 or 1)
        end)
    end
    local m = body.floatRemove
    return floats.edit(function(list)
        return floating.without(list, int(m.index), str(m.app), str(m.title))
    end)
end

-- `tilemo` is the started tilemo module: its wm, adapter, clock_dir,
-- clock_files, layout_files, startup_files, clipboard_files and picker.
function M.new(tilemo)
    local self = {}
    local page = build()
    local view
    -- The section to show once the page has loaded, or nil.
    local wanted

    local function push()
        if not view then
            return
        end
        -- An empty list must reach the page as one, not as an object.
        local json = hs.json.encode({
            clockFiles = tilemo.clock_files,
            startupFiles = tilemo.startup_files,
            layoutFiles = tilemo.layout_files,
            -- What the files lay over: start()'s layout, or tide's
            -- defaults, so the page shows and steps what's in effect.
            layoutBase = tilemo.layout_base and layout.file_form(tilemo.layout_base) or nil,
            clipboardFiles = tilemo.clipboard_files,
            clipboardCount = tilemo.picker and #tilemo.picker.history.items or 0,
            -- The settings in effect, which a file gone wrong since leaves
            -- as they were: the page shows these, not the defaults, then.
            clipboardSettings = tilemo.clipboard_settings and {
                history = tilemo.clipboard_settings.history,
                maxItems = tilemo.clipboard_settings.max_items,
            } or nil,
            muted = "__muted__",
            -- Each section's buttons, and what's wrong with LinearMouse, if
            -- anything, for the Mouse section.
            links = links.page_list(),
            mouse = { problem = linearmouse.say(tilemo.linearmouse, "section") or "" },
            floating = tilemo.floating and {
                rules = "__float_rules__",
                source = tilemo.floating.source,
                error = tilemo.floating.error,
                now = "__float_now__",
            } or nil,
        })
        json = json:gsub('"__muted__"', function()
            return mute.encode_list(tilemo.wm.muted.list)
        end)
        -- Lists that may be empty, which must reach the page as lists.
        json = json:gsub('"__float_rules__"', function()
            return M.list(tilemo.floating.rules, function(r)
                return hs.json.encode({ app = r.app, title = r.title or "" })
            end)
        end)
        json = json:gsub('"__float_now__"', function()
            return M.list(tilemo.wm:floating_now(), M.encode_fill)
        end)
        view:evaluateJavaScript("tilemo.update(" .. json .. ")", function(_, err)
            if err and next(err) then
                tilemo.adapter.log("settings: " .. hs.inspect(err))
            end
        end)
    end

    -- Scroll to section `id`, as settings.html names them: "clocks",
    -- "layouts", "startup", "clipboard", "muted", "floating", and the rest.
    local function reveal(id)
        if not (view and id) then
            return
        end
        view:evaluateJavaScript("tilemo.reveal(" .. hs.json.encode({ id }):sub(2, -2) .. ")", function(_, err)
            if err and next(err) then
                tilemo.adapter.log("settings: " .. hs.inspect(err))
            end
        end)
    end

    -- A write from the page: `text` to `name` in tide's folder, said in a
    -- notice naming `what` if it fails.
    local function save(name, text, what)
        local path = tilemo.clock_dir .. "/" .. name
        local ok, err = tilemo.adapter.write_file(path, text)
        if not ok then
            tilemo.adapter.notify("Couldn't save " .. what .. " to " .. path .. ": " .. tostring(err))
            -- The page showed the change already: back to the files.
            push()
        end
        -- The folder's watcher reloads the files, and then this page.
    end

    local content = hs.webview.usercontent.new("tilemo")
    content:setCallback(function(msg)
        local body = msg.body or {}
        tilemo.adapter.after(0, function()
            if type(body.write) == "string" then
                save(dashboard.LOCAL_FILE, body.write, "the clocks")
            elseif type(body.writeLayouts) == "string" then
                save(dashboard.LAYOUTS_LOCAL_FILE, body.writeLayouts, "the layouts")
            elseif type(body.writeStartup) == "string" then
                save(dashboard.STARTUP_LOCAL_FILE, body.writeStartup, "Start at login's commands")
            elseif type(body.writeClipboard) == "string" then
                save(dashboard.CLIPBOARD_LOCAL_FILE, body.writeClipboard, "the clipboard settings")
            elseif body.clearClipboard and tilemo.picker then
                picker.clear(tilemo.picker.history)
                push()
            elseif type(body.mute) == "string" then
                -- Typed at the Muted list's foot: as Cmd+M on a row, once
                -- the mute module takes it.
                local why = mute.add_problem(tilemo.wm.muted, body.mute)
                if why and view then
                    view:evaluateJavaScript("tilemo.mutedError(" .. hs.json.encode({ why, body.mute }):sub(2, -2) .. ")")
                elseif not why and tilemo.toggle_mute(body.mute) == nil then
                    push()
                end
            elseif type(body.unmute) == "string" then
                -- The same as Cmd+M on a muted row; it refreshes this page.
                if not mute.has(tilemo.wm.muted, body.unmute) or tilemo.toggle_mute(body.unmute) == nil then
                    push()
                end
            elseif type(body.floatAdd) == "table" or type(body.floatMove) == "table"
                or type(body.floatRemove) == "table" then
                -- The Floating section's edits, which tilemo makes, since the
                -- page can't check a Lua pattern (floating.lua).
                local ok, why = M.float_edit(tilemo.floating, body)
                if view then
                    if ok then
                        view:evaluateJavaScript("tilemo.floatingDone(" .. (body.floatAdd and "true" or "false") .. ")")
                    else
                        view:evaluateJavaScript("tilemo.floatingError(" .. hs.json.encode({ tostring(why) }):sub(2, -2) .. ")")
                    end
                end
            elseif type(body.open) == "string" then
                -- A section's button: what its name stands for, and nothing
                -- the page can name otherwise.
                if not links.open(body.open, tilemo.adapter) then
                    tilemo.adapter.log("settings: no button named " .. body.open)
                end
            elseif body.close and view then
                view:delete()
                view = nil
            end
        end)
    end)

    -- The files changed: show them as they are now.
    self.refresh = push

    -- The clipboard history changed: its count, alone, so a copy made while
    -- you're editing another section doesn't redraw it.
    function self.clipboard_changed()
        if not (view and tilemo.picker) then
            return
        end
        view:evaluateJavaScript("tilemo.count(" .. math.tointeger(#tilemo.picker.history.items) .. ")", function(_, err)
            if err and next(err) then
                tilemo.adapter.log("settings: " .. hs.inspect(err))
            end
        end)
    end

    -- Fill in the Floating section's fields (floating.prefill).
    local function fill_in(fill)
        if not (view and fill) then
            return
        end
        view:evaluateJavaScript("tilemo.floatingFill(" .. M.encode_fill(fill) .. ")", function(_, err)
            if err and next(err) then
                tilemo.adapter.log("settings: " .. hs.inspect(err))
            end
        end)
    end
    local wanted_fill

    -- Open the window, or bring it forward, showing `section` if given,
    -- with the Floating section filled in by `fill` if given.
    function self.show(section, fill)
        if view then
            local w = view:hswindow()
            if w then
                w:focus()
            end
            -- Floating now may have changed since it drew.
            push()
            reveal(section)
            fill_in(fill)
            return
        end
        wanted = section
        wanted_fill = fill
        local s = tilemo.wm:screen_by_uuid(tilemo.wm:current_screen())
        if not s then
            tilemo.adapter.log("settings: no display to show it on")
            return
        end
        local w, h = 560, 560
        local frame = { x = s.area.x + (s.area.w - w) / 2, y = s.area.y + (s.area.h - h) / 2, w = w, h = h }
        view = hs.webview.new(frame, { developerExtrasEnabled = false }, content)
        view:windowStyle({ "titled", "closable" })
        -- tilemo leaves it untiled, so a floating level keeps it over the
        -- tiles, as a float is (SPEC.md §5.1).
        view:level(hs.drawing.windowLevels.floating)
        -- tilemo leaves its own windows alone, by this title.
        view:windowTitle(brand.title("settings"))
        view:allowTextEntry(true)
        view:navigationCallback(function(action)
            if action == "didFinishNavigation" then
                push()
                reveal(wanted)
                fill_in(wanted_fill)
                wanted, wanted_fill = nil, nil
            end
        end)
        view:windowCallback(function(action)
            if action == "closing" then
                view = nil
            end
        end)
        view:html(page)
        view:show()
        local hw = view:hswindow()
        if hw then
            hw:focus()
        end
    end

    return self
end

return M
