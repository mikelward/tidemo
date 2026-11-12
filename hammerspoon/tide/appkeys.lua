-- Your own app keys (SPEC.md §7.2): apps.json and apps.local.json in
-- tide's folder, { "apps": [ { "keys": "SUPER + M", "app": "Spotify" } ] },
-- each opening an app by its name or bundle ID, as tide's app keys do:
-- its window forward with its workspace, or the app launched. "new": true
-- opens a new window every time, as Super+T does. Keys are Hyprland's
-- strings, as keys.json's are (shortcuts.lua). Yours come before tide's,
-- so one on tide's keys takes them. apps.local.json's list replaces
-- apps.json's whole. Pure Lua: files, decoding and finding an app's
-- bundle ID come from the caller.

local shortcuts = require("tide.shortcuts")
local mute = require("tide.mute")

local M = {}

M.FILE = "apps.json"
M.LOCAL_FILE = "apps.local.json"
M.MAX = 50

-- What could be a bundle ID, rather than an app's name: dotted, with no
-- spaces. An app's name can read so too, as zoom.us and draw.io do, so an
-- app of that name comes first (M.bindings).
local function is_bundle(s)
    return s:match("^[%w%-]+%.[%w%.%-]+$") ~= nil
end

-- One file's decoded JSON as a list of { keys, app, new }, or nil and why.
function M.parse(v, file)
    if type(v) ~= "table" or (next(v) ~= nil and mute.is_list(v)) then
        return nil, file .. ": not a JSON object"
    end
    for k in pairs(v) do
        if k ~= "apps" then
            return nil, file .. ": unknown setting " .. tostring(k)
        end
    end
    local list = v.apps or {}
    if type(list) ~= "table" or (next(list) ~= nil and not mute.is_list(list)) then
        return nil, file .. ": apps should be a list"
    end
    if #list > M.MAX then
        return nil, string.format("%s: %d apps, more than %d", file, #list, M.MAX)
    end
    local out = {}
    for i, e in ipairs(list) do
        local where = string.format("%s: apps[%d]", file, i)
        if type(e) ~= "table" or mute.is_list(e) and next(e) ~= nil then
            return nil, where .. " isn't an object"
        end
        for k in pairs(e) do
            if k ~= "keys" and k ~= "app" and k ~= "new" then
                return nil, where .. ": unknown setting " .. tostring(k)
            end
        end
        if type(e.keys) ~= "string" or not e.keys:match("%S") then
            return nil, where .. " has no keys"
        end
        if type(e.app) ~= "string" or not e.app:match("%S") or e.app:match('[%c"\\/]') then
            return nil, where .. " has no app"
        end
        if e.new ~= nil and type(e.new) ~= "boolean" then
            return nil, where .. ": new should be true or false"
        end
        out[#out + 1] = { keys = e.keys, app = e.app:match("^%s*(.-)%s*$"), new = e.new == true }
    end
    return out
end

-- Both files' entries, apps.local.json's in place of apps.json's when it
-- has any; or nil and why.
function M.load(dir, read, decode)
    local list = {}
    for _, name in ipairs({ M.FILE, M.LOCAL_FILE }) do
        local text = read(dir .. "/" .. name)
        if text and text:match("%S") then
            local v, err = M.parse(decode(text), name)
            if not v then
                return nil, err
            end
            list = v
        end
    end
    return list
end

-- The list as apps.local.json's text, entries in order.
function M.text(list, quote)
    local rows = {}
    for i, e in ipairs(list) do
        rows[i] = "    { \"keys\": " .. quote(e.keys) .. ", \"app\": " .. quote(e.app)
            .. (e.new and ", \"new\": true" or "") .. " }"
    end
    if #rows == 0 then
        return '{\n  "apps": []\n}\n'
    end
    return '{\n  "apps": [\n' .. table.concat(rows, ",\n") .. "\n  ]\n}\n"
end

-- Apply `fn` to the list in effect, which gives back the new list, or nil
-- and why, and write apps.local.json whole. Returns the new list, or nil
-- and why, writing nothing.
function M.edit(dir, read, decode, quote, write, fn)
    local list, err = M.load(dir, read, decode)
    if not list then
        return nil, err .. ". Fix the file to change your app keys here"
    end
    local copy = {}
    for i, e in ipairs(list) do
        copy[i] = { keys = e.keys, app = e.app, new = e.new }
    end
    local new, why = fn(copy)
    if not new then
        return nil, why
    end
    if #new > M.MAX then
        return nil, "that's more than " .. M.MAX .. " app keys"
    end
    local path = dir .. "/" .. M.LOCAL_FILE
    local ok, werr = write(path, M.text(new, quote))
    if not ok then
        return nil, "couldn't write " .. path .. ": " .. tostring(werr)
    end
    return new
end

-- Why `keys` and `app` can't be an app key, or nil when they can:
-- `bundle_of` as M.bindings takes it.
function M.check(keys, app, bundle_of)
    if type(keys) ~= "string" or not keys:match("%S") then
        return "type the keys, such as Super+M"
    end
    if type(app) ~= "string" or not app:match("%S") or app:match('[%c"\\/]') then
        return "type an app's name, such as Spotify"
    end
    local _, why = shortcuts.from_hypr(keys)
    if why then
        return keys .. ": " .. why
    end
    app = app:match("^%s*(.-)%s*$")
    if not is_bundle(app) and not bundle_of(app) then
        return "no app is called " .. app
    end
    return nil
end

-- The entries as keys.lua map bindings, { key, shift, action = "app",
-- arg = spec, does }, and what couldn't be one, each said once. `bundle_of`
-- gives an app name's bundle ID, or nil when there's no such app. An app
-- called what `app` says is the one meant, even where its name reads like a
-- bundle ID: Zoom's app is zoom.us, and its bundle ID us.zoom.xos.
function M.bindings(list, bundle_of)
    local out, problems = {}, {}
    for _, e in ipairs(list) do
        local b, why = shortcuts.from_hypr(e.keys)
        local bundle = bundle_of(e.app) or (is_bundle(e.app) and e.app or nil)
        if not b then
            problems[#problems + 1] = e.app .. " on " .. e.keys .. ": " .. why
        elseif not bundle then
            problems[#problems + 1] = e.app .. " on " .. e.keys .. ": no app is called " .. e.app
        else
            out[#out + 1] = {
                key = b.key, shift = b.shift, action = "app", does = e.app,
                -- Karabiner's Super+Backspace arrives as Super+F19, as
                -- close's does (shortcuts.apply).
                karabiner_key = b.key == "delete" and "f19" or nil,
                arg = { bundle = bundle, new = e.new or nil, name = e.app },
            }
        end
    end
    return out, problems
end

return M
