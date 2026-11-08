-- How tide runs a command in your login environment (SPEC.md §7.2): apps
-- launched by launchd, Hammerspoon among them, get a bare PATH, without
-- Homebrew's or ~/bin. With mikelward/scripts there's its ~/scripts/runenv,
-- which sets that environment up; without it, your login shell does, with
-- `-l`. Pure Lua: `exists(path)` says whether a file is there.

local M = {}

-- The shell when $SHELL is unset, or one this can't pass arguments to:
-- macOS's own default.
M.DEFAULT_SHELL = "/bin/zsh"

-- Shells that take `-c 'exec "$@"' NAME ARGS...` as the Bourne shell does.
M.POSIX = { sh = true, bash = true, zsh = true, ksh = true, mksh = true, dash = true }

-- The argv to run `words` (a list) in the login environment, for
-- /usr/bin/env, which puts any NAME=value words before it in the command's
-- environment. `home` and `shell` are $HOME and $SHELL.
function M.argv(home, shell, exists, words)
    local runenv = (home or "") .. "/scripts/runenv"
    local argv
    if home and home ~= "" and exists(runenv) then
        argv = { runenv }
    else
        local name = (shell or ""):match("[^/]+$")
        if name == "fish" then
            -- fish has no "$@": its arguments after the command are $argv,
            -- with no $0 before them.
            argv = { shell, "-l", "-c", "exec $argv" }
        else
            -- A shell whose syntax isn't the Bourne shell's, or none, gets
            -- zsh, whose login files set up PATH on a Mac.
            if not M.POSIX[name] then
                shell = M.DEFAULT_SHELL
            end
            -- "tide" is $0; the words are $1 on, never parsed as shell text.
            argv = { shell, "-l", "-c", 'exec "$@"', "tide" }
        end
    end
    for _, w in ipairs(words) do
        argv[#argv + 1] = w
    end
    return argv
end

return M
