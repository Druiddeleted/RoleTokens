local ADDON_NAME, NS = ...
NS.Expand = {}
local Expand = NS.Expand

-- Pure text transform: no frames, no WoW API. Loadable under plain Lua for tests.
--
-- A token is "@" + name + optional slot number, case-insensitive:
--   @tank  @tank1 ... @tank40   (@tank == @tank1)   built in, by role
--   @healer, @dps                                   built in, by role
--   @pi, @pi2 ...                                   custom, by priority list
-- "@tanky" is not a token (the word must end after the digits).
Expand.ROLES = { "tank", "healer", "dps" }
Expand.MAX_SLOT = 40

local isRole = {}
for _, r in ipairs(Expand.ROLES) do isRole[r] = true end
Expand.IsRole = function(name) return isRole[name] == true end

-- "@Tank12" -> "tank", 12 ; anything else -> nil
--   known: optional set of lower-case custom token names ({ pi = true, ... })
function Expand.ParseToken(word, known)
    local name, num = word:lower():match("^(%a+)(%d*)$")
    if not name then return nil end
    if not isRole[name] and not (known and known[name]) then return nil end
    local slot = tonumber(num) or 1
    if num == "" then slot = 1 elseif slot < 1 or slot > Expand.MAX_SLOT then return nil end
    return name, slot
end

-- Canonical key used in the units table: "tank1", "healer3", "pi2", ...
function Expand.Key(name, slot) return name .. slot end

-- Does this macro body contain any token at all?
function Expand.HasToken(body, known)
    if not body then return false end
    for word in body:gmatch("@(%w+)") do
        if Expand.ParseToken(word, known) then return true end
    end
    return false
end

-- Expand a template into a live macro body.
--   units: { tank1 = "party3", pi1 = "raid12", ... } — absent keys are unresolved.
-- An unresolved token is left exactly as written: "tank" is not a unit, so
-- [@tank,exists,nodead] fails and the macro falls through to the next clause,
-- and the macro page still reads the way you wrote it. (A clause without
-- "exists" would try to cast at nobody and error rather than fall through,
-- but that clause was already wrong for a missing tank.)
--
-- Because the live macro can therefore still contain tokens, the scanner must
-- not mistake our own output for a hand-edited template: see Macros.Sync.
function Expand.Body(template, units, known)
    if not template then return template end
    local body = template:gsub("@(%w+)", function(word)
        local name, slot = Expand.ParseToken(word, known)
        if not name then return nil end                -- leave unrelated "@foo" alone
        local unit = units[Expand.Key(name, slot)]
        return unit and ("@" .. unit) or nil
    end)
    return body
end

-- Custom token names: letters only, 2-12 characters, and never something the
-- client already treats as a unit (so we never rewrite a real macro target).
local RESERVED = {
    player = true, target = true, focus = true, mouseover = true, pet = true,
    party = true, raid = true, boss = true, arena = true, cursor = true,
    none = true, vehicle = true, nameplate = true, npc = true,
    softenemy = true, softfriend = true, softinteract = true,
    tank = true, healer = true, dps = true,
}
local RESERVED_PREFIX = { "party", "raid", "boss", "arena", "nameplate", "soft", "pet",
                          "target", "focus", "mouseover", "player", "vehicle" }

-- Returns lower-case name, or nil plus a reason.
function Expand.ValidName(text)
    local name = (text or ""):lower()
    if not name:match("^%a+$") then return nil, "letters only, no digits or symbols" end
    if #name < 2 or #name > 12 then return nil, "2 to 12 letters" end
    if RESERVED[name] then return nil, "'" .. name .. "' is a unit the client already understands" end
    for _, p in ipairs(RESERVED_PREFIX) do
        if name:sub(1, #p) == p then return nil, "names starting with '" .. p .. "' would collide with real units" end
    end
    return name
end
