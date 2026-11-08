-- tide's two Karabiner rules, karabiner/: tide.json makes the physical Win
-- key Super under setup-macos's modifier rotation, and tide-option.json
-- makes left Option Super on a Mac keyboard without it (SPEC.md §7.1).

local t = require("t")
local json = require("json")

local function load(name)
    local f = assert(io.open("karabiner/" .. name, "rb"))
    local text = f:read("a")
    f:close()
    local d = json.decode(text)
    assert(d, name .. " isn't valid JSON")
    return d.rules[1]
end

local win = load("tide.json")
local opt = load("tide-option.json")
local SUPER = { "left_option", "left_command", "left_control" }

local function mandatory(m)
    return m.from.modifiers and m.from.modifiers.mandatory or {}
end

-- The manipulators keyed by what they take: a key or button with its
-- modifiers.
local function by_from(rule)
    local out = {}
    for _, m in ipairs(rule.manipulators) do
        local from = m.from.key_code or m.from.pointing_button
        out[from .. " " .. table.concat(mandatory(m), "+")] = m
    end
    return out
end

t.test("both are tide's: their descriptions start tide:", function()
    t.eq(win.description:sub(1, 5), "tide:")
    t.eq(opt.description:sub(1, 5), "tide:")
end)

-- Tide Settings knows an enabled rule by its whole description, so a
-- change shows the rule as off until it's added again.
t.test("the Win rule keeps the description conf's had", function()
    t.eq(win.description, "tide: Win+key and Win+click send Ctrl+Option+Command, a lone Win tap opens the workspace list, and Alt+Tab swaps with the master (alongside the setup-macos modifier rotation)")
end)

t.test("Win is physical left_command, left Option is left_option", function()
    t.eq(by_from(win)["left_command "].to_if_alone[1].key_code, "f20")
    t.eq(by_from(opt)["left_option "].to_if_alone[1].key_code, "f20")
    t.eq(by_from(opt)["left_option "].to[1].key_code, "left_option")
end)

-- Every key and button the Win rule makes Super, the Option rule makes
-- Super from left Option, with the same output; Alt+Tab is the rotation's
-- alone.
t.test("left Option carries every Super key the Win rule does", function()
    local o = by_from(opt)
    local n = 0
    for key, m in pairs(by_from(win)) do
        local name, mods = key:match("^(%S+) (.*)$")
        if mods == "left_command" then
            n = n + 1
            local twin = o[name .. " left_option"]
            t.eq(twin ~= nil, true, name .. " is missing from tide-option.json")
            if twin then
                t.eq(twin.to, m.to, name .. "'s output differs")
            end
        end
    end
    t.eq(n > 60, true, "the Win rule maps the whole typing block")
    -- The Win rule's Alt+Tab, swap with the master, sends Ctrl+Option+
    -- Shift+Tab; without the rotation physical Alt is left Option, Super.
    for _, m in ipairs(opt.manipulators) do
        t.eq(m.to[1].modifiers ~= nil and m.to[1].modifiers[3] == "shift", false, "Alt+Tab is the rotation's alone")
    end
end)

t.test("Super is Ctrl+Option+Command", function()
    for _, case in ipairs({ { win, "left_command" }, { opt, "left_option" } }) do
        for _, m in ipairs(case[1].manipulators) do
            local mods = mandatory(m)
            if #mods == 1 and mods[1] == case[2] then
                local has = {}
                for _, x in ipairs(m.to[1].modifiers or {}) do
                    has[x] = true
                end
                for _, s in ipairs(SUPER) do
                    t.eq(has[s], true, (m.from.key_code or m.from.pointing_button) .. " lacks " .. s)
                end
            end
        end
    end
end)

-- Moved from conf's karabiner_test.sh with the rule.

-- tide binds by character in the current layout, so every key of the
-- typing block is mapped, by physical position, for Super to work in any
-- layout: on Dvorak, / is the physical [ key and S the ;.
t.test("every key of the typing block is Super's, in both rules", function()
    local block = { "grave_accent_and_tilde", "hyphen", "equal_sign", "open_bracket", "close_bracket",
        "backslash", "semicolon", "quote", "comma", "period", "slash" }
    for c in ("abcdefghijklmnopqrstuvwxyz0123456789"):gmatch(".") do
        block[#block + 1] = c
    end
    for _, case in ipairs({ { win, "left_command" }, { opt, "left_option" } }) do
        local have = by_from(case[1])
        for _, k in ipairs(block) do
            t.eq(have[k .. " " .. case[2]] ~= nil, true, k .. " isn't mapped from " .. case[2])
        end
    end
end)

-- Some Macs take Ctrl+Option+Command+Backspace before tide sees it, so
-- close goes on F19, a key no keyboard here has.
t.test("Super+Backspace sends Super+F19, tide's close", function()
    t.eq(by_from(win)["delete_or_backspace left_command"].to[1].key_code, "f19")
    t.eq(by_from(opt)["delete_or_backspace left_option"].to[1].key_code, "f19")
end)

-- Physical Alt+Tab, swap with the master, through the rotation:
-- left_option + left_command + shift, Control+Option+Shift+Tab.
t.test("the Win rule's Alt+Tab sends Control+Option+Shift+Tab", function()
    local m = by_from(win)["tab left_option"]
    t.eq(m.to[1].key_code, "tab")
    local mods = {}
    for _, x in ipairs(m.to[1].modifiers) do
        mods[#mods + 1] = x
    end
    table.sort(mods)
    t.eq(mods, { "left_command", "left_option", "shift" })
end)

t.test("Super+click, right-click and middle-click carry Super, in both rules", function()
    for _, case in ipairs({ { win, "left_command" }, { opt, "left_option" } }) do
        for _, b in ipairs({ "button1", "button2", "button3" }) do
            t.eq(by_from(case[1])[b .. " " .. case[2]] ~= nil, true, b .. " from " .. case[2])
        end
    end
end)

t.test("neither uses the left_alt spelling", function()
    for _, name in ipairs({ "tide.json", "tide-option.json" }) do
        local f = assert(io.open("hammerspoon/tide/karabiner/" .. name, "rb"))
        local text = f:read("a")
        f:close()
        t.eq(text:find('"left_alt"', 1, true), nil, name)
    end
end)

t.done("karabiner_rules_test")
