-- A click outside one of tide's popups closes it (SPEC.md §8): the volume
-- popover, the dashboard, the dashboard launcher and the overview. Each
-- also closes as its window loses focus, but only a click in another app
-- takes the focus. A click on the bar, or on another display's overlay,
-- lands on Hammerspoon's own windows and takes nothing, so the popup
-- stayed open. While one is open, an event tap watches for a mouse button
-- going down outside it, and passes the click on.

local M = {}

-- How long after a click closes a popup an open from that same click is
-- dropped: a second click on the speaker closes the popover rather than
-- opening it again.
M.GRACE = 0.5

-- Whether point `p` is in box `r`.
function M.inside(p, r)
    return p.x >= r.x and p.x < r.x + r.w and p.y >= r.y and p.y < r.y + r.h
end

local function any(p, boxes)
    for _, r in ipairs(boxes or {}) do
        if M.inside(p, r) then
            return true
        end
    end
    return false
end

-- `d`: after(secs, fn); now(), in seconds; log(text); and bars(), the
-- bars' frames. A click on a bar gives the focus back to the window you
-- were in; a click on anything else gives it to whatever you clicked.
function M.new(hs, d)
    local self = {}
    local tap, closed_at

    function self.stop()
        if tap then
            local t = tap
            tap = nil
            local ok, err = pcall(t.stop, t)
            if not ok then
                d.log("clickaway: stopping the tap: " .. tostring(err))
            end
        end
    end

    -- While open, a click outside every box in `keep` calls close(refocus)
    -- once, on the next turn, out of the tap's own callback.
    function self.start(keep, close)
        self.stop()
        local mine
        local made, err = pcall(function()
            local types = hs.eventtap.event.types
            mine = hs.eventtap.new({ types.leftMouseDown, types.rightMouseDown, types.otherMouseDown }, function(e)
                if tap ~= mine then
                    return false
                end
                local p = e:location()
                if any(p, keep) then
                    return false
                end
                local refocus = any(p, d.bars())
                closed_at = d.now()
                self.stop()
                d.after(0, function()
                    close(refocus)
                end)
                return false
            end)
            tap = mine
            mine:start()
        end)
        if not made then
            tap = nil
            d.log("clickaway: watching for a click outside: " .. tostring(err))
        end
    end

    -- Whether an open asked for now comes from the click that just closed
    -- a popup.
    function self.reopening()
        return closed_at ~= nil and d.now() - closed_at < M.GRACE
    end

    return self
end

-- The `d` for tide's popups.
function M.deps(hs, tide)
    return {
        after = tide.adapter.after,
        now = function()
            return hs.timer.secondsSinceEpoch()
        end,
        log = tide.adapter.log,
        bars = function()
            local out = {}
            local ok, frames = pcall(function()
                return tide.bar and tide.bar.frames() or {}
            end)
            if not ok then
                tide.adapter.log("clickaway: reading the bars' frames: " .. tostring(frames))
                return out
            end
            for _, f in pairs(frames) do
                if not f.hidden then
                    out[#out + 1] = f
                end
            end
            return out
        end,
    }
end

return M
