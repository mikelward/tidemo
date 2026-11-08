-- How tide runs a command in your login environment (SPEC.md §7.2): apps
-- launched by launchd, Hammerspoon among them, get a bare PATH, without
-- Homebrew's or ~/bin. With mikelward/scripts there's its ~/scripts/runenv,
-- which sets that environment up; without it, your login shell does, with
-- `-l`. Pure Lua: `exists(path)` says whether a file is there.

local M = {}

-- The shell when $SHELL is unset: macOS's own default.
M.DEFAULT_SHELL = "/bin/zsh"

-- The argv to run `words` (a list) in the login environment, for
-- /usr/bin/env, which puts any NAME=value words before it in the command's
-- environment. `home` and `shell` are $HOME and $SHELL.
function M.argv(home, shell, exists, words)
    local runenv = (home or "") .. "/scripts/runenv"
    local argv
    if home and home ~= "" and exists(runenv) then
        argv = { runenv }
    else
        if not shell or shell == "" then
            shell = M.DEFAULT_SHELL
        end
        -- The words are the shell's arguments, never parsed as shell text.
        argv = { shell, "-l", "-c", 'exec "$@"', "tide" }
    end
    for _, w in ipairs(words) do
        argv[#argv + 1] = w
    end
    return argv
end

return M
