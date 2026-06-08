# Agent entry point

If you are an AI agent or a new contributor, **read
[docs/ADDON_GUIDE.md](docs/ADDON_GUIDE.md) first**. It is the prescriptive
guide for working in this codebase and covers the 3.3.5a / WotLK / Lua
5.1 constraints, the architecture and scan-loop / bar lifecycle, the
required patterns, the library rationale, the saved-variable migrations,
the 3.3.5a gotchas, and the **Gotchas and refactoring traps** index. Read
that traps section before you "simplify" anything.

**Before you delete or "simplify" anything that looks like dead code,
cruft, or a bug, run `grep -rn "EC-TRAP:"`.** Every hit marks intentional
code that has lured (or could lure) someone down a wrong path: optional-dep
graceful-degradation guards that look dead, 3.3.5a APIs that look wrong
(the double `InterfaceOptionsFrame_OpenToCategory` call, bare
`GetItemCooldown`, `GetNumPartyMembers`), and the GCD-ignore rule that
looks like it drops real cooldowns. Read the marker and follow its
pointer before touching it. Do not remove an `EC-TRAP:` line as part of a
cleanup.

## The short version

- BarWarden is a bar-tracking addon for **WoW 3.3.5a (WotLK), Interface
  30300**: timer bars for spell cooldowns, buffs, debuffs, procs, item
  cooldowns, weapon enchants, totems, and class resources, grouped into
  movable on-screen containers and configured through a tabbed Interface
  Options panel. It ships as 27 `.lua` files plus the bundled `Libs/`.
  [BarWarden.toc](BarWarden.toc) lists every file in load order; add a
  new file after everything it depends on.
- **The bundled libraries are intentional.** LibStub,
  LibSharedMedia-3.0, LibDataBroker-1.1, and LibDBIcon-1.0 stay. LSM adds
  real texture/font value; LDB + LibDBIcon are the standard minimap stack.
  All degrade gracefully when absent (see the EC-TRAP guards). Do not
  remove them. We did not embed Ace3; the lifecycle, callback bus, and
  option widgets are hand-rolled. Rationale in docs/ADDON_GUIDE.md.
- **Never use em dashes (Unicode U+2014) anywhere in this repo.** Not in
  player-facing text, code comments, markdown docs, commit messages, or
  CHANGELOG entries. Em dashes read as LLM-authored and inauthentic for a
  human-shipped addon. Use plain hyphens with spaces (` - `), periods,
  colons, or commas. A grep for the U+2014 character against the repo
  MUST return zero (this line references the codepoint, not the character).
- **Player-facing text stays brief and jargon-free.** Tooltip labels,
  panel descriptions, checkbox text, chat messages, and slash-command
  help must lead with what happens, drop the mechanism, and avoid code
  jargon. Internal docstrings and comments may stay technical.
- **Verify before commit:** `luac -p` on changed files, `lua tests/run.lua`
  (117 logic tests; frame code is out of scope and rides the in-game
  smoke test), then `/reload` in game with `/console scriptErrors 1`.

## Conventions at a glance

- Everything attaches to the shared `ns` table. Every file starts
  `local addonName, ns = ...`. **Do not introduce globals** (`function
  Foo()` at file scope pollutes `_G`); use `ns:` or `local function`.
- Chat output goes through `ns:Print` ([Core.lua](Core.lua)). Never call
  `DEFAULT_CHAT_FRAME:AddMessage` directly outside the debug dump.
- Extend the lifecycle methods (`ns:OnInitialize` / `ns:OnEnable` /
  `ns:OnDisable` in Core.lua), not ad-hoc init in raw event handlers.
- New events get a `function ns:OnSomething(...)` plus one row in
  `GAMEPLAY_EVENTS` ([Events.lua](Events.lua)); do not hand-roll
  `local function OnFoo` wrappers.
- New settings go into `ns.DEFAULTS` ([DB.lua](DB.lua)) first, then the
  widget. `ns:DBSet` validates the path against `ns.DEFAULTS` at load.
- `ns.DEFAULTS` is the single source of truth for the schema. Bumping it
  means a `MigrateDB()` block plus a `CURRENT_SCHEMA` bump that only
  fills nil keys, never overwrites user data. The migration test catches
  silent corruption; run it.
- Borrow bars from the [BarPool.lua](BarPool.lua) pool; never
  `CreateFrame("StatusBar")` outside Bar.lua / BarPool.lua.
- British English (colour, behaviour, humanised). Comments explain
  *why*, not the obvious; no banner comments over short functions.

## Docs to keep in sync

When a change touches an externally visible surface, update the relevant
doc in the same patch:

- [README.md](README.md) - features, installation, the slash-command
  table (slash additions always get a row).
- [CHANGELOG.md](CHANGELOG.md) - a `### vX.Y.Z` stanza per release.
- [docs/ADDON_GUIDE.md](docs/ADDON_GUIDE.md) - architecture, patterns,
  naming, 3.3.5a gotchas, the EC-TRAP trap index.
- [NOTICE.md](NOTICE.md) - adopting or diverging from a convention shared
  with the sibling addon EbonClearance.
- This file - if you add or remove a `.lua` file (update the count) or
  introduce a new top-level convention.

For everything else, [docs/ADDON_GUIDE.md](docs/ADDON_GUIDE.md) is
authoritative.
