-- macOS's own settings that tide keeps (SPEC.md §15): Finder, screenshots,
-- the Dock and Mission Control, windows, dialogs, typing and text, each a
-- setting in tide's macos.json and macos.local.json, shown on the settings
-- window's macOS page, and written to macOS's preferences as the files
-- change. A setting the files leave out is macOS's own, untouched. Pure
-- Lua: the files come in as tables, and what to run goes out as
-- `defaults` arguments, for macprefs_hs.lua to run.

local M = {}

M.FILE = "macos"

-- What a change needs to show: a process tide restarts ("Finder", "Dock",
-- "SystemUIServer"), "apps", for each app as it next opens, or "login".
M.WHEN = {
    Finder = "now",
    Dock = "now",
    SystemUIServer = "now",
    apps = "as apps reopen",
    login = "at next login",
    tide = "now",
}

local G = "NSGlobalDomain"
local DOCK = "com.apple.dock"
local TRACKPADS = { "com.apple.AppleMultitouchTrackpad", "com.apple.driver.AppleBluetoothMultitouch.trackpad" }
local CORNERS = { "tl", "tr", "bl", "br" }

local function same(v)
    return v
end

local function invert(v)
    if v == nil then
        return nil
    end
    return not v
end

-- A key: its `domain` (`host` for -currentHost), `key` and `type`.
local function key(domain, name, type, host)
    return { domain = domain, key = name, type = type, host = host }
end

-- One setting on one key, its value as macOS's (or inverted).
local function one(k, map)
    map = map or same
    return {
        keys = { k },
        to = function(v)
            return { map(v) }
        end,
        from = map,
    }
end

