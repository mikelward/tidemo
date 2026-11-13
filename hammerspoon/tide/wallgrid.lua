-- The Appearance page's wallpaper grid (SPEC.md §10), as tide for Linux's
-- (tide for Linux SPEC.md §16): the wallpapers installed, and yours, each
-- with its light or dark and its collection, for the page to filter and
-- put your screen's shape first with tide for Linux's own functions. Pure
-- Lua: the walk takes its file calls as arguments, and wallpaper_hs.lua
-- passes hs.fs's.

local M = {}

M.SYSTEM = "/System/Library/Desktop Pictures"
M.LIBRARY = "/Library/Desktop Pictures"

-- The folders the grid shows, in order: macOS's own, then this Mac's (an
-- administrator's or an organization's), then yours. Yours is
-- ~/Pictures/Wallpapers, not all of Pictures, which can hold a Photos
-- library.
function M.folders(home)
    return { M.SYSTEM, M.LIBRARY, home .. "/Pictures/Wallpapers" }
end

-- The pictures it shows, by extension: macOS's desktop takes any of
-- these, and the page shows them. A .madesktop, macOS's aerials, is a
-- video's settings, not a picture, so it isn't one.
M.TYPES = { heic = true, heif = true, jpg = true, jpeg = true, png = true, tif = true, tiff = true, webp = true }

-- How deep under a folder it looks.
M.DEPTH = 3

local function ext(name)
    return (name:match("%.([^./]+)$") or ""):lower()
end

