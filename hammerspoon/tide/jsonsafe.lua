-- State for tide's pages, made encodable before hs.json.encode sees it.
-- hs.json.encode gives nothing for a value JSON can't hold, saying only
-- "Object cannot be serialised as JSON", and the page then never hears
-- what changed: the bar showed no workspaces. JSON can't hold a NaN or an
-- infinity, a function or userdata, text that isn't UTF-8 (a window's
-- title, say), or a table whose keys are neither 1…n nor all strings
-- (LuaSkin makes those an object with number keys). clean() drops what it
-- can't keep, mends the text and gives a mixed table string keys, saying
-- where each was, so the rest still reaches the page. Pure Lua.

local M = {}

-- `s` with each byte that isn't part of a UTF-8 character as U+FFFD.
local function mend(s)
    local out, i = {}, 1
    while i <= #s do
        local len = utf8.len(s, i, i)
        local ok = false
        if len then
            local c = s:byte(i)
            local n = c < 0x80 and 1 or c < 0xE0 and 2 or c < 0xF0 and 3 or 4
            if utf8.len(s:sub(i, i + n - 1)) == 1 then
                out[#out + 1] = s:sub(i, i + n - 1)
                i = i + n
                ok = true
            end
        end
        if not ok then
            out[#out + 1] = "\u{FFFD}"
            i = i + 1
        end
    end
    return table.concat(out)
end

local function bad_number(v)
    return v ~= v or v == math.huge or v == -math.huge
end

-- Whether `t`'s keys are exactly 1…#t.
local function is_sequence(t)
    local n = 0
    for _ in pairs(t) do
        n = n + 1
    end
    for i = 1, n do
        if t[i] == nil then
            return false
        end
    end
    return true
end

local function all_strings(t)
    for k in pairs(t) do
        if type(k) ~= "string" then
            return false
        end
    end
    return true
end

-- `v` as JSON can hold it, calling `report(path, why)` for each value
-- dropped or changed; `path` is where, as "state.icons.cpu.value".
function M.clean(v, report, path, seen)
    path = path or "state"
    local kind = type(v)
    if kind == "number" then
        if bad_number(v) then
            report(path, "not a number JSON can hold (" .. tostring(v) .. ")")
            return nil
        end
        return v
    elseif kind == "string" then
        if not utf8.len(v) then
            report(path, "text that isn't UTF-8, mended")
            return mend(v)
        end
        return v
    elseif kind == "boolean" or kind == "nil" then
        return v
    elseif kind ~= "table" then
        report(path, "a " .. kind)
        return nil
    end
    seen = seen or {}
    if seen[v] then
        report(path, "a table inside itself")
        return nil
    end
    seen[v] = true
    local out = {}
    if is_sequence(v) then
        -- A dropped item would leave a hole, so the rest close up.
        for i = 1, #v do
            local c = M.clean(v[i], report, path .. "[" .. i .. "]", seen)
            if c ~= nil then
                out[#out + 1] = c
            end
        end
    else
        if not all_strings(v) then
            report(path, "keys that are neither 1…n nor all strings, sent as strings")
        end
        for k, item in pairs(v) do
            local key = type(k) == "string" and k or tostring(k)
            local c = M.clean(item, report, path .. "." .. key, seen)
            if c ~= nil then
                out[key] = c
            end
        end
    end
    seen[v] = nil
    return out
end

-- An encoder for a page's state: `encode(v)` (hs.json.encode) after
-- clean(), with each problem logged once by `log` with `what`, the page's
-- name. Returns the JSON, or nil when even that failed, logged.
function M.encoder(encode, log, what)
    local said = {}
    return function(v)
        local clean = M.clean(v, function(path, why)
            local line = what .. ": " .. path .. " can't be sent as JSON, so it's left out: " .. why
            if not said[line] then
                said[line] = true
                log(line)
            end
        end)
        local ok, json = pcall(encode, clean)
        if not ok or type(json) ~= "string" then
            local line = what .. ": couldn't encode its state as JSON: " .. tostring(ok and json or json)
            if not said[line] then
                said[line] = true
                log(line)
            end
            return nil
        end
        return json
    end
end

return M
