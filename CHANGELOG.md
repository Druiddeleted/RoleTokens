# Changelog

## 0.1.0-alpha1

- Initial release. `@tankN`, `@healerN`, `@dpsN` tokens (N up to 40, `@tank` =
  `@tank1`) in any macro are rewritten to the real party/raid unit whenever the
  group changes.
- Raid main tank assignment is promoted to `@tank`; `/rt pin` overrides ordering
  per character.
- Unresolved tokens are left as written; the clause fails and the macro falls through.
