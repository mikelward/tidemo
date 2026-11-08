-- macOS's own settings that tide keeps (macprefs.lua): the files checked
-- and laid over each other, what to run for a change, what macOS has, the
-- page, and the page's edits to macos.local.json.

local t = require("t")
local macprefs = require("tide.macprefs")

local function args_of(steps)
    local out = {}
    for _, s in ipairs(steps) do
        for _, c in ipairs(s.commands) do
            out[#out + 1] = table.concat(c.args, " ")
        end
    end
    return out
end

t.test("a local file's setting is laid over the shared one's, setting by setting", function()
    local values, errors = macprefs.merge(
        { finder = { showHiddenFiles = true, showPathBar = true } },
        { finder = { showPathBar = false }, text = { smoothing = "light" } }
    )
    t.eq(errors, {})
    t.eq(values, { ["finder.showHiddenFiles"] = true, ["finder.showPathBar"] = false, ["text.smoothing"] = "light" })
end)

t.test("a wrong setting is an error naming the file and the setting", function()
    local _, errors = macprefs.merge(
        { finder = { showHidden = true }, typing = "off" },
        { text = { smoothing = "a bit" }, screenshots = { folder = "Pictures" } }
    )
    t.eq(errors, {
        "macos.json: finder.showHidden isn't a setting",
        "macos.json: typing isn't a JSON object",
        'macos.local.json: screenshots.folder takes a folder, from / or ~/, or "macos"',
        'macos.local.json: text.smoothing takes off, light, medium, strong or "macos"',
    })
    local _, not_object = macprefs.merge({ "a list" }, nil)
    t.eq(not_object, { "macos.json: 1 isn't a JSON object" })
end)

t.test("a change writes each of its keys; what didn't change runs nothing", function()
    local steps = macprefs.plan({ ["finder.showHiddenFiles"] = true, ["text.smoothing"] = "light" },
        { ["finder.showHiddenFiles"] = true }, "/Users/someone")
    t.eq(args_of(steps), { "-currentHost write -g AppleFontSmoothing -int 1" })
    t.eq(steps[1].effect, "apps")
    t.eq(#macprefs.plan({ ["text.smoothing"] = "light" }, { ["text.smoothing"] = "light" }, "/h"), 0)
end)

t.test("a setting taken out of the files is given back to macOS", function()
    local steps = macprefs.plan({}, { ["finder.showPathBar"] = true }, "/h")
    t.eq(args_of(steps), { "delete com.apple.finder ShowPathbar" })
    t.eq(steps[1].commands[1].delete, true)
    t.eq(steps[1].value, nil)
end)

t.test("an inverted key, a folder from ~/ and a setting of several keys", function()
    local steps = macprefs.plan({
        ["finder.animations"] = false,
        ["screenshots.folder"] = "~/Pictures/Screenshots",
        ["missionControl.hotCorners"] = false,
        ["windows.animations"] = false,
    }, {}, "/Users/someone")
    t.eq(args_of(steps), {
        "write com.apple.finder DisableAllAnimations -bool true",
        "write com.apple.screencapture location -string /Users/someone/Pictures/Screenshots",
        "write com.apple.dock wvous-tl-corner -int 1",
        "write com.apple.dock wvous-tl-modifier -int 0",
        "write com.apple.dock wvous-tr-corner -int 1",
        "write com.apple.dock wvous-tr-modifier -int 0",
        "write com.apple.dock wvous-bl-corner -int 1",
        "write com.apple.dock wvous-bl-modifier -int 0",
        "write com.apple.dock wvous-br-corner -int 1",
        "write com.apple.dock wvous-br-modifier -int 0",
        "write NSGlobalDomain NSAutomaticWindowAnimationsEnabled -bool false",
        "write NSGlobalDomain NSWindowResizeTime -float 0.001",
    })
end)

t.test("turning a setting of several keys back on gives them all back to macOS", function()
    local steps = macprefs.plan({ ["missionControl.swipes"] = true }, { ["missionControl.swipes"] = false }, "/h")
    local args = args_of(steps)
    t.eq(#args, 11)
    for _, a in ipairs(args) do
        t.eq(a:match("^delete ") ~= nil, true, a)
    end
end)

t.test("the restarts a change needs, once each, and what waits", function()
    local restart, later = macprefs.effects({
        { effect = "Finder" }, { effect = "apps" }, { effect = "Finder" }, { effect = "Dock" }, { effect = "login" },
    })
    t.eq(restart, { "Finder", "Dock" })
    t.eq(later, { "apps", "login" })
end)

t.test("what macOS has, read from defaults, as each setting's value", function()
    local s = macprefs.BY_NAME
    t.eq(macprefs.parse(s["finder.showHiddenFiles"], 0, "1\n"), true)
    t.eq(macprefs.parse(s["finder.animations"], 0, "1\n"), false, "inverted")
    t.eq(macprefs.parse(s["finder.showPathBar"], 1, "does not exist"), nil, "unset is macOS's own")
    t.eq(macprefs.parse(s["missionControl.hotCorners"], 0, "1\n"), false, "a corner that does nothing")
    t.eq(macprefs.parse(s["missionControl.hotCorners"], 1, ""), true)
    t.eq(macprefs.parse(s["text.smoothing"], 0, "0\n"), "off")
    t.eq(macprefs.parse(s["screenshots.folder"], 0, "/Users/someone/Shots\n"), "/Users/someone/Shots")
    t.eq(macprefs.read_args(s["text.smoothing"]), { "-currentHost", "read", "-g", "AppleFontSmoothing" })
end)

t.test("the page shows the files' value, else macOS's now, else macOS's own", function()
    local page = macprefs.page({ ["finder.showHiddenFiles"] = true }, { ["finder.showPathBar"] = true }, { "bad" })
    local rows = page.groups[1].rows
    t.eq(page.groups[1].label, "Finder")
    t.eq({ rows[1].value, rows[1].set, rows[1].when }, { true, true, "now" })
    t.eq({ rows[2].value, rows[2].set }, { true, false })
    t.eq({ rows[3].value, rows[3].set }, { false, false })
    t.eq(page.error, "bad")
    local total = 0
    for _, g in ipairs(page.groups) do
        total = total + #g.rows
    end
    t.eq(total, #macprefs.SETTINGS, "every setting on the page")
end)

t.test("an edit sets one setting in the local file, and a reset takes it out", function()
    local obj = macprefs.edit({ finder = { showPathBar = true }, other = 1 }, "finder.showHiddenFiles", true)
    t.eq(obj, { finder = { showPathBar = true, showHiddenFiles = true }, other = 1 })
    obj = macprefs.edit(obj, "finder.showPathBar", nil)
    obj = macprefs.edit(obj, "finder.showHiddenFiles", nil)
    t.eq(obj, { other = 1 }, "an empty group goes")
    t.eq(macprefs.edit(nil, "text.smoothing", "light"), { text = { smoothing = "light" } })
    local none, why = macprefs.edit({}, "text.smoothing", "loud")
    t.eq({ none, why }, { nil, 'Font smoothing takes off, light, medium, strong or "macos"' })
    none, why = macprefs.edit({}, "text.color", true)
    t.eq({ none, why }, { nil, "text.color isn't a setting" })
end)

t.test('"macos" in the local file leaves a setting the shared one sets to macOS', function()
    local values, errors = macprefs.merge({ finder = { showPathBar = true }, text = { smoothing = "off" } },
        { finder = { showPathBar = "macos" } })
    t.eq(errors, {})
    t.eq(values, { ["text.smoothing"] = "off" })
    local shared = { finder = { showPathBar = true } }
    t.eq(macprefs.edit({}, "finder.showPathBar", nil, shared), { finder = { showPathBar = "macos" } })
    t.eq(macprefs.edit({ finder = { showPathBar = false } }, "finder.showPathBar", nil, {}), {}, "nothing shared to take back")
end)

t.done("macprefs")
