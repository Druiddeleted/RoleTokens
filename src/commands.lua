local ADDON_NAME, NS = ...
NS.Commands = {}
local DB, Expand, Resolve, Macros, Names = NS.DB, NS.Expand, NS.Resolve, NS.Macros, NS.Names

local TAG = "|cff33ff99[RoleTokens]|r "
local function out(fmt, ...) print(TAG .. fmt:format(...)) end
local Y = function(s) return "|cffffff00" .. tostring(s) .. "|r" end
local GREY = function(s) return "|cff888888" .. tostring(s) .. "|r" end

local UNIT_WORDS = { target = true, focus = true, mouseover = true, player = true }
local function isUnitWord(w)
    w = (w or ""):lower()
    return UNIT_WORDS[w] or w:match("^party%d$") or w:match("^raid%d+$")
end

-- ---- status ---------------------------------------------------------------
local function tokenLine(name, token)
    local units = Macros.lastUnits or {}
    local slots = {}
    for slot = 1, #token.entries do
        local u = units[Expand.Key(name, slot)]
        if not u then break end
        slots[#slots + 1] = ("@%s%s -> %s"):format(name, slot == 1 and "" or slot, Resolve.Describe(u))
    end
    local filter = token.role and (" " .. GREY(token.role .. " only")) or ""
    out("  %s%s  %s", Y("@" .. name), filter, #slots > 0 and table.concat(slots, "  ") or Resolve.Describe(nil))
end

local function status()
    local units = Macros.lastUnits or {}
    out("built-in tokens:")
    for _, role in ipairs(Expand.ROLES) do
        local shown = false
        for slot = 1, Expand.MAX_SLOT do
            local unit = units[Expand.Key(role, slot)]
            if unit then
                shown = true
                out("  @%-9s -> %s", Expand.Key(role, slot), Resolve.Describe(unit))
            end
        end
        if not shown then out("  @%-9s -> %s", role, Resolve.Describe(nil)) end
    end
    local names = DB.TokenNames()
    if #names > 0 then
        out("your tokens:")
        for _, name in ipairs(names) do tokenLine(name, DB.Token(name)) end
    else
        out("no custom tokens yet. /rtk token <name> add target")
    end
    local any = false
    DB.Each(function(scope, name, entry)
        any = true
        out("  managing %s (%s macro)", Y(name), scope)
    end)
    if not any then
        out("no macros managed yet. Put @tank, @healer, @dps or one of your tokens in any macro and it will be picked up.")
    end
end

local function help()
    out("usage:")
    out("  /rtk                     - show resolved tokens and managed macros")
    out("  /rtk ui                  - open the RoleTokens page in Options > AddOns")
    out("  /rtk minimap             - show or hide the minimap button")
    out("  /rtk refresh             - re-scan macros and rewrite now")
    out("  /rtk forget <MacroName>  - stop managing a macro (its current text stays)")
    out("  /rtk token               - list your tokens")
    out("  /rtk token <name>        - show one token")
    out("  /rtk token <name> add target|focus|mouseover|partyN|raidN")
    out("  /rtk token <name> add <Name> [<Name-Realm> ...]")
    out("  /rtk token <name> add friend <name|target>   - a Battle.net friend, on any character")
    out("  /rtk token <name> remove <position|name>")
    out("  /rtk token <name> move <from> <to>")
    out("  /rtk token <name> role tank|healer|dps|any              - filter for the whole list")
    out("  /rtk token <name> role <position|name> tank|healer|dps|any - filter for one person")
    out("  /rtk token <name> except <friend> <target|Name-Realm>  - never that character")
    out("  /rtk token <name> allow <friend> <Name-Realm>          - undo an except")
    out("  /rtk token <name> clear | delete")
    out("  /rtk quiet | verbose     - chat notices;  /rtk debug - log sync timings to SavedVariables")
    out("tokens: @tank/@healer/@dps by role, @<name>/@<name>N by your list. Slot N is the Nth person present.")
    out("fallbacks belong to the macro: [@pi,exists,nodead] [@pi2,exists,nodead] [@dps,exists,nodead]")
end

-- ---- token display --------------------------------------------------------
local function showToken(name)
    local token = DB.Token(name)
    if not token then out("no token named @%s", name) return end
    local _, detail = Resolve.Units(DB.DropSelf(), { [name] = token }, true)
    local rows = detail[name] or {}
    out("%s%s", Y("@" .. name), token.role and GREY("  " .. token.role .. " only") or "")
    if #rows == 0 then out("  (empty) /rtk token %s add target", name) return end
    for i, r in ipairs(rows) do
        local e = r.entry
        local label = Names.Label(e)
        if e.kind == "bnet" then label = label .. GREY(" (friend)") end
        if e.role then label = label .. GREY(" [" .. e.role .. "]") end
        local slot = r.slot and Y(("  @%s%s"):format(name, r.slot == 1 and "" or r.slot)) or ""
        out("  %d. %-24s %s%s", i, label, GREY(r.status), slot)
        if e.kind == "bnet" and e.exclude then
            local ex = {}
            for k in pairs(e.exclude) do ex[#ex + 1] = k end
            table.sort(ex)
            out("       except %s", GREY(table.concat(ex, ", ")))
        end
    end
end

-- ---- helpers for editing --------------------------------------------------
-- Find an entry by position or by label/name/tag; returns index or nil.
local function findEntry(token, word)
    local n = tonumber(word)
    if n and token.entries[n] then return n end
    local w = (word or ""):lower()
    for i, e in ipairs(token.entries) do
        if e.kind == "char" then
            if Names.Key(e.name) == w or Names.Key(Names.Normalize(w)) == Names.Key(e.name) then return i end
        else
            if e.tag:lower() == w or Names.TagPrefix(e.tag):lower() == w then return i end
        end
    end
    return nil
end

local pendingFriends = nil   -- last ambiguous "add friend" list, picked by number

local function resolveFriend(word)
    if isUnitWord(word) then
        local tag = Names.FriendOfUnit(word)
        if not tag then return nil, ("%s is not a Battle.net friend"):format(word) end
        return tag
    end
    local n = tonumber(word)
    if n and pendingFriends and pendingFriends[n] then return pendingFriends[n].tag end
    local found = Names.FindFriends(word)
    if #found == 0 then return nil, ("no friend whose BattleTag starts with '%s'"):format(word) end
    if #found == 1 then return found[1].tag end
    pendingFriends = found
    out("%d friends match '%s'. Pick one by number:", #found, word)
    for i, f in ipairs(found) do
        out("  %d. %s  %s", i, Names.TagPrefix(f.tag), GREY(f.char and ("on " .. f.char) or "not in WoW right now"))
    end
    return nil, "then: /rtk token <name> add friend <number>"
end

local function unitOrName(word)
    if isUnitWord(word) then
        local full = Names.UnitFull(word)
        if not full then return nil, ("%s is nobody right now"):format(word) end
        return full
    end
    return Names.Normalize(word)
end

-- ---- /rtk token ... -------------------------------------------------------
local function tokenCmd(rest)
    local name, sub, args = rest:match("^@?(%S+)%s*(%S*)%s*(.*)$")
    if not name or name == "" then
        local names = DB.TokenNames()
        if #names == 0 then out("no custom tokens yet. /rtk token <name> add target") return end
        for _, n in ipairs(names) do tokenLine(n, DB.Token(n)) end
        return
    end
    name = name:lower()
    sub = (sub or ""):lower()
    if Expand.IsRole(name) then
        out("@%s is built in and resolves by role. Make your own: /rtk token my%s add target, then /rtk token my%s role %s", name, name, name, name)
        return
    end
    local token = DB.Token(name)
    if sub == "" or sub == "show" then
        if not token then
            local ok, why = Expand.ValidName(name)
            if not ok then out("no token @%s (%s)", name, why) else out("no token @%s yet. /rtk token %s add target", name, name) end
            return
        end
        showToken(name)
        return
    end

    local words = {}
    for w in args:gmatch("%S+") do words[#words + 1] = w end

    if sub == "add" then
        if not token then
            local ok, why = Expand.ValidName(name)
            if not ok then out("can't call a token @%s: %s", name, why) return end
            token = DB.CreateToken(name)
            out("created %s", Y("@" .. name))
        end
        if #words == 0 then out("add whom? /rtk token %s add target  (or a Name, or: add friend <name>)", name) return end
        if words[1]:lower() == "friend" then
            local tag, err = resolveFriend(words[2] or "")
            if not tag then out("%s", err) return end
            local _, new = DB.AddEntry(token, { kind = "bnet", tag = tag })
            out("%s %s %s", Y("@" .. name), new and "now includes friend" or "already had friend", Names.TagPrefix(tag))
            pendingFriends = nil
        else
            for _, w in ipairs(words) do
                local full, err = unitOrName(w)
                if not full then out("%s", err)
                else
                    local _, new = DB.AddEntry(token, { kind = "char", name = full })
                    out("%s %s %s", Y("@" .. name), new and "now includes" or "already had", Names.Short(full))
                end
            end
        end
    elseif not token then
        out("no token @%s", name) return
    elseif sub == "remove" then
        local i = words[1] and findEntry(token, words[1])
        if not i then out("remove which? position or name: /rtk token %s", name) return end
        local e = DB.RemoveEntry(token, i)
        out("removed %s from %s", Names.Label(e), Y("@" .. name))
    elseif sub == "move" then
        local from, to = tonumber(words[1]), tonumber(words[2])
        if not (from and to and DB.MoveEntry(token, from, to)) then out("usage: /rtk token %s move <from> <to>", name) return end
        out("moved %s to position %d in %s", Names.Label(token.entries[to]), to, Y("@" .. name))
    elseif sub == "role" then
        local function parseRole(w)
            w = (w or ""):lower()
            if w == "none" or w == "any" then return nil, true end
            if Expand.IsRole(w) then return w, true end
            return nil, false
        end
        if words[2] then                       -- role <position|name> <role|any>: one person
            local i = findEntry(token, words[1])
            local r, ok = parseRole(words[2])
            if not i or not ok then out("usage: /rtk token %s role <position|name> tank|healer|dps|any", name) return end
            DB.SetEntryRole(token.entries[i], r)
            out("%s counts on %s only while %s", Names.Label(token.entries[i]), Y("@" .. name), r and ("playing " .. r) or "any role (the token's filter applies)")
        else                                   -- role <role|any>: the whole token
            local r, ok = parseRole(words[1])
            if not ok then out("role must be tank, healer, dps or any") return end
            DB.SetRole(name, r)
            out("%s role filter: %s", Y("@" .. name), token.role or "any")
        end
    elseif sub == "except" or sub == "allow" then
        local i = words[1] and findEntry(token, words[1])
        local e = i and token.entries[i]
        if not e or e.kind ~= "bnet" then out("usage: /rtk token %s %s <friend> <target|Name-Realm>  (the friend must be on the list)", name, sub) return end
        local full, err = unitOrName(words[2] or "")
        if not full then out("%s", err or "which character?") return end
        DB.SetExclude(e, full, sub == "except")
        out("%s %s %s on %s", Names.TagPrefix(e.tag), sub == "except" and "will never count on" or "may count again on", Names.Short(full), Y("@" .. name))
    elseif sub == "clear" then
        token.entries = {}
        out("%s is now empty", Y("@" .. name))
    elseif sub == "delete" then
        DB.DeleteToken(name)
        out("deleted %s. Macros that mention @%s keep the text; it is no longer rewritten.", Y("@" .. name), name)
    else
        out("unknown token command '%s'. /rtk help", sub)
        return
    end
    Macros.Sync("token changed")
end

SLASH_ROLETOKENS1 = "/roletokens"
SLASH_ROLETOKENS2 = "/rtk"
SlashCmdList.ROLETOKENS = function(msg)
    msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local cmd, rest = msg:match("^(%S+)%s*(.*)$")
    cmd = (cmd or ""):lower()
    if cmd == "" or cmd == "status" then
        Macros.Sync()
        status()
    elseif cmd == "ui" or cmd == "show" then
        if NS.UI then NS.UI.Toggle() end
    elseif cmd == "refresh" then
        Macros.Sync("manual refresh")
        status()
    elseif cmd == "forget" then
        if rest == "" then out("forget which macro?") return end
        if Macros.Forget(rest) then out("no longer managing %s", Y(rest))
        else out("not managing any macro named %s", Y(rest)) end
    elseif cmd == "token" or cmd == "tokens" then
        tokenCmd(rest)
    elseif cmd == "pin" or cmd == "unpin" then
        out("pins are now tokens: /rtk token mytank add <Name>, /rtk token mytank role tank, then [@mytank,exists,nodead] [@tank,exists,nodead]")
    elseif cmd == "minimap" then
        if NS.Minimap then NS.Minimap.SetShown(DB.Minimap().hide == true) end
    elseif cmd == "quiet" then
        DB.SetVerbose(false); out("notices off")
    elseif cmd == "verbose" then
        DB.SetVerbose(true); out("notices on")
    elseif cmd == "debug" then
        DB.SetDebug(not DB.Debug())
        if DB.Debug() then out("debug on: sync timings go to RoleTokensLog (SavedVariables, written on /reload)")
        else out("debug off") end
    elseif cmd == "clearlog" then
        DB.ClearLog(); out("log cleared")
    else
        help()
    end
end
