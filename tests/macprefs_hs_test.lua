-- macOS's own settings kept (macprefs_hs.lua): the files read, each change
-- written with defaults and shown, what tide set kept so only a change is
-- applied, and the page's edits saved to macos.local.json. defaults,
-- killall and hs.settings are fakes.

local t = require("t")
local json = require("json")
local macprefs_hs = require("tide.macprefs_hs")

-- A world: `files` by path, `ran` each command as one string, `fail` the
-- defaults write commands that fail, `live` what defaults read answers.
local function world(files)
    local w = { files = files or {}, ran = {}, notes = {}, logs = {}, saved = {}, fail = {}, live = {}, changed = 0, own = {} }
    w.prefs = macprefs_hs.new({
        dir = "/c",
        home = "/Users/someone",
        read = function(p)
            return w.files[p]
        end,
        decode = function(text)
            local ok, v = pcall(json.decode, text)
            return ok and v or nil
        end,
        encode = json.encode,
        write = function(p, text)
            w.files[p] = text
            return true
        end,
        run = function(path, args, done)
            local line = path:match("[^/]+$") .. " " .. table.concat(args, " ")
            if args[1] == "read" or args[2] == "read" then
                local v = w.live[args[#args]]
                done(v and 0 or 1, v and "" or "does not exist", v or "")
                return true
            end
            w.ran[#w.ran + 1] = line
            if w.fail[line] then
                done(1, "permission denied\n", "")
            elseif args[1] == "delete" then
                done(1, "\nThe domain/default pair of (" .. args[2] .. ", " .. args[3] .. ") does not exist\n", "")
            else
                done(0, "", "")
            end
            return true
        end,
        get = function(k)
            return w.saved[k]
        end,
        set = function(k, v)
            w.saved[k] = v
        end,
        notify = function(text)
            w.notes[#w.notes + 1] = text
        end,
        log = function(text)
            w.logs[#w.logs + 1] = text
        end,
        changed = function()
            w.changed = w.changed + 1
        end,
        own = function(values)
            w.own[#w.own + 1] = values["keyboard.capsLockCompose"] == true
        end,
        hidden = function()
            return w.hidden
        end,
    })
    return w
end

t.test("a setting in the files is written, and Finder restarted to show it", function()
    local w = world({ ["/c/macos.json"] = '{"finder":{"showHiddenFiles":true,"showPathBar":true}}' })
    w.prefs.load()
    t.eq(w.ran, {
        "defaults write com.apple.finder AppleShowAllFiles -bool true",
        "defaults write com.apple.finder ShowPathbar -bool true",
        "killall Finder",
    })
    t.eq(w.saved[macprefs_hs.APPLIED_KEY], { ["finder.showHiddenFiles"] = true, ["finder.showPathBar"] = true })
    t.eq(w.notes, {})
end)

t.test("a setting tide applies itself is handed over each time the files are read, and runs no defaults", function()
    local w = world({ ["/c/macos.json"] = '{"keyboard":{"capsLockCompose":true}}' })
    w.prefs.load()
    t.eq(w.ran, {})
    t.eq(w.own, { true })
    w.files["/c/macos.local.json"] = '{"keyboard":{"capsLockCompose":false}}'
    w.prefs.load()
    t.eq(w.own, { true, false })
    -- Read again unchanged, it's handed over again, so a mapping lost to a
    -- restart comes back.
    w.prefs.load()
    t.eq(w.own, { true, false, false })
end)

t.test("loading again applies nothing, so a change in System Settings stays", function()
    local w = world({ ["/c/macos.json"] = '{"finder":{"showPathBar":true}}' })
    w.prefs.load()
    w.ran = {}
    w.prefs.load()
    t.eq(w.ran, {})
end)

t.test("a setting taken out is given back to macOS, a missing key no error", function()
    local w = world({ ["/c/macos.json"] = '{"finder":{"showPathBar":true}}' })
    w.prefs.load()
    w.files["/c/macos.json"] = "{}"
    w.ran = {}
    w.prefs.load()
    t.eq(w.ran, { "defaults delete com.apple.finder ShowPathbar", "killall Finder" })
    t.eq(w.saved[macprefs_hs.APPLIED_KEY], {})
    t.eq(w.notes, {})
end)

t.test("a setting that needs a login says so", function()
    local w = world({ ["/c/macos.local.json"] = '{"windows":{"stageManager":false}}' })
    w.prefs.load()
    t.eq(w.notes, { "Log out and back in for these to change: Stage Manager." })
end)

t.test("one that fails is said, recorded as half done, and tried again on the next change", function()
    local w = world({ ["/c/macos.json"] = '{"typing":{"autocorrect":false,"smartQuotes":false}}' })
    w.fail["defaults write NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool false"] = true
    w.prefs.load()
    t.eq(w.notes, { "Couldn't change macOS's Correct spelling (permission denied). tide tries again when its settings change." })
    t.eq(w.saved[macprefs_hs.APPLIED_KEY], { ["typing.autocorrect"] = "tide:partial", ["typing.smartQuotes"] = false })
    w.fail = {}
    w.ran = {}
    w.prefs.load()
    t.eq(w.ran, { "defaults write NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool false" })
end)

t.test("a file that's wrong is said once, and the last good settings stay", function()
    local w = world({ ["/c/macos.json"] = '{"finder":{"showPathBar":true}}' })
    w.prefs.load()
    w.files["/c/macos.json"] = '{"finder":{"showPathBar":"yes"}}'
    w.files["/c/macos.local.json"] = "{nope"
    w.ran = {}
    w.prefs.load()
    w.prefs.load()
    t.eq(w.ran, {})
    t.eq(w.notes, { "tide's macOS settings stay as they were: macos.local.json doesn't parse; macos.json: finder.showPathBar takes true, false or \"macos\"" })
    t.eq(w.prefs.state().groups[1].rows[2].value, true, "the page shows the good one")
end)

t.test("the page leaves out what tide says it can't apply now", function()
    local w = world({})
    local function names()
        local out = {}
        for _, g in ipairs(w.prefs.state().groups) do
            for _, r in ipairs(g.rows) do
                out[r.name] = true
            end
        end
        return out
    end
    t.eq(names()["keyboard.capsLockCompose"], true)
    w.hidden = { ["keyboard.capsLockCompose"] = true }
    t.eq(names()["keyboard.capsLockCompose"], nil)
end)

t.test("the page shows what macOS has for a setting the files leave out", function()
    local w = world({})
    w.live.AppleShowAllFiles = "1\n"
    w.prefs.read_live()
    local rows = w.prefs.state().groups[1].rows
    t.eq({ rows[1].value, rows[1].set }, { true, false })
    t.eq(w.changed > 0, true)
end)

t.test("a change on the page is saved to macos.local.json, keeping the rest", function()
    local w = world({ ["/c/macos.local.json"] = '{"finder":{"showPathBar":true},"text":{"smoothing":"off"}}' })
    t.eq(w.prefs.handle({ macSet = { name = "text.smoothing", value = "light" } }), true)
    t.eq(json.decode(w.files["/c/macos.local.json"]), { finder = { showPathBar = true }, text = { smoothing = "light" } })
    t.eq(w.prefs.handle({ macReset = "finder.showPathBar" }), true)
    t.eq(json.decode(w.files["/c/macos.local.json"]), { text = { smoothing = "light" } })
    t.eq(w.prefs.handle({ keepMenuBarHidden = true }), false, "not the page's")
    t.eq(w.prefs.handle({ barPosition = "bottom" }), false, "nor the Bar page's")
end)

t.test("a change the page can't save says why on the page", function()
    local w = world({ ["/c/macos.local.json"] = "{nope" })
    w.prefs.handle({ macSet = { name = "finder.showPathBar", value = true } })
    t.eq(w.prefs.state().error, "macos.local.json doesn't parse: fix it to change these here")
    t.eq(w.files["/c/macos.local.json"], "{nope", "left as it was")
    w.files["/c/macos.local.json"] = "{}"
    w.prefs.handle({ macSet = { name = "text.smoothing", value = "loud" } })
    t.eq(w.prefs.state().error, 'Font smoothing takes off, light, medium, strong or "macos"')
end)

t.test("Use macOS's takes back a setting the shared file sets, from the local file", function()
    local w = world({ ["/c/macos.json"] = '{"finder":{"showPathBar":true}}' })
    w.prefs.load()
    w.prefs.handle({ macReset = "finder.showPathBar" })
    t.eq(json.decode(w.files["/c/macos.local.json"]), { finder = { showPathBar = "macos" } })
    w.ran = {}
    w.prefs.load()
    t.eq(w.ran, { "defaults delete com.apple.finder ShowPathbar", "killall Finder" })
    t.eq(w.prefs.state().groups[1].rows[2].set, false, "macOS's own now")
end)

t.test("a setting of several keys that fails part way is undone whole once it's left out", function()
    local w = world({ ["/c/macos.json"] = '{"dialogs":{"expanded":true}}' })
    w.fail["defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode2 -bool true"] = true
    w.prefs.load()
    t.eq(w.ran[1], "defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode -bool true", "the first key changed")
    w.files["/c/macos.json"] = "{}"
    w.ran = {}
    w.prefs.load()
    t.eq(w.ran, {
        "defaults delete NSGlobalDomain NSNavPanelExpandedStateForSaveMode",
        "defaults delete NSGlobalDomain NSNavPanelExpandedStateForSaveMode2",
        "defaults delete NSGlobalDomain PMPrintingExpandedStateForPrint",
        "defaults delete NSGlobalDomain PMPrintingExpandedStateForPrint2",
    })
    t.eq(w.saved[macprefs_hs.APPLIED_KEY], {})
end)

t.test("a delete that fails, not for want of the key, is said and tried again", function()
    local w = world({ ["/c/macos.json"] = '{"finder":{"showPathBar":true}}' })
    w.prefs.load()
    w.files["/c/macos.json"] = "{}"
    w.fail["defaults delete com.apple.finder ShowPathbar"] = true
    w.ran = {}
    w.prefs.load()
    t.eq(w.notes, { "Couldn't change macOS's Show the path bar (permission denied). tide tries again when its settings change." })
    t.eq(w.saved[macprefs_hs.APPLIED_KEY], { ["finder.showPathBar"] = "tide:partial" })
    w.fail = {}
    w.ran = {}
    w.prefs.load()
    t.eq(w.ran, { "defaults delete com.apple.finder ShowPathbar", "killall Finder" })
    t.eq(w.saved[macprefs_hs.APPLIED_KEY], {})
    t.eq(macprefs_hs.absent("Domain (com.example) not found.\nDefaults have not been changed."), true)
end)

t.done("macprefs_hs")
