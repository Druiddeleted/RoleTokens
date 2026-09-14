# Custom tokens: design

Status: **proposal, nothing built.** This is the plan for turning the fixed
`@tank/@healer/@dps` tokens into user-defined tokens backed by a priority list.
Every section that ends in an open question needs an answer before the code
for that section starts.

## 1. The idea

Today a token is a role. You write `@tank` and get "whoever is tanking."
The real need is closer to "whoever I Power Infusion," and the answer to that
is a person, chosen from a ranked list of regulars, not a role. The same person
can be first for PI and absent from the Innervate list.

So: **a token is a name you choose, backed by an ordered list of people,
optionally filtered by role.**

```
/cast [@pi,exists,nodead] [@healer,exists,nodead] [] Power Infusion
```

`@pi` is the first person on the PI list who is in the group. `@pi2` is the
second. A slot with nobody to fill it is left as written and the clause
fails, exactly as today. Fallbacks belong to the macro, not the token: a
trailing `[@dps,exists,nodead]` clause is "anyone, if none of my list is
here," and `[@pi,exists,nodead] [@pi2,exists,nodead]` is "my second choice
if my first is dead." The client evaluates those at cast time, which the
addon never could.

`@tank`, `@healer` and `@dps` stay exactly what they are today: plain role
tokens with no list behind them, resolved by role assignment and group index
(main tank first for `@tank`). They are the defaults.
Priority lives only in tokens you create. "My preferred tanks, in order" is a
custom token with a tank filter, and the macro falls back to `@tank`:

```
/rtk token mt add Brutall
/rtk token mt role tank
/cast [@mt,exists,nodead] [@tank,exists,nodead] [] Misdirection
```

That is also what the current per-character **pin** was, so pins go away and
are migrated into a token (see migration).

## 2. Token definition

| Field      | Type                       | Meaning                                                                                |
|------------|----------------------------|----------------------------------------------------------------------------------------|
| `name`     | string, key                | What you write after `@`. See naming rules.                                            |
| `entries`  | ordered list of entries    | People, highest priority first. May be empty.                                          |
| `role`     | `tank`/`healer`/`dps`/nil  | If set, an entry only counts while that player is assigned this role.                  |
| `builtin`  | true for tank/healer/dps   | No entries, fixed role. Can't be edited, deleted or re-created.                        |

An **entry** is one of:

- **Character**: `Name-Realm`, always stored with the realm (see names).
- **Battle.net friend**: a BattleTag (stored, never typed: see below), with
  an optional **exclusion list** of characters. Matches whichever character that friend is currently playing
  unless it is excluded. This is how "Bob, on whatever alt he brought, but
  never his warrior" works without listing every alt. Only resolvable while
  the friend is online and on your friends list, which is always true when
  they're in your group.

You never see or type the `#1234` part. The friends list API gives the addon
every friend's BattleTag, so entries are created from the unit menu (a friends
list row, a guild roster row, or a grouped player who is a friend) or from
`add friend <text>`, which matches the part before the number. The full tag
is stored because it is the identifier that survives relogs.

**Labels.** The friends-list display name is a protected Kstring: it renders
but can't be compared, so the addon can't even detect two friends with the
same display name. The BattleTag prefix is plain text, so:

- The label is the BattleTag prefix, e.g. `SuperNinja`. **The number is
  never shown in a label.**
- Each Battle.net entry keeps `lastSeen`, the `Name-Realm` the friend was
  last seen on a WoW client: set when added, refreshed on every friends list
  update and whenever they're in the group.
- If two entries on the same token share a prefix (case-insensitive), those
  entries, and only those, get a suffix: the character they're on now if
  online, else `lastSeen`, e.g. `Bob (Bobpriest-Area52)`. If neither exists
  (added from the friends list while they were only on the mobile app) the
  suffix is `(no character seen)` until they log in once, and the tag is in
  that row's tooltip as a last resort.
- The Kstring display name is shown in the row tooltip, where rendering is
  all that's needed.
- The picker shows the current character on every friend row, so two Bobs
  are told apart before you click.
- `add friend <text>` with several prefix matches lists them with the
  character each is on now (or `lastSeen`) and accepts a position from that
  list. The menu and the picker never hit this case.

The two kinds combine. Because entries are matched in order and a person is
used at most once per token, a specific alt can outrank the rest of that
person's characters:

```
1  Bobmage-Area52     character: Bob on his mage is @pi
2  Alice-Stormrage
3  Bob (friend)       Battle.net: Bob on anything else is third
```

