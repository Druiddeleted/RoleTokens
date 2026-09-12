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
eq(E.HasToken("/say hi @Tank"), true, "case-insensitive")

eq(E.Body(md, { tank = "party3" }),
   "#showtooltip\n/cast [@party3,exists,nodead] [@mouseover,exists,help,nodead] [@party1,exists,nodead] [@pet,exists,nodead] [] Misdirection",
   "substitutes tank")
eq(E.Body(md, {}),
   "#showtooltip\n/cast [@mouseover,exists,help,nodead] [@party1,exists,nodead] [@pet,exists,nodead] [] Misdirection",
   "drops the whole clause when unresolved")
eq(E.Body("/cast [@tank] [@healer] [] Innervate", { healer = "raid7" }),
   "/cast [@raid7] [] Innervate", "mixed resolved/unresolved")
eq(E.Body("/cast [@Tank,exists] X", { tank = "party2" }), "/cast [@party2,exists] X", "case-insensitive substitution")
eq(E.Body("/tar @tank", {}), "/tar @none", "bare token becomes @none")
eq(E.Body("/tar @tank", { tank = "raid3" }), "/tar @raid3", "bare token substituted")
eq(E.Body("/cast [@focus,harm] Kick", { tank = "party1" }), "/cast [@focus,harm] Kick", "untouched macro unchanged")

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
eq(u.tank, "party2", "party tank"); eq(u.healer, "party3", "party healer"); eq(u.tank2, nil, "no second tank")

party({})
u = R.Units(true, {})
eq(u.tank, nil, "solo has no tank")

raid({ {"TANK","T1"}, {"HEALER","H1"}, {"TANK","T2"}, {"HEALER","H2"}, {"HEALER","H3"} }, "raid3")
u = R.Units(true, {})
eq(u.tank, "raid3", "main tank assignment wins"); eq(u.tank2, "raid1", "other tank second")
eq(u.healer, "raid2", "first healer by index"); eq(u.healer2, "raid4", "second healer")

u = R.Units(true, { healer = "H3", tank = "T1" })
eq(u.healer, "raid5", "pinned healer first"); eq(u.healer2, "raid2", "rest shift down")
eq(u.tank, "raid1", "pin beats main tank"); eq(u.tank2, "raid3", "main tank shifts to tank2")

u = R.Units(true, { healer = "Nobody" })
eq(u.healer, "raid2", "absent pin falls back to index order")

u = R.Units(true, { tank2 = "T1" })
eq(u.tank2, "raid1", "tank2 pin honored"); eq(u.tank, "raid3", "tank stays main tank")

-- Pinned player without the role still gets the slot (explicit choice).
raid({ {"TANK","T1"}, {"DAMAGER","Off"}, {"TANK","T2"} })
u = R.Units(true, { tank = "Off" })
eq(u.tank, "raid2", "pin can pick a non-role unit"); eq(u.tank2, "raid1", "tanks shift")

-- Self is excluded when dropSelf is on.
party({ {"TANK","Me"}, {"HEALER","H"} })
u = R.Units(true, {})
eq(u.tank, nil, "self excluded")
u = R.Units(false, {})
eq(u.tank, "party1", "self allowed when dropSelf off")

print("all tests passed")
