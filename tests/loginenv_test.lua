-- How tide runs a command in your login environment.

local t = require("t")
local loginenv = require("tide.loginenv")

local function only(path)
    return function(p)
        return p == path
    end
end

local function none()
    return false
end

t.test("runs through scripts' runenv where it's installed", function()
    t.eq(loginenv.argv("/Users/me", "/bin/bash", only("/Users/me/scripts/runenv"), { "browser1", "--new" }),
        { "/Users/me/scripts/runenv", "browser1", "--new" })
end)

t.test("runs through your login shell without runenv", function()
    t.eq(loginenv.argv("/Users/me", "/bin/bash", none, { "rbw", "list" }),
        { "/bin/bash", "-l", "-c", 'exec "$@"', "tide", "rbw", "list" })
end)

-- fish has no "$@", and its $argv has no $0 before the arguments.
t.test("passes fish its arguments as $argv", function()
    t.eq(loginenv.argv("/Users/me", "/opt/homebrew/bin/fish", none, { "rbw", "list" }),
        { "/opt/homebrew/bin/fish", "-l", "-c", "exec $argv", "rbw", "list" })
end)

t.test("uses zsh for a shell it can't pass arguments to", function()
    t.eq(loginenv.argv("/Users/me", "/opt/homebrew/bin/nu", none, { "notepad" }),
        { "/bin/zsh", "-l", "-c", 'exec "$@"', "tide", "notepad" })
end)

-- The Bourne form, run for real where the shells are: each word arrives
-- whole, spaces and quotes included, and none is run as shell text.
local function quote(word)
    return "'" .. (word:gsub("'", "'\\''")) .. "'"
end
for _, shell in ipairs({ "/bin/sh", "/bin/bash", "/bin/zsh" }) do
    local f = io.open(shell)
    if f then
        f:close()
        t.test("runs the words as given through " .. shell, function()
            local argv = loginenv.argv("/nonexistent", shell, none,
                { "printf", "[%s]", "two words", "it's", "$HOME", ";echo hi" })
            local cmd = {}
            for i, w in ipairs(argv) do
                cmd[i] = quote(w)
            end
            local p = io.popen(table.concat(cmd, " ") .. " 2>/dev/null")
            local out = p:read("a")
            p:close()
            t.eq(out, "[two words][it's][$HOME][;echo hi]")
        end)
    end
end

t.test("uses zsh when SHELL is unset", function()
    t.eq(loginenv.argv("/Users/me", nil, none, { "notepad" }),
        { "/bin/zsh", "-l", "-c", 'exec "$@"', "tide", "notepad" })
    t.eq(loginenv.argv("/Users/me", "", none, { "notepad" })[1], "/bin/zsh")
end)

t.test("doesn't look for runenv without a home folder", function()
    local looked = false
    local argv = loginenv.argv(nil, "/bin/zsh", function()
        looked = true
        return true
    end, { "x" })
    t.eq(looked, false)
    t.eq(argv[1], "/bin/zsh")
end)

t.done("loginenv_test")
