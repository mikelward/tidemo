-- sitekeys.lua: which site a browser window's title names, and the keys
-- turned into that site's own.

local t = require("t")
local sitekeys = require("tide.sitekeys")

local CHROME = "com.google.Chrome"
local BRAVE = "com.brave.Browser"

local function name(bundle, title)
    local site = sitekeys.site(bundle, title)
    return site and site.name or nil
end

t.test("Google Docs, Sheets and Slides are told by the title's ending", function()
    t.eq(name(CHROME, "Trip plan - Google Docs"), "Google Docs")
    t.eq(name(CHROME, "Budget 2026 - Google Sheets"), "Google Sheets")
    t.eq(name(CHROME, "Kickoff - Google Slides"), "Google Slides")
    t.eq(name(BRAVE, "Trip plan - Google Docs"), "Google Docs", "Brave too")
end)

t.test("other titles name no site", function()
    t.eq(name(CHROME, "My Drive - Google Drive"), nil)
    t.eq(name(CHROME, "Google Docs tips - Search"), nil, "merely containing Google Docs")
    t.eq(name(CHROME, "Trip plan - Google Docs - draft"), nil)
    t.eq(name(CHROME, "Trip plan - Google Docsx"), nil)
    t.eq(name(CHROME, ""), nil)
    t.eq(name(CHROME, nil), nil, "no title")
end)

t.test("only Chrome and Brave, the Chromium browsers the launcher knows", function()
    t.eq(name("com.apple.Safari", "Trip plan - Google Docs"), nil)
    t.eq(name("com.example.app", "Trip plan - Google Docs"), nil)
    t.eq(name(nil, "Trip plan - Google Docs"), nil)
end)

t.test("each Google site turns Cmd+Y and Cmd+H into Cmd+Shift+H, and Ctrl+/ into Option+/", function()
    for _, title in ipairs({ "a - Google Docs", "a - Google Sheets", "a - Google Slides" }) do
        local site = sitekeys.site(CHROME, title)
        local function to(chord)
            local k = sitekeys.translation(site, chord)
            return k and sitekeys.chord(k) or nil
        end
        t.eq(to("cmd+y"), "cmd+shift+h", title)
        t.eq(to("cmd+h"), "cmd+shift+h", title)
        t.eq(to("ctrl+/"), "alt+/", title)
        t.eq(to("cmd+c"), nil, title .. ": other keys are the page's")
    end
    t.eq(sitekeys.translation(nil, "cmd+y"), nil, "no site, no keys")
end)

t.test("keys() lists each key taken once, in table order", function()
    local chords = {}
    for _, k in ipairs(sitekeys.keys()) do
        chords[#chords + 1] = sitekeys.chord(k)
    end
    t.eq(chords, { "cmd+y", "cmd+h", "ctrl+/" })
end)

t.test("the table is well formed, and never sends a key it takes", function()
    local mods = { cmd = true, alt = true, ctrl = true, shift = true }
    local taken = {}
    for _, k in ipairs(sitekeys.keys()) do
        taken[sitekeys.chord(k)] = true
    end
    for _, site in ipairs(sitekeys.SITES) do
        t.eq(type(site.name), "string")
        t.eq(site.suffix:sub(1, 3), " - ", site.name)
        local seen = {}
        for _, tr in ipairs(site.keys) do
            for _, k in ipairs({ tr.from, tr.to }) do
                t.eq(type(k.key), "string", site.name)
                for _, m in ipairs(k.mods) do
                    t.eq(mods[m], true, site.name .. ": modifier " .. tostring(m))
                end
            end
            local from = sitekeys.chord(tr.from)
            t.eq(seen[from], nil, site.name .. ": " .. from .. " twice")
            seen[from] = true
            t.eq(taken[sitekeys.chord(tr.to)], nil, site.name .. " sends a key it takes")
        end
    end
end)

t.test("the rotation is on only with Karabiner running and Super on the Win key", function()
    t.eq(sitekeys.rotated(true, "win"), true)
    t.eq(sitekeys.rotated(true, "option"), false)
    t.eq(sitekeys.rotated(true, "none"), false)
    t.eq(sitekeys.rotated(false, "win"), false, "Karabiner not running")
    t.eq(sitekeys.rotated(nil, "win"), false, "not checked yet")
end)

t.done("sitekeys")
