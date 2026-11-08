-- State made encodable for tide's pages (jsonsafe.lua).

local t = require("t")
local jsonsafe = require("tide.jsonsafe")

local function clean(v)
    local said = {}
    local out = jsonsafe.clean(v, function(path, why)
        said[#said + 1] = path .. ": " .. why
    end)
    return out, said
end

t.test("what JSON holds passes as it is", function()
    local v = { workspaces = { { n = "in", current = true, apps = {} } }, title = "x", n = 3 }
    local out, said = clean(v)
    t.eq(out, v)
    t.eq(said, {})
end)

t.test("a NaN or an infinity is left out, saying where", function()
    local out, said = clean({ icons = { cpu = { value = 0 / 0, text = "–" } }, big = math.huge })
    t.eq(out, { icons = { cpu = { text = "–" } } })
    table.sort(said)
    t.eq(#said, 2)
    t.eq(said[1]:match("^state%.big: not a number") ~= nil, true, said[1])
    t.eq(said[2]:match("^state%.icons%.cpu%.value: not a number") ~= nil, true, said[2])
end)

t.test("a function is left out, and a list closes up", function()
    local out, said = clean({ list = { 1, print, 3 } })
    t.eq(out, { list = { 1, 3 } })
    t.eq(said, { "state.list[2]: a function" })
end)

t.test("a table with number keys that aren't 1…n gets string keys", function()
    local out, said = clean({ wins = { [42] = true, [7] = false } })
    t.eq(out, { wins = { ["42"] = true, ["7"] = false } })
    t.eq(said, { "state.wins: keys that are neither 1…n nor all strings, sent as strings" })
end)

t.test("text that isn't UTF-8 is mended, the rest of it kept", function()
    local out, said = clean({ title = "caf\xe9 \xe2\x9c\x93 ok" })
    t.eq(out, { title = "caf\u{FFFD} \u{2713} ok" })
    t.eq(said, { "state.title: text that isn't UTF-8, mended" })
    t.eq(clean({ title = "é ✓" }), { title = "é ✓" })
end)

t.test("a table inside itself is left out there", function()
    local a = { name = "a" }
    a.self = a
    local out, said = clean(a)
    t.eq(out, { name = "a" })
    t.eq(said, { "state.self: a table inside itself" })
end)

t.test("the encoder logs each problem once, and says when encoding still fails", function()
    local logs = {}
    local function log(m)
        logs[#logs + 1] = m
    end
    local enc = jsonsafe.encoder(function(v)
        return v.x and "{}" or "[]"
    end, log, "bar")
    t.eq(enc({ x = 0 / 0 }), "[]")
    t.eq(enc({ x = 0 / 0 }), "[]")
    t.eq(#logs, 1, "said once")
    t.eq(logs[1]:match("^bar: state%.x can't be sent as JSON, so it's left out: not a number") ~= nil, true, logs[1])
    local failing = jsonsafe.encoder(function()
        return nil
    end, log, "bar")
    t.eq(failing({}), nil)
    t.eq(logs[2], "bar: couldn't encode its state as JSON: nil")
end)

t.done("jsonsafe")
