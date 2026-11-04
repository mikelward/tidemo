-- The bar on Hammerspoon: bar.lua's state in a borderless hs.webview along
-- the top of each display (SPEC.md §8), kept open and updated rather than
-- rebuilt. The page is built like the dashboard's, from the same copies of
-- tileco's modules. Not runnable outside Hammerspoon.

local bar = require("tilemo.bar")
local bluetooth = require("tilemo.bluetooth")
local ddc = require("tilemo.ddc")
local tray_hs = require("tilemo.tray_hs")
local dashboard = require("tilemo.dashboard")
local brand = require("tilemo.brand")
local volume = require("tilemo.volume")
local volume_hs = require("tilemo.volume_hs")

local M = {}

-- How often to read the status items that have no watcher, in seconds.
M.POLL = 5
-- How often blueutil is asked whether Bluetooth is on, besides at start and
-- on wake: a process each time, so less often than the rest.
M.BLUETOOTH_POLL = 30

local DIR = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") .. "/dashboard/"

local function read(name)
    local f, err = io.open(DIR .. name)
    if not f then
        error("tide: can't read the bar's " .. name .. ": " .. tostring(err))
    end
    local text = f:read("a")
    f:close()
    return text
end

-- Built once at start, so a missing file is an error then.
local function build()
    local sources = {}
    for _, name in ipairs(dashboard.BAR_MODULES) do
        sources[name] = read(name)
    end
    return dashboard.page(read("bar.html"), read("launcher.css"), sources, dashboard.BAR_MODULES)
end

local function same(a, b)
    return a.x == b.x and a.y == b.y and a.w == b.w and a.h == b.h
end

-- Mute or unmute the default microphone, with a sign. Super+Shift+M calls
-- this too, with the bar on or off. Returns whether it changed.
function M.toggle_mic(log)
    local dev = hs.audiodevice.defaultInputDevice()
    if not dev then
        hs.alert.show("No microphone")
        return false
    end
    local muted = dev:inputMuted()
    -- Some devices have no mute control of their own.
    if muted == nil then
        hs.alert.show("This microphone can't be muted")
        log("bar: " .. tostring(dev:name()) .. " has no input mute")
        return false
    end
    if not dev:setInputMuted(not muted) then
        hs.alert.show("Couldn't " .. (muted and "unmute" or "mute") .. " the microphone")
        log("bar: setInputMuted failed on " .. tostring(dev:name()))
        return false
    end
    hs.alert.show(muted and "Microphone on" or "Microphone muted")
    return true
end

