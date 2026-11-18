-- "Report a bug" (SPEC.md §15): the report, as plain text, and the issue
-- page it opens. Nothing here sends anything: report_hs.lua puts the text
-- on the clipboard and in a file, and opens the page for you to fill in
-- and submit.

local trail = require("tide.trail")

local M = {}

M.REPO = "mikelward/tidemo"
-- Only what happened in the last this many seconds goes in: the
-- maintainer's call, so a report is about the moment you pressed the key.
M.WINDOW = 30
-- The issue page's address stays well under what GitHub and the browsers
-- take.
M.URL_MAX = 6000
-- Where the report is saved, under your home folder.
M.DIR = "Library/Logs/tide"
-- What stands in for this Mac's name and your user name.
M.HOST = "host1"
M.USER = "user1"

-- `text` with your home folder as ~, this Mac's names (`who.hosts`) as
-- host1 and your user name (`who.user`), as a word of its own, as user1.
function M.scrub(text, who)
    text = tostring(text or "")
    who = who or {}
    local function literal(s)
        return (s:gsub("%p", "%%%0"))
    end
    if who.home and who.home ~= "" then
        text = text:gsub(literal(who.home), "~")
    end
    -- Longest first, so a name that holds another goes whole.
    local hosts = {}
    for _, h in ipairs(who.hosts or {}) do
        if type(h) == "string" and h ~= "" then
            hosts[#hosts + 1] = h
        end
    end
    table.sort(hosts, function(a, b)
        return #a > #b
    end)
    for _, h in ipairs(hosts) do
        text = text:gsub(literal(h), M.HOST)
    end
    if who.user and who.user ~= "" then
        text = text:gsub("%f[%w_]" .. literal(who.user) .. "%f[^%w_]", M.USER)
    end
    return text
end

-- What's within M.WINDOW seconds before `at`, of trail entries `list`.
function M.recent(list, at)
    local out = {}
    for _, e in ipairs(list or {}) do
        if e.at >= at - M.WINDOW and e.at <= at then
            out[#out + 1] = e
        end
    end
    return out
end

-- The version as `make install` left it in the version file: "1234
-- abc1234", the commit count and commit, as "1234 (abc1234)".
function M.version(text)
    local count, commit = tostring(text or ""):match("^%s*(%S+)%s*(%S*)")
    if not count then
        return "unknown (not installed by make install from a checkout)"
    end
    if commit ~= "" then
        return count .. " (" .. commit .. ")"
    end
    return count
end

-- The window manager's state now, as the report's lines: each workspace in
-- bar order with its windows, the one showing marked *, and the focused
-- window.
function M.state(wm)
    local lines = {}
    local by_ws = {}
    for id, w in pairs(wm.windows) do
        if w.ws then
            by_ws[w.ws] = by_ws[w.ws] or {}
            local how = wm.parked[id] and " (parked)" or (w.mine and " (minimized)" or "")
            table.insert(by_ws[w.ws], tostring(w.app) .. " #" .. tostring(id) .. how)
        end
    end
    for _, n in ipairs(wm.names) do
        local list = by_ws[n] or {}
        table.sort(list)
        lines[#lines + 1] = (n == wm.current and "* " or "  ") .. n .. ": "
            .. (#list > 0 and table.concat(list, ", ") or "no windows")
    end
    local f = wm.a.focused()
    lines[#lines + 1] = "focused: " .. (f and wm:named(f) or "none")
    return lines
end

local function section(out, title, lines)
    out[#out + 1] = ""
    out[#out + 1] = "## " .. title
    if #lines == 0 then
        out[#out + 1] = "(none)"
    end
    for _, l in ipairs(lines) do
        out[#out + 1] = l
    end
end

-- The report, from `info`: { at, version, os, hammerspoon, doctor, state
-- (lines), trail and log (trail entries), who (M.scrub's) }. Only the
-- trail and the log's last M.WINDOW seconds go in.
function M.text(info)
    local out = {
        "tide for macOS " .. tostring(info.version),
        tostring(info.os) .. ", Hammerspoon " .. tostring(info.hammerspoon),
        "Made at " .. trail.clock(info.at) .. ", covering the " .. M.WINDOW .. " s before.",
    }
    section(out, "Workspace switches and focus moves, with why", trail.lines(M.recent(info.trail, info.at)))
    local log = {}
    for _, e in ipairs(M.recent(info.log, info.at)) do
        log[#log + 1] = trail.clock(e.at) .. " " .. tostring(e.what)
    end
    section(out, "tide's log", log)
    section(out, "Workspaces and windows now", info.state or {})
    local doctor = {}
    for line in tostring(info.doctor or ""):gmatch("[^\n]+") do
        doctor[#doctor + 1] = line
    end
    section(out, "tide doctor", doctor)
    return M.scrub(table.concat(out, "\n") .. "\n", info.who)
end

-- The issue's title, for you to finish.
function M.title()
    return "tide for macOS: "
end

-- The issue's body: what the report holds, first, then the version, and
-- where the report is.
function M.body(info)
    local version = tostring(info.version)
    if #version > 200 then
        version = version:sub(1, 200) .. "..."
    end
    return M.scrub(table.concat({
        "Nothing was sent: the report below can name your apps and windows, with your home folder as ~,"
            .. " this Mac's name as " .. M.HOST .. " and your user name as " .. M.USER .. ".",
        "",
        "tide for macOS " .. version .. ", " .. tostring(info.os),
        "",
        "What happened:",
        "",
        "",
        "The full report is on your clipboard: paste it below.",
        "",
    }, "\n"), info.who)
end

local function encode(s)
    return (tostring(s):gsub("[^%w%-%._~]", function(c)
        return string.format("%%%02X", c:byte())
    end))
end

-- The new issue page, with the title and body filled in.
function M.issue_url(info)
    local url = "https://github.com/" .. M.REPO .. "/issues/new?title=" .. encode(M.title())
        .. "&body=" .. encode(M.body(info))
    if #url >= M.URL_MAX then
        url = "https://github.com/" .. M.REPO .. "/issues/new?title=" .. encode(M.title())
    end
    return url
end

-- The report's file name, by the local date and time `at`.
function M.file_name(at)
    return os.date("tide-report-%Y%m%d-%H%M%S.txt", math.floor(at))
end

return M
