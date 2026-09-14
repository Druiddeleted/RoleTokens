# RoleTokens

Write `@tank`, `@healer`, or your own `@pi` in a macro and stop editing it
every run.

WoW macros only know fixed unit tokens (`@focus`, `@party1`, …). There is no
`@tank`, and there is certainly no "@the person I Power Infusion". RoleTokens
fills that gap the only way the client allows: it watches your group and
rewrites the macro text out of combat, so the macro on your bar always names
the right unit. Your focus is never touched.

## Use

1. Put a token in any macro, account or character:

   ```
   #showtooltip
   /cast [@tank,exists,nodead] [@mouseover,exists,help,nodead] [@party1,exists,nodead] [@pet,exists,nodead] [] Misdirection
   ```

2. Save it. The addon prints `now managing macro <name>` and swaps `@tank` for
   the current tank (e.g. `@party3`) immediately.
3. Every roster or role change rewrites it again. Changes made in combat apply
   as soon as combat ends.

To change the template later, edit the macro and put the token back in. To
stop managing it, edit the macro with no token, or `/rtk forget <name>`.

## Built-in tokens: by role

| Token                   | Resolves to                                      |
|-------------------------|--------------------------------------------------|
| `@tank` / `@tank1`      | raid main tank assignment, else first tank       |
| `@tank2` … `@tank40`    | the next tanks, by raid/party index              |
| `@healer` … `@healer40` | healers by index                                 |
| `@dps` … `@dps40`       | damage dealers by index                          |

## Your tokens: by priority list

A custom token is a name you choose backed by an ordered list of people.
`@pi` is the first person on the list who is in your group; `@pi2` is the
second. Optionally the token only counts people while they play a given role.

```
/rtk token pi add target           # whoever you're targeting
/rtk token pi add Moonwell         # by name (Name-Realm for other realms)
/rtk token pi add friend Bob       # a Battle.net friend, on whichever alt they bring
/rtk token pi role dps             # skip them while they're healing or tanking
/rtk token pi                      # see the list and who resolves right now
```

Or use the RoleTokens page under Options → AddOns (`/rtk ui` or the minimap
button opens it), or right-click any player, friends-list row or
guild-roster row and pick **Add … to @pi**.

Fallbacks belong to the macro, because the client evaluates conditionals at
cast time and the addon can only decide who is who:

```
/cast [@pi,exists,nodead] [@pi2,exists,nodead] [@dps,exists,nodead] [] Power Infusion
```

That reads "my first choice, else my second if the first is dead, else any
dps". A slot with nobody to fill it is left as written, so `[@pi2,exists]`
simply fails and the next clause is tried.

Details worth knowing:

- Tokens are account-wide. Names are letters only, 2 to 12 characters, and
  can't be something the client already treats as a unit (`focus`, `party`…).
- A Battle.net friend counts on any character they play. To keep one alt out:
  `/rtk token pi except Bob target` while they're on it (or right-click →
  **Never <alt> for @pi**). Friends are shown by BattleTag name, never the
  number; two friends with the same name are told apart by the character each
  is on or was last seen on.
- Listing the same person as a character and as a friend is allowed and
  useful: `Bobmage` at position 1 and friend `Bob` at position 3 means "Bob on
  his mage is first; Bob on anything else is third".
- Pins from older versions became tokens named `mytank`, `myhealer` and
  `mydps`, with a role filter. Change `@tank` to
  `[@mytank,exists,nodead] [@tank,exists,nodead]` where you relied on a pin.

You are never chosen for a token. Always pair a token with `exists`; a bare
`[@tank]` would try to cast at nobody instead of falling through.

## Commands

```
/rtk                      status: resolved tokens and managed macros
/rtk ui                   the RoleTokens page in Options > AddOns
/rtk minimap              show or hide the minimap button
/rtk refresh              re-scan and rewrite now
/rtk forget <MacroName>   stop managing (current text stays)
/rtk token <name> add | remove | move | role | except | allow | clear | delete
/rtk quiet | verbose      chat notices
/rtk debug                log each sync's duration to SavedVariables
```

## Who this is for

- **Hunter** Misdirection, **Rogue** Tricks of the Trade → `@tank`, or a
  `@md` list of your regular tanks.
- **Priests** Power Infusion → `@pi`, the people you actually want to buff.
- **Druids** Innervate → `@innervate`, or `@healer`.
- **Healers** with tank externals: Pain Suppression, Guardian Spirit, Ironbark,
  Life Cocoon, Blessing of Sacrifice → `@tank`, `@tank2`.
- **Warriors** Intervene, **Monks** Tiger's Lust on the tank → `@tank`.

## Limits

- Macro edits are blocked in combat by the client, so a change mid-fight
  applies after combat.
- Macro bodies cap at 255 characters after expansion (`raid12` is longer than
  `pi`); the addon warns and leaves the macro alone if it would overflow.
- Roles come from the group role assignment. In a premade group with no role
  check, players who never set a role won't resolve for role tokens or role
  filters.
- The addon does nothing per frame. Work happens only when the roster, roles
  or macros change, and one pass is bounded by group size × tokens × entries.
