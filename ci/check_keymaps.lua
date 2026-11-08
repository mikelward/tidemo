-- make check-tide: hammerspoon/tide/keymaps.lua's presets are tide's
-- shell/lib/keymaps.mjs's (the path given), read through node: the same
-- presets in the same order, each with the same label and keys.
package.path = "hammerspoon/?.lua;tests/?.lua;" .. package.path
local keymaps = require("tide.keymaps")
local json = require("json")

local path = assert(arg[1], "usage: check_keymaps.lua TIDE/shell/lib/keymaps.mjs")
-- A path, relative or not, as a file URL: import() takes "tide/..." for a
-- package.
local p = io.popen("node --input-type=module -e 'import(\"node:url\").then(u => import(u.pathToFileURL(process.argv[1]))).then(m => "
    .. "process.stdout.write(JSON.stringify({ names: m.PRESET_NAMES, presets: m.PRESETS })))' "
    .. "'" .. path:gsub("'", "'\\''") .. "'")
local text = p:read("a")
if not p:close() or text == "" then
    io.stderr:write("check_keymaps: couldn't read " .. path .. " with node\n")
    os.exit(1)
end
local tide = json.decode(text)

local function show(v)
    if type(v) ~= "table" then
        return tostring(v)
    end
    local keys = {}
    for k in pairs(v) do
        keys[#keys + 1] = k
    end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local out = {}
    for _, k in ipairs(keys) do
        out[#out + 1] = tostring(k) .. "=" .. show(v[k])
    end
    return "{" .. table.concat(out, ",") .. "}"
end

local ok = true
local function same(a, b, what)
    if show(a) ~= show(b) then
        io.stderr:write("check_keymaps: " .. what .. " differs from tide's:\n  tide: " .. show(a) .. "\n  here: " .. show(b) .. "\n")
        ok = false
    end
end
same(tide.names, keymaps.NAMES, "the preset list")
for _, name in ipairs(tide.names) do
    same(tide.presets[name], keymaps.PRESETS[name], name)
end
os.exit(ok and 0 or 1)
