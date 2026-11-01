-- hs_adapter.lua can't run outside Hammerspoon, but one thing about it can
-- be checked here: its constructor defines each function once. A second
-- definition of a name replaces the first for every caller, as a helper
-- opener once took the place of the launcher's open_app(path, env).

local t = require("t")

local function definitions(path)
    local f = assert(io.open(path))
    local seen, twice = {}, {}
    local n = 0
    for line in f:lines() do
        n = n + 1
        local code = line:gsub("%-%-.*$", "")
        local name = code:match("^%s*function%s+a%.([%w_]+)%s*%(") or code:match("^%s*a%.([%w_]+)%s*=%s*function")
        if name then
            if seen[name] then
                twice[#twice + 1] = name .. " (lines " .. seen[name] .. " and " .. n .. ")"
            else
                seen[name] = n
            end
        end
    end
    f:close()
    return seen, twice
end

t.test("the adapter defines each of its functions once", function()
    local seen, twice = definitions("hammerspoon/tilemo/hs_adapter.lua")
    t.eq(next(seen) ~= nil, true, "found the adapter's functions")
    t.eq(twice, {})
end)

t.done("adapter")
