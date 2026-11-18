-- The last few minutes of workspace switches and focus moves, each with
-- why, for "Report a bug" (SPEC.md §15). Kept in memory only: the newest
-- M.MAX entries from the last M.AGE seconds. A reload starts it afresh.

local M = {}
M.__index = M

-- At most this many entries, none older than this many seconds. Focus
-- follows mouse can add a few a second, so 400 holds a busy few minutes.
M.MAX = 400
M.AGE = 600

function M.new()
    return setmetatable({ entries = {} }, M)
end

-- Drop what's past M.MAX or older than M.AGE at time `now`.
function M:trim(now)
    local e = self.entries
    local drop = 0
    while drop < #e and (#e - drop > M.MAX or now - e[drop + 1].at > M.AGE) do
        drop = drop + 1
    end
    if drop > 0 then
        table.move(e, drop + 1, #e, 1)
        for i = #e - drop + 1, #e do
            e[i] = nil
        end
    end
end

-- Add what happened at time `at`: `kind` is "workspace", "focus",
-- "window", "grant" or "space"; `what` says what changed and `why` what
-- made it, "unknown" when nothing said.
function M:add(at, kind, what, why)
    local e = self.entries
    e[#e + 1] = { at = at, kind = kind, what = what, why = why or "unknown" }
    self:trim(at)
end

-- The entries still kept at time `now`, oldest first.
function M:recent(now)
    self:trim(now)
    local out = {}
    for i, v in ipairs(self.entries) do
        out[i] = v
    end
    return out
end

-- A time as the report shows it: local time to a tenth of a second.
function M.clock(at)
    return os.date("%H:%M:%S", math.floor(at)) .. string.format(".%d", math.floor((at % 1) * 10))
end

-- The entries as the report's lines, one each:
-- "10:00:00.0 workspace  re -> in  (key Super+Tab)".
function M.lines(entries)
    local out = {}
    for _, v in ipairs(entries) do
        out[#out + 1] = string.format("%s %-9s  %s  (%s)", M.clock(v.at), v.kind, v.what, v.why)
    end
    return out
end

-- With no reason given, which of tide's functions led here, innermost
-- first, from `level` up (1 is the function calling this): "via show < activate
-- < focused_window", so a call site that names no reason still shows in
-- the report.
function M.callers(level)
    local names = {}
    for l = level, level + 5 do
        local info = debug.getinfo(l + 1, "n")
        if not info then
            break
        end
        if info.name then
            names[#names + 1] = info.name
        end
    end
    if #names == 0 then
        return "unknown"
    end
    return "unknown, via " .. table.concat(names, " < ")
end

return M
