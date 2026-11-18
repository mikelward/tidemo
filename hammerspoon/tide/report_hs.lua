-- "Report a bug" through Hammerspoon (SPEC.md §15): gathers the report
-- (report.lua), puts it on the clipboard, saves it in ~/Library/Logs/tide,
-- opens the new issue page with a short body filled in, and says so.
-- Nothing is sent: you read the report and submit the issue yourself.

local report = require("tide.report")

local M = {}

-- This Mac's names, to take out of the report: the one System Settings
-- shows, and its host names, each whole and up to the first dot.
local function host_names()
    local out = {}
    local ok, name = pcall(hs.host.localizedName)
    if ok and type(name) == "string" then
        out[#out + 1] = name
    end
    local ok2, names = pcall(hs.host.names)
    for _, n in ipairs(ok2 and type(names) == "table" and names or {}) do
        if type(n) == "string" and n ~= "localhost" and not n:match("^[%d.:]+$") and not n:find(":", 1, true) then
            out[#out + 1] = n
            out[#out + 1] = n:match("^([^.]+)")
        end
    end
    return out
end

local function os_version()
    local ok, v = pcall(hs.host.operatingSystemVersion)
    if ok and type(v) == "table" then
        return string.format("macOS %s.%s.%s", tostring(v.major), tostring(v.minor), tostring(v.patch))
    end
    return "macOS (unknown version)"
end

-- `tide` is the started tide module: wm, adapter, doctor(). `getenv` is
-- os.getenv, or the tests' own.
function M.new(tide, getenv)
    getenv = getenv or os.getenv
    local self = {}

    -- What the report is made from, now.
    function self.info()
        local a = tide.adapter
        local now = a.now()
        local home = getenv("HOME") or ""
        local doctor_ok, doctor = xpcall(tide.doctor, debug.traceback)
        if not doctor_ok then
            a.log("report: tide doctor failed: " .. tostring(doctor))
            doctor = "tide doctor failed: " .. tostring(doctor)
        end
        return {
            at = now,
            version = report.version(a.read(hs.configdir .. "/tide/version")),
            os = os_version(),
            hammerspoon = hs.processInfo and hs.processInfo.version or "unknown",
            doctor = doctor,
            state = report.state(tide.wm),
            trail = tide.wm.trail:recent(now),
            log = a.recent_log and a.recent_log(now) or {},
            who = { home = home, hosts = host_names(), user = getenv("USER") },
        }
    end

    -- Save `text` as ~/Library/Logs/tide/<name>; the path as the report
    -- names it (from ~), or nil, having logged why.
    local function save(home, name, text)
        local dir = home .. "/" .. report.DIR
        hs.fs.mkdir(home .. "/Library/Logs")
        hs.fs.mkdir(dir)
        local path = dir .. "/" .. name
        local f, err = io.open(path, "w")
        if not f then
            tide.adapter.log("report: couldn't save it in ~/" .. report.DIR .. ": " .. tostring(err))
            return nil
        end
        local ok, werr = f:write(text)
        f:close()
        if not ok then
            tide.adapter.log("report: couldn't write ~/" .. report.DIR .. "/" .. name .. ": " .. tostring(werr))
            os.remove(path)
            return nil
        end
        return "~/" .. report.DIR .. "/" .. name
    end

    function self.run()
        local a = tide.adapter
        local info = self.info()
        local text = report.text(info)
        local copied = hs.pasteboard.setContents(text)
        if not copied then
            a.log("report: couldn't put it on the clipboard")
        end
        local saved = save(getenv("HOME") or "", report.file_name(info.at), text)
        a.open_url(report.issue_url(info))
        a.log("report: made, " .. (copied and "on the clipboard" or "not on the clipboard")
            .. (saved and (", saved as " .. saved) or ", not saved"))
        if copied then
            a.notify("The bug report is on your clipboard, and the issue page is open."
                .. (saved and (" It's saved in " .. saved .. " too.") or ""))
        elseif saved then
            a.notify("Couldn't copy the bug report. It's saved in " .. saved .. ", and the issue page is open.")
        else
            a.notify("Couldn't copy or save the bug report. The issue page is open.")
        end
    end

    return self
end

return M
