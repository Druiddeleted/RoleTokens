local ADDON_NAME, NS = ...
NS.Names = {}
local Names = NS.Names

-- Everything about identifying a person: character names, realms, Battle.net
-- friends. Deliberately thin so the resolver and the UI share one spelling.
--
-- Stored character form is always "Name-Realm" with the realm normalized
-- (spaces removed, apostrophes kept), which is what UnitFullName, the guild
-- roster and the friends list all agree on. Comparison is case-insensitive.

local function ownRealm()
    local r = GetNormalizedRealmName and GetNormalizedRealmName()
    if not r or r == "" then r = (GetRealmName() or ""):gsub("%s", "") end
    return r
end
Names.OwnRealm = ownRealm

-- "Name" -> "Name-OwnRealm"; "Name-Realm" -> unchanged; realm spaces removed.
function Names.Normalize(text)
    if not text or text == "" then return nil end
    local name, realm = text:match("^([^%-]+)%-(.+)$")
    if not name then name, realm = text, ownRealm() end
    realm = realm:gsub("%s", "")
    return name .. "-" .. realm
end

function Names.Key(full) return full and full:lower() or nil end

-- "Name-Realm" of a group unit, or nil.
function Names.UnitFull(unit)
    local name, realm = UnitFullName(unit)
    if not name then return nil end
    if not realm or realm == "" then realm = ownRealm() end
    return name .. "-" .. realm
end

-- Drop "-Realm" when it is the player's own realm (display only).
function Names.Short(full)
    if not full then return nil end
    local name, realm = full:match("^([^%-]+)%-(.+)$")
    if name and realm and realm:lower() == ownRealm():lower() then return name end
    return full
end

-- "SuperNinja#1201821" -> "SuperNinja"
function Names.TagPrefix(tag)
    return tag and tag:match("^([^#]+)") or tag
end

-- The Battle.net friend a group unit belongs to, if any: battleTag, accountInfo.
function Names.FriendOfUnit(unit)
    local guid = UnitGUID(unit)
    if not guid or not C_BattleNet or not C_BattleNet.GetAccountInfoByGUID then return nil end
    local acct = C_BattleNet.GetAccountInfoByGUID(guid)
    if acct and acct.battleTag then return acct.battleTag, acct end
    return nil
end

-- "Name-Realm" the friend is currently on, from a BNetAccountInfo, or nil.
-- friendIndex (optional) lets us look past the primary game account.
function Names.FriendCharacter(acct, friendIndex)
    local function fromGame(g)
        if g and g.clientProgram == "WoW" and g.characterName and g.characterName ~= "" then
            local realm = (g.realmName or ""):gsub("%s", "")
            if realm == "" then return nil end
            return g.characterName .. "-" .. realm
        end
    end
    local c = acct and fromGame(acct.gameAccountInfo)
    if c or not friendIndex then return c end
    local n = C_BattleNet.GetFriendNumGameAccounts(friendIndex) or 0
    for j = 1, n do
        c = fromGame(C_BattleNet.GetFriendGameAccountInfo(friendIndex, j))
        if c then return c end
    end
    return nil
end

-- Every friend whose BattleTag prefix matches text (case-insensitive prefix
-- match, exact match preferred). Returns a list of { tag=, char=, index= }.
function Names.FindFriends(text)
    local out, exact = {}, {}
    if not text or text == "" or not BNGetNumFriends then return out end
    local want = text:lower()
    for i = 1, (BNGetNumFriends() or 0) do
        local acct = C_BattleNet.GetFriendAccountInfo(i)
        local tag = acct and acct.battleTag
        if tag then
            local prefix = Names.TagPrefix(tag):lower()
            if prefix == want or tag:lower() == want then
                exact[#exact + 1] = { tag = tag, char = Names.FriendCharacter(acct, i), index = i }
            elseif prefix:sub(1, #want) == want then
                out[#out + 1] = { tag = tag, char = Names.FriendCharacter(acct, i), index = i }
            end
        end
    end
    if #exact > 0 then return exact end
    return out
end

-- Is this stored entry the same person as the given identity?
--   entry: { kind = "char", name = "Name-Realm" } or { kind = "bnet", tag = "X#1" }
function Names.EntryMatches(entry, charFull, tag)
    if entry.kind == "char" then
        return charFull ~= nil and Names.Key(entry.name) == Names.Key(charFull)
    elseif entry.kind == "bnet" then
        return tag ~= nil and entry.tag:lower() == tag:lower()
    end
    return false
end

-- Label shown for an entry in the window and status output. Never shows the
-- BattleTag number; two friends with the same prefix are told apart by the
-- status column (current or last-seen character), not by the label.
function Names.Label(entry)
    if entry.kind == "bnet" then return Names.TagPrefix(entry.tag) end
    return Names.Short(entry.name)
end