-- The hot corners: off sets each to do nothing; on gives them back to
-- macOS, which has its own for each.
local function hot_corners()
    local keys, off = {}, {}
    for _, c in ipairs(CORNERS) do
        keys[#keys + 1] = key(DOCK, "wvous-" .. c .. "-corner", "int")
        off[#keys] = 1
        keys[#keys + 1] = key(DOCK, "wvous-" .. c .. "-modifier", "int")
        off[#keys] = 0
    end
    return {
        keys = keys,
        to = function(on)
            return on and {} or off
        end,
        from = function(v)
            return v ~= 1
        end,
    }
end

-- Mission Control's and App Exposé's swipes, on the trackpad and the
-- mouse: off turns each off; on gives them back to macOS.
local function swipes()
    local keys, off = {
        key(DOCK, "showMissionControlGestureEnabled", "bool"),
        key(DOCK, "showAppExposeGestureEnabled", "bool"),
    }, { false, false }
    for _, d in ipairs(TRACKPADS) do
        for _, name in ipairs({
            "TrackpadThreeFingerVertSwipeGesture",
            "TrackpadFourFingerVertSwipeGesture",
            "TrackpadThreeFingerHorizSwipeGesture",
            "TrackpadFourFingerHorizSwipeGesture",
        }) do
            keys[#keys + 1] = key(d, name, "int")
            off[#keys] = 0
        end
    end
    keys[#keys + 1] = key("com.apple.driver.AppleBluetoothMultitouch.mouse", "MouseTwoFingerDoubleTapGesture", "int")
    off[#keys] = 0
    return {
        keys = keys,
        to = function(on)
            return on and {} or off
        end,
        from = function(v)
            return v ~= false
        end,
    }
end

-- Open and Save, and Print, dialogs that show their folders and options.
local function expanded()
    local keys = {
        key(G, "NSNavPanelExpandedStateForSaveMode", "bool"),
        key(G, "NSNavPanelExpandedStateForSaveMode2", "bool"),
        key(G, "PMPrintingExpandedStateForPrint", "bool"),
        key(G, "PMPrintingExpandedStateForPrint2", "bool"),
    }
    return {
        keys = keys,
        to = function(v)
            return { v, v, v, v }
        end,
        from = same,
    }
end

-- Windows that open and resize at once: off turns the animations off and
-- makes a resize instant; on gives both back to macOS.
local function window_animations()
    return {
        keys = { key(G, "NSAutomaticWindowAnimationsEnabled", "bool"), key(G, "NSWindowResizeTime", "float") },
        to = function(on)
            return on and {} or { false, 0.001 }
        end,
        from = function(v)
            return v ~= false
        end,
    }
end

local SMOOTHING = { off = 0, light = 1, medium = 2, strong = 3 }

local function smoothing()
    return {
        keys = { key("-g", "AppleFontSmoothing", "int", true) },
        to = function(v)
            return { SMOOTHING[v] }
        end,
        from = function(n)
            for name, v in pairs(SMOOTHING) do
                if v == n then
                    return name
                end
            end
            return nil
        end,
    }
end

local function setting(group, name, label, kind, default, effect, how, extra)
    local s = how
    s.group, s.name, s.label, s.kind, s.default, s.effect = group, group .. "." .. name, label, kind, default, effect
    s.key = name
    for k, v in pairs(extra or {}) do
        s[k] = v
    end
    return s
end

-- The page's groups, in its order.
M.GROUPS = {
    { id = "finder", label = "Finder" },
    { id = "screenshots", label = "Screenshots" },
    { id = "missionControl", label = "Dock and Mission Control" },
    { id = "windows", label = "Windows" },
    { id = "dialogs", label = "Dialogs" },
    { id = "keyboard", label = "Keyboard" },
    { id = "typing", label = "Typing" },
    { id = "text", label = "Text" },
}

-- Every setting, in the page's order: its `group` and `key` in the files
-- (`name` is both), what the page calls it, its `kind` ("bool", "choice" or
-- "folder"), macOS's own value, and `effect`, when a change shows (M.WHEN).
-- One that's `own` has no `defaults` keys: tide applies it itself, with
-- the values macprefs_hs hands it (`own`), as it starts, after a wake and
-- as the files change.
M.SETTINGS = {
    setting("finder", "showHiddenFiles", "Show hidden files", "bool", false, "Finder",
        one(key("com.apple.finder", "AppleShowAllFiles", "bool"))),
    setting("finder", "showPathBar", "Show the path bar", "bool", false, "Finder",
        one(key("com.apple.finder", "ShowPathbar", "bool"))),
    setting("finder", "showExtensions", "Show every file's extension", "bool", false, "Finder",
        one(key(G, "AppleShowAllExtensions", "bool"))),
    setting("finder", "animations", "Animate Finder's windows", "bool", true, "Finder",
        one(key("com.apple.finder", "DisableAllAnimations", "bool"), invert)),
    setting("screenshots", "folder", "Save screenshots to", "folder", "~/Desktop", "SystemUIServer",
        one(key("com.apple.screencapture", "location", "string"))),
    setting("screenshots", "thumbnail", "Show a thumbnail after taking one", "bool", true, "SystemUIServer",
        one(key("com.apple.screencapture", "show-thumbnail", "bool"))),
    setting("missionControl", "reorderSpaces", "Rearrange Spaces by most recent use", "bool", true, "Dock",
        one(key(DOCK, "mru-spaces", "bool"))),
    setting("missionControl", "hotCorners", "Hot corners", "bool", true, "Dock", hot_corners()),
    setting("missionControl", "swipes", "Mission Control and App Exposé swipes", "bool", true, "login", swipes()),
    setting("windows", "stageManager", "Stage Manager", "bool", false, "login",
        one(key("com.apple.WindowManager", "GloballyEnabled", "bool"))),
    setting("windows", "tileByDragging", "Tile a window dragged to the screen's edge", "bool", true, "login",
        one(key("com.apple.WindowManager", "EnableTilingByEdgeDrag", "bool"))),
    setting("windows", "tileWithOption", "Tile a window dragged with Option", "bool", true, "login",
        one(key("com.apple.WindowManager", "EnableTilingOptionAccelerator", "bool"))),
    setting("windows", "clickToShowDesktop", "Click the wallpaper to show the desktop", "bool", true, "login",
        one(key("com.apple.WindowManager", "EnableStandardClickToShowDesktop", "bool"))),
    setting("windows", "animations", "Animate windows opening and resizing", "bool", true, "apps",
        window_animations()),
    setting("dialogs", "expanded", "Open dialogs expanded", "bool", false, "apps", expanded()),
    setting("dialogs", "saveToICloud", "Save new documents to iCloud", "bool", true, "apps",
        one(key(G, "NSDocumentSaveNewDocumentsToCloud", "bool"))),
    setting("typing", "autocorrect", "Correct spelling", "bool", true, "apps",
        one(key(G, "NSAutomaticSpellingCorrectionEnabled", "bool"))),
    setting("typing", "capitalize", "Capitalize sentences", "bool", true, "apps",
        one(key(G, "NSAutomaticCapitalizationEnabled", "bool"))),
    setting("typing", "smartQuotes", "Smart quotes", "bool", true, "apps",
        one(key(G, "NSAutomaticQuoteSubstitutionEnabled", "bool"))),
    setting("typing", "smartDashes", "Smart dashes", "bool", true, "apps",
        one(key(G, "NSAutomaticDashSubstitutionEnabled", "bool"))),
    setting("typing", "doubleSpacePeriod", "Add a period with a double space", "bool", true, "apps",
        one(key(G, "NSAutomaticPeriodSubstitutionEnabled", "bool"))),
    -- Ctrl, Win and Alt where a PC keyboard has them, on every keyboard
    -- (capslock.lua, karabiner.lua).
    setting("keyboard", "type", "Keyboard", "choice", "mac", "tide", { keys = {}, own = true, choices = { "mac", "pc" } }),
    -- Caps Lock sending F18, tide's Compose (capslock.lua).
    setting("keyboard", "capsLockCompose", "Caps Lock is Compose", "bool", false, "tide", { keys = {}, own = true }),
    setting("text", "smoothing", "Font smoothing", "choice", "medium", "apps", smoothing(),
        { choices = { "off", "light", "medium", "strong" } }),
}

M.BY_NAME = {}
for _, s in ipairs(M.SETTINGS) do
    M.BY_NAME[s.name] = s
end

-- What tide records for a setting it couldn't finish applying: no value
-- a setting takes, so the next plan runs it again, or gives every one of
-- its keys back to macOS once the files leave it out.
M.PARTIAL = "tide:partial"

-- The value that leaves a setting to macOS, so a local file can take back
-- one the shared file sets.
M.MACOS = "macos"

-- Whether `v` is a value `s` takes.
local function valid(s, v)
    if v == M.MACOS then
        return true
    end
    if s.kind == "bool" then
        return type(v) == "boolean"
    end
    if s.kind == "choice" then
        for _, c in ipairs(s.choices) do
            if v == c then
                return true
            end
        end
        return false
    end
    -- A folder: absolute, or from ~/.
    return type(v) == "string" and (v:sub(1, 1) == "/" or v:sub(1, 2) == "~/") and not v:find("[%c]")
end

-- What a setting takes, said for an error.
local function wanted(s)
    if s.kind == "bool" then
        return 'true, false or "macos"'
    end
    if s.kind == "choice" then
        return table.concat(s.choices, ", ") .. ' or "macos"'
    end
    return 'a folder, from / or ~/, or "macos"'
end

M.valid = valid

-- One file's settings, `obj` as decoded, checked: name -> value, and the
-- errors, each naming `file` and the setting.
function M.check(obj, file)
    local out, errors = {}, {}
    if obj == nil then
        return out, errors
    end
    if type(obj) ~= "table" then
        return out, { file .. " isn't a JSON object" }
    end
    local groups = {}
    for name in pairs(obj) do
        groups[#groups + 1] = name
    end
    table.sort(groups, function(a, b)
        return tostring(a) < tostring(b)
    end)
    for _, g in ipairs(groups) do
        local values = obj[g]
        if type(values) ~= "table" then
            errors[#errors + 1] = file .. ": " .. tostring(g) .. " isn't a JSON object"
        else
            local names = {}
            for k in pairs(values) do
                names[#names + 1] = k
            end
            table.sort(names, function(a, b)
                return tostring(a) < tostring(b)
            end)
            for _, k in ipairs(names) do
                local name = tostring(g) .. "." .. tostring(k)
                local s = M.BY_NAME[name]
                if not s then
                    errors[#errors + 1] = file .. ": " .. name .. " isn't a setting"
                elseif not valid(s, values[k]) then
                    errors[#errors + 1] = file .. ": " .. name .. " takes " .. wanted(s)
                else
                    out[name] = values[k]
                end
            end
        end
    end
    return out, errors
end

-- The settings in effect from macos.json's `shared` and macos.local.json's
-- `local_` (each decoded, or nil), the local one's laid over the shared
-- one's, setting by setting: name -> value, and the errors.
function M.merge(shared, local_)
    local a, ea = M.check(shared, M.FILE .. ".json")
    local b, eb = M.check(local_, M.FILE .. ".local.json")
    for k, v in pairs(b) do
        a[k] = v
    end
    for k, v in pairs(a) do
        if v == M.MACOS then
            a[k] = nil
        end
    end
    for _, e in ipairs(eb) do
        ea[#ea + 1] = e
    end
    return a, ea
end

-- `path` as macOS takes it: ~/ from `home`.
local function expand(path, home)
    if type(path) == "string" and path:sub(1, 2) == "~/" then
        return home .. path:sub(2)
    end
    return path
end

-- `defaults` arguments writing `value` to key `k`, or deleting it for nil.
function M.command(k, value)
    local args = {}
    if k.host then
        args[#args + 1] = "-currentHost"
    end
    if value == nil then
        args[#args + 1] = "delete"
        args[#args + 1] = k.domain
        args[#args + 1] = k.key
        return args, true
    end
    args[#args + 1] = "write"
    args[#args + 1] = k.domain
    args[#args + 1] = k.key
    args[#args + 1] = "-" .. k.type
    if k.type == "bool" then
        args[#args + 1] = value and "true" or "false"
    elseif k.type == "int" then
        args[#args + 1] = tostring(math.tointeger(value) or value)
    else
        args[#args + 1] = tostring(value)
    end
    return args, false
end

-- What to do to bring macOS to `values` (M.merge's) from `applied`, what
-- tide last set (name -> value; nil for left to macOS): a step for each
-- setting that changed, in the page's order, each { name, value, effect,
-- commands }, a command { args, delete }. A setting taken out of the files
-- gives its keys back to macOS. `home` expands a folder's ~/.
function M.plan(values, applied, home)
    local steps = {}
    for _, s in ipairs(M.SETTINGS) do
        local want, had = values[s.name], applied[s.name]
        if want ~= had and not s.own then
            local per = want ~= nil and s.to(want) or {}
            local commands = {}
            for i, k in ipairs(s.keys) do
                local v = per[i]
                if s.kind == "folder" then
                    v = expand(v, home)
                end
                local args, delete = M.command(k, v)
                commands[#commands + 1] = { args = args, delete = delete }
            end
            steps[#steps + 1] = { name = s.name, value = want, effect = s.effect, commands = commands }
        end
    end
    return steps
end

-- What macOS has for setting `s`, from `defaults read`'s exit code and
-- output for its first key, as the setting's value: nil when it can't be
-- told, so the page shows macOS's own.
function M.parse(s, code, out)
    local k = s.keys[1]
    if code ~= 0 then
        return s.from(nil)
    end
    out = (out or ""):gsub("%s+$", "")
    local v
    if k.type == "bool" then
        if out == "1" or out == "true" then
            v = true
        elseif out == "0" or out == "false" then
            v = false
        end
    elseif k.type == "int" then
        v = math.tointeger(tonumber(out))
    elseif k.type == "float" then
        v = tonumber(out)
    else
        v = out
    end
    if v == nil then
        return nil
    end
    return s.from(v)
end

-- `defaults read` arguments for setting `s`'s first key.
function M.read_args(s)
    local k = s.keys[1]
    local args = {}
    if k.host then
        args[#args + 1] = "-currentHost"
    end
    args[#args + 1] = "read"
    args[#args + 1] = k.domain
    args[#args + 1] = k.key
    return args
end

-- The macOS page: each group's rows, each { name, label, kind, value,
-- set, when, choices }. `value` is the files' (`values`), else what macOS
-- has (`live`), else macOS's own; `set` says the files set it, so it can
-- be given back to macOS. A setting named in `hide` isn't shown, and a
-- group left empty isn't either.
function M.page(values, live, errors, hide)
    hide = hide or {}
    local groups = {}
    for _, g in ipairs(M.GROUPS) do
        local rows = {}
        for _, s in ipairs(M.SETTINGS) do
            if s.group == g.id and not hide[s.name] then
                local v = values[s.name]
                local set = v ~= nil
                if not set then
                    v = live[s.name]
                    if v == nil then
                        v = s.default
                    end
                end
                rows[#rows + 1] = {
                    name = s.name,
                    label = s.label,
                    kind = s.kind,
                    value = v,
                    set = set,
                    when = M.WHEN[s.effect],
                    choices = s.choices,
                }
            end
        end
        if #rows > 0 then
            groups[#groups + 1] = { label = g.label, rows = rows }
        end
    end
    return { groups = groups, error = table.concat(errors or {}, "; ") }
end

-- macos.local.json's object `obj` (decoded, or nil) with setting `name` set
-- to `value`, or given back to macOS for nil: taken out, or "macos" when
-- `shared` (macos.json's object, decoded) sets it, so it's left to macOS
-- all the same. A group left empty is taken out too. Returns the object,
-- or nil and why.
function M.edit(obj, name, value, shared)
    local s = M.BY_NAME[name]
    if not s then
        return nil, tostring(name) .. " isn't a setting"
    end
    if value ~= nil and not valid(s, value) then
        return nil, s.label .. " takes " .. wanted(s)
    end
    if obj == nil then
        obj = {}
    end
    if type(obj) ~= "table" then
        return nil, M.FILE .. ".local.json isn't a JSON object"
    end
    local group = obj[s.group]
    if group ~= nil and type(group) ~= "table" then
        return nil, M.FILE .. ".local.json: " .. s.group .. " isn't a JSON object"
    end
    group = group or {}
    if value == nil then
        local from
        if type(shared) == "table" and type(shared[s.group]) == "table" then
            from = shared[s.group][s.key]
        end
        if from ~= nil and from ~= M.MACOS then
            value = M.MACOS
        end
    end
    group[s.key] = value
    if next(group) == nil then
        obj[s.group] = nil
    else
        obj[s.group] = group
    end
    return obj
end

-- The processes to restart for `steps` (M.plan's) that ran, once each, in
-- the order first needed, and the later effects, "apps" and "login", each
-- once.
function M.effects(steps)
    local restart, later, seen = {}, {}, {}
    for _, step in ipairs(steps) do
        local e = step.effect
        if not seen[e] then
            seen[e] = true
            if M.WHEN[e] == "now" then
                restart[#restart + 1] = e
            else
                later[#later + 1] = e
            end
        end
    end
    return restart, later
end

return M