Guild members who are not Battle.net friends are added as characters, one alt
each. The guild roster gives no reliable main/alt link, so the addon doesn't
guess one.

### Naming rules

- Letters only, 2 to 12 characters, stored lower-case, matched
  case-insensitively. `@PI` and `@pi` are the same token.
- No trailing digits: the digits are the slot number (`@pi2`).
- Reserved: every unit token the client already understands, so the addon
  never rewrites a real macro target. `player target focus mouseover pet
  party raid boss arena cursor none vehicle nameplate npc softenemy softfriend
  softinteract` plus anything starting with those. Also `tank healer dps`
  (built-in, can't be re-created).
- Unrelated `@word` text in macros that doesn't name a token is untouched, as
  today. Creating a token called `@bob` when you have `@bob` written somewhere
  as plain text will start rewriting it; the status output shows every managed
  macro so this is visible.

## 3. Resolution

Each token produces an **ordered candidate sequence** of units. Slot N of the
token is the Nth unit in the sequence. A unit appears at most once per
sequence. You are never a candidate (`dropSelf`, as today).

```
sequence(builtin role token) =
    (tank only) the raid main tank assignment
 ++ everyone assigned that role, by group index

sequence(custom token) =
    entries that are present in the group, in list order,
        skipping any whose assigned role doesn't match token.role (if set)
```

Worked examples, group has Alice (dps), Bob (healer), Carol (dps), Dave (tank):

| Token                              | @token | @token2 | @token3 |
|------------------------------------|--------|---------|---------|
| `pi` = [Bob, Alice], role nil       | Bob    | Alice   | (none)  |
| `pi` = [Bob, Alice], role dps       | Alice  | (none)  |         |
| `md` = [Alice], role tank           | (none) |         |         |
| `tank` (built-in)                   | Dave   | (none)  |         |

Rules that fall out of this:

- A person on the list who is present but in the wrong role is skipped, not
  demoted.
- Slots past the last present entry are unresolved. The macro decides what
  to do about that with its next clause.
- An unassigned role (player hasn't picked one yet) matches no filter. Roles
  are re-read on every roster/role event, so they slot in once assigned.

The resolver output stays the same shape as today, `{ [tokenName..slot] =
unit }`, so `Expand.Body` needs no change beyond recognising user token names.

## 4. Characters, realms, alts

**Your alts.** Tokens are account-wide. A PI list only matters on a priest,
but it does no harm elsewhere and you may have two priests. There is no
per-character token scope in the first version; if a real need shows up,
`entries` could later carry an optional "only on these characters" mark.

**Their alts.** Add the person as a Battle.net entry when they're a friend;
otherwise add each character. The picker (section 6) shows both forms.

**Realms.** Group members from other realms show up as `Name-Realm` with realm
spaces removed (`Ærin-Area52`). The addon stores every character entry in that
full form, filling in your own realm when a typed name has none. Matching is
case-insensitive on both halves. Because names never contain spaces, slash
commands can split on whitespace safely; the only thing a user must not type
is a realm with spaces, and the help text says so.

**Migration.** On first load with the new schema, pins are converted into
custom tokens and the `pins` table is deleted. A pin on `tank1` becomes token
`mytank` with that name (as `Name-<the pinning character's realm>`) and role
tank; `healer1` becomes `myhealer`, `dps1` becomes `mydps`.
Pins on slot 2+ are appended after slot-1 pins. Pins from several characters
merge into one list in character order; duplicates drop. The addon prints one
notice per created token so the user knows to change `@tank` to
`[@mytank,exists,nodead] [@tank,exists,nodead]` in the macros that relied on
the pin. Macros are not rewritten automatically,
because `@tank` may also be used where the plain role was wanted. This loses
"pinned regardless of role"; the README will say so.

## 5. Slash commands

Everything about tokens lives under `/rtk token`. Names are never required
when there's a way to point at the person instead.

```
/rtk token                          list every token, its settings, and what each slot resolves to now
/rtk token pi                       show one token in full, present people highlighted
/rtk token pi add target            add the unit you're targeting (also focus, mouseover, party3, raid7)
/rtk token pi add Ærin Bob-Stormrage   add typed names, appended in the order given
/rtk token pi add friend Bob        add a Battle.net friend; matches the BattleTag prefix, asks if ambiguous
/rtk token pi add friend target     the friend your target is playing
/rtk token pi except Bob target     exclude the character that friend is on now (or a typed Name-Realm)
/rtk token pi allow Bob Bobwarrior-Area52   remove an exclusion
/rtk token pi remove 2              by position
/rtk token pi remove Bob            by name (character or BattleTag)
/rtk token pi move 3 1              move position 3 to position 1
/rtk token pi role dps              tank | healer | dps | none
/rtk token pi delete                built-ins refuse
/rtk token pi clear                 empty the list, keep the token
```

`/rtk pin` and `/rtk unpin` are removed; the help text points at
`/rtk token`. Commands that edit a built-in are refused with a hint to create
a custom token with that role filter. The first `add` to an unknown name creates the token,
after checking the naming rules. Every command ends with `Macros.Sync("token
changed")`, so macros update immediately.

Status (`/rtk`) grows one line per token showing the resolved units, which is
the quickest way to check "who is @pi right now."

## 6. UI

Three pieces, listed in the order they'd ship.

### 6.1 Unit menu entry

Right-clicking a player anywhere the client offers a unit menu (party and raid
frames, target, focus, the friends list, the guild roster) gets a **RoleTokens**
submenu:

```
RoleTokens ▸  Add to @pi
              Add to @pi as friend   (only when the player is a Battle.net friend)
              Add to @md
              ─────────
              Remove from @pi      (only shown where they're already listed)
              Exclude this character from @pi   (only when they matched through a Battle.net entry)
```

This uses the retail menu system's `Menu.ModifyMenu` on the party, raid,
target, focus, friend, Battle.net friend and guild member menu tags. The
context data carries the name and server, and for Battle.net friends the
account, so the entry is created in the right form without typing. This is
the main input path; the window is for reordering and review.

### 6.2 Token window (`/rtk ui`)

One movable, resizable frame, built once and repainted on change.

```
┌ RoleTokens ─────────────────────────────────────────────────┐
│ Tokens          │ @pi                                        │
│ ─────────────   │ Role  [ any     ▾]                          │
│ @tank           │                                            │
│ @healer         │  1  ● Bob (friend)      (Bobpriest-Area52) │   label is the BattleTag prefix
│ @dps            │  2  ○ Ærin-Area52        healing           │
│ ─────────────   │  3  ○ Carol-Stormrage    not in group      │
│ @pi          ◂  │                                            │
│ @md             │      ▲ ▼ ✕ on the hovered row              │
│ @innervate      │                                            │
│                 │  [+ Add]     resolves now: @pi → raid17     │
│ [+ New token]   │                          @pi2 → none       │
└─────────────────┴────────────────────────────────────────────┘
```

- Left column: built-ins first, greyed and read-only (selecting one shows
  only its live resolution), then user tokens alphabetically. Selecting one
  fills the right side. "New token" opens a one-line name box with the
  naming rules enforced live.
- Right side header: the role dropdown.
- Rows: position, presence dot (filled: present and passes the filter; hollow:
  present but wrong role, excluded, or absent, with the reason in grey), the
  entry as stored, and for Battle.net entries the character they're currently
  on. A Battle.net entry with exclusions shows them as a grey sub-line, each
  with an x. Arrows and remove appear on hover. Drag-to-reorder is not planned; the
  arrows are enough for lists of a handful of names.
- "+ Add" opens a picker: a search box, then sections **Group**, **Friends
  online**, **Guild online**, each row a click to add. Battle.net friends
  appear once with their tag; guild members appear per character. A typed name
  that matches nothing is added as-is so you can rank someone who's offline.
- Footer: live resolution for the selected token, the same data `/rtk token pi`
  prints.
- Repaint on: token change, roster/role events (already coalesced in core),
  friend list and guild roster updates while the window is open.

Position is saved account-wide. No Edit Mode integration is needed for a
window that is never on screen during play.

### 6.3 Status line in the window

Not a separate piece, but worth naming: every repaint shows what each token
resolves to right now, so the window doubles as the "why did my macro pick
Carol" debugger.

## 7. Data

```lua
RoleTokensDB = {
    account = {...}, characters = {...}, dropSelf, verbose,   -- unchanged
    tokens = {   -- custom only; tank/healer/dps are code, not data
        pi     = { role = nil,
                   entries = { { kind = "bnet", tag = "Bob#1234",
                                 lastSeen = "Bobpriest-Area52",
                                 exclude = { ["bobwarrior-area52"] = true } },
                               { kind = "char", name = "Ærin-Area52" } } },
    },
    ui = { point = ..., x = ..., y = ... },
    schema = 2,
}
```

`schema` guards the pin migration so it runs once.

## 8. Events and API surface

Beyond what core registers today:

- `BN_FRIEND_INFO_CHANGED`, `FRIENDLIST_UPDATE`: a Battle.net entry can start
  or stop matching as friends log alts. Coalesced into the same sync.
- Friend lookup uses `C_BattleNet.GetFriendAccountInfo` for the tag and
  display name and `GetFriendGameAccountInfo` for the character and realm each
  friend is on; a friend with two clients open is matched on any of them.

### What the Blizzard UI source confirms (live branch, Sept 2026)

Read from `Blizzard_UnitPopupShared`, `Blizzard_UnitPopup/Mainline`,
`Blizzard_FriendsFrame/Mainline` and `Blizzard_Communities`:

- Unit menus are tagged `MENU_UNIT_<which>`; the registered `which` values we
  care about are `PARTY`, `RAID_PLAYER`, `RAID`, `TARGET`, `FOCUS`, `PLAYER`,
  `FRIEND`, `BN_FRIEND`, `BN_FRIEND_OFFLINE`, `GUILD`, `GUILD_OFFLINE`,
  `COMMUNITIES_GUILD_MEMBER`, `COMMUNITIES_WOW_MEMBER`.
- `contextData` for a unit menu gets `name` and `server` filled from
  `UnitName` when `unit` is set, and `accountInfo` filled automatically: from
  `bnetIDAccount` when present, else by `C_BattleNet.GetAccountInfoByGUID`.
  So a grouped player who is a Battle.net friend arrives with their account
  info attached; no lookup needed to offer "add as friend."
- Friends list rows pass `bnetIDAccount` and `battleTag` (Battle.net) or
  `name` and `guid` (character friends).
- Guild roster rows pass `name`, `guid` and `clubMemberInfo`.
- `BNetAccountInfo` carries `accountName` (display), `battleTag`,
  `bnetAccountID` (session-only, never stored), and `gameAccountInfo` with
  `characterName`, `realmName`, `isOnline`, `clientProgram`.

### What the POC proved in-game (12.1, 2026-09-14)

- `Menu.ModifyMenu` fires on `MENU_UNIT_PARTY` and
  `MENU_UNIT_COMMUNITIES_GUILD_MEMBER`. Party context has `unit`, `name`,
  `server` and `accountInfo` but **no `guid`**: use `UnitGUID(contextData.unit)`.
  Guild roster context has `name`, `server`, `guid`, `accountInfo` and
  `clubMemberInfo.name` already in `Name-Realm` form.
- `accountInfo` is attached for a grouped player and for a guild member who
  is a Battle.net friend, found by GUID. So "add as friend" needs no lookup.
- **`accountName` is a Kstring** (`|Ks62|k`): it renders in a FontString or
  chat as the friend's name but is opaque to string functions. It cannot be
  searched, compared or stored meaningfully. `battleTag` is plain text.
  Consequence: the readable, searchable label for a friend is the BattleTag
  prefix (`SuperNinja`), and `add friend <text>` matches that prefix.
- A friend has several game accounts (`App`, `BSAp` mobile, `WoW`); only the
  `WoW` one carries `characterName`, `realmName` and **`playerGuid`**.
  Consequence: match a Battle.net entry to a group unit by GUID
  (`C_BattleNet.GetAccountInfoByGUID(UnitGUID(unit))` then compare
  `battleTag`), never by name and realm, so realm spelling never matters.
- Guild roster names come back as `Name-Realm` with spaces removed and
  apostrophes kept (`Grîmreefer-Kel'Thuzad`, `Lichlighter-BurningBlade`), the
  same shape `UnitFullName` gives. That is the stored form for characters.
- `GetRealmName` and `GetNormalizedRealmName` agree on a one-word realm; the
  normalized one is what gets appended to a typed bare name.
- Non-ASCII names (`Oní`, `Àvaa`, `Rëckless`) pass through every API intact.

- `MENU_UNIT_BN_FRIEND` (friends list row) fires with `bnetIDAccount`,
  `battleTag` and `accountInfo`; `name` is the Kstring.
- A targeted player outside the group opens `MENU_UNIT_PLAYER` (not
  `TARGET`), with `unit = "target"`, `name`, `server = nil` for same-realm,
  no `guid` and no `accountInfo`. Hook `PLAYER` as well as `TARGET`/`FOCUS`,
  and derive GUID and account from the unit.
- The submenu button accepts child buttons (used on the target menu).

## 8a. Proof of concept

`../RoleTokensPOC` is a throwaway addon (not a git repo, never released) that
exercises all of the above. Sync it, `/reload`, then:

- `/rtp friends`: prints every online Battle.net friend with tag, display
  name and character/realm, then every group unit with `UnitName`,
  `UnitFullName` and whether the GUID maps back to a friend.
- Right-click a party/raid member, your target, a friends-list row, or a
  guild roster row: a "RoleTokens POC" section appears with a submenu and a
  button that prints the context data.
- `/rtp guild`: requests the roster and prints online members as returned.

Once each prints what section 8 predicts, delete the folder and start
phase 1. Anything that differs gets written back into this doc first.
- `GUILD_ROSTER_UPDATE`: picker refresh only; doesn't affect resolution.
- Menu registration at `PLAYER_LOGIN`.

Nothing here touches combat data, so Secret Values are not a concern. Macro
edits remain blocked in combat and are deferred as today.

## 8b. Performance budget

The addon must be unnoticeable. These are constraints, not goals.

- **Nothing runs per frame.** No `OnUpdate`, no polling timers. Work happens
  only in response to roster, role, macro and combat-end events, and those
  are already coalesced into one pass on the next frame (`core.lua`).
- **One sync is bounded and small.** Group units (at most 40) × custom
  tokens × entries, all string compares on tables already in memory. For
  Battle.net entries, one `GetAccountInfoByGUID` per grouped unit per sync,
  cached in a local table for that sync, never per entry. Expected cost: well
  under a millisecond in a 40-player raid with a dozen tokens.
- **The friends list is never scanned for resolution.** GUID lookup replaces
  it. It is walked only when the picker opens, and `lastSeen` is refreshed
  from grouped units (free, we already have the account) and from the picker
  walk, not from friend events.
- **The guild roster is never requested by the addon** except when the
  picker's Guild section is opened, and that request is throttled by the
  client anyway.
- **Macro writes stay gated.** `EditMacro` is the most expensive call and is
  only made when the desired body differs from the current one, as today.
- **The window costs nothing while hidden.** Built once on first open,
  repainted only on events while shown; its event registrations are dropped
  on hide.
- **No per-sync allocation churn.** Working tables are reused; the resolver
  output is the only table created per sync, as today.
- **Verified, not assumed.** `/rtk debug` logs the duration of each sync via
  `debugprofilestop()` to the SavedVariables log, so the budget is checked
  in a real raid before release.

## 9. Files

| File                | Change                                                                  |
|---------------------|-------------------------------------------------------------------------|
| `src/expand.lua`    | `ParseToken` takes the set of custom token names in addition to the fixed 3. |
| `src/resolve.lua`   | Candidate-sequence resolver for custom tokens; built-in path loses the pin loop. |
| `src/db.lua`        | `tokens` table, entry helpers, schema-2 migration from pins.            |
| `src/names.lua`     | new: normalise `Name`/`Name-Realm`, match a unit against an entry, Battle.net lookup. Pure enough to test under luajit with stubs. |
| `src/commands.lua`  | `/rtk token ...`, drop pin/unpin, status per token.                     |
| `src/menu.lua`      | new: unit menu entries.                                                 |
| `src/ui.lua`        | new: the window and picker.                                             |
| `README.md`         | tokens table becomes "your tokens", pin section replaced.               |

## 10. Phases

1. **Model and resolver.** `names.lua`, `db.lua` migration, `resolve.lua`,
   `expand.lua`. Tested under luajit with stubbed `UnitName`,
   `UnitGroupRolesAssigned`, `GetPartyAssignment`, and Battle.net lookups.
   Existing behaviour must survive unchanged: the current README examples are
   the regression cases.
2. **Commands and unit menu.** In-game usable end to end without a window.
   Ships as an alpha.
3. **Window.** Ships as the release.

## 11. Open questions

All settled (2026-09-14):

1. Battle.net entries in phase 1, with exclusions.
2. A token may list people who don't currently play its role; the filter
   applies at resolve time only.
3. Tokens have no fallback. Fallback is the macro's next clause.
4. "Pinned regardless of role" is dropped; a migrated pin token can have its
   role set to none to get it back.
5. Migrated pins are named `mytank` / `myhealer` / `mydps`.
