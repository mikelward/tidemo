-- The wallpapers, light and dark, from tide's appearance.json and
-- appearance.local.json (tide SPEC.md §15, §16), as the Mac's desktop
-- picture (SPEC.md §10). Pure Lua.

local M = {}

-- Each mode's setting, as tide names them.
M.KEYS = { light = "lightWallpaper", dark = "darkWallpaper" }

M.SHARED_FILE = "appearance.json"
M.LOCAL_FILE = "appearance.local.json"

-- Why `v` can't be a wallpaper, as tide's wallpaperError says, or nil: a
-- file's path, absolute or from ~/, on one line, or "" for macOS's own.
local function problem(key, v)
    if type(v) ~= "string" or v:find("[\n\r]") or (v ~= "" and v:sub(1, 1) ~= "/" and v:sub(1, 2) ~= "~/") then
        return key .. ' must be a file\'s path, such as "~/Pictures/day.jpg", or "" for the default'
    end
end

-- The wallpapers set, { light, dark }, each a path or "" for none, from
-- the two files' texts (nil for a file that isn't there), the local one's
-- over the shared one's, as tide reads them; and what's wrong with either.
-- `decode` is hs.json.decode.
function M.load(shared, own, decode)
    local out, errors = { light = "", dark = "" }, {}
    for _, f in ipairs({ { M.SHARED_FILE, shared }, { M.LOCAL_FILE, own } }) do
        local name, text = f[1], f[2]
        if text then
            local ok, t = pcall(decode, text)
            if not ok or type(t) ~= "table" then
                errors[#errors + 1] = name .. " isn't a JSON object"
            else
                for mode, key in pairs(M.KEYS) do
                    if t[key] ~= nil then
                        local why = problem(key, t[key])
                        if why then
                            errors[#errors + 1] = name .. ": " .. why
                        else
                            out[mode] = t[key]
                        end
                    end
                end
            end
        end
    end
    table.sort(errors)
    return out, errors
end

-- `path` with a leading ~/ as `home`.
function M.expand(path, home)
    if path:sub(1, 2) == "~/" then
        return home .. path:sub(2)
    end
    return path
end

-- The setting for a file chosen, `path`: one under `home` from ~/, so it
-- reads the same on another machine sharing appearance.json, as tide's
-- pickedWallpaper; nil for none.
function M.setting(path, home)
    if type(path) ~= "string" or path:sub(1, 1) ~= "/" or path:find("[\n\r]") then
        return nil
    end
    if home ~= "" and path:sub(1, #home + 1) == home .. "/" then
        return "~/" .. path:sub(#home + 2)
    end
    return path
end

-- The picture to show for the mode, `dark` or light, from `walls`
-- (M.load's), as a path, or nil to leave macOS's own.
function M.now(walls, dark, home)
    local set = walls[dark and "dark" or "light"]
    if set == nil or set == "" then
        return nil
    end
    return M.expand(set, home)
end

-- The file:// URL for `path`, as macOS takes a desktop picture's: each
-- byte but a letter, digit, slash or one of -._~ percent-encoded.
function M.file_url(path)
    return "file://" .. (path:gsub("[^%w%-%._~/]", function(c)
        return string.format("%%%02X", c:byte())
    end))
end

-- The folder the chooser opens in for `setting`: its file's, or `home`'s
-- Pictures for none.
function M.folder(setting, home)
    local full = setting ~= "" and M.expand(setting, home) or ""
    return full:match("^(.*)/[^/]*$") or (home .. "/Pictures")
end

return M
