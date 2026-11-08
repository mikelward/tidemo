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

t.done("appkeys")
