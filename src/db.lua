local ADDON_NAME, NS = ...
NS.DB = {}
local DB = NS.DB

-- Schema (account-wide file):
--   RoleTokensDB.account[macroName]                = { template = "...", lastBody = "..." }
--   RoleTokensDB.characters[charKey][macroName]    = same shape, for character macros
--   RoleTokensDB.dropSelf                          = true  (never resolve a token to yourself)
--   RoleTokensDB.tokens[name]                      = { role = "dps"|nil, entries = { entry, ... } }
--     entry = { kind = "char", name = "Name-Realm", role = "dps"|nil }
--           | { kind = "bnet", tag = "Tag#1234", role = ..., lastSeen = "Name-Realm"|nil, exclude = { [key] = true }|nil }
--     entry.role overrides the token's role filter for that person.
--   RoleTokensDB.ui                                = window position
--   RoleTokensDB.schema                            = 2
-- RoleTokensLog is a separate SavedVariable: a capped list of debug lines.
local defaults = {
    account = {},
    characters = {},
    dropSelf = true,
    verbose = true,
    tokens = {},
    ui = {},
    minimap = {},     -- LibDBIcon state: { hide = bool, minimapPos = angle }
    debug = false,
}
local SCHEMA = 2

local function charKey()
    return GetRealmName() .. "-" .. UnitName("player")
end

local notices = {}   -- migration messages, printed by core after PLAYER_LOGIN

