-- ci/tide_defaults.lua, which make check-tide runs through
-- ci/check_defaults.lua: tide for Linux's defaults read from a checkout's
-- files, and tidemo's compared with them.
local t = require("t")
package.path = "ci/?.lua;" .. package.path
local defaults = require("tide_defaults")

-- layout.lua's M.defaults as tide writes it, with `tile_mfact` for tile's.
local function layout_lua(tile_mfact)
    return [[
local M = {}
M.defaults = {
    ultrawide_aspect = 2.1,
    single = { { min_aspect = 2.1, width = 0.8 }, { min_aspect = 3.2, width = 0.6 } },
    modes = { tile = { mfact = ]] .. tile_mfact .. [[, nmaster = 1 }, monocle = {} },
    cycle = { "tile", "threecol", "twocol" },
    mfact_step = 0.025,
}
return M
]]
end

-- A tide checkout's files that tide_defaults.lua reads, in a fresh
-- directory, removed after `f` has it.
local function with_tide(tile_mfact, f)
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p '" .. dir .. "/hypr/tide' '" .. dir .. "/shell/lib'"))
    local function write(path, text)
        local file = assert(io.open(dir .. "/" .. path, "w"))
        file:write(text)
        file:close()
    end
    write("hypr/tide/layout.lua", layout_lua(tile_mfact))
    write("shell/lib/workspacenames.mjs", 'export const DEFAULT_STANDING = Object.freeze(["in", "re"]);\n')
    local ok, err = pcall(f, dir)
    os.execute("rm -rf '" .. dir .. "'")
    assert(ok, err)
end

-- tidemo's defaults, matching the fixture's.
local SAME = {
    {
        from = "hammerspoon/tide/layout.lua",
        values = {
            ultrawide_aspect = 2.1,
            single = { { min_aspect = 2.1, width = 0.8 }, { min_aspect = 3.2, width = 0.6 } },
            modes = { tile = { mfact = 0.55, nmaster = 1 }, monocle = {} },
            cycle = { "tile", "threecol", "twocol" },
            mfact_step = 0.025,
        },
    },
    { from = "hammerspoon/tide/wm.lua", values = { standing = { "in", "re" } } },
}

local function tide(over)
    local out = {
        ultrawide_aspect = 2.1,
        single = { { min_aspect = 2.1, width = 0.8 }, { min_aspect = 3.2, width = 0.6 } },
        modes = { tile = { mfact = 0.55, nmaster = 1 }, monocle = {} },
        cycle = { "tile", "threecol", "twocol" },
        mfact_step = 0.025,
        standing = { "in", "re" },
    }
    for k, v in pairs(over or {}) do
        out[k] = v
    end
    return out
end

t.test("defaults that match pass", function()
    t.eq(defaults.compare("tide for macOS", SAME, tide()), {})
end)

t.test("a default that drifts fails, naming the setting and both values", function()
    t.eq(defaults.compare("tide for macOS", SAME, tide({ modes = { tile = { mfact = 0.6, nmaster = 1 } } })),
        { "modes.tile.mfact: tide for macOS 0.55 (hammerspoon/tide/layout.lua), tide for Linux 0.6" })
    t.eq(defaults.compare("tide for macOS", SAME, tide({ standing = { "in" } })),
        { 'standing: tide for macOS {"in","re"} (hammerspoon/tide/wm.lua), tide for Linux {"in"}' })
end)

t.test("a default tide doesn't have fails, so a rename in tide is seen", function()
    t.eq(defaults.compare("tide for macOS", { { from = "x.lua", values = { mfact_stpe = 0.025 } } }, tide()),
        { "mfact_stpe: tide for macOS 0.025 (x.lua), but tide for Linux has no such default" })
end)

t.test("an exception allows the difference it names, and fails once either side moves", function()
    local exceptions = { cycle = { ours = { "tile", "monocle" }, tide = { "tile", "threecol", "twocol" } } }
    local function ours(cycle)
        return { { from = "layout.lua", values = { cycle = cycle } } }
    end
    t.eq(defaults.compare("tide for macOS", ours({ "tile", "monocle" }), tide(), exceptions), {})
    local now = defaults.compare("tide for macOS", ours({ "tile", "threecol", "twocol" }), tide(), exceptions)
    assert(now[1]:find("take it out of the exceptions", 1, true), now[1])
    local moved = defaults.compare("tide for macOS", ours({ "tile" }), tide(), exceptions)
    assert(moved[1]:find("but the exception allows", 1, true), moved[1])
    t.eq(defaults.compare("tide for macOS", {}, tide(), exceptions), { "cycle: an exception for a setting tide for macOS doesn't compare" })
end)

-- Reading a checkout takes node, for the standing workspaces.
if io.popen("command -v node"):read("l") then
    t.test("a checkout whose defaults match passes, and one that drifts fails", function()
        with_tide("0.55", function(dir)
            local errors = {}
            t.eq(defaults.check("tide for macOS", SAME, dir, {}, function(s) errors[#errors + 1] = s end), true)
            t.eq(errors, {})
        end)
        with_tide("0.6", function(dir)
            local errors = {}
            t.eq(defaults.check("tide for macOS", SAME, dir, {}, function(s) errors[#errors + 1] = s end), false)
            t.eq(errors, { "check_defaults: modes.tile.mfact: tide for macOS 0.55 (hammerspoon/tide/layout.lua), tide for Linux 0.6\n" })
        end)
    end)
elseif os.getenv("TIDE_NEED_NODE") then
    error("node is needed to read a tide checkout")
else
    print("check_defaults: a checkout's reading skipped, no node")
end

t.test("a checkout missing layout.lua fails, naming it", function()
    local errors = {}
    t.eq(defaults.check("tide for macOS", SAME, "/nonexistent", {}, function(s) errors[#errors + 1] = s end), false)
    assert(errors[1]:find("can't load tide for Linux's /nonexistent/hypr/tide/layout.lua", 1, true), errors[1])
end)

t.done("check_defaults")
