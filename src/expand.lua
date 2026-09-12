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

-- Replace tokens within one piece of text. Returns text and whether any token
-- could not be resolved (so the caller can decide to drop the whole clause).
local function substitute(text, units)
    local missing = false
    local out = text:gsub("@(%w+)", function(word)
        local role, slot = Expand.ParseToken(word)
        if not role then return nil end                -- leave unrelated "@foo" alone
        local unit = units[Expand.Key(role, slot)]
        if unit then return "@" .. unit end
        missing = true
        return "@none"
    end)
    return out, missing
end

-- Expand a template into a live macro body.
--   units: { tank1 = "party3", healer2 = "raid12", ... } — absent keys are unresolved.
-- Rules:
--   * inside a [conditional] group, an unresolved token deletes the whole group
--     (and the whitespace after it) so the macro falls through to the next clause;
--   * outside brackets an unresolved token becomes "@none", which never exists.
function Expand.Body(template, units)
    if not template then return template end
    local body = template:gsub("(%[[^%]]*%])(%s*)", function(group, ws)
        local out, missing = substitute(group, units)
        if missing then return "" end
        return out .. ws
    end)
    body = substitute(body, units)
    return body
end
