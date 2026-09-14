local ADDON_NAME, NS = ...
NS.Resolve = {}
local Resolve = NS.Resolve
local Expand, Names = NS.Expand, NS.Names

-- Group-state lookup only: roles and raid assignments are ordinary group
-- data, not combat data, so Secret Values don't apply here. Still, we only
-- run this out of combat because macros can't be edited in combat anyway.
--
-- Cost per call is bounded by group size (<= 40) x tokens x entries, plus one
-- GUID -> Battle.net lookup per unit when any token lists a friend. Nothing
-- here runs per frame; Macros.Sync calls it once per coalesced event burst.

local function groupUnits()
    local units = {}
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do units[#units + 1] = "raid" .. i end
    elseif IsInGroup() then
        for i = 1, GetNumSubgroupMembers() do units[#units + 1] = "party" .. i end
    end
    return units
end

local ROLE_OF = { TANK = "tank", HEALER = "healer", DAMAGER = "dps" }
Resolve.ROLE_OF = ROLE_OF

-- Returns { tank1 = unit, ..., pi1 = unit, pi2 = unit, ... } with only the
-- resolved keys present, and (when wantDetail) a per-token explanation:
--   detail[name] = { { entry = e, unit = u|nil, slot = n|nil, status = "..." }, ... }
--
-- Built-in tokens: raid main tank first (tank only), then everyone assigned
-- that role by group index. Custom tokens: entries in list order, present in
-- the group, matching the role filter if one is set, each person once.
--   tokens: DB.Tokens()  { pi = { role = "dps"|nil, entries = {...} }, ... }
function Resolve.Units(dropSelf, tokens, wantDetail)
    local byRole, all = { tank = {}, healer = {}, dps = {} }, {}
    local roleOf, fullOf = {}, {}
    local inRaid = IsInRaid()
    for _, unit in ipairs(groupUnits()) do
        if not (dropSelf and UnitIsUnit(unit, "player")) then
            all[#all + 1] = unit
            local role = ROLE_OF[UnitGroupRolesAssigned(unit)]
            roleOf[unit] = role
            if role then
                local list = byRole[role]
                if role == "tank" and inRaid and GetPartyAssignment("MAINTANK", unit) then
                    table.insert(list, 1, unit)
                else
                    list[#list + 1] = unit
                end
            end
        end
    end

    local out = {}
    for _, role in ipairs(Expand.ROLES) do
        for slot, unit in ipairs(byRole[role]) do
            if slot > Expand.MAX_SLOT then break end
            out[Expand.Key(role, slot)] = unit
        end
    end

    if not tokens or next(tokens) == nil then return out, wantDetail and {} or nil end

    -- Lazy per-unit identity, computed at most once per sync.
    local tagOf, tagKnown = {}, {}
    local function fullName(unit)
        local f = fullOf[unit]
        if f == nil then f = Names.UnitFull(unit) or false; fullOf[unit] = f end
        return f or nil
    end
    local function friendTag(unit)
        if not tagKnown[unit] then
            tagKnown[unit] = true
            tagOf[unit] = Names.FriendOfUnit(unit) or false
        end
        return tagOf[unit] or nil
    end

    local detail = wantDetail and {} or nil
    for name, token in pairs(tokens) do
        local slot, taken = 0, {}
        local rows = detail and {} or nil
        for _, entry in ipairs(token.entries) do
            local unit, status
            local wantKey = entry.kind == "char" and Names.Key(Names.Normalize(entry.name)) or nil
            for _, u in ipairs(all) do
                if entry.kind == "char" then
                    local f = fullName(u)
                    if f and Names.Key(f) == wantKey then unit = u break end
                elseif entry.kind == "bnet" then
                    local t = friendTag(u)
                    if t and t:lower() == entry.tag:lower() then
                        unit = u
                        local f = fullName(u)
                        if f and entry.lastSeen ~= f then entry.lastSeen = f end
                        break
                    end
                end
            end
            local resolved
            if unit then
                local f = fullName(unit)
                if entry.kind == "bnet" and entry.exclude and f and entry.exclude[Names.Key(f)] then
                    status = "excluded"
                elseif token.role and roleOf[unit] ~= token.role then
                    status = (roleOf[unit] and (roleOf[unit] == "dps" and "dps" or roleOf[unit] == "tank" and "tanking" or "healing") or "no role") .. " · skipped"
                elseif taken[unit] then
                    status = "already listed"
                elseif slot >= Expand.MAX_SLOT then
                    status = "no slot left"
                else
                    slot = slot + 1
                    taken[unit] = true
                    out[Expand.Key(name, slot)] = unit
                    resolved = slot
                    status = "on " .. (f or unit)
                end
            else
                if entry.kind == "bnet" and entry.lastSeen then status = "last seen " .. entry.lastSeen
                else status = "not in group" end
            end
            if rows then rows[#rows + 1] = { entry = entry, unit = unit, slot = resolved, status = status } end
        end
        if detail then detail[name] = rows end
    end
    return out, detail
end

-- Human-readable "party3 (Brutall)" for status output.
function Resolve.Describe(unit)
    if not unit then return "|cff888888none|r" end
    local name = UnitName(unit)
    if name then return unit .. " (" .. name .. ")" end
    return unit
end