-- Schema 1 kept per-character pins on the built-in tokens. Those become
-- custom tokens (mytank / myhealer / mydps) with a role filter, so the same
-- person is picked first whenever they are here and playing that role.
local function migratePins()
    local pins = RoleTokensDB.pins
    if type(pins) ~= "table" then return end
    local Names = NS.Names
    local order = {}
    for ck in pairs(pins) do order[#order + 1] = ck end
    table.sort(order)
    for _, role in ipairs({ "tank", "healer", "dps" }) do
        local list, seen = {}, {}
        for pass = 1, 2 do                       -- slot-1 pins first, then the rest
            for _, ck in ipairs(order) do
                local realm = (ck:match("^(.-)%-[^%-]+$") or ""):gsub("%s", "")
                local keys = {}
                for k in pairs(pins[ck]) do keys[#keys + 1] = k end
                table.sort(keys)
                for _, k in ipairs(keys) do
                    local r, slot = k:match("^(%a+)(%d*)$")
                    slot = tonumber(slot) or 1
                    if r == role and ((pass == 1 and slot == 1) or (pass == 2 and slot > 1)) then
                        local name = pins[ck][k]
                        local full = name:find("-", 1, true) and name or (name .. "-" .. realm)
                        if not seen[full:lower()] then
                            seen[full:lower()] = true
                            list[#list + 1] = { kind = "char", name = full }
                        end
                    end
                end
            end
        end
        if #list > 0 then
            local tname = "my" .. role
            RoleTokensDB.tokens[tname] = { role = role, entries = list }
            local names = {}
            for _, e in ipairs(list) do names[#names + 1] = Names and Names.Short(e.name) or e.name end
            notices[#notices + 1] = ("your @%s pin is now the token |cffffff00@%s|r (%s). Use [@%s,exists,nodead] [@%s,exists,nodead] in macros that relied on it."):format(
                role, tname, table.concat(names, ", "), tname, role)
        end
    end
    RoleTokensDB.pins = nil
end

function DB.Init()
    RoleTokensDB = RoleTokensDB or {}
    RoleTokensLog = RoleTokensLog or {}
    for k, v in pairs(defaults) do
        if RoleTokensDB[k] == nil then
            if type(v) == "table" then RoleTokensDB[k] = {} else RoleTokensDB[k] = v end
        end
    end
    RoleTokensDB.characters[charKey()] = RoleTokensDB.characters[charKey()] or {}
    if (RoleTokensDB.schema or 1) < 2 then migratePins() end
    RoleTokensDB.schema = SCHEMA
end

function DB.TakeNotices()
    local n = notices
    notices = {}
    return n
end

-- ---- macros (unchanged) ---------------------------------------------------
local function bucket(scope)
    if scope == "account" then return RoleTokensDB.account end
    return RoleTokensDB.characters[charKey()]
end

function DB.Get(scope, name)          return bucket(scope)[name] end
function DB.Set(scope, name, entry)   bucket(scope)[name] = entry end
function DB.Forget(scope, name)
    local had = bucket(scope)[name] ~= nil
    bucket(scope)[name] = nil
    return had
end

function DB.Each(fn)
    for name, e in pairs(RoleTokensDB.account) do fn("account", name, e) end
    for name, e in pairs(bucket("character")) do fn("character", name, e) end
end

function DB.DropSelf() return RoleTokensDB.dropSelf ~= false end
function DB.Verbose()  return RoleTokensDB.verbose ~= false end
function DB.SetVerbose(on) RoleTokensDB.verbose = on and true or false end
function DB.Debug()    return RoleTokensDB.debug == true end
function DB.SetDebug(on) RoleTokensDB.debug = on and true or false end
function DB.UI()       return RoleTokensDB.ui end
function DB.Minimap()  return RoleTokensDB.minimap end

-- ---- tokens ---------------------------------------------------------------
function DB.Tokens() return RoleTokensDB.tokens end
function DB.Token(name) return RoleTokensDB.tokens[name] end

-- Sorted list of custom token names.
function DB.TokenNames()
    local out = {}
    for name in pairs(RoleTokensDB.tokens) do out[#out + 1] = name end
    table.sort(out)
    return out
end

-- Set of lower-case names for the expander; built once per sync.
function DB.KnownTokens()
    local set = {}
    for name in pairs(RoleTokensDB.tokens) do set[name] = true end
    return set
end

function DB.CreateToken(name)
    if RoleTokensDB.tokens[name] then return RoleTokensDB.tokens[name], false end
    RoleTokensDB.tokens[name] = { entries = {} }
    return RoleTokensDB.tokens[name], true
end

function DB.DeleteToken(name)
    local had = RoleTokensDB.tokens[name] ~= nil
    RoleTokensDB.tokens[name] = nil
    return had
end

function DB.SetRole(name, role)          -- role: "tank"|"healer"|"dps"|nil
    RoleTokensDB.tokens[name].role = role
end

-- Index of the entry matching this identity, or nil.
function DB.FindEntry(token, charFull, tag)
    for i, e in ipairs(token.entries) do
        if NS.Names.EntryMatches(e, charFull, tag) then return i end
    end
    return nil
end

-- Append; returns index and whether it was new.
function DB.AddEntry(token, entry)
    local i = DB.FindEntry(token, entry.kind == "char" and entry.name or nil, entry.kind == "bnet" and entry.tag or nil)
    if i then return i, false end
    token.entries[#token.entries + 1] = entry
    return #token.entries, true
end

function DB.RemoveEntry(token, index)
    return table.remove(token.entries, index)
end

function DB.MoveEntry(token, from, to)
    local n = #token.entries
    if from < 1 or from > n or to < 1 or to > n or from == to then return false end
    local e = table.remove(token.entries, from)
    table.insert(token.entries, to, e)
    return true
end

function DB.SetEntryRole(entry, role)     -- role: "tank"|"healer"|"dps"|nil (nil = token's filter)
    entry.role = role
end

function DB.SetExclude(entry, charFull, on)
    if entry.kind ~= "bnet" then return end
    entry.exclude = entry.exclude or {}
    entry.exclude[NS.Names.Key(charFull)] = on and true or nil
    if next(entry.exclude) == nil then entry.exclude = nil end
end

-- ---- debug log ------------------------------------------------------------
local LOG_MAX = 300
function DB.Log(line)
    local log = RoleTokensLog
    log[#log + 1] = date("%H:%M:%S ") .. line
    if #log > LOG_MAX then table.remove(log, 1) end
end
function DB.ClearLog() RoleTokensLog = {} end
