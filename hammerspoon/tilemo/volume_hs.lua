-- The volume popover on Hammerspoon: volume.lua's page in a borderless
-- hs.webview under the bar's speaker (SPEC.md §8). A second click on the
-- speaker, Esc, or clicking anywhere else closes it. Not runnable outside
-- Hammerspoon.

local brand = require("tilemo.brand")
local dashboard = require("tilemo.dashboard")
local volume = require("tilemo.volume")

local M = {}

local DIR = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") .. "/dashboard/"

local function read(name)
    local f, err = io.open(DIR .. name)
    if not f then
        error("tide: can't read the volume popover's " .. name .. ": " .. tostring(err))
    end
    local text = f:read("a")
    f:close()
    return text
end

-- The page: volume.html with tileco's colors and its script in place.
function M.page()
    local html = read("volume.html"):gsub("/%*TILEMO_CSS%*/", function()
        return read("launcher.css")
    end)
    return (html:gsub("/%*TILEMO_SCRIPT%*/", function()
        return read("volume.js")
    end))
end

-- `tilemo` is the started tilemo module. `ops` is bar_hs.lua's: state() for
-- volume.state's table, and set_volume(v), set_mute(on), use(uid) and
-- settings() as volume.handle takes them.
function M.new(tilemo, ops)
    local self = {}
    local log = tilemo.adapter.log
    local page = M.page()
    local view, before

    local function close(refocus)
        if not view then
            return
        end
        local v = view
        view = nil
        tilemo.wm:hold("volume", false)
        tilemo.wm:own_window("volume", nil)
        v:delete()
        if refocus and before then
            tilemo.wm:focus_window(before)
        end
    end

    local function push()
        if not view then
            return
        end
        local json = hs.json.encode(ops.state())
        view:evaluateJavaScript("tilemo.update(" .. json .. ")", function(_, err)
            if dashboard.js_failed(err) then
                log("volume: " .. hs.inspect(err))
            end
        end)
    end

    local act = {
        set_volume = ops.set_volume,
        set_mute = ops.set_mute,
        use = ops.use,
        settings = function()
            close(true)
            ops.settings()
        end,
        close = function()
            close(true)
        end,
    }

    local content = hs.webview.usercontent.new("tilemo")
    content:setCallback(function(msg)
        local body = msg.body or {}
        if body.error then
            log("volume: page error: " .. tostring(body.error))
            return
        end
        -- Out of the page's own callback before changing what's on screen.
        tilemo.adapter.after(0, function()
            local ok, err = pcall(volume.handle, body, act)
            if not ok then
                log("volume: " .. hs.inspect(body) .. " failed: " .. tostring(err))
            end
            push()
        end)
    end)

    -- Under bar `frame` (a display's bar, in screen px), its right edge at
    -- the speaker's `right`; closes it instead if it's open.
    function self.toggle(frame, right)
        if view then
            close(true)
            return
        end
        local state = ops.state()
        before = tilemo.adapter.focused()
        local box = volume.frame(frame, right, #state.outputs)
        view = hs.webview.new(box, { developerExtrasEnabled = false }, content)
        view:windowStyle({ "borderless" })
        view:transparent(true)
        -- A title for the rules to see: tilemo leaves its own windows alone.
        view:windowTitle(brand.title("volume"))
        view:level(hs.drawing.windowLevels.popUpMenu)
        -- Without it the window never becomes key: Esc wouldn't reach the
        -- page, and no click elsewhere would close it, as the dashboard's.
        view:allowTextEntry(true)
        view:behavior(hs.drawing.windowBehaviors.canJoinAllSpaces + hs.drawing.windowBehaviors.transient)
        view:navigationCallback(function(action)
            if action == "didFinishNavigation" then
                push()
            end
        end)
        view:windowCallback(function(action, _, focused)
            -- Clicking away closes it, as the dashboard does.
            if action == "focusChange" and focused == false then
                close(false)
            elseif action == "closing" then
                view = nil
                tilemo.wm:hold("volume", false)
                tilemo.wm:own_window("volume", nil)
            end
        end)
        view:html(page)
        view:show()
        -- Focus follows mouse leaves it be (wm.own_window).
        tilemo.wm:own_window("volume", box)
        -- Focus follows mouse waits while it's open, so moving the pointer
        -- off it doesn't focus a window under it and close it.
        tilemo.wm:hold("volume", true)
        local w = view:hswindow()
        if w then
            w:focus()
        end
    end

    -- The output, its volume or the outputs changed: an open popover shows
    -- it now.
    function self.refresh()
        push()
    end

    function self.shown()
        return view ~= nil
    end

    return self
end

return M
