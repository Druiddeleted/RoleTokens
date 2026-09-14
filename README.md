# RoleTokens

Macros can target `@focus` or `@party3`. They can't target "the tank", and they
definitely can't target "Bob, unless he brought his warrior". RoleTokens lets
you write exactly that.

```
/cast [@tank,exists,nodead] Misdirection
/cast [@pi,exists,nodead] [@pi2,exists,nodead] [@dps,exists,nodead] [] Power Infusion
```

`@tank` is whoever is tanking. `@pi` is the first person on your Power
Infusion list who showed up tonight. You write the macro once and it keeps
pointing at the right people as your group changes.

## How it works

The game doesn't let addons cast spells for you, but it does let them edit
macro text when you're out of combat. So RoleTokens watches your group, and
every time someone joins, leaves, or changes role, it rewrites your macro so
`@tank` becomes `@party3` or `@raid17` or whoever it is right now. The macro on
your bar is always a plain, ordinary macro. Your focus is never touched.

If someone changes during a fight, the macro updates the moment combat ends.

## Getting started

1. Put a token in any macro and save it. RoleTokens notices, says
   `now managing macro <name>`, and fills in the real unit right away.
2. That's it. Edit the macro any time; as long as a token is in it, it stays
   managed. Save it without a token and RoleTokens leaves it alone from then on.

Always pair a token with `exists`, like `[@tank,exists,nodead]`. When there is
no tank, the token is left as written, `@tank` isn't a real unit, and the
clause fails so the macro moves on to the next one. That's the whole fallback
mechanism, and it's why a bare `[@tank]` would be a mistake: it would try to
cast at nobody instead of moving on.

## The role tokens

These come built in and need no setup.

| Write this            | You get                                                |
|-----------------------|--------------------------------------------------------|
| `@tank`               | the raid's assigned main tank, otherwise the first tank |
| `@tank2`, `@tank3`…   | the other tanks                                        |
| `@healer`, `@healer2`… | healers, in group order                               |
| `@dps`, `@dps2`…      | damage dealers, in group order                         |

Roles come from the group role assignment. Someone who never picks a role
won't show up under any of these.

## Your own tokens

This is the part built for the people you actually play with.

A token of your own is a name plus a ranked list of people. `@pi` is the
highest-ranked person on your list who is in your group. `@pi2` is the next
one, and so on. Everyone else is ignored.

Build one from the RoleTokens page (Options, AddOns, RoleTokens, or click the
minimap button), by right-clicking someone and choosing **Add … to @pi**, or
from chat:

```
/rtk token pi add target          whoever you have targeted
/rtk token pi add friend Bob      a Battle.net friend, whatever character they're on
/rtk token pi add Moonwell        by name; use Name-Realm for other realms
/rtk token pi                     show the list and who @pi is right now
```

The first `add` creates the token. Names are letters only, up to twelve of
them, and you can't reuse a name the game already knows like `focus` or
`party`.

**Only when they're playing the right role.** Say the list is for Power
Infusion and one of your friends sometimes heals. Tell the token to skip
anyone who isn't dps right now:

```
/rtk token pi role dps
```

Or set it per person, which overrides the list setting for them. "Count Alice
only as dps, and Bob only as tank" is:

```
/rtk token pi role Alice dps
/rtk token pi role Bob tank
```

On the page, that's the small role button on each row.

**Fallbacks go in the macro, not the token.** RoleTokens decides who is who.
The game decides who is alive, and it decides that at the instant you press the
key. So write the chain in the macro and let each step carry its own
conditions:

```
/cast [@pi,exists,nodead] [@pi2,exists,nodead] [@dps,exists,nodead] [] Power Infusion
```

Read it as: my first choice, or my second choice if the first one is dead, or
any dps if none of my people are here, or my own target.

## Friends and their alts

When you add someone as a friend, they count on whatever character they log
in with. Two things make that practical:

**Keep one alt out.** Bob is great on his mage and useless on his warrior.
While he's on the warrior, target him and:

```
/rtk token pi except Bob target
```

or right-click him and choose **Never Bobwarrior for @pi**. The page shows it
as an `except` line under his name. `allow` undoes it.

**Rank one alt higher than the rest.** Add the character and the friend
separately. `Bobmage` at position 1 and friend `Bob` at position 4 means: Bob
on his mage is my first choice, Bob on anything else is my fourth. A person is
only ever used once per token, so there's no double counting.

Friends are shown by the name part of their BattleTag, never the number. If
two friends share a name, the page tells them apart by the character each one
is on, or was last seen on.

## The page

Options, AddOns, RoleTokens. Or `/rtk ui`, or the minimap button.

Left side: the built-in tokens, then yours. Right side: the selected token's
list. A green dot means that person is in your group and counts right now,
and the slot they fill is shown at the end of the row. A grey dot with a
reason (`not in group`, `healing · skipped`, `excluded`) means they don't.
The bottom line shows what each slot resolves to at this moment, which is the
quickest way to answer "why did my macro pick Carol".

The **+ Add** button opens a picker over your group, your online friends and
your online guild members, with a search box. Typing a name that matches
nothing and pressing Enter adds it as written.

The minimap button can be turned off with the checkbox at the top of the page
or with `/rtk minimap`.

## Commands

```
/rtk                     what every token resolves to, and which macros are managed
/rtk ui                  open the page
/rtk refresh             rewrite macros now
/rtk forget <MacroName>  stop managing a macro; its current text stays
/rtk token <name> add | remove | move | role | except | allow | clear | delete
/rtk minimap             show or hide the minimap button
/rtk quiet, /rtk verbose chat notices off or on
```

## Good to know

- Tokens are shared across all your characters. Your Power Infusion list is
  only useful on a priest, but it does no harm anywhere else.
- Macros can't be edited in combat, so a change mid-fight lands when combat
  ends.
- Macros cap at 255 characters after expansion, and `raid17` is longer than
  `pi`. If a macro would overflow, RoleTokens says so and leaves it alone.
- Nothing runs in the background. RoleTokens only does work when your group,
  roles or macros change, and one pass is a handful of comparisons.
- If you used pins in an older version, they became tokens named `mytank`,
  `myhealer` and `mydps` with a role filter. Where a macro relied on a pin,
  change `@tank` to `[@mytank,exists,nodead] [@tank,exists,nodead]`.
