-- A picture's size in pixels from its first bytes, as tide for Linux's
-- tide-pick --list reads one (tide for Linux SPEC.md §16), so the wallpaper
-- grid can put the pictures your screen's shape first without decoding
-- any: PNG, JPEG, and HEIC or HEIF, as macOS's own wallpapers are. Plain
-- Lua.

local M = {}

local function u16(s, i)
    local a, b = s:byte(i, i + 1)
    return a * 256 + b
end

local function u32(s, i)
    local a, b, c, d = s:byte(i, i + 3)
    return ((a * 256 + b) * 256 + c) * 256 + d
end

-- PNG: the IHDR chunk's width and height, right after the signature.
function M.png(s)
    if #s < 24 or s:sub(1, 8) ~= "\137PNG\r\n\26\n" or s:sub(13, 16) ~= "IHDR" then
        return nil
    end
    return u32(s, 17), u32(s, 21)
end

-- JPEG: the first start-of-frame marker's height and width, stepping over
-- every segment before it (EXIF's among them).
function M.jpeg(s)
    if #s < 4 or s:sub(1, 2) ~= "\255\216" then
        return nil
    end
    local i = 3
    while i + 3 <= #s do
        if s:byte(i) ~= 0xFF then
            return nil
        end
        local marker = s:byte(i + 1)
        if marker == 0xFF then
            -- Fill bytes before a marker.
            i = i + 1
        elseif marker == 0xD8 or marker == 0x01 or (marker >= 0xD0 and marker <= 0xD7) then
            i = i + 2
        else
            local length = u16(s, i + 2)
            -- SOF0 to SOF15, but DHT (C4), JPG (C8) and DAC (CC).
            if marker >= 0xC0 and marker <= 0xCF and marker ~= 0xC4 and marker ~= 0xC8 and marker ~= 0xCC then
                if i + 8 > #s then
                    return nil
                end
                return u16(s, i + 7), u16(s, i + 5)
            end
            if length < 2 then
                return nil
            end
            i = i + 2 + length
        end
    end
    return nil
end

-- HEIC and HEIF: the largest image spatial extent ("ispe") in the `meta`
-- box, `meta` being that box's bytes. A picture macOS ships is a grid of
-- tiles, each with its own ispe; the grid's, the whole picture's, is the
-- largest.
function M.heif_meta(meta)
    local w, h = nil, nil
    local at = 1
    while true do
        local i = meta:find("ispe", at, true)
        if not i then
            break
        end
        -- The box's size, then "ispe", then a full box's version and
        -- flags, then the width and height.
        if i >= 5 and i + 15 <= #meta and u32(meta, i - 4) >= 20 then
            local bw, bh = u32(meta, i + 8), u32(meta, i + 12)
            if bw > 0 and bh > 0 and (w == nil or bw * bh > w * h) then
                w, h = bw, bh
            end
        end
        at = i + 4
    end
    return w, h
end

-- The most of a file read for its size: a JPEG's EXIF comes before its
-- frame, and a HEIC's meta box lists every tile.
M.MAX_READ = 4 * 1024 * 1024

-- The top-level boxes of an ISO media file `f`, open: the `meta` box's
-- bytes, or nil. `ftyp` must come first.
local function heif_meta_box(f)
    local at = 0
    local first = true
    while true do
        f:seek("set", at)
        local head = f:read(8)
        if not head or #head < 8 then
            return nil
        end
        local size, kind = u32(head, 1), head:sub(5, 8)
        local body_at = at + 8
        if size == 1 then
            local big = f:read(8)
            if not big or #big < 8 then
                return nil
            end
            size = u32(big, 1) * 4294967296 + u32(big, 5)
            body_at = at + 16
        end
        if first and kind ~= "ftyp" then
            return nil
        end
        first = false
        if kind == "meta" then
            local length = (size == 0 and M.MAX_READ) or math.min(size - (body_at - at), M.MAX_READ)
            return f:read(length)
        end
        if size < 8 then
            return nil
        end
        at = at + size
    end
end

-- The size of the picture in file `path`, width and height, or nil and
-- why: one of a type it can't read, or whose header it can't make out, has
-- none.
function M.read(path)
    local f, err = io.open(path, "rb")
    if not f then
        return nil, err
    end
    local head = f:read(32) or ""
    local w, h
    if head:sub(1, 8) == "\137PNG\r\n\26\n" then
        w, h = M.png(head)
    elseif head:sub(1, 2) == "\255\216" then
        f:seek("set", 0)
        w, h = M.jpeg(f:read(M.MAX_READ) or "")
    elseif head:sub(5, 8) == "ftyp" then
        local meta = heif_meta_box(f)
        if meta then
            w, h = M.heif_meta(meta)
        end
    end
    f:close()
    if not w then
        return nil, "no size in its header"
    end
    return w, h
end

return M
