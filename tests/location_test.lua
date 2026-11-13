-- The city picker's Find (location.lua): when it can ask Location
-- Services, and what it hands the page from macOS's answer.

local t = require("t")
local location = require("tide.location")

t.test("Find asks unless Location Services is off, for Hammerspoon or all", function()
    t.eq(location.problem(true, "authorized"), nil)
    t.eq(location.problem(true, "undefined"), nil, "asking has macOS ask")
    t.eq(location.problem(nil, nil), nil, "can't tell, so it tries")
    t.eq(location.problem(true, "denied"),
        "Location Services is off for Hammerspoon. Turn it on in Privacy & Security, under Location Services")
    t.eq(location.problem(true, "restricted") ~= nil, true)
    t.eq(location.problem(false, "authorized"), "Location Services is off. Turn it on in Privacy & Security")
end)

t.test("macOS's answer is where it is, and how close, in whole km", function()
    t.eq(location.found({ latitude = 53.35, longitude = -6.26, horizontalAccuracy = 2400 }),
        { latitude = 53.35, longitude = -6.26, accuracyKm = 2 })
    t.eq(location.found({ latitude = 53.35, longitude = -6.26, horizontalAccuracy = 65 }).accuracyKm, 1,
        "never \"within about 0 km\"")
    t.eq(location.found({ latitude = 53.35, longitude = -6.26, horizontalAccuracy = -1 }).accuracyKm, nil,
        "a negative accuracy is CoreLocation's invalid")
    t.eq(location.found({ latitude = 53.35, longitude = -6.26 }).accuracyKm, nil)
end)

t.test("no answer, or one out of range, is none", function()
    t.eq(location.found(nil), nil)
    t.eq(location.found({}), nil)
    t.eq(location.found({ latitude = 91, longitude = 0 }), nil)
    t.eq(location.found({ latitude = 0, longitude = -181 }), nil)
    t.eq(location.found({ latitude = 0 / 0, longitude = 0 }), nil, "NaN")
end)

t.test("a Find with no answer says how long it waited", function()
    t.eq(location.timed_out(), { error = "Location Services didn't answer in 30 seconds" })
end)

t.done("location")
