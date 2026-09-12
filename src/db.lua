local ADDON_NAME, NS = ...
NS.DB = {}
local DB = NS.DB

-- Schema (account-wide file, per-scope tables):
--   RoleTokensDB.account[macroName]                = { template = "...", lastBody = "..." }
--   RoleTokensDB.characters[charKey][macroName]    = same shape, for character macros
--   RoleTokensDB.dropSelf                          = true  (never resolve a token to yourself)
local defaults = {
    account = {},
    characters = {},
    dropSelf = true,
    verbose = true,
    pins = {},        -- [charKey] = { tank = "Name", healer = "Name", ... }
}

local function charKey()
    return GetRealmName() .. "-" .. UnitName("player")
end

function DB.Init()
    RoleTokensDB = RoleTokensDB or {}
    for k, v in pairs(defaults) do
        if RoleTokensDB[k] == nil then
            if type(v) == "table" then RoleTokensDB[k] = {} else RoleTokensDB[k] = v end
        end
    end
    RoleTokensDB.characters[charKey()] = RoleTokensDB.characters[charKey()] or {}
    RoleTokensDB.pins[charKey()] = RoleTokensDB.pins[charKey()] or {}
end

-- Pins are per character: "on this hunter, @tank is Brutall whenever he's in my group."
function DB.Pins() return RoleTokensDB.pins[charKey()] end
function DB.SetPin(token, name)
    RoleTokensDB.pins[charKey()][token] = name   -- nil clears
end

-- scope is "account" or "character"
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
