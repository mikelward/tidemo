-- "Report a bug" (report.lua): what the report holds, what it leaves out,
-- and the issue page it opens.

local t = require("t")
local fake = require("fake")
local trail = require("tide.trail")
local report = require("tide.report")
local wm_mod = require("tide.wm")

local function has(s, part)
    return type(s) == "string" and s:find(part, 1, true) ~= nil
end

-- What the report is made from, at time 1000, with trail and log entries
-- 40, 31, 29 and 1 seconds before.
local function fixture()
    local tr = trail.new()
    local log = trail.new()
    for _, ago in ipairs({ 40, 31, 29, 1 }) do
        tr:add(1000 - ago, "workspace", "switch " .. ago .. " s before", "key Super+" .. ago)
        log:add(1000 - ago, "log", "log line " .. ago .. " s before", "")
    end
    return {
        at = 1000,
        version = "1234 (abc1234)",
        os = "macOS 26.1.0",
        hammerspoon = "1.0.0",
        doctor = "Hammerspoon has Accessibility.",
        state = { "showing: in" },
        trail = tr:recent(1000),
        log = log:recent(1000),
        who = { home = "/Users/someone", hosts = { "Someone's MacBook Pro", "someones-mbp" }, user = "someone" },
    }
end

t.test("only the last 30 seconds go in", function()
    local text = report.text(fixture())
    t.eq(has(text, "switch 29 s before"), true, "29 s before")
    t.eq(has(text, "switch 1 s before"), true, "1 s before")
    t.eq(has(text, "switch 31 s before"), false, "31 s before")
    t.eq(has(text, "switch 40 s before"), false, "40 s before")
    t.eq(has(text, "log line 29 s before"), true, "log, 29 s before")
    t.eq(has(text, "log line 31 s before"), false, "log, 31 s before")
end)

t.test("the reasons go in with each switch", function()
    local text = report.text(fixture())
    t.eq(has(text, "(key Super+29)"), true, text)
end)

t.test("the version, macOS, Hammerspoon and the doctor go in", function()
    local text = report.text(fixture())
    t.eq(has(text, "tide for macOS 1234 (abc1234)"), true, "version")
    t.eq(has(text, "macOS 26.1.0"), true, "macOS")
    t.eq(has(text, "Hammerspoon 1.0.0"), true, "Hammerspoon")
    t.eq(has(text, "Hammerspoon has Accessibility."), true, "doctor")
    t.eq(has(text, "showing: in"), true, "state")
end)

t.test("the home folder, this Mac's names and your user name are replaced", function()
    local f = fixture()
    f.log = { { at = 999, kind = "log", what = "read /Users/someone/x on Someone's MacBook Pro (someones-mbp) for someone, someoneelse", why = "" } }
    local text = report.text(f)
    t.eq(has(text, "/Users/someone"), false, "home")
    t.eq(has(text, "~/x"), true, "home as ~")
    t.eq(has(text, "MacBook"), false, "the Mac's name")
    t.eq(has(text, "someones-mbp"), false, "its host name")
    t.eq(has(text, "on host1 (host1)"), true, "host1")
    t.eq(has(text, "for user1, someoneelse"), true, "the user name, as a whole word only")
end)

t.test("the issue page's address prefills a title and a short body", function()
    local url = report.issue_url(fixture())
    t.eq(url:sub(1, #"https://github.com/mikelward/tidemo/issues/new?"), "https://github.com/mikelward/tidemo/issues/new?")
    t.eq(has(url, "title="), true, url)
    t.eq(has(url, "body="), true, url)
    t.eq(#url < report.URL_MAX, true, "short enough: " .. #url)
    t.eq(has(url, " "), false, "encoded")
end)

t.test("the body's first line says what the report holds and that nothing was sent", function()
    local body = report.body(fixture())
    local first = body:match("^[^\n]*")
    t.eq(has(first, "~"), true, first)
    t.eq(has(first, "host1"), true, first)
    t.eq(has(first, "Nothing was sent"), true, first)
    t.eq(has(body, "clipboard: paste it below"), true, body)
    t.eq(has(body, "1234 (abc1234)"), true, body)
end)

t.test("a long trail never makes the address too long", function()
    local f = fixture()
    f.version = string.rep("x", 10000)
    t.eq(#report.issue_url(f) < report.URL_MAX, true)
end)

t.test("the version file says the version and commit", function()
    t.eq(report.version("1234 abc1234\n"), "1234 (abc1234)")
    t.eq(report.version("1234\n"), "1234")
    t.eq(has(report.version(nil), "unknown"), true)
    t.eq(has(report.version(""), "unknown"), true)
end)

t.test("the file name has the date and time", function()
    t.eq(report.file_name(0):match("^tide%-report%-%d%d%d%d%d%d%d%d%-%d%d%d%d%d%d%.txt$") ~= nil, true,
        report.file_name(0))
end)

t.test("the state lists each workspace's windows, the one showing marked", function()
    local a = fake.new()
    a.add(1, { app = "com.a", pid = 1 })
    a.add(2, { app = "com.b", pid = 2 })
    local wm = wm_mod.new(a, {})
    wm:sync()
    wm:send(2, "re")
    wm:focus_window(1)
    local lines = report.state(wm)
    local text = table.concat(lines, "\n")
    t.eq(has(text, "* in: com.a #1"), true, text)
    t.eq(has(text, "  re: com.b #2 (parked)"), true, text)
    t.eq(has(text, "focused: com.a #1 on in"), true, text)
end)

t.done("report")
