# Code review - deferred work & standing decisions

A curated backlog so future sessions don't re-litigate settled questions or
re-discover known follow-ups. Cite items by number when you touch adjacent code.
Three sections: **Active backlog** (known, not yet actioned), **Audit decisions**
(intentional / won't-fix), and **Resolved** (done, kept for the record).

## Active backlog

1. **Luacheck gate is non-blocking.** The CI `luacheck` step
   ([tests.yml](../.github/workflows/tests.yml)) runs `continue-on-error` for now,
   matching EbonClearance's deferred gate. The [.luacheckrc](../.luacheckrc)
   `read_globals` list was authored without a local luacheck run (the tool was
   unavailable in the authoring environment), so it may miss or over-list a few
   APIs. Follow-up: run `luacheck *.lua` on a box that has it, reconcile the
   globals, then flip the step to a hard gate. Low risk, low-med effort.
2. **StyLua not yet run over the tree.** [stylua.toml](../stylua.toml) is in place
   but no `stylua --check *.lua` has been run (StyLua was unavailable when the
   config landed). The config matches the existing 4-space style, so churn should
   be minimal, but verify on a box with StyLua before enforcing. Never format
   `Libs/`. Low effort.
3. **`ns.COLORS` adoption is incremental.** New and changed code references the
   palette tokens, but older files still carry some inline `|cff...` hex. Migrate
   opportunistically when editing a file; not worth a dedicated sweep. Low priority.

## Audit decisions (intentional - do not "fix")

A. **Bundled libraries stay.** LibStub, LibSharedMedia-3.0, LibDataBroker-1.1,
   LibDBIcon-1.0 earn their place (LSM media value; the standard minimap stack)
   and degrade gracefully when absent. Rationale in
   [ADDON_GUIDE.md](ADDON_GUIDE.md) "Library rationale". Do not remove or embed Ace3.
B. **Versioned `MigrateDB` + `CURRENT_SCHEMA` kept** over EbonClearance's
   nil-default `EnsureDB` style. It is explicit and testable, and
   `tests/test_db_migrations.lua` guards it against silent corruption.
C. **Help is a 6th tab,** not a separate Interface Options sub-panel (EC's shape).
   The tabbed shell is correct for a bar editor.
D. **3.3.5a APIs that look wrong are correct here:** the double
   `InterfaceOptionsFrame_OpenToCategory`, bare `GetItemCooldown`,
   `GetNumPartyMembers` / `GetNumRaidMembers`, and the GCD-ignore-under-1.5s rule.
   All carry `EC-TRAP:` markers and are indexed in ADDON_GUIDE. Do not modernise.

## Resolved (kept for the record)

- Em dashes removed repo-wide; no-em-dash rule established and locked by
  `tests/test_hygiene.lua`.
- Per-file attribution headers + `LICENSE` (source-available attribution).
- `EC-TRAP:` markers added at the intentional-but-looks-wrong sites and indexed
  in ADDON_GUIDE.
- Contributor doc set: CLAUDE.md, ADDON_GUIDE.md, CHANGELOG.md, NOTICE.md, this
  file, and ARCHITECTURE.md.
- In-game Help tab with `[?]` deep-links; empty-state messaging; the runnable
  slash-command list on the General tab.
- Release workflow parity with EC (Title-badge stamping, CHANGELOG-stanza release
  notes, version-bump-back, `workflow_dispatch`).
- Shared palette (`ns.COLORS`), the version-update nudge (`Comms.lua`), the
  stat-rich minimap tooltip, and the lint/format configs + `luac -p` CI gate
  (shipped in v1.12.0).
