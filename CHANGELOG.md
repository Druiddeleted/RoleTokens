# Changelog

## Unreleased

- Custom tokens: `/rtk token pi add target` creates `@pi`, resolved from an
  ordered list of people who are in your group, with `@pi2`, `@pi3` for the
  next ones and an optional role filter. Entries are characters or Battle.net
  friends (any alt, with per-alt exclusions). Account-wide.
- Token window (`/rtk ui`) with a picker over your group, online friends and
  online guild members, and a right-click unit menu entry on players, friends
  and guild rows.
- Pins are replaced: existing pins become `@mytank` / `@myhealer` / `@mydps`
  tokens with a role filter. `/rtk pin` explains the change.
- `/rtk debug` logs sync timings to `RoleTokensLog` (SavedVariables).

## 0.1.0

- Initial release. `@tankN`, `@healerN`, `@dpsN` tokens (N up to 40, `@tank` =
  `@tank1`) in any macro are rewritten to the real party/raid unit whenever the
  group changes.
- Raid main tank assignment is promoted to `@tank`; `/rt pin` overrides ordering
  per character.
- Unresolved tokens are left as written; the clause fails and the macro falls through.
