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
    t.eq(loginenv.argv("/Users/me", "/opt/homebrew/bin/fish", none, { "rbw", "list" }),
        { "/opt/homebrew/bin/fish", "-l", "-c", 'exec "$@"', "tide", "rbw", "list" })
end)

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
