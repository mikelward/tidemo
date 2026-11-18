-- "Report a bug" through Hammerspoon (report_hs.lua), against a stand-in
-- macOS: the report on the clipboard and in ~/Library/Logs/tide, the
-- issue page opened, and a notification.

local t = require("t")
local fake = require("fake")
local wm_mod = require("tide.wm")
local report = require("tide.report")

local function has(s, part)
    return type(s) == "string" and s:find(part, 1, true) ~= nil
end

local function stub(opts)
    opts = opts or {}
    local home = os.tmpname()
    os.remove(home)
    assert(os.execute("mkdir -p '" .. home .. "'"))
    local s = { home = home, logs = {}, notes = {}, urls = {} }
    _G.hs = {
        configdir = home .. "/.hammerspoon",
        processInfo = { version = "1.0.0" },
        host = {
            localizedName = function()
                return "Someone's MacBook Pro"
            end,
            names = function()
                return { "someones-mbp.local", "localhost", "127.0.0.1" }
            end,
            operatingSystemVersion = function()
                return { major = 26, minor = 1, patch = 0 }
            end,
        },
        pasteboard = {
            setContents = function(text)
                if opts.no_clipboard then
                    return false
                end
                s.clipboard = text
                return true
            end,
        },
        fs = {
            mkdir = function(dir)
                if opts.no_save then
                    return false
                end
                return os.execute("mkdir -p '" .. dir .. "'")
            end,
        },
    }
    local a = fake.new()
    a.add(1, { app = "com.a", pid = 1 })
    a.add(2, { app = "com.b", pid = 2 })
    a.clock = 1000
    local wm = wm_mod.new(a, {})
    wm:sync()
    wm:send(2, "re")
    a.clock = 1010
    wm:act("nth", 2, "key Super+2")
    a.clock = 1015
    a.files[home .. "/.hammerspoon/tide/version"] = "1234 abc1234\n"
    a.log = function(line)
        s.logs[#s.logs + 1] = line
    end
    a.recent_log = function()
        return { { at = 1012, kind = "log", what = "read " .. home .. "/x on someones-mbp", why = "" } }
    end
    a.open_url = function(url)
        s.urls[#s.urls + 1] = url
    end
    a.notify = function(text)
        s.notes[#s.notes + 1] = text
    end
    local tide = {
        wm = wm,
        adapter = a,
        doctor = function()
            return "Hammerspoon has Accessibility."
        end,
    }
    package.loaded["tide.report_hs"] = nil
    local r = require("tide.report_hs").new(tide, function(name)
        return ({ HOME = home, USER = "someone" })[name]
    end)
    return s, r
end

local function cleanup(s)
    os.execute("rm -rf '" .. s.home .. "'")
end

t.test("the report goes on the clipboard, with the switch and its key", function()
    local s, r = stub()
    r.run()
    t.eq(has(s.clipboard, "in -> re"), true, s.clipboard)
    t.eq(has(s.clipboard, "(key Super+2)"), true, "why")
    t.eq(has(s.clipboard, "tide for macOS 1234 (abc1234)"), true, "version")
    t.eq(has(s.clipboard, "macOS 26.1.0, Hammerspoon 1.0.0"), true, "macOS and Hammerspoon")
    t.eq(has(s.clipboard, "Hammerspoon has Accessibility."), true, "doctor")
    cleanup(s)
end)

t.test("the report holds no home folder or host name", function()
    local s, r = stub()
    r.run()
    t.eq(has(s.clipboard, s.home), false, "home")
    t.eq(has(s.clipboard, "read ~/x on host1"), true, s.clipboard)
    cleanup(s)
end)

t.test("the report is saved in ~/Library/Logs/tide", function()
    local s, r = stub()
    r.run()
    local name = report.file_name(1015)
    local f = io.open(s.home .. "/Library/Logs/tide/" .. name)
    t.eq(f ~= nil, true, "saved")
    t.eq(f and f:read("a"), s.clipboard)
    if f then
        f:close()
    end
    t.eq(has(s.notes[1], "on your clipboard"), true, s.notes[1])
    t.eq(has(s.notes[1], "~/Library/Logs/tide/" .. name), true, s.notes[1])
    cleanup(s)
end)

t.test("the issue page opens on tide for macOS's repository", function()
    local s, r = stub()
    r.run()
    t.eq(#s.urls, 1)
    t.eq(has(s.urls[1], "https://github.com/mikelward/tidemo/issues/new?"), true, s.urls[1])
    cleanup(s)
end)

t.test("a clipboard that won't take it says so, and the file still has it", function()
    local s, r = stub({ no_clipboard = true })
    r.run()
    t.eq(has(s.notes[1], "Couldn't copy"), true, s.notes[1])
    t.eq(has(table.concat(s.logs, "\n"), "couldn't put it on the clipboard"), true, "logged")
    t.eq(#s.urls, 1)
    cleanup(s)
end)

t.test("a folder that can't be made says so, and the clipboard still has it", function()
    local s, r = stub({ no_save = true })
    r.run()
    t.eq(has(s.notes[1], "on your clipboard"), true, s.notes[1])
    t.eq(has(table.concat(s.logs, "\n"), "couldn't save it"), true, table.concat(s.logs, "\n"))
    cleanup(s)
end)

t.done("report_hs")
