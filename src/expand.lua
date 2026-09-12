local ADDON_NAME, NS = ...
NS.Expand = {}
local Expand = NS.Expand

-- Pure text transform: no frames, no WoW API. Loadable under plain Lua for tests.
--
-- A token is "@" + role + optional slot number, case-insensitive:
--   @tank  @tank1 ... @tank40   (@tank == @tank1)
--   @healer @healer1 ... @healer40
--   @dps    @dps1   ... @dps40
-- "@tanky" is not a token (the word must end after the digits).
Expand.ROLES = { "tank", "healer", "dps" }
Expand.MAX_SLOT = 40

local isRole = {}
for _, r in ipairs(Expand.ROLES) do isRole[r] = true end

-- "@Tank12" -> "tank", 12 ; anything else -> nil
function Expand.ParseToken(word)
    local role, num = word:lower():match("^(%a+)(%d*)$")
    if not role or not isRole[role] then return nil end
    local slot = tonumber(num) or 1
    if num == "" then slot = 1 elseif slot < 1 or slot > Expand.MAX_SLOT then return nil end
    return role, slot
end

-- Canonical key used in the units table and for pins: "tank1", "healer3", ...
function Expand.Key(role, slot) return role .. slot end

-- Does this macro body contain any token at all?
function Expand.HasToken(body)
    if not body then return false end
    for word in body:gmatch("@(%w+)") do
        if Expand.ParseToken(word) then return true end
    end
    return false
end

-- Expand a template into a live macro body.
--   units: { tank1 = "party3", healer2 = "raid12", ... } — absent keys are unresolved.
-- An unresolved token becomes "@none": a unit that never exists, so a clause
-- like [@none,exists,nodead] fails and the macro falls through to the next one.
-- The clause itself is kept so the macro still reads as written on the macro
-- page. (A clause without "exists" would try to cast at @none and error rather
-- than fall through, but that clause was already wrong for a missing tank.)
Expand.UNRESOLVED = "none"

function Expand.Body(template, units)
    if not template then return template end
    local body = template:gsub("@(%w+)", function(word)
        local role, slot = Expand.ParseToken(word)
        if not role then return nil end                -- leave unrelated "@foo" alone
        return "@" .. (units[Expand.Key(role, slot)] or Expand.UNRESOLVED)
    end)
    return body
end
