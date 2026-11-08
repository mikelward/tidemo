-- Karabiner-Elements' rules, on and off from tide's settings (SPEC.md §15):
-- the rule files conf links into Karabiner's assets folder, and the copies
-- Karabiner runs in karabiner.json. tide turns each on and off itself,
-- keeps the copies up to date with their files, and turns a rule it hasn't
-- seen before on once. dashboard/karabiner.js does the editing, in
-- JavaScriptCore, so the rest of karabiner.json stays as it was; Karabiner
-- reloads the file when it changes. Pure Lua: files, the JavaScript and the
-- settings come from `deps`.

local dashboard = require("tide.dashboard")
local keys = require("tide.keys")
local names = require("tide.names")

local M = {}

M.CONFIG = "/.config/karabiner/karabiner.json"
M.ASSETS = "/.config/karabiner/assets/complex_modifications"
-- conf's rules, top first, as each description starts: Karabiner uses the
-- first rule that matches a key, so tide's and the terminal rule must sit
-- above the arrow rule, which wants the same keys (conf's
-- config/karabiner/README.md). A rule not here goes at the top.
M.ORDER = {
    -- Above tide's, which would take a Mac keyboard's Command+U as
    -- Super+U at the lock screen too.
    "Ctrl+U clears the password at the lock screen",
    "tide:",
    "tilemo:",
    "timo:",
    "Ctrl is Control and Alt is Meta",
    "Ctrl+Tab goes to the next tab",
    "Alt+Tab switches applications",
    "Ctrl+Left/Right moves by word",
}
-- conf's rule files: one of their rules off is a doctor line.
M.CONF_FILES = {
    ["pc-alt-tab.json"] = true,
    ["pc-arrows.json"] = true,
    ["pc-lock.json"] = true,
    ["pc-terminal.json"] = true,
    ["tide.json"] = true,
    ["tilemo.json"] = true,
}
-- The rules tide has seen, by description, in hs.settings: one it hasn't
-- is turned on once, and one you turn off stays off.
M.SEEN_KEY = "tide.karabiner_seen"
-- dashboard/karabiner.js, beside this file.
local HERE = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") or "."
M.SOURCE_PATH = HERE .. "/dashboard/karabiner.js"

-- The Super key (SPEC.md §7.1): tide's rule for each, in karabiner/ beside
-- this file, installed in Karabiner's folder as M.SUPER_FILE; "none" is
-- plain Option, with tide's rule off. In the settings window's order.
M.SUPER_DIR = HERE .. "/karabiner"
M.SUPER_FILE = "tide.json"
M.SUPER_CHOICES = {
    { value = "option", label = "Left Option", file = "tide-option.json" },
    { value = "win", label = "Win, with the PC keyboard rotation", file = "tide.json" },
    { value = "none", label = "Option, without Karabiner" },
}
-- The left Option rule's description starts so; any other tide rule is the
-- Win key's.
M.OPTION_PREFIX = "tide: left Option"

local js = names.js_string

local function js_list(items, each)
    local out = {}
    for i, v in ipairs(items) do
        out[i] = each(v)
    end
    return "[" .. table.concat(out, ",") .. "]"
end

-- What to say, in the section and the doctor, when the rules can't be
-- switched.
M.NO_CONFIG = "Karabiner-Elements hasn't written its settings yet: open it once, and allow what its Setup page lists."
M.NO_RULES = "There are no Karabiner rules to switch: run tide's installer, install/tide-setup, which adds tide's rule to Karabiner's folder."
M.NOT_RUNNING = "Karabiner-Elements isn't running, so these rules do nothing: open it, and allow what its Setup page lists."

