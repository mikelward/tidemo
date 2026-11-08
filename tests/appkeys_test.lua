-- Your own app keys, apps.json (appkeys.lua).

local t = require("t")
local json = require("json")
local appkeys = require("tide.appkeys")

local DIR = "/Users/me/.config/tide"

local function files(map)
    return function(path)
        return map[path:match("[^/]+$")]
    end
end

local function bundle_of(name)
    return ({ Spotify = "com.spotify.client", Safari = "com.apple.Safari" })[name]
end

t.test("an app by name or bundle ID, on its keys, Shift or not, a new window if asked", function()
    local list = assert(appkeys.load(DIR, files({
        ["apps.json"] = json.encode({ apps = {
            { keys = "SUPER + M", app = "Spotify" },
            { keys = "SUPER + SHIFT + S", app = "com.apple.Safari", new = true },
        } }),
    }), json.decode))
    local b, problems = appkeys.bindings(list, bundle_of)
    t.eq(problems, {})
    t.eq(#b, 2)
    t.eq(b[1].key, "m")
    t.eq(b[1].shift, false)
    t.eq(b[1].action, "app")
    t.eq(b[1].arg, { bundle = "com.spotify.client", name = "Spotify" })
    t.eq(b[1].does, "Spotify")
    t.eq(b[2].key, "s")
    t.eq(b[2].shift, true)
    t.eq(b[2].arg, { bundle = "com.apple.Safari", new = true, name = "com.apple.Safari" })
end)

-- Karabiner sends Super+Backspace as Super+F19, as it does for close.
t.test("an app on Super+Backspace takes Karabiner's F19", function()
    local b = appkeys.bindings({ { keys = "SUPER + BackSpace", app = "Spotify" } }, bundle_of)
    t.eq(b[1].key, "delete")
    t.eq(b[1].karabiner_key, "f19")
    b = appkeys.bindings({ { keys = "SUPER + M", app = "Spotify" } }, bundle_of)
    t.eq(b[1].karabiner_key, nil)
end)

t.test("apps.local.json's list replaces apps.json's", function()
    local list = appkeys.load(DIR, files({
        ["apps.json"] = json.encode({ apps = { { keys = "SUPER + M", app = "Spotify" } } }),
        ["apps.local.json"] = json.encode({ apps = { { keys = "SUPER + J", app = "Safari" } } }),
    }), json.decode)
    t.eq(list, { { keys = "SUPER + J", app = "Safari", new = false } })
end)

t.test("no files is no app keys", function()
    t.eq(appkeys.load(DIR, files({}), json.decode), {})
end)

t.test("an app that isn't there, or keys a Mac can't have, is said, and the rest bind", function()
    local b, problems = appkeys.bindings({
        { keys = "SUPER + M", app = "Nope" },
        { keys = "CTRL + M", app = "Spotify" },
        { keys = "SUPER + K", app = "Spotify" },
    }, bundle_of)
    t.eq(#b, 1)
    t.eq(b[1].key, "k")
    t.eq(problems, {
        "Nope on SUPER + M: no app is called Nope",
        "Spotify on CTRL + M: a Mac binding needs Super",
    })
end)

t.test("a file that's wrong names itself and what's wrong", function()
    local function load(text)
        return appkeys.load(DIR, files({ ["apps.json"] = text }), json.decode)
    end
    local _, why = load('[1]')
    t.eq(why, "apps.json: not a JSON object")
    _, why = load('{"keys": []}')
    t.eq(why, "apps.json: unknown setting keys")
    _, why = load('{"apps": [{"app": "Spotify"}]}')
    t.eq(why, "apps.json: apps[1] has no keys")
    _, why = load('{"apps": [{"keys": "SUPER + M"}]}')
    t.eq(why, "apps.json: apps[1] has no app")
    _, why = load('{"apps": [{"keys": "SUPER + M", "app": "Spotify", "new": "yes"}]}')
    t.eq(why, "apps.json: apps[1]: new should be true or false")
    _, why = load('{"apps": [{"keys": "SUPER + M", "app": "Spotify", "colour": "red"}]}')
    t.eq(why, "apps.json: apps[1]: unknown setting colour")
end)

-- The settings window's edits, written to apps.local.json.
t.test("an edit writes the list in effect, changed, to apps.local.json", function()
    local disk = { ["apps.json"] = json.encode({ apps = { { keys = "SUPER + M", app = "Spotify" } } }) }
    local written
    local function write(path, text)
        written = path
        disk[path:match("[^/]+$")] = text
        return true
    end
    local new = appkeys.edit(DIR, files(disk), json.decode, json.encode, write, function(list)
        list[#list + 1] = { keys = "Super+S", app = "Safari", new = true }
        return list
    end)
    t.eq(written, DIR .. "/apps.local.json")
    t.eq(#new, 2)
    t.eq(appkeys.load(DIR, files(disk), json.decode), {
        { keys = "SUPER + M", app = "Spotify", new = false },
        { keys = "Super+S", app = "Safari", new = true },
    })
    -- Removing the last leaves an empty list, which keeps apps.json's out.
    appkeys.edit(DIR, files(disk), json.decode, json.encode, write, function()
        return {}
    end)
    t.eq(appkeys.load(DIR, files(disk), json.decode), {})
end)

t.test("an edit that fails, or a file that's wrong, writes nothing", function()
    local wrote = false
    local function write()
        wrote = true
        return true
    end
    local _, why = appkeys.edit(DIR, files({ ["apps.json"] = "[1]" }), json.decode, json.encode, write, function(l)
        return l
    end)
    t.eq(why, "apps.json: not a JSON object. Fix the file to change your app keys here")
    _, why = appkeys.edit(DIR, files({}), json.decode, json.encode, write, function()
        return nil, "no"
    end)
    t.eq(why, "no")
    t.eq(wrote, false)
end)

t.test("what can't be an app key says why", function()
    t.eq(appkeys.check("Super+M", "Spotify", bundle_of), nil)
    t.eq(appkeys.check("Super+M", "com.example.app", bundle_of), nil, "a bundle ID needs no lookup")
    t.eq(appkeys.check("", "Spotify", bundle_of), "type the keys, such as Super+M")
    t.eq(appkeys.check("Super+M", " ", bundle_of), "type an app's name, such as Spotify")
    t.eq(appkeys.check("Ctrl+M", "Spotify", bundle_of), "Ctrl+M: a Mac binding needs Super")
    t.eq(appkeys.check("Super+M", "Nope", bundle_of), "no app is called Nope")
end)

t.done("appkeys")
