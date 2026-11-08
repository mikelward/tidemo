-- Caps Lock sending F18, set by tide with hidutil (capslock.lua).

local t = require("t")
local capslock = require("tide.capslock")

-- hidutil's output for setup-macos's rotation, as an NSArray's
-- description prints it.
local ROTATION = [[
(
        {
        HIDKeyboardModifierMappingDst = 30064771299;
        HIDKeyboardModifierMappingSrc = 30064771296;
    },
        {
        HIDKeyboardModifierMappingSrc = 30064771299;
        HIDKeyboardModifierMappingDst = 30064771298;
    }
)
]]

t.test("reads hidutil's mapping, none or some", function()
    t.eq(capslock.parse("(null)\n"), {})
    t.eq(capslock.parse(""), {})
    t.eq(capslock.parse(ROTATION), {
        { src = 0x7000000E0, dst = 0x7000000E3 },
        { src = 0x7000000E3, dst = 0x7000000E2 },
    })
    local list, why = capslock.parse("Error: no such property")
    t.eq(list, nil)
    t.eq(why:find("not a list", 1, true) ~= nil, true, why)
    list, why = capslock.parse("( { HIDKeyboardModifierMappingSrc = 1; } )")
    t.eq(list, nil)
    t.eq(why:find("without a source and destination", 1, true) ~= nil, true, why)
end)

t.test("adds Caps Lock to F18 to what's there, and leaves a Caps Lock already mapped", function()
    local rotation = capslock.parse(ROTATION)
    local new = capslock.with_compose(rotation)
    t.eq(#new, 3)
    t.eq(new[1], rotation[1], "the rotation stays")
    t.eq(new[3], { src = capslock.CAPS_LOCK, dst = capslock.F18 })
    t.eq(capslock.with_compose(new), nil, "already Compose")
    t.eq(capslock.with_compose({ { src = capslock.CAPS_LOCK, dst = 0x700000029 } }), nil, "yours: Caps Lock to Escape")
    t.eq(#capslock.with_compose({}), 1)
end)

t.test("writes the JSON hidutil --set takes", function()
    t.eq(capslock.json({ { src = capslock.CAPS_LOCK, dst = capslock.F18 } }),
        '{"UserKeyMapping":[{"HIDKeyboardModifierMappingSrc":0x700000039,"HIDKeyboardModifierMappingDst":0x70000006D}]}')
end)

-- hidutil, standing in: `get` is what --get prints, and each call is kept.
local function hidutil(get, codes)
    codes = codes or {}
    local h = { calls = {}, logs = {} }
    function h.run(path, args, done)
        h.calls[#h.calls + 1] = path .. " " .. table.concat(args, " ")
        if args[2] == "--get" then
            done(codes.get or 0, codes.get and "denied" or "", get)
        else
            done(codes.set or 0, codes.set and "denied" or "", "")
        end
        return true
    end
    function h.log(m)
        h.logs[#h.logs + 1] = m
    end
    return h
end

t.test("sets the mapping with Caps Lock added, keeping the rotation", function()
    local h = hidutil(ROTATION)
    local changed
    capslock.apply(h.run, h.log, function(c)
        changed = c
    end)
    t.eq(changed, true)
    t.eq(#h.calls, 2)
    t.eq(h.calls[2], "/usr/bin/hidutil property --set " .. capslock.json({
        { src = 0x7000000E0, dst = 0x7000000E3 },
        { src = 0x7000000E3, dst = 0x7000000E2 },
        { src = capslock.CAPS_LOCK, dst = capslock.F18 },
    }))
    t.eq(h.logs, {})
end)

t.test("sets nothing when Caps Lock is mapped already", function()
    local h = hidutil("( { HIDKeyboardModifierMappingSrc = 30064771129; HIDKeyboardModifierMappingDst = 30064771181; } )")
    local changed
    capslock.apply(h.run, h.log, function(c)
        changed = c
    end)
    t.eq(changed, false)
    t.eq(#h.calls, 1)
end)

t.test("a mapping it can't read, or hidutil failing, is logged and changes nothing", function()
    local h = hidutil("garbage")
    capslock.apply(h.run, h.log)
    t.eq(#h.calls, 1)
    t.eq(h.logs[1]:find("couldn't read the key mapping, so Caps Lock is left as it is", 1, true) ~= nil, true, h.logs[1])
    h = hidutil("(null)", { get = 1 })
    capslock.apply(h.run, h.log)
    t.eq(h.logs[1], "capslock: hidutil --get exited 1: denied")
    h = hidutil("(null)", { set = 2 })
    capslock.apply(h.run, h.log)
    t.eq(h.logs[1], "capslock: hidutil --set exited 2: denied")
    local logs = {}
    capslock.apply(function()
        return false
    end, function(m)
        logs[#logs + 1] = m
    end)
    t.eq(logs, { "capslock: couldn't run /usr/bin/hidutil to read the key mapping" })
end)

t.done("capslock")
