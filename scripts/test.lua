-- Run: luajit scripts/test.lua   (from the RoleTokens directory)
-- Loads expand.lua and resolve.lua with the WoW globals stubbed and asserts
-- the text transform and role ordering behave as documented.
local NS = {}
local function load(file) assert(loadfile(file))("RoleTokens", NS) end
load("src/expand.lua")
load("src/resolve.lua")
local E, R = NS.Expand, NS.Resolve

local function eq(got, want, label)
    if got ~= want then
        error(("%s\n  want: %s\n  got:  %s"):format(label, tostring(want), tostring(got)), 2)
    end
end

-- ---- Expand -------------------------------------------------------------
local md = "#showtooltip\n/cast [@tank,exists,nodead] [@mouseover,exists,help,nodead] [@party1,exists,nodead] [@pet,exists,nodead] [] Misdirection"
eq(E.HasToken(md), true, "detects token")
eq(E.HasToken("/cast [@focus] Kick"), false, "no false positive")
eq(E.HasToken("/cast [@tanky] X"), false, "word boundary")
eq(E.HasToken("/cast [@tank41] X"), false, "slot above 40 is not a token")
eq(E.HasToken("/cast [@tank0] X"), false, "slot 0 is not a token")
eq(E.HasToken("/cast [@healer12] X"), true, "numbered token")
eq(E.HasToken("/cast [@dps] X"), true, "dps token")
eq(E.HasToken("/say hi @Tank"), true, "case-insensitive")

eq(E.Body(md, { tank1 = "party3" }),
   "#showtooltip\n/cast [@party3,exists,nodead] [@mouseover,exists,help,nodead] [@party1,exists,nodead] [@pet,exists,nodead] [] Misdirection",
   "substitutes tank")
eq(E.Body(md, {}),
   "#showtooltip\n/cast [@none,exists,nodead] [@mouseover,exists,help,nodead] [@party1,exists,nodead] [@pet,exists,nodead] [] Misdirection",
   "unresolved token becomes @none, clause kept")
eq(E.Body("/cast [@tank1] [@healer] [] Innervate", { healer1 = "raid7" }),
   "/cast [@none] [@raid7] [] Innervate", "mixed resolved/unresolved")
eq(E.Body("/cast [@Tank,exists] X", { tank1 = "party2" }), "/cast [@party2,exists] X", "case-insensitive substitution")
eq(E.Body("/tar @tank", {}), "/tar @none", "bare token becomes @none")
eq(E.Body("/tar @tank", { tank1 = "raid3" }), "/tar @raid3", "bare token substituted")
eq(E.Body("/cast [@healer12] X", { healer12 = "raid40" }), "/cast [@raid40] X", "high slot")
eq(E.Body("/cast [@focus,harm] Kick", { tank1 = "party1" }), "/cast [@focus,harm] Kick", "untouched macro unchanged")

-- ---- Resolve ------------------------------------------------------------
local G = {}
function IsInRaid() return G.raid end
function IsInGroup() return G.raid or (G.units and #G.units > 0) end
function GetNumGroupMembers() return #G.units end
function GetNumSubgroupMembers() return #G.units end
function UnitIsUnit(u, other) return G.names[u] == "Me" end
function UnitGroupRolesAssigned(u) return G.roles[u] or "NONE" end
function GetPartyAssignment(kind, u) return G.mt == u end
function UnitName(u) return G.names[u] end

local function party(spec)
    G = { raid = false, units = {}, roles = {}, names = {} }
    for i, s in ipairs(spec) do
        local u = "party" .. i
        G.units[#G.units + 1] = u; G.roles[u] = s[1]; G.names[u] = s[2]
    end
end
local function raid(spec, mt)
    G = { raid = true, units = {}, roles = {}, names = {}, mt = mt }
    for i, s in ipairs(spec) do
        local u = "raid" .. i
        G.units[#G.units + 1] = u; G.roles[u] = s[1]; G.names[u] = s[2]
    end
end

party({ {"DAMAGER","A"}, {"TANK","Brutall"}, {"HEALER","Moon"}, {"DAMAGER","B"} })
local u = R.Units(true, {})
eq(u.tank1, "party2", "party tank"); eq(u.healer1, "party3", "party healer"); eq(u.tank2, nil, "no second tank")
eq(u.dps1, "party1", "dps1"); eq(u.dps2, "party4", "dps2")

party({})
u = R.Units(true, {})
eq(u.tank1, nil, "solo has no tank")

raid({ {"TANK","T1"}, {"HEALER","H1"}, {"TANK","T2"}, {"HEALER","H2"}, {"HEALER","H3"} }, "raid3")
u = R.Units(true, {})
eq(u.tank1, "raid3", "main tank assignment wins"); eq(u.tank2, "raid1", "other tank second")
eq(u.healer1, "raid2", "first healer by index"); eq(u.healer2, "raid4", "second healer"); eq(u.healer3, "raid5", "third healer")

u = R.Units(true, { healer1 = "H3", tank1 = "T1" })
eq(u.healer1, "raid5", "pinned healer first"); eq(u.healer2, "raid2", "rest shift down"); eq(u.healer3, "raid4", "rest keep order")
eq(u.tank1, "raid1", "pin beats main tank"); eq(u.tank2, "raid3", "main tank shifts to tank2")

u = R.Units(true, { healer1 = "Nobody" })
eq(u.healer1, "raid2", "absent pin falls back to index order")

u = R.Units(true, { tank2 = "T1" })
eq(u.tank2, "raid1", "tank2 pin honored"); eq(u.tank1, "raid3", "tank stays main tank")

u = R.Units(true, { healer3 = "H1" })
eq(u.healer3, "raid2", "pin into a high slot"); eq(u.healer1, "raid4", "others fill below"); eq(u.healer2, "raid5", "others fill below 2")

u = R.Units(true, { healer1 = "H1", healer2 = "H1" })
eq(u.healer1, "raid2", "same player pinned twice keeps first"); eq(u.healer2, "raid4", "second slot goes to next")

-- Pinned player without the role still gets the slot (explicit choice).
raid({ {"TANK","T1"}, {"DAMAGER","Off"}, {"TANK","T2"} })
u = R.Units(true, { tank1 = "Off" })
eq(u.tank1, "raid2", "pin can pick a non-role unit"); eq(u.tank2, "raid1", "tanks shift")
eq(u.dps1, "raid2", "pinned unit still appears in its own role list")

-- 40 healers resolve to 40 slots.
local spec = {}
for i = 1, 40 do spec[i] = { "HEALER", "H" .. i } end
raid(spec, nil)
u = R.Units(true, {})
eq(u.healer1, "raid1", "healer1 of 40"); eq(u.healer40, "raid40", "healer40 of 40"); eq(u.healer41, nil, "no slot 41")

-- Self is excluded when dropSelf is on.
party({ {"TANK","Me"}, {"HEALER","H"} })
u = R.Units(true, {})
eq(u.tank1, nil, "self excluded")
u = R.Units(false, {})
eq(u.tank1, "party1", "self allowed when dropSelf off")

print("all tests passed")
