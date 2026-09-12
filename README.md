# RoleTokens

Write `@tank` or `@healer` in a macro and stop editing it every run.

WoW macros only know fixed unit tokens (`@focus`, `@party1`, …). There is no
`@tank`. RoleTokens fills that gap the only way the client allows: it watches
your group and rewrites the macro text out of combat, so the macro on your bar
always names the right unit. Your focus is never touched.

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
stop managing it, edit the macro with no token, or `/rt forget <name>`.

## Tokens

| Token      | Resolves to                                                  |
|------------|--------------------------------------------------------------|
| `@tank`    | pinned tank, else raid main tank assignment, else first tank |
| `@tank2`   | the next tank                                                |
| `@healer`  | pinned healer, else first healer by raid/party index         |
| `@healer2` | the next healer                                              |

You are never chosen for a token. When a token has nobody to resolve to, its
`[...]` clause is removed so the macro falls through to the next one.

## Raids: choosing between several tanks or healers

Raid index order is arbitrary, so pin who you mean, per character:

```
/rt pin healer Moonwell      # @healer is Moonwell whenever they're in the group
/rt pin tank Brutall
/rt unpin healer
```

A pinned player takes the slot even if their role differs (you asked for them
by name). Absent pins fall back to the default order.

## Commands

```
/rt                      status: resolved tokens and managed macros
/rt refresh              re-scan and rewrite now
/rt forget <MacroName>   stop managing (current text stays)
/rt pin <token> <Name>   /rt unpin <token>
/rt quiet | verbose      chat notices
```

## Who this is for

- **Hunter** Misdirection, **Rogue** Tricks of the Trade → `@tank`.
- **Healers** with tank externals: Pain Suppression, Guardian Spirit, Ironbark,
  Life Cocoon, Blessing of Sacrifice → `@tank`, `@tank2`.
- **Druids** Innervate, **Priests** Power Infusion on a healer → `@healer`.
- **Warriors** Intervene, **Monks** Tiger's Lust on the tank → `@tank`.

Anything that keys on a role rather than a person.

## Limits

- Macro edits are blocked in combat by the client, so a tank change mid-fight
  applies after combat.
- Macro bodies cap at 255 characters after expansion (`raid12` is longer than
  `tank`); the addon warns and leaves the macro alone if it would overflow.
- Roles come from the group role assignment. In a premade group with no role
  check, players who never set a role won't resolve.
