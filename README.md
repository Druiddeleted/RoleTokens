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

## Quick and easy: the role tokens

Nothing to set up. Write `@tank`, `@healer` or `@dps` in a macro, save it, and
it works.

```
/cast [@tank,exists,nodead] Misdirection        hunters
/cast [@tank,exists,nodead] Tricks of the Trade rogues
/cast [@healer,exists,nodead] Innervate         druids
/cast [@tank,exists,nodead] Pain Suppression    healers with a tank external
```

The moment you save, RoleTokens says `now managing macro <name>` and swaps the
token for the real unit. From then on the macro follows your group.

`@tank` is the raid's assigned main tank if there is one, otherwise the first
tank. `@tank2`, `@healer2`, `@dps3` and so on count through the rest in group
order.

You are never picked yourself, so a tank who writes `@tank` gets the other
tank, which is what you want for Tricks or an external. For something you can
also cast on yourself, like Innervate, make yourself the last resort in the
macro:

```
/cast [@healer,exists,nodead] [@player] Innervate
```

If you'd rather be counted like anyone else, `/rtk self` turns that on.

One rule to keep: always pair a token with `exists`. When there is no tank,
the token is left as written, `@tank` isn't a real unit, and the clause fails
so the macro moves on to the next one. That's the entire fallback system, and
it's why a bare `[@tank]` would try to cast at nobody instead of moving on.

## If you want to choose who gets it: your own tokens

Say you're a priest with two friends who should always get Power Infusion
before anyone else. Make a token called `pi` and put them on it:

```
/rtk token pi add friend Alice
/rtk token pi add friend Bob
/rtk token pi add Carol-Illidan
```

Now `@pi` is Alice if she's in the group, otherwise Bob, otherwise Carol.
`@pi2` is the next one down, `@pi3` the one after that. People who aren't
here are simply skipped.

Then write the macro so it walks the list and skips the dead:

```
#showtooltip
/cast [@pi,exists,nodead] [@pi2,exists,nodead] [@pi3,exists,nodead] [@dps,exists,nodead] [] Power Infusion
```

Read it as: my first choice, or my second if the first is dead, or my third,
or any dps if none of my people made it, or whatever I'm targeting. The game
checks `nodead` at the instant you press the key, so this stays correct
mid-fight even though RoleTokens itself only edits macros out of combat.

You can also do all of this from the RoleTokens page (Options, AddOns,
RoleTokens, or the minimap button), or by right-clicking a player, a friends
list row or a guild roster row and choosing **Add … to @pi**.

## The details

**Naming.** The first `add` creates the token. Names are letters only, up to
twelve, and can't be something the game already treats as a unit like `focus`
or `party`.

**Only while they're playing the right role.** If Bob sometimes heals, tell
the token to skip anyone who isn't dps right now:

```
/rtk token pi role dps
```

Or set it per person, which overrides the list setting for them. "Alice only
as dps, Bob only as tank" is:

```
/rtk token pi role Alice dps
/rtk token pi role Bob tank
```

On the page, that's the small role button on each row.

**Seeing what's going on.** `/rtk token pi` lists everyone on the token with
a reason next to each name: who they're on, `not in group`,
`healing · skipped`, and which slot they fill. `/rtk` on its own shows every
token at once.

**Editing.** `remove 2` or `remove Bob`, `move 3 1`, `clear`, `delete`. The
page has arrows and an x on each row.

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
/rtk self                let tokens pick you too (off by default)
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
