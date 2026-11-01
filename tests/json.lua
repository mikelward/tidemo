-- A small JSON reader and writer for the tests, standing in for hs.json:
-- objects, lists, strings with the common escapes, numbers, true, false
-- and null (read as the string "null"). decode() gives nil for anything
-- else.

local M = {}

local ESCAPES = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/", n = "\n", t = "\t", r = "\r", b = "\b", f = "\f" }

function M.decode(text)
    local i = 1
    local value
    local function ws()
        i = text:find("%S", i) or #text + 1
    end
    local function fail()
        error("bad json", 0)
    end
    local function str()
        local out = {}
        i = i + 1
        while true do
            local c = text:sub(i, i)
            if c == "" then
                fail()
            elseif c == '"' then
                i = i + 1
                return table.concat(out)
            elseif c == "\\" then
                local e = text:sub(i + 1, i + 1)
                if e == "u" then
                    local hex = text:sub(i + 2, i + 5)
                    if not hex:match("^%x%x%x%x$") then
                        fail()
                    end
                    out[#out + 1] = utf8.char(tonumber(hex, 16))
                    i = i + 6
                else
                    out[#out + 1] = ESCAPES[e] or fail()
                    i = i + 2
                end
            else
                out[#out + 1] = c
                i = i + 1
            end
        end
    end
    function value()
        ws()
        local c = text:sub(i, i)
        if c == "{" then
            local out = {}
            i = i + 1
            ws()
            if text:sub(i, i) == "}" then
                i = i + 1
                return out
            end
            while true do
                ws()
                if text:sub(i, i) ~= '"' then fail() end
                local k = str()
                ws()
                if text:sub(i, i) ~= ":" then fail() end
                i = i + 1
                out[k] = value()
                ws()
                local d = text:sub(i, i)
                i = i + 1
                if d == "}" then return out end
                if d ~= "," then fail() end
            end
        elseif c == "[" then
            local out = {}
            i = i + 1
            ws()
            if text:sub(i, i) == "]" then
                i = i + 1
                return out
            end
            while true do
                out[#out + 1] = value()
                ws()
                local d = text:sub(i, i)
                i = i + 1
                if d == "]" then return out end
                if d ~= "," then fail() end
            end
        elseif c == '"' then
            return str()
        end
        for word, v in pairs({ ["true"] = true, ["false"] = false, ["null"] = "null" }) do
            if text:sub(i, i + #word - 1) == word then
                i = i + #word
                return v
            end
        end
        local num = text:match("^-?%d+%.?%d*", i) or fail()
        i = i + #num
        return tonumber(num)
    end
    local ok, v = pcall(value)
    if not ok then
        return nil
    end
    ws()
    return i > #text and v or nil
end

local function quote(s)
    return '"' .. s:gsub('[%c"\\]', function(c)
        local named = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\t"] = "\\t", ["\r"] = "\\r" }
        return named[c] or string.format("\\u%04x", c:byte())
    end) .. '"'
end

-- Objects with their keys sorted; a table with a [1] is a list.
function M.encode(v)
    if type(v) == "string" then
        return quote(v)
    elseif type(v) ~= "table" then
        return tostring(v)
    elseif v[1] ~= nil then
        local out = {}
        for i, x in ipairs(v) do
            out[i] = M.encode(x)
        end
        return "[" .. table.concat(out, ", ") .. "]"
    end
    local keys = {}
    for k in pairs(v) do
        keys[#keys + 1] = k
    end
    table.sort(keys)
    local out = {}
    for _, k in ipairs(keys) do
        out[#out + 1] = quote(k) .. ": " .. M.encode(v[k])
    end
    return "{" .. table.concat(out, ", ") .. "}"
end

return M