-- `tilemo` is the started tilemo module: its wm, adapter and dashboard.
-- The interfaces macOS's network services are up on, each { interface,
-- type, subtype }, by interface, for telling a VPN (bar.lua's
-- is_vpn_service). `holder` keeps the configuration store open between
-- readings. The settings window's Network page reads them too.
function M.services(holder)
    local store = holder.net_store
    if not store then
        store = hs.network.configuration.open()
        holder.net_store = store
    end
    local up = {}
    for key, v in pairs(store:contents("State:/Network/Service/[^/]+/IPv[46]", true) or {}) do
        local id = key:match("^State:/Network/Service/([^/]+)/")
        if id and type(v) == "table" and type(v.InterfaceName) == "string" then
            up[id] = v.InterfaceName
        end
    end
    local out = {}
    for id, interface in pairs(up) do
        local key = "Setup:/Network/Service/" .. id .. "/Interface"
        local setup = store:contents(key)
        setup = setup and setup[key] or {}
        out[#out + 1] = { interface = interface, type = setup.Type, subtype = setup.SubType }
    end
    table.sort(out, function(a, b)
        return a.interface < b.interface
    end)
    return out
end

function M.new(tilemo)
    -- `errors` keeps what the pages reported going wrong, for the log and
    -- the smoke test.
    local self = { views = {}, icons = {}, errors = {} }
    local page = build()
    local log = tilemo.adapter.log
    -- The last error from each source, so a lasting one is logged once.
    local failed = {}

    local function try(what, fn)
        local ok, v = pcall(fn)
        if ok then
            failed[what] = nil
            return v
        end
        if failed[what] ~= tostring(v) then
            failed[what] = tostring(v)
            log("bar: couldn't read " .. what .. ": " .. tostring(v))
        end
    end

    -- The network services that are up, from the System Configuration
    -- store, for the VPN lock (bar.lua): each with the interface it has an
    -- address on and the type and subtype of its Setup: interface, so a
    -- VPN's service counts even when it carries only some traffic, and a
    -- tunnel with no VPN service doesn't.
    local function services()
        return M.services(self)
    end

    local function read_icons()
        local raw = {}
        raw.bluetooth = self.bluetooth and self.bluetooth.state
        raw.battery = try("the battery", function()
            local p = hs.battery.percentage()
            return p and {
                percent = p,
                charging = hs.battery.isCharging(),
                charged = hs.battery.isCharged(),
                remaining = hs.battery.timeRemaining(),
                to_full = hs.battery.timeToFullCharge(),
            }
        end)
        raw.audio = try("the volume", function()
            local dev = hs.audiodevice.defaultOutputDevice()
            if not dev then
                return nil
            end
            -- outputVolume() is nil on an output with no volume control, and
            -- outputMuted() on one that can't mute; bar.lua shows it anyway.
            -- A monitor's speakers answer over DDC instead (ddc.lua).
            local a = { volume = dev:outputVolume(), muted = dev:outputMuted(), name = dev:name() }
            return ddc.merge(a, self.ddc and self.ddc.state)
        end)
        -- Bluetooth audio devices, outputs then inputs, by name; bar.lua
        -- lists each once.
        raw.bluetooth_audio = try("the Bluetooth audio devices", function()
            local out = {}
            for _, list in ipairs({ hs.audiodevice.allOutputDevices(), hs.audiodevice.allInputDevices() }) do
                for _, dev in ipairs(list or {}) do
                    if dev:transportType() == "Bluetooth" then
                        out[#out + 1] = dev:name()
                    end
                end
            end
            return out
        end)
        -- No "in use": Hammerspoon's inUse() asks whether the device is
        -- running at all, so a headset playing sound would light it.
        raw.mic = try("the microphone", function()
            local dev = hs.audiodevice.defaultInputDevice()
            return dev and { muted = dev:inputMuted() }
        end)
        raw.camera = try("the cameras", function()
            local cams = hs.camera.allCameras()
            if #cams == 0 then
                return nil
            end
            for _, c in ipairs(cams) do
                if c:isInUse() then
                    return { in_use = true }
                end
            end
            return { in_use = false }
        end)
        raw.source = try("the input source", function()
            local list = {}
            for _, name in ipairs(hs.keycodes.layouts()) do
                list[#list + 1] = { name = name, method = false }
            end
            for _, name in ipairs(hs.keycodes.methods()) do
                list[#list + 1] = { name = name, method = true }
            end
            return { current = hs.keycodes.currentMethod() or hs.keycodes.currentLayout(), list = list }
        end)
        raw.awake = try("keep awake", function()
            return hs.caffeinate.get("displayIdle")
        end)
        raw.presenting = tilemo.presenter and tilemo.presenter.presenting() or false
        -- The network name needs Location Services on recent macOS; without
        -- it ssid is nil and the icon shows without a name.
        raw.wifi = try("Wi-Fi", function()
            local d = hs.wifi.interfaceDetails()
            return d and { power = d.power, rssi = d.rssi, ssid = d.ssid, interface = d.interface }
        end)
        -- The CPU's share busy since the last reading, so the first has
        -- none; memory; and macOS's thermal state (bar.lua).
        raw.sysmon = try("the system monitor", function()
            local ticks = hs.host.cpuUsageTicks()
            local now = ticks and ticks.overall
            local share = bar.cpu_share(self.cpu_ticks, now)
            self.cpu_ticks = now
            return { cpu = share, memory = bar.memory(hs.host.vmStat()), thermal = hs.host.thermalState() }
        end)
        raw.network = try("the network", function()
            -- false with no route, as Hammerspoon reports it.
            local v4, v6 = hs.network.primaryInterfaces()
            return { primary = v4 or v6 or nil, services = services() }
        end)
        self.sources = raw.source and raw.source.list or {}
        self.current_source = raw.source and raw.source.current
        self.icons = bar.icons(raw, function(name, err)
            if failed["item " .. name] ~= tostring(err) then
                failed["item " .. name] = tostring(err)
                log("bar: couldn't draw " .. name .. ": " .. tostring(err))
            end
        end)
    end

    local open_url = tilemo.adapter.open_url

    function self.refresh()
        read_icons()
        self.update()
        if self.volume_popover then
            self.volume_popover.refresh()
        end
        -- The settings window's Sound page, if it's open, follows too.
        if tilemo.settings and tilemo.settings.sound_changed then
            tilemo.settings.sound_changed()
        end
        -- And the Network and Power pages.
        if tilemo.settings and tilemo.settings.netpower_changed then
            tilemo.settings.netpower_changed()
        end
    end

    -- A watcher can fire many times in a burst (a volume slider, a device
    -- appearing), so they share one refresh shortly after.
    local pending
    local function refresh_soon()
        if pending then
            return
        end
        pending = tilemo.adapter.after(0.1, function()
            pending = nil
            self.refresh()
        end)
    end

    -- The DDC reading for output `dev`, when macOS has no volume for it.
    local function ddc_state(dev)
        local d = self.ddc and self.ddc.state
        if dev and ddc.applies({ volume = dev:outputVolume(), name = dev:name() }, d) then
            return d
        end
    end

    local function toggle(what)
        if what == "mic" then
            M.toggle_mic(log)
        elseif what == "volume" then
            local dev = hs.audiodevice.defaultOutputDevice()
            local d = ddc_state(dev)
            -- The monitor's mute only when it says whether it's muted;
            -- else the output's own, which the bar shows then (ddc.merge).
            if d and d.muted ~= nil then
                self.ddc:set_mute(not d.muted)
            elseif dev and not dev:setOutputMuted(not dev:outputMuted()) then
                log("bar: setOutputMuted failed on " .. tostring(dev:name()))
            end
        elseif what == "awake" then
            tilemo.presenter.toggle_keep_awake()
        elseif what == "presenter" then
            tilemo.presenter.toggle_presenter()
        elseif what == "source" then
            local nxt = bar.next_source(self.sources or {}, self.current_source)
            if nxt then
                local ok
                if nxt.method then
                    ok = hs.keycodes.setMethod(nxt.name)
                else
                    ok = hs.keycodes.setLayout(nxt.name)
                end
                if not ok then
                    log("bar: couldn't switch to " .. nxt.name)
                end
            end
        end
        self.refresh()
    end

    local function step_volume(d)
        local dev = hs.audiodevice.defaultOutputDevice()
        local m = ddc_state(dev)
        if m then
            local own = m.muted == nil
            local muted = m.muted
            if own then
                muted = dev:outputMuted()
            end
            local v, unmute = bar.volume_step(m.volume, muted, d)
            self.ddc:set_volume(v)
            if unmute and not own then
                self.ddc:set_mute(false)
            elseif unmute and not dev:setOutputMuted(false) then
                log("bar: setOutputMuted failed on " .. tostring(dev:name()))
            end
            self.refresh()
            return
        end
        -- No volume control: nothing to step.
        if not dev or dev:outputVolume() == nil then
            return
        end
        local v, unmute = bar.volume_step(dev:outputVolume(), dev:outputMuted(), d)
        if not dev:setOutputVolume(v) then
            log("bar: setOutputVolume failed on " .. tostring(dev:name()))
        end
        if unmute and not dev:setOutputMuted(false) then
            log("bar: setOutputMuted failed on " .. tostring(dev:name()))
        end
        self.refresh()
    end

    -- The volume popover (volume.lua): the output in use, read as the bar
    -- reads it, the outputs to pick from, and what its controls change.
    -- The settings window's Sound page (sound_hs.lua) uses them too.
    local function output_reading()
        local dev = hs.audiodevice.defaultOutputDevice()
        local m = ddc_state(dev)
        local audio = dev and ddc.merge({ volume = dev:outputVolume(), muted = dev:outputMuted(), name = dev:name() }, m)
        local outputs = {}
        for _, o in ipairs(hs.audiodevice.allOutputDevices() or {}) do
            outputs[#outputs + 1] = { uid = o:uid(), name = o:name() }
        end
        return { audio = audio, devices = outputs, current = dev and dev:uid(), over_ddc = m ~= nil }
    end
    local function popover_state()
        local r = output_reading()
        return volume.state(r.audio, r.devices, r.current, r.over_ddc)
    end
    local popover_ops = {
        state = popover_state,
        reading = output_reading,
        set_volume = function(v)
            local dev = hs.audiodevice.defaultOutputDevice()
            if ddc_state(dev) then
                self.ddc:set_volume(v)
            elseif dev and dev:outputVolume() ~= nil and not dev:setOutputVolume(v) then
                log("bar: setOutputVolume failed on " .. tostring(dev:name()))
            end
            self.refresh()
        end,
        set_mute = function(on)
            local dev = hs.audiodevice.defaultOutputDevice()
            local m = ddc_state(dev)
            if m and m.muted ~= nil then
                self.ddc:set_mute(on)
            elseif dev and not dev:setOutputMuted(on) then
                log("bar: setOutputMuted failed on " .. tostring(dev:name()))
            end
            self.refresh()
        end,
        use = function(uid)
            local dev = hs.audiodevice.findDeviceByUID(uid)
            if not dev or not dev:setDefaultOutputDevice() then
                log("bar: couldn't switch the output to " .. tostring(dev and dev:name() or uid))
            end
            self.refresh()
        end,
        settings = function()
            open_url(bar.PANES.volume)
        end,
    }
    self.output_ops = popover_ops

    -- A bar item's tip, or the full title's, below a bar (SPEC.md §8),
    -- drawn as the tray's tips are: the page can't draw past its own strip.
    local TIP_MAX = 600
    -- The tip on screen, if any: its canvas, and the display and bar frame
    -- it was drawn for, so it goes with that bar (drop_orphaned_tip).
    local tip
    local function hide_tip()
        if tip then
            tip.canvas:delete()
            tip = nil
        end
    end
    local function show_tip(uuid, t)
        hide_tip()
        local v = uuid and self.views[uuid]
        local text = type(t.text) == "string" and t.text or ""
        if text == "" or not v or v.hidden then
            return
        end
        local size = hs.drawing.getTextDrawingSize(text, { size = tray_hs.TIP_SIZE })
        local w, h = bar.tip_size(size.w, size.h, TIP_MAX)
        local c = tray_hs.colors()
        local canvas = tray_hs.floating(hs.canvas.new(bar.tip_frame(v.frame, tonumber(t.x) or v.frame.w / 2, w, h)))
        tip = { canvas = canvas, uuid = uuid, frame = { x = v.frame.x, y = v.frame.y, w = v.frame.w, h = v.frame.h } }
        canvas:appendElements({
            type = "rectangle",
            action = "fill",
            fillColor = c.tip,
            roundedRectRadii = { xRadius = 7, yRadius = 7 },
        }, {
            type = "text",
            text = text,
            textSize = tray_hs.TIP_SIZE,
            textColor = c.fg,
            textLineBreak = "wordWrap",
            frame = { x = 9, y = 5, w = w - 18, h = h - 10 },
        })
        canvas:show()
    end

    -- The session menu (bar.lua), macOS's own, under the icon on display
    -- `uuid`'s bar. Log out, restart and shut down ask System Events, which
    -- lets an app with unsaved work stop them, as on any Mac; the adapter
    -- logs and says so when System Events refuses.
    local SESSION_RUN = {
        lock = tilemo.adapter.lock,
        logout = tilemo.adapter.logout,
        sleep = tilemo.adapter.sleep,
        restart = tilemo.adapter.restart,
        shutdown = tilemo.adapter.shutdown,
    }
    local function show_session(uuid, at)
        local v = uuid and self.views[uuid]
        if not v or v.hidden then
            return
        end
        hide_tip()
        self.session_menu = self.session_menu or hs.menubar.new(false)
        if not self.session_menu then
            log("bar: couldn't make the session menu")
            return
        end
        self.session_menu:setMenu(bar.session_menu(function(id)
            local ok, err = pcall(SESSION_RUN[id])
            if not ok then
                log("bar: session " .. id .. " failed: " .. tostring(err))
                tilemo.adapter.notify("Couldn't " .. id .. ": " .. tostring(err))
            end
        end))
        local x = v.frame.x + (tonumber(at.x) or v.frame.w)
        self.session_menu:popupMenu({ x = x, y = v.frame.y + v.frame.h })
    end

    -- The volume popover under the speaker of display `uuid`'s bar, at its
    -- right edge `at.right`, or closed if it's open.
    local function show_sound(uuid, at)
        local v = uuid and self.views[uuid]
        if not v or v.hidden then
            return
        end
        hide_tip()
        if not self.volume_popover then
            local ok, p = pcall(volume_hs.new, tilemo, popover_ops)
            if not ok then
                log("bar: couldn't make the volume popover: " .. tostring(p))
                tilemo.adapter.notify("Couldn't open the volume popover: " .. tostring(p))
                return
            end
            self.volume_popover = p
        end
        self.volume_popover.toggle(v.frame, at.right)
    end

    -- The Apple logo opens the real Apple menu (SPEC.md §8), since the menu
    -- bar is hidden for this bar. Through Accessibility it's a press on the
    -- first item of the frontmost app's menu bar, which macOS shows the menu
    -- bar for. Without it, the pointer goes to the top of that display,
    -- which reveals the menu bar, and a click there opens the menu; a second
    -- logo click inside 2 s is ignored, so a click that lands on the bar
    -- again can't start it over.
    -- The Apple menu, as bar.apple_menu plans it.
    local function open_apple_menu(uuid)
        local now = hs.timer.secondsSinceEpoch()
        local plan, why = bar.apple_menu(tilemo.adapter.screens(), uuid, now, self.apple_at)
        if not plan then
            if why ~= "again" then
                log("bar: can't open the Apple menu: " .. why)
            end
            return
        end
        self.apple_at = now
        log("bar: opening the Apple menu with Control+F2 (Move focus to the menu bar), then Down")
        hs.eventtap.keyStroke(plan.focus.mods, plan.focus.key, 0)
        tilemo.adapter.after(plan.open_after, function()
            hs.eventtap.keyStroke(plan.open.mods, plan.open.key, 0)
        end)
    end

    local function on_message(msg, from)
        local body = msg.body or {}
        if body.error then
            local e = "display " .. tostring(from) .. ": " .. tostring(body.error)
            self.errors[#self.errors + 1] = e
            log("bar: page error on " .. e)
            return
        end
        -- Out of the page's own callback before changing what's on screen.
        tilemo.adapter.after(0, function()
            bar.handle(tilemo.wm, body, {
                open = open_url,
                dashboard = function(uuid)
                    tilemo.dashboard.show(uuid)
                end,
                -- tide's logo: the switcher on Launch, or closed if open.
                switcher = function()
                    tilemo.launcher.toggle()
                end,
                toggle = toggle,
                volume = step_volume,
                clock_errors = tilemo.report_clock_errors,
                good_clocks = tilemo.keep_good_clocks,
                tip = show_tip,
                session = show_session,
                menubar = open_apple_menu,
                -- The "+n" chip over a notch: every workspace, in the switcher.
                workspaces = function()
                    tilemo.launcher.show("workspaces")
                end,
                sound = show_sound,
            })
        end)
    end

    -- Each app's icon as a small PNG data URL, made once per bundle id:
    -- 32 px is the chip's 16 at 2x, a few kilobytes a time. An app with no
    -- icon is cached as false, so it isn't asked again every update.
    self.app_icons = {}
    local function icon_of(bundle)
        local url = self.app_icons[bundle]
        if url == nil then
            url = try("the icon of " .. bundle, function()
                local img = hs.image.imageFromAppBundle(bundle)
                return img and img:setSize({ w = 32, h = 32 }):encodeAsURLString(false, "PNG")
            end) or false
            self.app_icons[bundle] = url
        end
        return url or nil
    end
    self.icon_of = icon_of

    local function run(v, js)
        v.view:evaluateJavaScript(js, function(_, err)
            if dashboard.js_failed(err) then
                log("bar: " .. hs.inspect(err))
            end
        end)
    end

    local function push(v, title)
        if not v.ready then
            return
        end
        local state = bar.state(tilemo.wm, v.uuid, title, self.icons, icon_of)
        state.clockFiles = tilemo.clock_files
        state.goodClocks = tilemo.good_clocks
        local json = hs.json.encode(state)
        if json == v.sent then
            return
        end
        v.sent = json
        run(v, "tilemo.update(" .. json .. ")")
    end

    -- Hover. The bar's window never becomes key, and WebKit follows the
    -- pointer only in the key window, so :hover never fires there; tilemo
    -- tells the page where the pointer is instead, on every move over a
    -- bar, and that it left.
    local hovered
    function self.pointer(x, y)
        local frames = {}
        for uuid, v in pairs(self.views) do
            frames[uuid] = { x = v.frame.x, y = v.frame.y, w = v.frame.w, h = v.frame.h, hidden = v.hidden }
        end
        -- Kept off the top row, so the hidden menu bar doesn't slide over
        -- the bar; the Apple logo opens the Apple menu instead. The
        -- Appearance page's Menu bar switch turns it off.
        local down = tilemo.keep_menu_bar_hidden ~= false and bar.off_top(frames, x, y)
        if down then
            hs.mouse.absolutePosition({ x = x, y = down })
            y = down
        end
        local uuid, px, py = bar.pointer_at(frames, x, y)
        local old = hovered and self.views[hovered]
        if old and hovered ~= uuid and old.ready then
            run(old, "tilemo.pointer(null)")
        end
        hovered = uuid
        local v = uuid and self.views[uuid]
        if v and v.ready then
            run(v, string.format("tilemo.pointer(%d, %d)", math.floor(px), math.floor(py)))
        end
    end

    local function create(uuid, frame)
        local v = { uuid = uuid, frame = frame }
        -- Each view keeps its own handler, and both stay referenced here.
        v.content = hs.webview.usercontent.new("tilemo")
        v.content:setCallback(function(msg)
            on_message(msg, uuid)
        end)
        v.view = hs.webview.new(frame, { developerExtrasEnabled = false }, v.content)
        v.view:windowStyle({ "borderless" })
        -- A title for the rules to see: tilemo leaves its own windows alone.
        v.view:windowTitle(brand.title("bar"))
        -- Above every app's windows; over a notch, at the main menu's level
        -- (bar.level), set by sync_views before it places the window.
        v.view:behavior(hs.drawing.windowBehaviors.canJoinAllSpaces + hs.drawing.windowBehaviors.stationary)
        -- `nav` is how far the page got, for a smoke test that finds it
        -- not ready.
        v.nav = "loading"
        v.view:navigationCallback(function(action, _, _, err)
            v.nav = action
            if action == "didFinishNavigation" then
                v.ready = true
                v.sent = nil
                self.update()
            elseif action == "didFailNavigation" or action == "didFailProvisionalNavigation" then
                local e = "display " .. uuid .. ": " .. action .. ": " .. hs.inspect(err)
                self.errors[#self.errors + 1] = e
                log("bar: " .. e)
            end
        end)
        v.view:html(page)
        v.view:show()
        return v
    end

    -- One strip per display, following displays as they come and go.
    -- A tip whose bar was hidden (a full-screen window, entered from the
    -- keyboard with the pointer still), removed with its display, or moved
    -- goes too. That bar's page, if it's still there, is told the pointer
    -- left, so it asks again once the pointer is back over an item with a tip.
    local function drop_orphaned_tip()
        if not tip or not bar.tip_orphaned(tip.uuid, tip.frame, self.views) then
            return
        end
        local v = self.views[tip.uuid]
        hide_tip()
        if v and v.ready then
            run(v, "tilemo.pointer(null)")
        end
    end

    -- macOS can refuse the bar its strip and move the window down: over a
    -- notch, it keeps the strip for the menu bar *(seen on a MacBook)*. Then
    -- windows tile below where the bar really is, not under it, and the log
    -- says so once per change. One frame read per display per redraw.
    local function check_floor(uuid, v, frame)
        local got = try("the bar's frame", function()
            return v.view:frame()
        end)
        local floor
        if got and got.y + got.h > frame.y + frame.h + 0.5 then
            floor = got.y + got.h
        end
        if floor ~= tilemo.wm.bar_floor[uuid] then
            tilemo.wm.bar_floor[uuid] = floor
            if floor then
                log(string.format("bar: macOS put display %s's bar at y=%g, not y=%g; windows tile below it", uuid, got.y, frame.y))
            end
            tilemo.wm:retile()
        end
    end

    local function sync_views()
        local present = {}
        for _, s in ipairs(tilemo.adapter.screens()) do
            present[s.uuid] = true
            local frame = bar.place(s, bar.HEIGHT)
            local v = self.views[s.uuid]
            local level = bar.level(s)
            if not v then
                v = create(s.uuid, frame)
                self.views[s.uuid] = v
            end
            -- The level first: macOS moves a window below the main menu's
            -- level out of a notch's strip as it's placed.
            if v.level ~= level then
                v.level = level
                v.view:level(hs.drawing.windowLevels[level])
                v.frame = nil
            end
            if not v.frame or not same(v.frame, frame) then
                v.frame = frame
                v.view:frame(frame)
            end
            check_floor(s.uuid, v, frame)
        end
        for uuid, v in pairs(self.views) do
            if not present[uuid] then
                v.view:delete()
                self.views[uuid] = nil
            end
        end
        drop_orphaned_tip()
        -- A display coming or going can renumber ddcctl's, so the monitor
        -- volume is looked for again at once (ddc.lua).
        local uuids = {}
        for uuid in pairs(present) do
            uuids[#uuids + 1] = uuid
        end
        table.sort(uuids)
        local key = table.concat(uuids, ",")
        if key ~= self.displays_key then
            self.displays_key = key
            if self.poll_ddc then
                self.poll_ddc()
            end
        end
    end

    function self.update()
        sync_views()
        local f = tilemo.adapter.focused()
        local title = f and tilemo.wm.windows[f] and tilemo.adapter.title(f) or ""
        for _, v in pairs(self.views) do
            -- Out of a full-screen window's way, and back after.
            local hide = bar.hidden(tilemo.wm, v.uuid)
            if hide ~= (v.hidden or false) then
                v.hidden = hide
                if hide then
                    v.view:hide()
                else
                    v.view:show()
                end
            end
            push(v, title)
        end
        drop_orphaned_tip()
    end

    -- The bar's frames, for the smoke test.
    function self.frames()
        local out = {}
        for uuid, v in pairs(self.views) do
            local f = v.view:frame()
            out[uuid] = { x = f.x, y = f.y, w = f.w, h = f.h, hidden = v.hidden or false }
        end
        return out
    end

    -- Watchers, so a change shows at once rather than on the next poll.
    -- Each is kept here: Hammerspoon stops one that's collected.
    local function watch_devices()
        for _, k in ipairs({ "out_dev", "in_dev" }) do
            local d = self[k]
            if d then
                try("an audio device watcher", function()
                    d:watcherStop()
                end)
            end
        end
        self.out_dev = try("the output device", hs.audiodevice.defaultOutputDevice)
        self.in_dev = try("the input device", hs.audiodevice.defaultInputDevice)
        for _, k in ipairs({ "out_dev", "in_dev" }) do
            local d = self[k]
            if d then
                try("an audio device watcher", function()
                    d:watcherCallback(function()
                        refresh_soon()
                    end):watcherStart()
                end)
            end
        end
    end

    local function watch_cameras()
        for _, c in ipairs(self.cameras or {}) do
            try("a camera watcher", function()
                c:stopPropertyWatcher()
            end)
        end
        self.cameras = try("the cameras", hs.camera.allCameras) or {}
        for _, c in ipairs(self.cameras) do
            try("a camera watcher", function()
                c:setPropertyWatcherCallback(function()
                    refresh_soon()
                end):startPropertyWatcher()
            end)
        end
    end

    try("the audio device watcher", function()
        hs.audiodevice.watcher.setCallback(function()
            watch_devices()
            if self.poll_ddc then
                self.poll_ddc()
            end
            refresh_soon()
        end)
        hs.audiodevice.watcher.start()
    end)
    watch_devices()
    try("the camera watcher", function()
        hs.camera.setWatcherCallback(function()
            watch_cameras()
            refresh_soon()
        end)
        hs.camera.startWatcher()
    end)
    watch_cameras()
    -- Shared with the settings window's Keyboard page (inputsrc.watch).
    if tilemo.on_input_source then
        tilemo.on_input_source(refresh_soon)
    end

    -- Runs a helper without waiting, calling done(code, out, err).
    local function run_task(path, args, done)
        local ok, task = pcall(hs.task.new, path, function(code, out, err)
            done(code, out, err)
        end, args)
        if not ok then
            return false, tostring(task)
        end
        if not task or not task:start() then
            return false, "hs.task couldn't run " .. path
        end
        return true
    end

    -- Bluetooth on or off, from blueutil, run without waiting so it never
    -- holds the bar up (bluetooth.lua). Each answer that changes it redraws.
    self.bluetooth = bluetooth.poller({
        find = function()
            return bluetooth.find(function(p)
                return hs.fs.attributes(p) ~= nil
            end)
        end,
        run = run_task,
        log = log,
        changed = function()
            refresh_soon()
        end,
    })
    self.bluetooth:poll()

    -- A monitor's own speaker volume, over DDC (ddc.lua), for an output
    -- macOS reads no volume for: as tilemo starts, when the output changes,
    -- on wake, and every 30 s, since the monitor's own buttons change it
    -- without telling anyone.
    self.ddc = ddc.monitor({
        find = function()
            return ddc.find(function(p)
                return hs.fs.attributes(p) ~= nil
            end)
        end,
        run = run_task,
        log = log,
        changed = function()
            refresh_soon()
        end,
    })
    function self.poll_ddc()
        local dev = try("the output device", hs.audiodevice.defaultOutputDevice)
        if not dev or try("the volume", function()
            return dev:outputVolume()
        end) ~= nil then
            return self.ddc:poll(nil)
        end
        local screens = {}
        for _, s in ipairs(try("the displays", hs.screen.allScreens) or {}) do
            screens[#screens + 1] = { uuid = s:getUUID(), name = s:name() }
        end
        self.ddc:poll(dev:name(), screens)
    end
    self.poll_ddc()

    -- The volume keys, for a monitor's speakers read over DDC: macOS has no
    -- volume there and shows its "no volume" sign, so tilemo steps the
    -- monitor's own, as a scroll on the speaker does, and shows the level.
    -- Any other output's keys go on to macOS untouched.
    local function volume_key(e)
        local k = e:systemKey()
        if not k or not k.key then
            return false
        end
        local dev = hs.audiodevice.defaultOutputDevice()
        local d = bar.volume_key(k.key, ddc_state(dev) ~= nil)
        if d == nil then
            return false
        end
        if k.down then
            if d == 0 then
                toggle("volume")
            else
                step_volume(d)
            end
            local m = ddc_state(dev)
            if m then
                local muted = m.muted
                if muted == nil then
                    muted = dev:outputMuted()
                end
                hs.alert.closeAll(0)
                hs.alert.show(bar.volume_sign(m.volume, muted), {}, hs.screen.mainScreen(), 1)
            end
        end
        return true
    end
    try("the volume keys", function()
        self.volume_keys = hs.eventtap.new({ hs.eventtap.event.types.systemDefined }, function(e)
            local ok, taken = pcall(volume_key, e)
            if not ok then
                log("bar: a volume key failed: " .. tostring(taken))
                return false
            end
            return taken
        end):start()
    end)

    self.bluetooth_timer = hs.timer.doEvery(M.BLUETOOTH_POLL, function()
        self.bluetooth:poll()
        self.poll_ddc()
    end)
    -- Waking, the radio may have changed while asleep, and the monitor.
    try("the wake watcher", function()
        self.wake_watcher = hs.caffeinate.watcher.new(function(event)
            if event == hs.caffeinate.watcher.systemDidWake then
                self.bluetooth:poll()
                self.poll_ddc()
            end
        end):start()
    end)

    read_icons()
    -- The battery, Wi-Fi, the network and keep awake have no watcher here.
    self.timer = hs.timer.doEvery(M.POLL, function()
        self.refresh()
    end)
    sync_views()
    return self
end

return M
