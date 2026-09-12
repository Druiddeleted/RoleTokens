# Changelog

## 0.1.0

- Initial release. `@tank`, `@tank2`, `@healer`, `@healer2` tokens in any macro
  are rewritten to the real party/raid unit whenever the group changes.
- Raid main tank assignment is promoted to `@tank`; `/rt pin` overrides ordering
  per character.
- Unresolved tokens drop their `[conditional]` clause so the macro falls through.
