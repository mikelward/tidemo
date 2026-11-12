-- macOS's own settings that tide keeps (macprefs.lua, SPEC.md §15), kept:
-- macos.json and macos.local.json read as tide starts and as its folder
-- changes, each setting that changed written with `defaults`, and Finder,
-- the Dock or SystemUIServer restarted where one needs it to show. What
-- tide set last is kept (`get` and `set`, hs.settings), so a file's change
-- is what's applied, and a change made in System Settings since stays until
-- the files change that setting again. Pure, given `deps`, so it tests with
-- fakes.

local macprefs = require("tide.macprefs")

local M = {}

M.APPLIED_KEY = "tide.macos.applied"
M.DEFAULTS = "/usr/bin/defaults"
M.KILLALL = "/usr/bin/killall"

-- Whether `defaults delete`'s error `err` says there was nothing to
-- delete: "The domain/default pair of (…) does not exist", or "Domain (…)
-- not found". Anything else, such as a permission error, is a failure.
function M.absent(err)
    err = err or ""
    return err:find("does not exist", 1, true) ~= nil or err:find("not found", 1, true) ~= nil
end

-- `deps`: dir (tide's settings folder), home, read(path) (nil when
-- missing), decode(text) (nil when it doesn't parse), encode(obj),
-- write(path, text) (true, or nil and why), run(path, args, done(code,
-- err, out)) (whether it started), get(key) and set(key, value), notify,
-- log, changed(), called when what the page shows has changed, and own(values),
-- given the good settings each time the files are read, for the ones tide
-- applies itself (macprefs.lua's `own`), and hidden(), the settings the
-- page leaves out, as a set of names, since tide can't apply them now.
function M.new(d)
    local self = {}
    local good = {}
    local errors = {}
    local live = {}
    local edit_error
    local said
    local busy, again

    local function path(local_)
        return d.dir .. "/" .. macprefs.FILE .. (local_ and ".local.json" or ".json")
    end

    -- A file decoded: nil when it isn't there; nil and why when it doesn't
    -- parse.
    local function decode(p)
        local text = d.read(p)
        if text == nil then
            return nil
        end
        local obj = d.decode(text)
        if obj == nil then
            return nil, p:match("[^/]+$") .. " doesn't parse"
        end
        return obj
    end

    -- Say `text` once, until it changes.
    local function say(text)
        if text ~= "" and text ~= said then
            d.notify(text)
        end
        said = text
    end

    -- Run `commands` one at a time, then done(why), why nil when each did
    -- what it should. A delete that finds nothing to delete is fine.
    local function run_each(commands, i, done)
        local c = commands[i]
        if not c then
            done(nil)
            return
        end
        local started = d.run(M.DEFAULTS, c.args, function(code, err)
            if code ~= 0 and not (c.delete and M.absent(err)) then
                local why = (err or ""):gsub("%s+$", "")
                done(why ~= "" and why or ("exit " .. tostring(code)))
                return
            end
            run_each(commands, i + 1, done)
        end)
        if not started then
            done("couldn't run defaults")
        end
    end

    local function label(name)
        return macprefs.BY_NAME[name].label
    end

    local apply

    -- Each step in turn, then the restarts the ones that ran need.
    local function run_steps(steps, i, applied, ran, failed)
        local step = steps[i]
        if not step then
            d.set(M.APPLIED_KEY, applied)
            local restart = macprefs.effects(ran)
            for _, name in ipairs(restart) do
                if not d.run(M.KILLALL, { name }, function(code, err)
                    if code ~= 0 then
                        d.log("macOS settings: couldn't restart " .. name .. ": " .. tostring(err))
                    end
                end) then
                    d.log("macOS settings: couldn't run killall " .. name)
                end
            end
            local login = {}
            for _, s in ipairs(ran) do
                if s.effect == "login" then
                    login[#login + 1] = label(s.name)
                end
            end
            if #failed > 0 then
                d.notify("Couldn't change macOS's " .. table.concat(failed, "; ") .. ". tide tries again when its settings change.")
            end
            if #login > 0 then
                d.notify("Log out and back in for these to change: " .. table.concat(login, ", ") .. ".")
            end
            busy = false
            self.read_live()
            if again then
                again = false
                apply()
            end
            return
        end
        run_each(step.commands, 1, function(why)
            if why then
                d.log("macOS settings: " .. step.name .. ": " .. why)
                failed[#failed + 1] = label(step.name) .. " (" .. why .. ")"
                -- Some of its keys may have changed: recorded as half done,
                -- so it's run again, or undone whole once it's left out.
                applied[step.name] = macprefs.PARTIAL
            else
                applied[step.name] = step.value
                ran[#ran + 1] = step
            end
            run_steps(steps, i + 1, applied, ran, failed)
        end)
    end

    -- Bring macOS to the good settings, from what tide set last.
    apply = function()
        if busy then
            again = true
            return
        end
        local applied = {}
        for k, v in pairs(d.get(M.APPLIED_KEY) or {}) do
            applied[k] = v
        end
        local steps = macprefs.plan(good, applied, d.home)
        if #steps == 0 then
            return
        end
        busy = true
        run_steps(steps, 1, applied, {}, {})
    end

    -- The files read again: what's wrong said once, and the last good
    -- settings kept, or the new ones applied.
    function self.load()
        local shared, e1 = decode(path(false))
        local local_, e2 = decode(path(true))
        local values, errs = macprefs.merge(shared, local_)
        if e1 then
            table.insert(errs, 1, e1)
        end
        if e2 then
            table.insert(errs, e1 and 2 or 1, e2)
        end
        errors = errs
        if #errs > 0 then
            say("tide's macOS settings stay as they were: " .. table.concat(errs, "; "))
        else
            say("")
            good = values
            apply()
        end
        if d.own then
            d.own(good)
        end
        d.changed()
    end

    -- What macOS has for each setting, read afresh, for the page.
    function self.read_live()
        local read = {}
        for _, s in ipairs(macprefs.SETTINGS) do
            if not s.own then
                read[#read + 1] = s
            end
        end
        local left = #read
        local fresh = {}
        local function one_done()
            left = left - 1
            if left == 0 then
                live = fresh
                d.changed()
            end
        end
        for _, s in ipairs(read) do
            if not d.run(M.DEFAULTS, macprefs.read_args(s), function(code, _, out)
                fresh[s.name] = macprefs.parse(s, code, out)
                one_done()
            end) then
                one_done()
            end
        end
    end

    -- The macOS page, as update()'s `macos`.
    function self.state()
        local all = {}
        for _, e in ipairs(errors) do
            all[#all + 1] = e
        end
        if edit_error then
            all[#all + 1] = edit_error
        end
        return macprefs.page(good, live, all, d.hidden and d.hidden() or nil)
    end

    -- The page's { macSet = { name, value } } or { macReset = name }:
    -- macos.local.json changed to say so, which the folder's watcher then
    -- applies. Returns whether it was the page's.
    function self.handle(body)
        if type(body) ~= "table" then
            return false
        end
        local name, value
        if type(body.macSet) == "table" then
            name, value = body.macSet.name, body.macSet.value
            if value == nil then
                edit_error = "Choose a value for " .. tostring(name)
                d.changed()
                return true
            end
        elseif body.macReset ~= nil then
            name = body.macReset
        else
            return false
        end
        local obj, why = decode(path(true))
        if why then
            edit_error = why .. ": fix it to change these here"
            d.changed()
            return true
        end
        -- A shared file that doesn't parse sets nothing to take back.
        local shared = decode(path(false))
        obj, why = macprefs.edit(obj, name, value, shared)
        if not obj then
            edit_error = why
            d.changed()
            return true
        end
        local ok, err = d.write(path(true), d.encode(obj))
        if not ok then
            edit_error = "Couldn't save " .. path(true) .. ": " .. tostring(err)
            d.log("macOS settings: " .. edit_error)
        else
            edit_error = nil
        end
        d.changed()
        return true
    end

    return self
end

return M
