-- A picture's size from its header (imagesize.lua), as the wallpaper grid
-- reads one: PNG, JPEG, and HEIC as macOS ships its wallpapers.

local t = require("t")
local imagesize = require("tide.imagesize")

local function be32(n)
    return string.char((n >> 24) & 255, (n >> 16) & 255, (n >> 8) & 255, n & 255)
end

local function be16(n)
    return string.char((n >> 8) & 255, n & 255)
end

local function box(kind, body)
    return be32(8 + #body) .. kind .. body
end

local function png(w, h)
    return "\137PNG\r\n\26\n" .. be32(13) .. "IHDR" .. be32(w) .. be32(h) .. "\8\2\0\0\0" .. "rest"
end

-- A JPEG with an APP1 (EXIF) segment before its baseline frame.
local function jpeg(w, h)
    local app1 = "\255\225" .. be16(2 + 6) .. "Exif\0\0"
    local sof = "\255\192" .. be16(17) .. "\8" .. be16(h) .. be16(w) .. "\3" .. string.rep("\0", 9)
    return "\255\216" .. app1 .. sof .. "\255\218"
end

-- A HEIC whose meta box has a 512×512 tile's ispe, then the grid's.
local function heic(w, h)
    local ispe = function(iw, ih)
        return box("ispe", "\0\0\0\0" .. be32(iw) .. be32(ih))
    end
    local meta = box("meta", "\0\0\0\0" .. box("hdlr", string.rep("\0", 24))
        .. box("iprp", box("ipco", ispe(512, 512) .. ispe(w, h))))
    return box("ftyp", "heic\0\0\0\0mif1heic") .. meta .. box("mdat", "pixels")
end

local function file(bytes)
    local path = os.tmpname()
    local f = assert(io.open(path, "wb"))
    f:write(bytes)
    f:close()
    return path
end

t.test("a PNG's size is its IHDR's", function()
    t.eq({ imagesize.png(png(3024, 1964)) }, { 3024, 1964 })
    t.eq(imagesize.png("not a png at all, really not"), nil)
end)

t.test("a JPEG's size is its frame's, past EXIF", function()
    t.eq({ imagesize.jpeg(jpeg(6016, 6016)) }, { 6016, 6016 })
    t.eq(imagesize.jpeg("\255\216\255\225"), nil, "cut short")
    t.eq(imagesize.jpeg("GIF89a"), nil)
end)

t.test("a HEIC's size is its largest ispe, the whole grid's, not a tile's", function()
    local path = file(heic(6016, 6016))
    t.eq({ imagesize.read(path) }, { 6016, 6016 })
    os.remove(path)
end)

t.test("each type is told by its bytes, not its name", function()
    for _, bytes in ipairs({ png(5120, 2880), jpeg(5120, 2880), heic(5120, 2880) }) do
        local path = file(bytes)
        t.eq({ imagesize.read(path) }, { 5120, 2880 })
        os.remove(path)
    end
end)

t.test("a file with no size it can read has none, and says why", function()
    local path = file("plain text")
    t.eq({ imagesize.read(path) }, { nil, "no size in its header" })
    os.remove(path)
    path = file(box("ftyp", "heic") .. box("mdat", "x"))
    t.eq(imagesize.read(path), nil, "a HEIC with no meta box")
    os.remove(path)
    local none, why = imagesize.read("/no/such/picture.heic")
    t.eq(none, nil)
    t.eq(type(why), "string")
end)

t.done("imagesize")
