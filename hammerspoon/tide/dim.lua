-- The dim (SPEC.md §5.6): every window but the focused one darkened, as
-- tide's inactive dim (tide SPEC.md §6.2). tide can't draw inside or
-- below another app's window (§2.4), so it lays one click-through layer
-- over the windows on each display, a hole cut where the focused window
-- is, and the windows in front of that one filled in again. Tiles don't
-- overlap, so the hole is the focused window and nothing else. Pure Lua:
-- dim_hs.lua draws what this says.

local M = {}

-- tide's strength when nothing sets one (tide-appearance.js's DIM_STRENGTH).
M.STRENGTH = 0.12
M.KEY = "dimStrength"
M.SHARED_FILE = "appearance.json"
M.LOCAL_FILE = "appearance.local.json"

-- The strength set, from appearance.json's and appearance.local.json's
-- texts (nil for a file that isn't there), the local one's over the shared
-- one's, as tide reads them; and what's wrong with either. A bad value is
-- left out, so the one before it stands. `decode` is hs.json.decode.
function M.load(shared, own, decode)
    local strength, errors = M.STRENGTH, {}
    for _, f in ipairs({ { M.SHARED_FILE, shared }, { M.LOCAL_FILE, own } }) do
        local name, text = f[1], f[2]
        if text then
            local ok, t = pcall(decode, text)
            if not ok or type(t) ~= "table" then
                errors[#errors + 1] = name .. " isn't a JSON object"
            elseif t[M.KEY] ~= nil then
                local v = t[M.KEY]
                if type(v) ~= "number" or v ~= v or v < 0 or v > 1 then
                    errors[#errors + 1] = name .. ": " .. M.KEY .. " must be a number from 0 to 1"
                else
                    strength = v
                end
            end
        end
    end
    return strength, errors
end

local function overlap(a, b)
    return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

local function relative(b, origin)
    return { x = b.x - origin.x, y = b.y - origin.y, w = b.w, h = b.h }
end

local function grown(b, by)
    return { x = b.x - by, y = b.y - by, w = b.w + 2 * by, h = b.h + 2 * by }
end

-- How dark a painted shadow is at its darkest *(a guess, to compare with
-- macOS's own)*.
M.SHADOW_ALPHA = 0.45

-- What one display's layer draws, as hs.canvas elements in the display's
-- own coordinates, or nil for no layer: the dim, and the focused window's
-- shadow when tide paints it (shadow.lua).
-- `dim_scene` is wm:dim_scene(): { focused = frame, above = { frame, ... } },
-- with no focused frame when every window's to be dimmed, or nil when
-- nothing is. `focus` is wm:focus_scene(), the same for the shadow, which a
-- lone window casts too, or nil for no shadow. `full` is the display's
-- whole frame, `strength` the dim's, `radius` a window's corner radius and
-- `size` how far the shadow reaches (0 for none).
function M.layer(dim_scene, focus, full, strength, radius, size)
    local dimming = dim_scene ~= nil and strength ~= nil and strength > 0
    local f = focus and focus.focused
    local shadow = f ~= nil and (size or 0) > 0 and overlap(grown(f, size), full)
    if not dimming and not shadow then
        return nil
    end
    local color = { red = 0, green = 0, blue = 0, alpha = dimming and strength or 0 }
    local corners = { xRadius = radius, yRadius = radius }
    local out = {}
    if dimming then
        out[#out + 1] = { type = "rectangle", action = "fill", fillColor = color, frame = { x = 0, y = 0, w = full.w, h = full.h } }
    end
    if shadow then
        -- The window's own shape, shadowed, its body cut out below with
        -- the dim's hole, leaving the shadow round it.
        out[#out + 1] = {
            type = "rectangle",
            action = "fill",
            fillColor = { red = 0, green = 0, blue = 0, alpha = 1 },
            roundedRectRadii = corners,
            withShadow = true,
            shadow = {
                blurRadius = size,
                color = { red = 0, green = 0, blue = 0, alpha = M.SHADOW_ALPHA },
                offset = { h = 0, w = 0 },
            },
            frame = relative(f, full),
        }
    end
    local hole = (dimming and dim_scene.focused) or (shadow and f) or nil
    if hole and overlap(hole, full) then
        -- destinationOut takes the layer away under an opaque shape, its
        -- rounded edge's antialiasing too.
        out[#out + 1] = {
            type = "rectangle",
            action = "fill",
            fillColor = { red = 0, green = 0, blue = 0, alpha = 1 },
            compositeRule = "destinationOut",
            roundedRectRadii = corners,
            frame = relative(hole, full),
        }
        -- A window in front of the focused one is dimmed where it covers the
        -- hole too, and takes none of the shadow. copy sets it to the dim
        -- exactly (none, with no dim), so where it reaches past the hole it
        -- isn't dimmed twice.
        local reach = shadow and grown(hole, size) or hole
        local above = (dim_scene and dim_scene.above) or (focus and focus.above) or {}
        for _, b in ipairs(above) do
            if overlap(b, reach) and overlap(b, full) then
                out[#out + 1] = {
                    type = "rectangle",
                    action = "fill",
                    fillColor = color,
                    compositeRule = "copy",
                    roundedRectRadii = corners,
                    frame = relative(b, full),
                }
            end
        end
    end
    return out
end

-- The dim alone (no shadow).
function M.elements(scene, full, strength, radius)
    return M.layer(scene, scene, full, strength, radius, 0)
end

-- The corner radius of a window on macOS `major`: larger from macOS 26
-- *(unverified: it differs by kind of window)*.
function M.radius(major)
    if (major or 0) >= 26 then
        return 16
    end
    return 10
end

return M
