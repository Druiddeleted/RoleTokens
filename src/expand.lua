local ADDON_NAME, NS = ...
NS.Expand = {}
local Expand = NS.Expand

-- Pure text transform: no frames, no WoW API. Loadable under plain Lua for tests.
--
-- A token is "@" + a known name, case-insensitive, not followed by another
-- word character (so "@tank" matches, "@tanky" does not). Known names:
Expand.TOKENS = { "tank", "tank2", "healer", "healer2" }

local known = {}
for _, t in ipairs(Expand.TOKENS) do known[t] = true end

-- Does this macro body contain any token at all?
function Expand.HasToken(body)
    if not body then return false end
    for name in body:gmatch("@(%w+)") do
        if known[name:lower()] then return true end
    end
    return false
end

-- Replace tokens within one piece of text. Returns text and whether any token
-- could not be resolved (so the caller can decide to drop the whole clause).
local function substitute(text, units)
    local missing = false
    local out = text:gsub("@(%w+)", function(name)
        local key = name:lower()
        if not known[key] then return nil end          -- leave unrelated "@foo" alone
        local unit = units[key]
        if unit then return "@" .. unit end
        missing = true
        return "@none"
    end)
    return out, missing
end

-- Expand a template into a live macro body.
--   units: { tank = "party3", healer = "raid12", ... } — absent keys are unresolved.
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
