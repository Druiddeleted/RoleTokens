local ADDON_NAME, NS = ...
NS.Resolve = {}
local Resolve = NS.Resolve

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

-- Returns { tank = unit, tank2 = unit, healer = unit, healer2 = unit } with
-- only the resolved keys present. In a raid the assigned main tank is always
-- @tank; otherwise order follows raid/party index.
-- pins: { tank = "Name", healer = "Name" } — a pinned player, if present in
-- the group, takes that slot regardless of index or role; the rest shift down.
-- Precedence for slot 1: pin > raid main tank assignment > lowest raid index.
local function sameName(unit, name)
    local n, realm = UnitName(unit)
    if not n then return false end
    if n == name then return true end
    return realm and realm ~= "" and (n .. "-" .. realm) == name
end

function Resolve.Units(dropSelf, pins)
    pins = pins or {}
    local tanks, healers, all = {}, {}, {}
    local inRaid = IsInRaid()
    for _, unit in ipairs(groupUnits()) do
        if not (dropSelf and UnitIsUnit(unit, "player")) then
            all[#all + 1] = unit
            local role = UnitGroupRolesAssigned(unit)
            if role == "TANK" then
                if inRaid and GetPartyAssignment("MAINTANK", unit) then
                    table.insert(tanks, 1, unit)
                else
                    tanks[#tanks + 1] = unit
                end
            elseif role == "HEALER" then
                healers[#healers + 1] = unit
            end
        end
    end
    -- A pinned player who is in the group but not in that role list still
    -- wins the slot (you asked for them by name), so search the whole group.
    local function pinned(name)
        if not name then return nil end
        for _, unit in ipairs(all) do
            if sameName(unit, name) then return unit end
        end
    end
    local function pick(list, pin1, pin2)
        local first, second = pinned(pin1), pinned(pin2)
        local rest = {}
        for _, u in ipairs(list) do
            if u ~= first and u ~= second then rest[#rest + 1] = u end
        end
        first = first or table.remove(rest, 1)
        second = second or table.remove(rest, 1)
        if first == second then second = table.remove(rest, 1) end
        return first, second
    end
    local t1, t2 = pick(tanks, pins.tank, pins.tank2)
    local h1, h2 = pick(healers, pins.healer, pins.healer2)
    return { tank = t1, tank2 = t2, healer = h1, healer2 = h2 }
end

-- Human-readable "party3 (Brutall)" for status output.
function Resolve.Describe(unit)
    if not unit then return "|cff888888none|r" end
    local name = UnitName(unit)
    if name then return unit .. " (" .. name .. ")" end
    return unit
end
