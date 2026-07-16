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
4. **Dead v2 scaffolding.** `ListWidget.lua` (`ns:CreateListWidget`) is never
   called - the Bars/Groups lists use a direct FauxScrollFrame instead - and the
   PanelInfra helpers `InitPanel` / `WrapPanelInScrollFrame` / `FitScrollContent` /
   `RegisterScrollFit` have no call sites (so the `scrollFits` refit passes in
   `RefreshLayouts` are permanent no-ops). Harmless but loaded every session.
   Candidate for removal (would drop `ListWidget.lua` from the TOC + the file
   count). Deferred to avoid TOC churn right before v2.0.0.
5. **In-game drag-reorder in multi-column groups is approximate.** `CalcDropIndex`
   now handles growth direction and picks the nearest bar in 2D, but the linear
   bar order maps ambiguously onto a 2D grid, so a drop between columns snaps to
   the nearest linear slot. The Options Bars-tab list drag (single column) is
   exact; this only affects the in-game ghost drag on 2-4 column groups. Low.
6. **Empty-group edge display.** A group with all bars hidden by a condition (or a
   glow ending) stays backdrop-visible until the next 0.25s scan (brief flash),
   and a brand-new group with no bars is hidden until its first bar is added
   (no frame to grab in-game). Both cosmetic; the group-hide check lives in
   `ScanAllBars` only, not the event-driven scans. Low.
7. **Two profile export encodings.** `ns:ExportProfile`/`ImportProfile` (Utils,
   fingerprint-suffixed, test-covered) are NOT what the Profiles tab uses (its own
   inline `BarWarden:v1:` encoding, no fingerprint). Each round-trips with itself;
   a string from one will not import via the other. Unify or document before
   exposing `ns:ExportProfile` to a caller. Low / latent.

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
E. **GCD threshold stays 1.5s for spell cooldowns** (`GCD_THRESHOLD`, Utils.lua).
   On a reduced-GCD server (Project Ebonhold's ~1s GCD) this hides genuine
   1.0-1.5s cooldowns, but lowering it risks the global cooldown itself leaking
   through as a bar. Owner chose to keep 1.5s; `ns.SpellDurations` remains the
   per-spell escape hatch for display. Items use `duration > 0` instead (they do
   not share the spell GCD).
F. **`smoothExpiry` masks a shortened refresh (B7).** The aura expiry smoothing
   is monotonic by design (holds the longer value against any backward jump, so
   server drift never stutters the bar); `test_smoothExpiry_*` enforce this. The
   trade-off is that a genuine re-application with a SHORTER duration is masked
   until it drains. A clean fix needs an absolute-time bar model (ClassTimer's
   approach), which is out of scope for the frozen engine. Rare on 3.3.5a; won't-fix.

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
- **v2 tracking-engine review fixes** (compared against ClassTimer; EbonClearance
  does no tracking): aura **stack counts** now render on time-based bars
  (`bar.stacks` written in `ScanBar`); **Only Mine** accepts `player`/`pet`/`vehicle`
  casters; `smoothExpiry`/`clearExpiry` now share a key so name-tracked entries
  are pruned (no slow leak); `UNIT_AURA` throttles **per-unit** so a two-unit burst
  never drops a scan; **permanent (0-duration) auras** show a static "present" bar
  (`ActivateStaticBar`); **item** cooldowns gate on `duration > 0` not the spell GCD.
  All covered by `tests/test_trackers_logic.lua`.
- **v2 whole-addon review fixes (2nd pass).** Data: Reset-to-Defaults now backs up
  first and no longer wipes the saved-profile library (was irrecoverable);
  `OnProfileChanged` invalidates the visual cache (bars kept the old look until
  /reload); profile Load backfills visual defaults. UI: the bar-editor and
  group-settings scroll children had fixed heights (660/500) that the stacked
  content overflowed - lower controls were unreachable; now a generous fallback +
  `fitEditorHeight`/`fitGroupHeight` trim to real content. Activity empty-state
  used `#` on a set (always 0) - now `next()`. `UNIT_HEALTH` throttles per-unit.
  Engine: `RunScan` is `pcall`-guarded so a scan error can't wedge `scanDepth` and
  freeze all layout. `DragReorder` `CalcDropIndex` handles growth direction + 2D.
  `DuplicateFrame` refreshes the scan cache. Group colour swatch re-checks its
  toggle. Same-client comparison confirmed clean: comms semver, activity
  accumulation, minimap, conditions, CLEU.
