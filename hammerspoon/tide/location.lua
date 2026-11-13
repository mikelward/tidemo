-- The city picker's Find (SPEC.md §10): where this Mac is, from macOS's
-- Location Services (hs.location), for the Appearance page to list the
-- cities nearest it. Pure Lua: asking macOS is settings_hs.lua's.

local M = {}

-- Seconds Find waits for an answer: time for macOS's question, the first
-- time, as well as for the answer.
M.TIMEOUT = 30

-- Why Find can't ask, from hs.location.servicesEnabled()'s `enabled` and
-- hs.location.authorizationStatus()'s `status`, or nil when it can:
-- "undefined" is fine, as asking has macOS ask.
function M.problem(enabled, status)
    if enabled == false then
        return "Location Services is off. Turn it on in Privacy & Security"
    end
    if status == "denied" or status == "restricted" then
        return "Location Services is off for Hammerspoon. Turn it on in Privacy & Security, under Location Services"
    end
    return nil
end

-- What the page takes from hs.location.get()'s `loc`: { latitude,
-- longitude, accuracyKm }, accuracyKm a whole km, at least 1, or nil when
-- macOS gives none; nil for no location, or one out of range.
function M.found(loc)
    if type(loc) ~= "table" then
        return nil
    end
    local lat, lng = loc.latitude, loc.longitude
    if type(lat) ~= "number" or type(lng) ~= "number" or not (lat >= -90 and lat <= 90)
        or not (lng >= -180 and lng <= 180) then
        return nil
    end
    local accuracy = loc.horizontalAccuracy
    -- CoreLocation's horizontalAccuracy is negative for a fix whose
    -- latitude and longitude are invalid, so there's no location yet.
    if type(accuracy) == "number" and accuracy < 0 then
        return nil
    end
    local km
    -- In metres.
    if type(accuracy) == "number" and accuracy > 0 and accuracy < math.huge then
        km = math.max(1, math.floor(accuracy / 1000 + 0.5))
    end
    return { latitude = lat, longitude = lng, accuracyKm = km }
end

-- The answer for the page when there's none in M.TIMEOUT seconds.
function M.timed_out()
    return { error = "Location Services didn't answer in " .. M.TIMEOUT .. " seconds" }
end

return M
