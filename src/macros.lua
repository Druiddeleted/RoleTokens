local ADDON_NAME, NS = ...
NS.Macros = {}
local Macros = NS.Macros
local DB, Expand, Resolve = NS.DB, NS.Expand, NS.Resolve

local TAG = "|cff33ff99[RoleTokens]|r "
local function say(fmt, ...)
    if DB.Verbose() then print(TAG .. fmt:format(...)) end
end
Macros.Say = say

local MAX_ACCOUNT = MAX_ACCOUNT_MACROS or 120

-- Call fn(index, scope, name, icon, body) for every macro that exists.
local function eachMacro(fn)
    local numAccount, numChar = GetNumMacros()
    for i = 1, numAccount do
        local name, icon, body = GetMacroInfo(i)
        if name then fn(i, "account", name, icon, body or "") end
    end
    for i = MAX_ACCOUNT + 1, MAX_ACCOUNT + numChar do
        local name, icon, body = GetMacroInfo(i)
        if name then fn(i, "character", name, icon, body or "") end
    end
end

local pendingAfterCombat = false
Macros.lastUnits = {}

-- One pass over every macro:
--   * a body containing a token that is not what we last wrote becomes (or
--     replaces) that macro's template — unresolved tokens stay in the live
--     text, so "what we last wrote" is the only way to tell our output from
--     a hand edit;
--   * a managed macro whose body we didn't write and that has no token has
--     been hand-edited away, so we stop managing it;
--   * every managed macro is rewritten to match the current group.
function Macros.Sync(reason)
    if InCombatLockdown() then
        pendingAfterCombat = true
        return
    end
    local units = Resolve.Units(DB.DropSelf(), DB.Pins())
    Macros.lastUnits = units

    eachMacro(function(index, scope, name, icon, body)
        local entry = DB.Get(scope, name)
        local ours = entry and body == entry.lastBody
        if Expand.HasToken(body) and not ours then
            if not entry or entry.template ~= body then
                entry = { template = body }
                DB.Set(scope, name, entry)
                say("now managing macro |cffffff00%s|r", name)
            end
        elseif entry and not ours then
            DB.Forget(scope, name)
            say("macro |cffffff00%s|r was edited without a token; no longer managing it", name)
            return
        end
        if not entry then return end

        local desired = Expand.Body(entry.template, units)
        if #desired > 255 then
            say("|cffff4444%s|r would be %d characters after expansion (limit 255); left unchanged", name, #desired)
            return
        end
        if desired ~= body then
            EditMacro(index, name, icon, desired)
            if reason then
                say("updated |cffffff00%s|r (%s)", name, reason)
            end
        end
        entry.lastBody = desired
    end)
end

function Macros.OnCombatEnd()
    if pendingAfterCombat then
        pendingAfterCombat = false
        Macros.Sync("after combat")
    end
end

function Macros.Forget(name)
    local found = false
    for _, scope in ipairs({ "account", "character" }) do
        if DB.Forget(scope, name) then found = true end
    end
    return found
end
