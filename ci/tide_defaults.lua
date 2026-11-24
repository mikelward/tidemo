-- tide for Linux's defaults, read from a tide checkout, and a comparison
-- with tidemo's own, so a default that drifts fails make check-tide rather
-- than waiting for a review (ci/check_defaults.lua). tide's layout.lua is
-- loaded as it is, and its standing workspaces and shadow colors are read
-- from shell/lib/workspacenames.mjs and shell/lib/appearance.mjs through
-- node, as check_keymaps.lua reads its key presets.
package.path = "tests/?.lua;" .. package.path
local json = require("json")

local M = { TIDE = "tide for Linux" }

local function quote(s)
    return "'" .. s:gsub("'", "'\\''") .. "'"
end

-- `v` as text, keys sorted, whole numbers without a ".0", so equal
-- values read the same whichever side they came from.
local function show(v)
    if type(v) == "number" then
        return v == math.floor(v) and string.format("%d", v) or string.format("%.14g", v)
    elseif type(v) == "string" then
        return string.format("%q", v)
    elseif type(v) ~= "table" then
        return tostring(v)
    end
    local keys = {}
    for k in pairs(v) do
        keys[#keys + 1] = k
    end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local out = {}
    for _, k in ipairs(keys) do
        out[#out + 1] = (math.type(k) == "integer" and "" or tostring(k) .. "=") .. show(v[k])
    end
    return "{" .. table.concat(out, ",") .. "}"
end
M.show = show

local function is_list(v)
    return type(v) == "table" and v[1] ~= nil
end

-- Each setting in `v` by its dotted path ("modes.tile.mfact"); a list is
-- one setting, compared whole, and an empty table (monocle's) none.
function M.flatten(v, prefix, out)
    prefix, out = prefix or "", out or {}
    for k, x in pairs(v) do
        local path = prefix .. tostring(k)
        if type(x) == "table" and not is_list(x) then
            M.flatten(x, path .. ".", out)
        else
            out[path] = x
        end
    end
    return out
end

local function sorted_keys(t)
    local keys = {}
    for k in pairs(t) do
        keys[#keys + 1] = k
    end
    table.sort(keys)
    return keys
end

-- Where `name`'s defaults differ from tide for Linux's `tide`, as messages
-- naming the setting and both values. `sources` is a list of { from,
-- values }, `from` saying where tidemo keeps them; every setting in
-- `values` must be one of tide's. `exceptions` allows a deliberate
-- difference by path, as { ours, tide }: it passes while both sides hold
-- those values, and fails once either moves, including to agree.
function M.compare(name, sources, tide, exceptions)
    exceptions = exceptions or {}
    local theirs = M.flatten(tide)
    local problems, seen = {}, {}
    for _, source in ipairs(sources) do
        local ours = M.flatten(source.values)
        for _, path in ipairs(sorted_keys(ours)) do
            seen[path] = true
            local value, want, ex = ours[path], theirs[path], exceptions[path]
            local at = string.format("%s: %s %s (%s)", path, name, show(value), source.from)
            if want == nil then
                problems[#problems + 1] = at .. ", but " .. M.TIDE .. " has no such default"
            elseif not ex then
                if show(value) ~= show(want) then
                    problems[#problems + 1] = string.format("%s, %s %s", at, M.TIDE, show(want))
                end
            elseif show(value) == show(want) then
                problems[#problems + 1] = at .. " now matches " .. M.TIDE .. "'s: take it out of the exceptions"
            elseif show(value) ~= show(ex.ours) or show(want) ~= show(ex.tide) then
                problems[#problems + 1] = string.format("%s, %s %s, but the exception allows %s %s and %s %s",
                    at, M.TIDE, show(want), name, show(ex.ours), M.TIDE, show(ex.tide))
            end
        end
    end
    for _, path in ipairs(sorted_keys(exceptions)) do
        if not seen[path] then
            problems[#problems + 1] = path .. ": an exception for a setting " .. name .. " doesn't compare"
        end
    end
    return problems
end

-- What tide's module at `mjs` exports as `name`, read with node: false if
-- it exports nothing by that name (or null), or nil and why if node can't load it.
function M.export(mjs, name)
    -- A path, relative or not, as a file URL: import() takes "tide/..." for
    -- a package.
    local p = io.popen("node --input-type=module -e 'import(\"node:url\").then(u => import(u.pathToFileURL(process.argv[1])))"
        .. ".then(m => process.stdout.write(JSON.stringify([m[process.argv[2]] ?? null])))' " .. quote(mjs) .. " "
        .. quote(name) .. " 2>&1")
    local text = p:read("a")
    if not p:close() then
        return nil, "can't read " .. M.TIDE .. "'s " .. mjs .. " with node: " .. text
    end
    local ok, v = pcall(json.decode, text)
    if not ok or type(v) ~= "table" then
        return nil, "can't read " .. M.TIDE .. "'s " .. mjs .. " with node: " .. text
    end
    -- tests/json.lua reads JSON's null as "null".
    return (v[1] ~= nil and v[1] ~= "null") and v[1] or false
end

-- tide for Linux's defaults in the checkout at `dir`: layout.lua's
-- M.defaults, in its own names, `standing`, the standing workspaces, and
-- `shadow_colors`, the painted shadow's colors by light and dark.
-- Nil and why, if a file can't be read.
function M.read(dir)
    local path = dir .. "/hypr/tide/layout.lua"
    local ok, layout = pcall(dofile, path)
    if not ok then
        return nil, "can't load " .. M.TIDE .. "'s " .. path .. ": " .. tostring(layout)
    end
    if type(layout) ~= "table" or type(layout.defaults) ~= "table" then
        return nil, path .. " has no M.defaults table"
    end
    local standing, why = M.export(dir .. "/shell/lib/workspacenames.mjs", "DEFAULT_STANDING")
    if standing == nil then
        return nil, why
    elseif type(standing) ~= "table" then
        return nil, dir .. "/shell/lib/workspacenames.mjs has no DEFAULT_STANDING list"
    end
    local colors
    colors, why = M.export(dir .. "/shell/lib/appearance.mjs", "SHADOW_COLORS")
    if colors == nil then
        return nil, why
    elseif type(colors) ~= "table" then
        return nil, dir .. "/shell/lib/appearance.mjs has no SHADOW_COLORS"
    end
    local out = {}
    for k, v in pairs(layout.defaults) do
        out[k] = v
    end
    out.standing = standing
    out.shadow_colors = colors
    return out
end

-- The comparison with the checkout at `dir`, written to `err` (stderr by
-- default) a line per difference: true if nothing differs.
function M.check(name, sources, dir, exceptions, err)
    err = err or function(s) io.stderr:write(s) end
    local tide, why = M.read(dir)
    if not tide then
        err("check_defaults: " .. why .. "\n")
        return false
    end
    local problems = M.compare(name, sources, tide, exceptions)
    for _, p in ipairs(problems) do
        err("check_defaults: " .. p .. "\n")
    end
    return #problems == 0
end

return M
