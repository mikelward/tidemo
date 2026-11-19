-- Every workspace switch and focus move goes into the trail with why
-- (wm.lua, trail.lua), for "Report a bug": the report must say why a
-- workspace changed when you didn't expect it to.

local t = require("t")
local fake = require("fake")
local wm_mod = require("tide.wm")
local bar = require("tide.bar")
local swipe = require("tide.swipe")
local tray = require("tide.tray")

-- Window 1 of app "a" on "in", window 2 of app "b" on "re", "in" showing
-- with 1 focused, long enough ago that nothing you did still counts.
local function setup()
    local a = fake.new()
    a.add(1, { app = "a", pid = 1 })
    a.add(2, { app = "b", pid = 2 })
    local wm = wm_mod.new(a, {})
    wm:sync()
    wm:retile()
    wm:send(2, "re")
    wm:focus_window(1)
    wm:focused(1)
    a.clock = 100
    a.calls = {}
    return a, wm
end

-- The trail's entries since `from` (an index), of kind `kind`.
local function entries(wm, kind, from)
    local out = {}
    for i, e in ipairs(wm.trail:recent(wm.a.now())) do
        if i > (from or 0) and e.kind == kind then
            out[#out + 1] = e
        end
    end
    return out
end

local function last(wm, kind)
    local list = entries(wm, kind)
    return list[#list]
end

local function has(s, part)
    return type(s) == "string" and s:find(part, 1, true) ~= nil
end

t.test("a key's switch says which key", function()
    local _, wm = setup()
    wm:act("nth", 2, "key Super+2")
    local e = last(wm, "workspace")
    t.eq(e.what, "in -> re")
    t.eq(e.why, "key Super+2")
end)

t.test("an action with no key named says which action", function()
    local _, wm = setup()
    wm:act("nth", 2)
    wm:act("flip")
    t.eq(last(wm, "workspace").what, "re -> in")
    t.eq(last(wm, "workspace").why, "action flip")
end)

t.test("the focus a key's switch moves says the same key", function()
    local _, wm = setup()
    wm:act("nth", 2, "key Super+2")
    local e = last(wm, "focus")
    t.eq(has(e.what, "#2"), true, e.what)
    t.eq(e.why, "key Super+2")
end)

t.test("a switch with no reason says where it came from", function()
    local _, wm = setup()
    wm:show("re")
    local e = last(wm, "workspace")
    t.eq(has(e.why, "unknown, via show"), true, e.why)
end)

t.test("Cmd+Tab to a window on a hidden workspace says so", function()
    local a, wm = setup()
    wm:modifiers(true)
    wm:key_down("tab", true)
    a.focus_ = 2
    wm:focused(2)
    local e = last(wm, "workspace")
    t.eq(e.what, "in -> re")
    t.eq(has(e.why, "Cmd+Tab"), true, e.why)
end)

t.test("a click that brings a hidden workspace says it was a click", function()
    local a, wm = setup()
    wm:clicked("dock")
    a.focus_ = 2
    wm:focused(2)
    local e = last(wm, "workspace")
    t.eq(e.what, "in -> re")
    t.eq(has(e.why, "click"), true, e.why)
end)

t.test("an app coming forward by itself is noted, and you stay", function()
    local a, wm = setup()
    -- A click on the desktop lets the focus move, but isn't choosing it.
    wm:clicked("desktop")
    a.focus_ = 2
    wm:focused(2)
    t.eq(wm.current, "in")
    local e = last(wm, "focus")
    local report = entries(wm, "focus")
    local said = false
    for _, r in ipairs(report) do
        said = said or has(r.what, "by itself")
    end
    t.eq(said, true, "the trail says it came forward by itself")
    t.eq(has(e.why, "macOS focused b"), true, e.why)
end)

t.test("an app taking focus on the workspace you're on is noted as taken back", function()
    local a, wm = setup()
    a.add(3, { app = "c", pid = 3 })
    wm:sync()
    wm:retile()
    a.clock = 200
    a.focus_ = 3
    wm:focused(3)
    local said = false
    for _, r in ipairs(entries(wm, "focus")) do
        said = said or has(r.what, "taken back")
    end
    t.eq(said, true, "the trail says it was taken back")
    local e = last(wm, "focus")
    t.eq(has(e.what, "#1"), true, "focus goes back to 1: " .. e.what)
    t.eq(has(e.why, "macOS focused c"), true, e.why)
end)

t.test("a focus kept says which rule kept it", function()
    local a, wm = setup()
    a.add(3, { app = "c", pid = 3 })
    wm:sync()
    wm:retile()
    wm:focus_window(3)
    wm:focused(3)
    local e = last(wm, "focus")
    t.eq(has(e.what, "kept"), true, e.what)
    t.eq(has(e.what, "tide asked"), true, e.what)
end)

t.test("a window restored from the Dock brings its workspace and says so", function()
    local a, wm = setup()
    a.wins[2].minimized = true
    wm:minimized(2)
    a.clock = 200
    wm:clicked("dock")
    a.wins[2].minimized = false
    wm:unminimized(2)
    local e = last(wm, "workspace")
    t.eq(e.what, "in -> re")
    t.eq(has(e.why, "restored"), true, e.why)
end)

t.test("a window closing hands focus on, and says why", function()
    local a, wm = setup()
    a.add(3, { app = "a", pid = 1 })
    wm:sync()
    wm:retile()
    wm:focus_window(3)
    wm:focused(3)
    a.drop(3)
    wm:schedule()
    a.tick()
    local e = last(wm, "focus")
    t.eq(has(e.what, "#1"), true, e.what)
    t.eq(has(e.why, "closed"), true, e.why)
    local w = last(wm, "window")
    t.eq(has(w.what, "closed"), true, w.what)
end)

t.test("a launch grant is noted", function()
    local _, wm = setup()
    wm:grant("com.example.app")
    local e = last(wm, "grant")
    t.eq(has(e.what, "com.example.app"), true, e.what)
end)

t.test("a new window says which workspace it went to and why", function()
    local a, wm = setup()
    wm:launch_to("c", "re")
    a.add(3, { app = "c", pid = 3 })
    wm:sync()
    local e = last(wm, "window")
    t.eq(has(e.what, "c #3"), true, e.what)
    t.eq(has(e.what, "re"), true, e.what)
    t.eq(has(e.why, "launch"), true, e.why)
end)

t.test("a macOS Space change is noted", function()
    local _, wm = setup()
    wm:space_changed()
    local e = last(wm, "space")
    t.eq(e.why, "macOS")
end)

t.test("focus follows mouse says so", function()
    local _, wm = setup()
    wm:focus_window(1, true)
    t.eq(last(wm, "focus").why, "focus follows mouse")
end)

t.test("the name prompt's answer says so", function()
    local a, wm = setup()
    wm.ask_go = function() end
    wm:act("go_to", nil, "key Super+Return")
    wm:go_answer(wm.prompting, "re")
    local e = last(wm, "workspace")
    t.eq(e.what, "in -> re")
    t.eq(has(e.why, "name prompt"), true, e.why)
    t.eq(a.focused(), 2)
end)

t.test("a launch's question shows its workspace with why", function()
    local _, wm = setup()
    wm.ask_launch = function() end
    wm:before_launch({ fresh = true, default = "x" }, function()
        wm:grant("x")
    end)
    wm:launch_answer(wm.prompting, "new")
    local e = last(wm, "workspace")
    t.eq(e.what, "in -> new")
    t.eq(has(e.why, "launch"), true, e.why)
    t.eq(last(wm, "grant").why, e.why, "the launch's grant says the same")
end)

t.test("the bar's clicks and scrolls say so", function()
    local _, wm = setup()
    bar.handle(wm, { uuid = "A", show = "re" }, {})
    t.eq(has(last(wm, "workspace").why, "bar"), true, last(wm, "workspace").why)
    bar.handle(wm, { uuid = "A", step = -1 }, {})
    t.eq(last(wm, "workspace").what, "re -> in")
    t.eq(has(last(wm, "workspace").why, "bar"), true, last(wm, "workspace").why)
end)

t.test("a trackpad swipe says so", function()
    local _, wm = setup()
    local s = swipe.for_wm(wm)
    s.on_swipe(1)
    t.eq(last(wm, "workspace").why, "trackpad swipe")
end)

t.test("a click on the tray says so", function()
    local a, wm = setup()
    a.wins[2].minimized = true
    wm:minimized(2)
    tray.click(wm, 2)
    t.eq(has(last(wm, "workspace").why, "tray"), true, last(wm, "workspace").why)
end)

t.test("Super+Z's refocus says which key", function()
    local a, wm = setup()
    a.add(3, { app = "a", pid = 1 })
    wm:sync()
    wm:retile()
    wm:focus_window(3)
    wm:focused(3)
    wm:act("minimize", nil, "key Super+Z")
    local e = last(wm, "focus")
    t.eq(has(e.what, "#1"), true, e.what)
    t.eq(e.why, "key Super+Z")
end)

t.test("tide's own window taking the keyboard and giving it back is noted", function()
    local _, wm = setup()
    wm:hold("launcher", true)
    t.eq(last(wm, "focus").what, "tide's launcher took the keyboard")
    wm:hold("launcher", false)
    t.eq(last(wm, "focus").what, "tide's launcher let it go")
end)

t.test("a parked window losing focus to nothing says so", function()
    local a, wm = setup()
    a.focus_ = 2
    wm.parked[2] = true
    wm:unfocus_parked()
    t.eq(has(last(wm, "focus").what, "none: b #2"), true, last(wm, "focus").what)
end)

t.done("reasons")
