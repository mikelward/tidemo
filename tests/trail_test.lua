-- The trail of workspace switches and focus moves (trail.lua), for
-- "Report a bug".

local t = require("t")
local trail = require("tide.trail")

t.test("keeps the newest entries, up to MAX", function()
    local tr = trail.new()
    for i = 1, trail.MAX + 5 do
        tr:add(i * 0.01, "focus", "w" .. i, "test")
    end
    local got = tr:recent(10)
    t.eq(#got, trail.MAX, "count")
    t.eq(got[1].what, "w6", "oldest kept")
    t.eq(got[#got].what, "w" .. (trail.MAX + 5), "newest")
end)

t.test("forgets what's older than AGE", function()
    local tr = trail.new()
    tr:add(0, "workspace", "in -> re", "key Super+2")
    tr:add(trail.AGE, "workspace", "re -> in", "key Super+1")
    local got = tr:recent(trail.AGE + 1)
    t.eq(#got, 1, "count")
    t.eq(got[1].what, "re -> in")
end)

t.test("an entry with no reason says unknown", function()
    local tr = trail.new()
    tr:add(0, "focus", "a #1", nil)
    t.eq(tr:recent(0)[1].why, "unknown")
end)

t.test("each line has the time, kind, what and why", function()
    local tr = trail.new()
    tr:add(3600.25, "workspace", "in -> re", "key Super+2")
    local line = trail.lines(tr:recent(3600.25))[1]
    t.eq(line:match("^%d%d:%d%d:%d%d%.2 workspace  in %-> re  %(key Super%+2%)$") ~= nil, true, line)
end)

t.test("with no reason, the callers say where it came from", function()
    -- Not tail calls, which leave no frame to name.
    local function inner()
        local why = trail.callers(1)
        return why
    end
    local function outer()
        local why = inner()
        return why
    end
    local got = outer()
    t.eq(got:match("^unknown, via inner < outer") ~= nil, true, got)
end)

t.done("trail")