-- `deps`: home; read(path) -> text or nil; list(dir) -> file names or nil;
-- run_js(source) -> ok, result; decode(json) -> table or nil;
-- write(path, text) -> true or nil, why; resolve(path) -> the path a
-- symlink names, or the path; running() -> whether Karabiner's service
-- runs; get(key) and set(key, value), for M.SEEN_KEY; notify(text); log(text);
-- source, karabiner.js's text.
function M.new(deps)
    local self = { state = { rules = {}, problem = "" } }
    local bundle = dashboard.bundle({ ["karabiner.js"] = deps.source }, { "karabiner.js" })
    local config_path = (deps.home or "") .. M.CONFIG
    local assets = (deps.home or "") .. M.ASSETS
    local last

    -- The rule files, sorted by name, as { name, text }.
    local function files()
        local list = {}
        for _, name in ipairs(deps.list(assets) or {}) do
            if name:match("%.json$") then
                local text = deps.read(assets .. "/" .. name)
                if text then
                    list[#list + 1] = { name = name, text = text }
                end
            end
        end
        table.sort(list, function(a, b)
            return a.name < b.name
        end)
        return list
    end

    -- Runs `body`, JavaScript with K the module, FILES the files and the
    -- rest as `bind` names them, and gives back what it returns.
    local function run(body, file_list, bind)
        local vars = {
            "const K = modules[\"./karabiner.js\"];",
            "const FILES = " .. js_list(file_list, function(f)
                return "{name:" .. js(f.name) .. ",text:" .. js(f.text) .. "}"
            end) .. ";",
            "const ORDER = " .. js_list(M.ORDER, js) .. ";",
        }
        for name, value in pairs(bind or {}) do
            vars[#vars + 1] = "const " .. name .. " = " .. value .. ";"
        end
        local source = "(function(){" .. bundle .. table.concat(vars, "\n")
            .. "\nreturn JSON.stringify((function(){" .. body .. "})());})()"
        local ok, out = deps.run_js(source)
        if not ok then
            return nil, "couldn't run the Karabiner rules' JavaScript: " .. tostring(out)
        end
        local v = deps.decode(out)
        if type(v) ~= "table" then
            return nil, "the Karabiner rules' JavaScript gave back " .. tostring(out)
        end
        return v
    end

    local function seen()
        local s = deps.get(M.SEEN_KEY)
        return type(s) == "table" and s or {}
    end

    local function remember(rules)
        local set, list = {}, {}
        for _, d in ipairs(seen()) do
            if not set[d] then
                set[d] = true
                list[#list + 1] = d
            end
        end
        for _, r in ipairs(rules) do
            if not set[r.description] then
                set[r.description] = true
                list[#list + 1] = r.description
            end
        end
        deps.set(M.SEEN_KEY, list)
    end

    local function save(text)
        local ok, err = deps.write(deps.resolve(config_path), text)
        if not ok then
            local why = "Couldn't save Karabiner's rules to " .. config_path .. ": " .. tostring(err)
            deps.log(why)
            deps.notify(why)
            return false
        end
        return true
    end

    local function labels(list, by)
        local out = {}
        for _, d in ipairs(list or {}) do
            out[#out + 1] = by[d] or d
        end
        return table.concat(out, "; ")
    end

    -- Read the files again, bring karabiner.json up to date with them, and
    -- give the state the section shows: { rules = { { description, label,
    -- file, on } }, problem }. Nothing runs when nothing changed, unless
    -- `force`.
    function self.check(force)
        local config = deps.read(config_path)
        local list = files()
        local key = (config or "") .. "\0"
        for _, f in ipairs(list) do
            key = key .. f.name .. "\0" .. f.text .. "\0"
        end
        key = key .. tostring(deps.running())
        if key == last and not force then
            return self.state
        end
        last = key
        local v, err = run([[
            const a = K.assetRules(FILES);
            const rules = a.rules;
            const view = (states) => rules.map((r, i) => ({
                description: r.description, label: r.label, file: r.file, on: states ? states[i].on : false,
            }));
            if (CONFIG === null) return { rules: view(null), errors: a.errors, missing: true };
            const s = K.synced(CONFIG, rules, SEEN, ORDER, SUPER_FILE, SUPER_PREFIXES, a.errors.length > 0);
            if (s.error) return { rules: view(null), errors: a.errors, error: s.error };
            const st = K.ruleStates(s.text ?? CONFIG, rules);
            // No text, not a null one, when nothing changed: a JSON null
            // needn't come back to Lua as nil. `before` is the rules as the
            // file has them now, for when the new text can't be saved.
            return {
                rules: view(st.states), before: view(K.ruleStates(CONFIG, rules).states), errors: a.errors,
                text: s.text ?? undefined, updated: s.updated, enabled: s.enabled, replaced: s.replaced, super: s.super,
            };
        ]], list, {
            CONFIG = config and js(config) or "null",
            SEEN = js_list(seen(), js),
            SUPER_FILE = js(M.SUPER_FILE),
            SUPER_PREFIXES = js_list(keys.RULE_PREFIXES, js),
        })
        if not v then
            deps.log(err)
            self.state = { rules = {}, problem = err }
            return self.state
        end
        local rules = v.rules or {}
        local by = {}
        for _, r in ipairs(rules) do
            by[r.description] = r.label
        end
        local problems = {}
        if v.missing then
            problems[#problems + 1] = M.NO_CONFIG
        elseif v.error then
            problems[#problems + 1] = "Can't switch Karabiner's rules: " .. v.error
                .. ". Fix karabiner.json, or open Karabiner-Elements, which writes it again."
        elseif #rules == 0 then
            problems[#problems + 1] = M.NO_RULES
        elseif not deps.running() then
            problems[#problems + 1] = M.NOT_RUNNING
        end
        for _, e in ipairs(v.errors or {}) do
            problems[#problems + 1] = "Karabiner's " .. e .. "."
        end
        local saved = true
        if type(v.text) == "string" then
            saved = save(v.text)
            if saved then
                if #(v.enabled or {}) > 0 then
                    deps.notify("tide turned on conf's Karabiner rules: " .. labels(v.enabled, by)
                        .. ". Switch them under Keyboard in tide's settings.")
                end
                if #(v.replaced or {}) > 0 then
                    local old = "\"" .. table.concat(v.replaced, "\", \"") .. "\""
                    deps.notify((v.super and ("tide's Super key rule is now \"" .. v.super .. "\", in place of " .. old .. ", which it turned off.")
                        or ("tide turned off " .. old .. ", whose file is gone, so Super is plain Option."))
                        .. " Choose the Super key under Keyboard in tide's settings.")
                end
                if #(v.updated or {}) > 0 then
                    deps.notify("tide brought Karabiner's copy up to date with conf: " .. labels(v.updated, by) .. ".")
                end
                -- What's in the file now, not what was.
                last = nil
            else
                -- Not saved: show the file as it is, and try again at the
                -- next check, though nothing changed.
                rules = v.before or {}
                last = nil
            end
        end
        -- Only once what they say is in the file, or there was nothing to
        -- write: one not saved is turned on again next time.
        if saved and not v.missing and not v.error then
            remember(rules)
        end
        self.state = { rules = rules, problem = table.concat(problems, " ") }
        return self.state
    end

    -- Turn the rule named `description` on or off. Returns true, or nil and
    -- why.
    function self.set(description, on)
        local config = deps.read(config_path)
        if not config then
            return nil, M.NO_CONFIG
        end
        local list = files()
        local v, err = run("return K.withRule(CONFIG, K.assetRules(FILES).rules, DESC, ON, ORDER);", list, {
            CONFIG = js(config),
            DESC = js(description),
            ON = on and "true" or "false",
        })
        if not v then
            return nil, err
        end
        if v.error then
            return nil, v.error
        end
        if not save(v.text) then
            return nil, "couldn't save karabiner.json"
        end
        remember({ { description = description } })
        self.check(true)
        return true
    end

    -- The Super key in use, as an M.SUPER_CHOICES value: which tide rule
    -- is on, from the last check.
    -- A tide rule, by its description, whatever its file: an old conf
    -- checkout's tilemo.json is one too.
    local function is_tide(description)
        for _, prefix in ipairs(keys.RULE_PREFIXES) do
            if description:sub(1, #prefix) == prefix then
                return true
            end
        end
        return false
    end

    function self.super()
        for _, r in ipairs(self.state.rules) do
            if is_tide(r.description) and r.on then
                return r.description:sub(1, #M.OPTION_PREFIX) == M.OPTION_PREFIX and "option" or "win"
            end
        end
        return "none"
    end

    -- Make `value`, an M.SUPER_CHOICES value, the Super key: the rule in use
    -- goes off, and the chosen one goes into Karabiner's folder, on. A link
    -- there, as an old conf checkout made, is replaced, not written through.
    -- Returns true, or nil and why.
    function self.set_super(value)
        local choice
        for _, c in ipairs(M.SUPER_CHOICES) do
            if c.value == value then
                choice = c
            end
        end
        if not choice then
            return nil, "there's no Super key called " .. tostring(value)
        end
        -- The chosen rule is read first, so a missing one changes nothing.
        local text, description
        if choice.file then
            text = deps.read(M.SUPER_DIR .. "/" .. choice.file)
            local rule = text and deps.decode(text)
            description = type(rule) == "table" and type(rule.rules) == "table" and rule.rules[1]
                and rule.rules[1].description
            if type(description) ~= "string" then
                return nil, "couldn't read tide's rule " .. M.SUPER_DIR .. "/" .. choice.file .. ": install tide again"
            end
        end
        self.check(true)
        for _, r in ipairs(self.state.rules) do
            if is_tide(r.description) and r.on then
                local ok, err = self.set(r.description, false)
                if not ok then
                    return nil, err
                end
            end
        end
        if not choice.file then
            return true
        end
        local path = assets .. "/" .. M.SUPER_FILE
        if deps.resolve(path) ~= path then
            local ok, err = (deps.remove or os.remove)(path)
            if not ok then
                return nil, "couldn't replace the link " .. path .. ": " .. tostring(err)
            end
        end
        local ok, err = deps.write(path, text)
        if not ok then
            return nil, "couldn't write " .. path .. ": " .. tostring(err)
        end
        return self.set(description, true)
    end

    -- tide doctor's lines: what's wrong, and conf's rules that are off.
    function self.doctor()
        local lines = {}
        local s = self.state
        if s.problem ~= "" then
            lines[#lines + 1] = s.problem
        end
        local off = {}
        for _, r in ipairs(s.rules) do
            if M.CONF_FILES[r.file] and not r.on then
                off[#off + 1] = r.label
            end
        end
        if #off > 0 then
            lines[#lines + 1] = "conf's Karabiner rules that are off: " .. table.concat(off, "; ")
                .. ". Turn them on under Keyboard in tide's settings."
        end
        return lines
    end

    return self
end

return M
