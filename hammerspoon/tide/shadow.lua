-- Window shadows (SPEC.md §5.7), from tide's appearance.json, as tide for
-- Linux's Borders page sets them (tide SPEC.md §6.2): `shadows`, which
-- windows cast one, and `shadowSize`, how far it reaches. macOS draws every
-- window's own shadow and gives no way to choose which (§2.4), so tide can
-- only turn them all off (hs.window.setShadows) and paint the focused
-- window's itself, on the dim's layer (dim.layer). Pure Lua: dim_hs.lua
-- draws what this says.

local M = {}

-- tide-appearance.js's SHADOWS, SHADOWS_DEFAULT, SHADOW_SIZE and
-- SHADOW_SIZE_MAX.
M.MODES = { none = true, floating = true, focused = true, all = true }
M.DEFAULT = "focused"
M.SIZE = 16
M.SIZE_MAX = 32
M.SHARED_FILE = "appearance.json"
M.LOCAL_FILE = "appearance.local.json"

-- { mode, size } from appearance.json's and appearance.local.json's texts
-- (nil for a file that isn't there), the local one's over the shared one's,
-- and what's wrong with either. A bad value is left out, so the one before
-- it stands. `decode` is hs.json.decode.
function M.load(shared, own, decode)
    local out, errors = { mode = M.DEFAULT, size = M.SIZE }, {}
    for _, f in ipairs({ { M.SHARED_FILE, shared }, { M.LOCAL_FILE, own } }) do
        local name, text = f[1], f[2]
        if text then
            local ok, t = pcall(decode, text)
            if not ok or type(t) ~= "table" then
                errors[#errors + 1] = name .. " isn't a JSON object"
            else
                local mode, size = t.shadows, t.shadowSize
                if mode ~= nil then
                    if M.MODES[mode] then
                        out.mode = mode
                    else
                        errors[#errors + 1] = name .. ': shadows must be one of "none", "floating", "focused", "all"'
                    end
                end
                if size ~= nil then
                    if math.type(size) == "integer" or (type(size) == "number" and size == math.floor(size)) then
                        if size >= 0 and size <= M.SIZE_MAX then
                            out.size = math.tointeger(size)
                        else
                            errors[#errors + 1] = name .. ": shadowSize must be a whole number from 0 to " .. M.SIZE_MAX
                        end
                    else
                        errors[#errors + 1] = name .. ": shadowSize must be a whole number from 0 to " .. M.SIZE_MAX
                    end
                end
            end
        end
    end
    return out, errors
end

-- Whether macOS draws its own shadows for `mode`. It shadows every window
-- or none: "floating" leaves them all on, the nearest it can, and
-- "focused" turns them off for tide's own.
function M.macos(mode)
    return mode == "all" or mode == "floating"
end

-- Whether tide paints the focused window's shadow itself.
function M.painted(s)
    return s ~= nil and s.mode == "focused" and (s.size or 0) > 0
end

return M
