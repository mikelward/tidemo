-- The workspace rules (SPEC.md §6.1), checked against random runs of what
-- macOS and apps do on the fake adapter, rather than one bug's steps at a
-- time. Each run starts from a seed, so a failure names the seed and the
-- steps that led to it, and replays the same way.
--
-- What only you do: show a workspace, send a window, Cmd+Tab to a window,
-- click one in the Dock, close or minimize the window you're in, open
-- and close tide's launcher. What macOS and apps do unasked: an app brings
-- its window forward, a click on the desktop brings up Finder's, a
-- window drops out of macOS's list for a moment, an app opens a window,
-- an app quits and comes back with its windows, a sync, and each of those
-- reported early or late.
--
-- The rules, after every step:
-- 1. The workspace showing changes only when you show one, or choose a
--    window on another one.
-- 2. A window tide knows changes workspace only when you send it.
-- 3. A workspace with windows is listed, and so is the one showing.
-- 4. Once tide has synced, the window with the focus isn't parked: what
--    you type reaches a window you can see.

local t = require("t")
local fake = require("fake")
local wm_mod = require("tide.wm")

local RUNS = tonumber(os.getenv("TIDE_RULE_RUNS") or "") or 200
local STEPS = 40
local WORKSPACES = { "in", "work", "web" }
local APPS = {
    { app = "com.example.term", pid = 100 },
    { app = "com.example.browser", pid = 200 },
    { app = "com.apple.finder", pid = 300 },
}

-- A small PRNG of its own, so a seed gives the same run on Lua 5.4 and 5.5.
local function rng(seed)
    local s = seed * 2654435761 % 4294967296
    if s == 0 then
        s = 1
    end
    return function(n)
        s = (s * 1103515245 + 12345) % 2147483648
        return s % n + 1
    end
end

