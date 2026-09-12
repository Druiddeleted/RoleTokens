local ADDON_NAME, NS = ...
NS.Resolve = {}
local Resolve = NS.Resolve
local Expand = NS.Expand

-- Group-state lookup only: roles and raid assignments are ordinary group
-- data, not combat data, so Secret Values don't apply here. Still, we only
-- run this out of combat because macros can't be edited in combat anyway.

local function groupUnits()
    local units = {}
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do units[#units + 1] = "raid" .. i end
    elseif IsInGroup() then
        for i = 1, GetNumSubgroupMembers() do units[#units + 1] = "party" .. i end
    end
    return units
end

local function sameName(unit, name)
    local n, realm = UnitName(unit)
    if not n then return false end
    if n == name then return true end
    return realm and realm ~= "" and (n .. "-" .. realm) == name
end

local ROLE_OF = { TANK = "tank", HEALER = "healer", DAMAGER = "dps" }

-- Returns { tank1 = unit, tank2 = unit, ..., healer1 = unit, ..., dps1 = unit, ... }
-- with only the resolved keys present.
--
-- Slot order per role: pinned players first, in their pinned slots; then the
-- raid main tank (for tanks); then raid/party index. A pinned player who is in
-- the group takes their slot regardless of role (you asked for them by name).
--   pins: { tank1 = "Name", healer3 = "Name", ... }
function Resolve.Units(dropSelf, pins)
    pins = pins or {}
    local byRole, all = { tank = {}, healer = {}, dps = {} }, {}
    local inRaid = IsInRaid()
    for _, unit in ipairs(groupUnits()) do
        if not (dropSelf and UnitIsUnit(unit, "player")) then
            all[#all + 1] = unit
            local role = ROLE_OF[UnitGroupRolesAssigned(unit)]
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

    local function findByName(name)
        for _, unit in ipairs(all) do
            if sameName(unit, name) then return unit end
        end
    end

    local out = {}
    for _, role in ipairs(Expand.ROLES) do
        -- 1. pins claim their slots
        local taken = {}
        local maxSlot = 0
        for slot = 1, Expand.MAX_SLOT do
            local name = pins[Expand.Key(role, slot)]
            local unit = name and findByName(name)
            if unit and not taken[unit] then
                out[Expand.Key(role, slot)] = unit
                taken[unit] = true
                maxSlot = slot
            end
        end
        -- 2. everyone else with the role fills the remaining slots in order
        local slot = 1
        for _, unit in ipairs(byRole[role]) do
            if not taken[unit] then
                while out[Expand.Key(role, slot)] do slot = slot + 1 end
                if slot > Expand.MAX_SLOT then break end
                out[Expand.Key(role, slot)] = unit
                taken[unit] = true
            end
        end
    end
    return out
end

-- Human-readable "party3 (Brutall)" for status output.
function Resolve.Describe(unit)
    if not unit then return "|cff888888none|r" end
    local name = UnitName(unit)
    if name then return unit .. " (" .. name .. ")" end
    return unit
end