-- Every picture under `folders`, sorted, and what it couldn't read.
-- `fs` is { dir(path) -> a list of names, or nil and why; kind(path) ->
-- "file", "directory" or nil, following links }. A folder that isn't
-- there is passed over; one it can't read, and a link to nothing, are
-- named in `problems`. Hidden entries (".thumbnails") and packages (a
-- folder whose name has an extension, such as a Photos library) aren't
-- looked in.
function M.walk(folders, fs)
    local found, problems = {}, {}
    local function visit(dir, depth, top)
        local ok, list, err = pcall(fs.dir, dir)
        if not ok or not list then
            local why = ok and err or list
            if not (top and fs.kind(dir) == nil) then
                problems[#problems + 1] = "couldn't read " .. dir .. ": " .. tostring(why)
            end
            return
        end
        local names = {}
        for _, name in ipairs(list) do
            if name ~= "." and name ~= ".." and name:sub(1, 1) ~= "." then
                names[#names + 1] = name
            end
        end
        table.sort(names)
        for _, name in ipairs(names) do
            local path = dir .. "/" .. name
            local kind = fs.kind(path)
            if kind == "file" then
                if M.TYPES[ext(name)] then
                    found[#found + 1] = path
                end
            elseif kind == "directory" then
                if depth < M.DEPTH and not name:find("%.[^.]+$") then
                    visit(path, depth + 1, false)
                end
            elseif kind == nil then
                problems[#problems + 1] = "passed over " .. path .. ": a link to nothing, or gone"
            end
        end
    end
    for _, dir in ipairs(folders) do
        visit(dir, 1, true)
    end
    return found, problems
end

-- Which collection a picture is in, for the grid's chips: macOS for one
-- loose in macOS's folder, else its subfolder's name (Solid Colors);
-- This Mac for one in /Library/Desktop Pictures; Yours for yours.
function M.collection(path, home)
    local yours = home .. "/Pictures/Wallpapers/"
    if home ~= "" and path:sub(1, #yours) == yours then
        return "Yours"
    end
    if path:sub(1, #M.LIBRARY + 1) == M.LIBRARY .. "/" then
        return "This Mac"
    end
    if path:sub(1, #M.SYSTEM + 1) == M.SYSTEM .. "/" then
        local sub = path:sub(#M.SYSTEM + 2):match("^([^/]+)/")
        return sub or "macOS"
    end
    return "Other"
end

-- A picture's pair, as tide for Linux's pairName: { base, mode } for one
-- named as the light or dark one of a pair ("-l" and "-d", "light" with
-- "dark" or "dimmed", "day" with "night"), a size at its end aside;
-- else nil.
local WORDS = { dark = "dark", dimmed = "dark", night = "dark", light = "light", day = "light" }

local function pair_name(path)
    local stem = path:gsub("%.[^./]*$", ""):gsub("[-_ ]%d+x%d+$", "")
    local base, word = stem:match("^(.*[-_ ])(%a+)$")
    if base and WORDS[word:lower()] then
        return { base = base:lower(), mode = WORDS[word:lower()] }
    end
    local b, letter = stem:match("^(.*%-)([ld])$")
    if b then
        return { base = b .. "\n", mode = letter == "l" and "light" or "dark" }
    end
    return nil
end

-- Each of `paths`' mode: "light" or "dark" when it's named as one of a pair
-- and its partner is there too, else "", so it shows for either.
function M.modes(paths)
    local pairs_ = {}
    for _, path in ipairs(paths) do
        local p = pair_name(path)
        if p then
            pairs_[p.base] = pairs_[p.base] or {}
            pairs_[p.base][p.mode] = true
        end
    end
    local out = {}
    for _, path in ipairs(paths) do
        local p = pair_name(path)
        out[path] = (p and pairs_[p.base].light and pairs_[p.base].dark) and p.mode or ""
    end
    return out
end

-- The grid's pictures from `paths`, as tide for Linux's galleryImages
-- gives them: { path, name, mode, collection, setting }, sorted by name,
-- then path. `setting` is what choosing it sets (wallpaper.setting's).
-- Sizes come later, as each is read.
function M.images(paths, home, setting)
    local modes = M.modes(paths)
    local out = {}
    for _, path in ipairs(paths) do
        out[#out + 1] = {
            path = path,
            name = path:match("([^/]+)$"):gsub("%.[^.]*$", ""),
            mode = modes[path],
            collection = M.collection(path, home),
            setting = setting(path, home),
        }
    end
    table.sort(out, function(a, b)
        local x, y = a.name:lower(), b.name:lower()
        if x ~= y then
            return x < y
        end
        return a.path < b.path
    end)
    return out
end

-- Where a smaller copy of `path` may be, to draw its thumbnail from, in
-- order: macOS keeps one for each of its own in .thumbnails beside it.
-- The picture itself is the caller's last resort.
function M.thumbnail_sources(path)
    local dir, name = path:match("^(.*)/([^/]+)$")
    if not dir then
        return {}
    end
    local stem = name:gsub("%.[^.]*$", "")
    return { dir .. "/.thumbnails/" .. stem .. ".heic", dir .. "/.thumbnails/" .. stem .. ".png",
        dir .. "/.thumbnails/" .. stem .. ".jpg" }
end

-- A thumbnail's size for a picture `w` by `h`: within `max_w` by `max_h`,
-- its shape kept, whole points; the box itself for a size unknown.
function M.thumb_size(w, h, max_w, max_h)
    if not (type(w) == "number" and type(h) == "number" and w > 0 and h > 0) then
        return { w = max_w, h = max_h }
    end
    local scale = math.min(max_w / w, max_h / h, 1)
    return { w = math.max(1, math.floor(w * scale + 0.5)), h = math.max(1, math.floor(h * scale + 0.5)) }
end

-- The displays' sizes, as tide for Linux's previewScreens gives them,
-- { width, height } each, from hs.screen frames { w, h }, each size once.
function M.screens(frames)
    local out, seen = {}, {}
    for _, f in ipairs(frames) do
        local w, h = math.floor(f.w + 0.5), math.floor(f.h + 0.5)
        local key = w .. "x" .. h
        if w > 0 and h > 0 and not seen[key] then
            seen[key] = true
            out[#out + 1] = { width = w, height = h }
        end
    end
    return out
end

return M