-- The world: three apps' windows spread over three workspaces, "work"
-- showing, and the expectations the rules check against.
local function world(seed)
    local r = rng(seed)
    local a = fake.new()
    local w = { r = r, a = a, trail = {}, next_id = 1 }
    for i = 1, 5 do
        local app = APPS[r(#APPS)]
        a.add(i, { app = app.app, pid = app.pid, title = app.app .. " " .. i })
    end
    w.next_id = 6
    local wm = wm_mod.new(a, {})
    w.wm = wm
    wm:sync()
    wm:reconcile()
    wm:retile()
    for id = 1, 5 do
        local ws = WORKSPACES[r(#WORKSPACES)]
        if ws ~= "in" then
            wm:send(id, ws)
        end
    end
    wm:show("work", nil, true)
    -- Whatever's on "work" has the focus, as after a switch.
    for id, o in pairs(wm.windows) do
        if o.ws == "work" then
            a.focus_ = id
            wm:focused(id)
            break
        end
    end
    w.current = wm.current
    return w
end

local function ids(w)
    local out = {}
    for id in pairs(w.wm.windows) do
        out[#out + 1] = id
    end
    table.sort(out)
    return out
end

local function pick(w)
    local list = ids(w)
    if #list == 0 then
        return nil
    end
    return list[w.r(#list)]
end

-- macOS reports a focus tide asked for, as it reports any other.
local function report(w)
    local f = w.a.focus_
    if f and f ~= w.reported then
        w.reported = f
        w.wm:focused(f)
    end
    w.reported = w.a.focus_
end

local function sync(w)
    w.wm:schedule()
    w.a.tick()
    report(w)
end

-- Past every grace: what came before no longer counts as you choosing.
local function later(w)
    w.a.clock = w.a.clock + 30
end

-- macOS gives the focus to window `id` and says so.
local function macos_focuses(w, id)
    if id and w.a.wins[id] and not w.a.wins[id].minimized then
        w.a.focus_ = id
        w.reported = id
        w.wm:focused(id)
        report(w)
    end
end

-- Another window macOS might give the focus to as one goes: any it lists.
local function next_focus(w, gone)
    local list = {}
    for _, id in ipairs(w.a.ordered()) do
        if id ~= gone and not w.a.wins[id].minimized then
            list[#list + 1] = id
        end
    end
    if #list == 0 then
        return nil
    end
    return list[w.r(#list)]
end

-- Each step: its name, and what it does. A step you take returns what it
-- allows: { current = name } for the workspace that may show after it,
-- { moved = { [id] = ws } } for a window it sends.
local STEPS_LIST = {
    -- You.
    { "you show a workspace", function(w)
        local ws = WORKSPACES[w.r(#WORKSPACES)]
        w.wm:show(ws, nil, true)
        return { current = ws }, ws
    end },
    { "you send the focused window", function(w)
        local id = w.a.focus_
        local o = id and w.wm.windows[id]
        if not o then
            return {}
        end
        local ws = WORKSPACES[w.r(#WORKSPACES)]
        w.wm:act("send", ws)
        return { moved = { [id] = ws } }, id .. " to " .. ws
    end },
    { "you Cmd+Tab to a window", function(w)
        later(w)
        local id = pick(w)
        if not id or w.a.wins[id].minimized then
            return {}
        end
        local ws = w.wm.windows[id].ws
        w.wm:modifiers(true)
        w.wm:key_down("tab", true)
        macos_focuses(w, id)
        w.wm:modifiers(false)
        return { current = ws }, id
    end },
    { "you click a window in the Dock", function(w)
        later(w)
        local id = pick(w)
        if not id or w.a.wins[id].minimized then
            return {}
        end
        local ws = w.wm.windows[id].ws
        w.wm:clicked(false)
        macos_focuses(w, id)
        return { current = ws }, id
    end },
    { "you close the window you're in, focus reported first", function(w)
        local id = w.a.focus_
        if not id then
            return {}
        end
        w.wm:modifiers(true)
        local to = next_focus(w, id)
        w.a.drop(id)
        macos_focuses(w, to)
        w.wm:modifiers(false)
        sync(w)
        return {}, id .. ", then " .. tostring(to)
    end },
    { "you close the window you're in, synced first", function(w)
        local id = w.a.focus_
        if not id then
            return {}
        end
        local to = next_focus(w, id)
        w.a.drop(id)
        sync(w)
        macos_focuses(w, to)
        return {}, id .. ", then " .. tostring(to)
    end },
    { "you minimize the window you're in", function(w)
        local id = w.a.focus_
        if not id then
            return {}
        end
        local to = next_focus(w, id)
        w.a.wins[id].minimized = true
        w.wm:minimized(id)
        macos_focuses(w, to)
        sync(w)
        return {}, id .. ", then " .. tostring(to)
    end },
    { "you open and close the launcher", function(w)
        local to = next_focus(w)
        w.wm:hold("launcher", true)
        w.wm:hold("launcher", false)
        macos_focuses(w, to)
        return {}, "then " .. tostring(to)
    end },
    -- macOS and apps, unasked.
    { "an app brings its window forward", function(w)
        later(w)
        local id = pick(w)
        macos_focuses(w, id)
        return nil, id
    end },
    { "a click on the desktop brings up Finder's window", function(w)
        later(w)
        local list = {}
        for id, o in pairs(w.wm.windows) do
            if o.app == "com.apple.finder" then
                list[#list + 1] = id
            end
        end
        table.sort(list)
        if #list == 0 then
            return nil
        end
        local id = list[w.r(#list)]
        w.wm:clicked(true)
        macos_focuses(w, id)
        return nil, id
    end },
    { "a window drops out of macOS's list for a sync", function(w)
        later(w)
        local id = pick(w)
        if not id then
            return nil
        end
        local f = w.a.wins[id]
        local at
        for i, v in ipairs(w.a.order) do
            if v == id then
                at = i
            end
        end
        table.remove(w.a.order, at)
        w.a.wins[id] = nil
        sync(w)
        w.a.wins[id] = f
        table.insert(w.a.order, at, id)
        sync(w)
        return nil, id
    end },
    { "an app opens a window", function(w)
        later(w)
        local app = APPS[w.r(#APPS)]
        local id = w.next_id
        w.next_id = id + 1
        w.a.add(id, { app = app.app, pid = app.pid, title = app.app .. " " .. id })
        if w.r(2) == 1 then
            macos_focuses(w, id)
            sync(w)
        else
            sync(w)
            macos_focuses(w, id)
        end
        return { new = id }, id
    end },
    { "an app quits and comes back with its windows", function(w)
        later(w)
        local app = APPS[w.r(#APPS)]
        local back = {}
        for _, id in ipairs(ids(w)) do
            local f = w.a.wins[id]
            if f and f.pid == app.pid then
                back[#back + 1] = f.title
                w.a.drop(id)
            end
        end
        if #back == 0 then
            return nil
        end
        w.a.pids[app.pid] = false
        sync(w)
        w.a.pids[app.pid] = nil
        later(w)
        local first
        for _, title in ipairs(back) do
            local id = w.next_id
            w.next_id = id + 1
            w.a.add(id, { app = app.app, pid = app.pid, title = title })
            first = first or id
        end
        macos_focuses(w, first)
        sync(w)
        return nil, app.app
    end },
    { "a sync", function(w)
        later(w)
        sync(w)
        return nil
    end },
}

local function fail(w, seed, why)
    -- TIDE_RULE_SEED=n TIDE_RULE_TRAIL=1 also prints why tide did what it
    -- did, as Report a bug does.
    if os.getenv("TIDE_RULE_TRAIL") then
        local trail = require("tide.trail")
        print(table.concat(trail.lines(w.wm.trail:recent(w.a.clock)), "\n"))
        print(table.concat(w.a.calls, " "))
    end
    error(string.format("seed %d: %s\n  after: %s", seed, why, table.concat(w.trail, "; ")), 0)
end

local function check(w, seed, allowed, before)
    local wm = w.wm
    allowed = allowed or {}
    -- 1.
    local want = allowed.current or w.current
    if wm.current ~= want then
        fail(w, seed, string.format("rule 1: %s shows, not %s", tostring(wm.current), tostring(want)))
    end
    w.current = wm.current
    -- 2.
    for id, ws in pairs(before) do
        local o = wm.windows[id]
        local to = allowed.moved and allowed.moved[id] or ws
        if o and o.ws ~= to then
            fail(w, seed, string.format("rule 2: window %d moved from %s to %s", id, tostring(ws), tostring(o.ws)))
        end
    end
    -- 3.
    for id, o in pairs(wm.windows) do
        if o.ws and not wm:find(o.ws) then
            fail(w, seed, string.format("rule 3: %s has window %d but isn't listed", o.ws, id))
        end
    end
    if not wm:find(wm.current) then
        fail(w, seed, string.format("rule 3: %s shows but isn't listed", tostring(wm.current)))
    end
    -- 4.
    sync(w)
    local f = w.a.focus_
    if f and wm.parked[f] then
        fail(w, seed, string.format("rule 4: window %d has the focus, parked on %s", f, tostring(wm.windows[f].ws)))
    end
end

local function run(seed)
    local w = world(seed)
    check(w, seed, {}, {})
    for _ = 1, STEPS do
        local before = {}
        for id, o in pairs(w.wm.windows) do
            before[id] = o.ws
        end
        local step = STEPS_LIST[w.r(#STEPS_LIST)]
        local allowed, what = step[2](w)
        report(w)
        w.trail[#w.trail + 1] = step[1] .. (what and (" (" .. tostring(what) .. ")") or "")
        check(w, seed, allowed, before)
    end
end

t.test("the workspace rules hold through random runs of macOS's and apps' events", function()
    local first = tonumber(os.getenv("TIDE_RULE_SEED") or "")
    if first then
        run(first)
        return
    end
    for seed = 1, RUNS do
        run(seed)
    end
end)

t.done("workspace_rules_test")
