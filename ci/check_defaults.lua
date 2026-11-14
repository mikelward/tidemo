-- make check-tide: the defaults tide for macOS restates, beside the files it
-- copies whole, are still tide for Linux's, read from the tide checkout
-- given: layout.lua's (each layout's mfact and master count, the default
-- layouts by aspect, the ultrawide aspect, the lone-window rules, the
-- cycle, where a new window goes, the mfact step) and the standing
-- workspaces. The geometry, with the mfact bounds, and the clocks are
-- tide's files, which make check-tide compares whole.
package.path = "hammerspoon/?.lua;ci/?.lua;tests/?.lua;" .. package.path
local defaults = require("tide_defaults")
local layout = require("tide.layout")
local wm = require("tide.wm")

local dir = assert(arg[1], "usage: check_defaults.lua TIDE")

-- Deliberate differences, by setting, each saying why: they pass while both
-- sides keep these values, and fail once either moves. None today.
local EXCEPTIONS = {}

local SOURCES = {
    { from = "hammerspoon/tide/layout.lua", values = layout.defaults },
    { from = "hammerspoon/tide/wm.lua", values = { standing = wm.STANDING } },
}

os.exit(defaults.check("tide for macOS", SOURCES, dir, EXCEPTIONS) and 0 or 1)
