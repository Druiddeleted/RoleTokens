-- Run: luajit scripts/test.lua   (from the RoleTokens directory)
-- Loads the frame-free modules with the WoW globals stubbed and asserts the
-- text transform, resolution order, name handling and pin migration.
local NS = {}
local function load(file) assert(loadfile(file))("RoleTokens", NS) end

-- ---- WoW stubs ----------------------------------------------------------
local G = {}
function IsInRaid() return G.raid end
function IsInGroup() return G.raid or (G.units and #G.units > 0) end
function GetNumGroupMembers() return #G.units end
function GetNumSubgroupMembers() return #G.units end
function UnitIsUnit(u, other) return G.names[u] == "Me" end
function UnitGroupRolesAssigned(u) return G.roles[u] or "NONE" end
function GetPartyAssignment(kind, u) return G.mt == u end
function UnitName(u) return G.names[u] end
function UnitFullName(u)
    local n = G.names[u]; if not n then return nil end
    local name, realm = n:match("^([^%-]+)%-(.+)$")
    return name or n, realm or ""
end
function UnitGUID(u) return G.names[u] and ("Player-" .. G.names[u]) or nil end
function GetNormalizedRealmName() return "Tichondrius" end
function GetRealmName() return "Tichondrius" end
function BNGetNumFriends() return #(G.friends or {}) end
C_BattleNet = {
    GetAccountInfoByGUID = function(guid)
        for _, f in ipairs(G.friends or {}) do
            if guid == "Player-" .. ((f.char or ""):match("^[^%-]+") or "") then return { battleTag = f.tag, gameAccountInfo = { clientProgram = "WoW", characterName = f.char:match("^[^%-]+"), realmName = f.char:match("%-(.+)$") } } end
        end
    end,
    GetFriendAccountInfo = function(i)
        local f = G.friends[i]
        return { battleTag = f.tag, gameAccountInfo = f.char and { clientProgram = "WoW", characterName = f.char:match("^[^%-]+"), realmName = f.char:match("%-(.+)$") } or { clientProgram = "App" } }
    end,
    GetFriendNumGameAccounts = function() return 0 end,
}
function date(fmt) return "00:00:00 " end

load("src/names.lua")
load("src/expand.lua")
load("src/db.lua")
load("src/resolve.lua")
local N, E, D, R = NS.Names, NS.Expand, NS.DB, NS.Resolve

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
eq(E.HasToken("/say hi @Tank"), true, "case-insensitive")
eq(E.HasToken("/cast [@pi] X"), false, "unknown custom token is plain text")
eq(E.HasToken("/cast [@pi] X", { pi = true }), true, "known custom token")
eq(E.HasToken("/cast [@PI3] X", { pi = true }), true, "custom token numbered, any case")

eq(E.Body(md, { tank1 = "party3" }),
   "#showtooltip\n/cast [@party3,exists,nodead] [@mouseover,exists,help,nodead] [@party1,exists,nodead] [@pet,exists,nodead] [] Misdirection",
   "substitutes tank")
eq(E.Body(md, {}), md, "unresolved token is left as written")
eq(E.Body("/cast [@Tank1] [@healer] [] Innervate", { healer1 = "raid7" }),
   "/cast [@Tank1] [@raid7] [] Innervate", "mixed resolved/unresolved keeps original spelling")
eq(E.Body("/cast [@pi,exists,nodead] [@pi2,exists,nodead] [@dps,exists,nodead] [] PI", { pi1 = "raid17", dps1 = "raid4" }, { pi = true }),
   "/cast [@raid17,exists,nodead] [@pi2,exists,nodead] [@raid4,exists,nodead] [] PI", "custom token chain")
eq(E.Body("/cast [@pi] X", { pi1 = "raid1" }), "/cast [@pi] X", "custom token not expanded when unknown")

eq(E.ValidName("pi"), "pi", "valid name")
eq(E.ValidName("PI"), "pi", "name lower-cased")
eq(E.ValidName("focus"), nil, "reserved unit")
eq(E.ValidName("party"), nil, "reserved family")
eq(E.ValidName("raidx"), nil, "reserved prefix")
eq(E.ValidName("tank"), nil, "built-in")
eq(E.ValidName("pi2"), nil, "no digits")
eq(E.ValidName("x"), nil, "too short")
eq(E.ValidName("innervate"), "innervate", "long enough name ok")

-- ---- Names --------------------------------------------------------------
eq(N.Normalize("Bob"), "Bob-Tichondrius", "own realm appended")
eq(N.Normalize("Bob-Area 52"), "Bob-Area52", "realm spaces removed")
eq(N.Normalize("Grîm-Kel'Thuzad"), "Grîm-Kel'Thuzad", "apostrophe kept")
eq(N.Short("Bob-Tichondrius"), "Bob", "own realm hidden")
eq(N.Short("Bob-Illidan"), "Bob-Illidan", "other realm shown")
eq(N.TagPrefix("SuperNinja#1201821"), "SuperNinja", "tag prefix")
eq(N.Label({ kind = "bnet", tag = "SuperNinja#1201821" }), "SuperNinja", "friend label has no number")
eq(N.EntryMatches({ kind = "char", name = "bob-illidan" }, "Bob-Illidan"), true, "char match case-insensitive")
eq(N.EntryMatches({ kind = "bnet", tag = "A#1" }, nil, "a#1"), true, "tag match case-insensitive")

-- ---- Resolve: built-ins unchanged ----------------------------------------
local function party(spec, friends)
    G = { raid = false, units = {}, roles = {}, names = {}, friends = friends or {} }
    for i, s in ipairs(spec) do
        local u = "party" .. i
        G.units[#G.units + 1] = u; G.roles[u] = s[1]; G.names[u] = s[2]
    end
end
local function raid(spec, mt, friends)
    G = { raid = true, units = {}, roles = {}, names = {}, mt = mt, friends = friends or {} }
    for i, s in ipairs(spec) do
        local u = "raid" .. i
        G.units[#G.units + 1] = u; G.roles[u] = s[1]; G.names[u] = s[2]
    end
end

party({ {"DAMAGER","A"}, {"TANK","Brutall"}, {"HEALER","Moon"}, {"DAMAGER","B"} })
local u = R.Units(true, {})
eq(u.tank1, "party2", "party tank"); eq(u.healer1, "party3", "party healer"); eq(u.tank2, nil, "no second tank")
eq(u.dps1, "party1", "dps1"); eq(u.dps2, "party4", "dps2")

party({}); u = R.Units(true, {}); eq(u.tank1, nil, "solo has no tank")

raid({ {"TANK","T1"}, {"HEALER","H1"}, {"TANK","T2"}, {"HEALER","H2"}, {"HEALER","H3"} }, "raid3")
u = R.Units(true, {})
eq(u.tank1, "raid3", "main tank assignment wins"); eq(u.tank2, "raid1", "other tank second")
eq(u.healer1, "raid2", "first healer by index"); eq(u.healer3, "raid5", "third healer")

local spec = {}
for i = 1, 40 do spec[i] = { "HEALER", "H" .. i } end
raid(spec, nil); u = R.Units(true, {})
eq(u.healer1, "raid1", "healer1 of 40"); eq(u.healer40, "raid40", "healer40 of 40"); eq(u.healer41, nil, "no slot 41")

party({ {"TANK","Me"}, {"HEALER","H"} })
u = R.Units(true, {}); eq(u.tank1, nil, "self excluded")
u = R.Units(false, {}); eq(u.tank1, "party1", "self allowed when dropSelf off")

-- ---- Resolve: custom tokens -----------------------------------------------
local function tok(role, ...) return { role = role, entries = { ... } } end
local function ch(n) return { kind = "char", name = n } end
local function bn(t, ex) return { kind = "bnet", tag = t, exclude = ex } end

-- Alice dps, Bob healer, Carol dps, Dave tank
party({ {"DAMAGER","Alice"}, {"HEALER","Bob"}, {"DAMAGER","Carol"}, {"TANK","Dave"} })
u = R.Units(true, { pi = tok(nil, ch("Bob"), ch("Alice")) })
eq(u.pi1, "party2", "pi = Bob (no filter)"); eq(u.pi2, "party1", "pi2 = Alice"); eq(u.pi3, nil, "pi3 none")

u = R.Units(true, { pi = tok("dps", ch("Bob"), ch("Alice")) })
eq(u.pi1, "party1", "role filter skips healer Bob"); eq(u.pi2, nil, "pi2 none: fallback is the macro's job")

u = R.Units(true, { md = tok("tank", ch("Alice")) })
eq(u.md1, nil, "wrong role -> unresolved")

u = R.Units(true, { pi = tok(nil, ch("bob-tichondrius"), ch("Alice-Tichondrius")) })
eq(u.pi1, "party2", "stored Name-Realm form, case-insensitive")

u = R.Units(true, { pi = tok(nil, ch("Alice"), ch("Alice")) })
eq(u.pi1, "party1", "dup entry once"); eq(u.pi2, nil, "dup entry not twice")

u = R.Units(true, { pi = tok(nil, ch("Nobody"), ch("Carol")) })
eq(u.pi1, "party3", "absent entry skipped, next takes slot 1")

-- per-entry role overrides the token's: Alice only as dps, Bob only as tank
u = R.Units(true, { pi = tok(nil, { kind = "char", name = "Alice", role = "dps" }, { kind = "char", name = "Bob", role = "tank" }, { kind = "char", name = "Dave", role = "tank" }) })
eq(u.pi1, "party1", "entry role dps matches Alice"); eq(u.pi2, "party4", "Bob healing skipped, Dave tanking counts")
u = R.Units(true, { pi = tok("dps", { kind = "char", name = "Dave", role = "tank" }, ch("Bob")) })
eq(u.pi1, "party4", "entry role overrides token filter"); eq(u.pi2, nil, "token filter still applies to others")

-- friend entries: Bob is SuperNinja#1 on Bob-Tichondrius
party({ {"DAMAGER","Alice"}, {"HEALER","Bob"}, {"DAMAGER","Carol"} }, { { tag = "SuperNinja#1", char = "Bob-Tichondrius" } })
local t = tok(nil, bn("superninja#1"))
u = R.Units(true, { pi = t })
eq(u.pi1, "party2", "friend matched by GUID"); eq(t.entries[1].lastSeen, "Bob-Tichondrius", "lastSeen recorded")

u = R.Units(true, { pi = tok(nil, bn("SuperNinja#1", { ["bob-tichondrius"] = true }), ch("Carol")) })
eq(u.pi1, "party3", "excluded character skipped")

-- character entry outranks the friend entry for the same person
u = R.Units(true, { pi = tok(nil, ch("Alice"), bn("SuperNinja#1")) })
eq(u.pi1, "party1", "char first"); eq(u.pi2, "party2", "friend second")
u = R.Units(true, { pi = tok(nil, ch("Bob"), bn("SuperNinja#1"), ch("Carol")) })
eq(u.pi1, "party2", "Bob by char"); eq(u.pi2, "party3", "friend entry for same person skipped, Carol next")

-- detail
local _, det = R.Units(true, { pi = tok("dps", ch("Bob"), bn("SuperNinja#1"), ch("Carol"), ch("Zed")) }, true)
eq(det.pi[1].status, "healing · skipped", "detail: wrong role")
eq(det.pi[2].status, "healing · skipped", "detail: friend wrong role")
eq(det.pi[3].status, "on Carol-Tichondrius", "detail: resolved"); eq(det.pi[3].slot, 1, "detail: slot")
eq(det.pi[4].status, "not in group", "detail: absent")

-- two tokens are independent
u = R.Units(true, { pi = tok(nil, ch("Alice")), inn = tok(nil, ch("Alice"), ch("Carol")) })
eq(u.pi1, "party1", "token a"); eq(u.inn1, "party1", "token b same person"); eq(u.inn2, "party3", "token b second")

-- ---- DB: pin migration -----------------------------------------------------
G.names = { player = "Me" }
RoleTokensDB = { schema = nil, pins = {
    ["Tichondrius-Me"]   = { tank1 = "Brutall", healer1 = "Moon", healer2 = "Sun" },
    ["Area 52-Alt"]      = { tank1 = "Brutall", tank2 = "Wall" },
} }
D.Init()
eq(RoleTokensDB.schema, 2, "schema bumped"); eq(RoleTokensDB.pins, nil, "pins removed")
local mt = RoleTokensDB.tokens.mytank
eq(mt.role, "tank", "mytank role")
eq(mt.entries[1].name, "Brutall-Area52", "slot-1 pins first, realm from charKey, spaces stripped")
eq(mt.entries[2].name, "Brutall-Tichondrius", "same bare name on another realm is another character")
eq(mt.entries[3].name, "Wall-Area52", "slot-2 pin after all slot-1 pins")
eq(#mt.entries, 3, "three distinct characters")
eq(RoleTokensDB.tokens.myhealer.entries[2].name, "Sun-Tichondrius", "healer2 pin kept in order")
eq(RoleTokensDB.tokens.mydps, nil, "no dps pins, no token")
eq(#D.TakeNotices(), 2, "one notice per created token")

-- token ops
local pt = D.CreateToken("pi")
D.AddEntry(pt, ch("A-X")); D.AddEntry(pt, ch("B-X")); D.AddEntry(pt, ch("a-x"))
eq(#pt.entries, 2, "AddEntry dedups"); D.MoveEntry(pt, 2, 1); eq(pt.entries[1].name, "B-X", "MoveEntry")
D.SetExclude(bn("T#1"), "X-Y", true)
local be = bn("T#1"); D.SetExclude(be, "X-Y", true); eq(be.exclude["x-y"], true, "exclude set"); D.SetExclude(be, "X-Y", false); eq(be.exclude, nil, "exclude cleared")
eq(D.KnownTokens().pi, true, "KnownTokens")

print("all tests passed")
