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
4. **Dead PanelInfra scaffolding.** `ListWidget.lua` was removed in v2.0.1 (never
   called; the Bars/Groups lists use a direct FauxScrollFrame). The PanelInfra
   helpers `InitPanel` / `WrapPanelInScrollFrame` / `FitScrollContent` /
   `RegisterScrollFit` still have no real call sites (so the `scrollFits` refit
   passes in `RefreshLayouts` are permanent no-ops); left in place because they
   are entangled with live layout code and not worth the churn. Low priority.
5. **In-game drag-reorder in multi-column groups is approximate.** `CalcDropIndex`
   now handles growth direction and picks the nearest bar in 2D, but the linear
   bar order maps ambiguously onto a 2D grid, so a drop between columns snaps to
   the nearest linear slot. The Options Bars-tab list drag (single column) is
   exact; this only affects the in-game ghost drag on 2-4 column groups. Low.
6. **Empty-group edge display.** A group with all bars hidden by a condition (or a
   glow ending) stays backdrop-visible until the next 0.25s scan (brief flash).
   Cosmetic; the group-hide check lives in `ScanAllBars` only, not the
   event-driven scans. (The other half of this item - a brand-new group being
   invisible until its first bar - was fixed in v2.1.1: a bar-less group now
   renders solid at the screen centre.) Low.
7. **Two profile export encodings.** `ns:ExportProfile`/`ImportProfile` (Utils,
   fingerprint-suffixed, test-covered) are NOT what the Profiles tab uses (its own
   inline `BarWarden:v1:` encoding, no fingerprint). Each round-trips with itself;
   a string from one will not import via the other. Unify or document before
   exposing `ns:ExportProfile` to a caller. Low / latent.
8. **Preset positions are stored by reference.** `ClassPresets.lua`
   `BuildGroupFromPreset` assigns `groupPreset.position` straight into
   SavedVariables, aliasing the shipped preset constant (and sharing one table
   between two groups if a starter is appended twice in a session). Benign only
   because every writer replaces `position` wholesale; deep-copy it when
   convenient. Low / latent.
9. **Truncated import strings parse as valid.** `ns:Deserialize` returns a
   partial table rather than failing, and the Profiles tab only checks
   `type(data.frames) == "table"`, so half a pasted export imports cleanly with
   groups silently missing. Lands in a new profile, so no live data is lost.
   Relates to item 7. Low.
10. **Enchant and totem uptime may never close.** `ScanEnchantActivity` runs only
    on `UNIT_INVENTORY_CHANGED` and `ScanTotemActivity` only on
    `PLAYER_TOTEM_UPDATE`; neither reliably fires when the effect merely expires,
    so the Activity tab under-reports their uptime (proc counts are correct).
    Needs an expiry poll like `CheckCooldownExpiry`. Low-med.
11. **Drag-reorder is wrong under a sorted group.** `CalcDropIndex` maps screen
    position onto `frameData.bars` order, which is not the on-screen order when
    `sortMode` is `remaining`/`alpha`, so a drop lands in an unrelated slot (and
    manual order has no visible effect there anyway). Consider suppressing the
    ghost when sorting is not manual. Extends item 5. Low.
12. **Per-bar `scaleOverride` shifts row offsets.** `UpdateGroupLayout` applies
    `bar:SetScale` after `SetPoint`, so a scaled bar's row offset scales too -
    the same coordinate-space class as the v2.0.2 group drift. The editor tooltip
    warns about column overlap but not vertical drift. Low.
13. **Three divergent "new bar" constructors.** `NewBar` (Options_Bars),
    `Options_Stats`'s Create Bar, and `MakeFullBar` (ClassPresets) write
    different subsets of `conditions`/`display`. This divergence is what made the
    v2.1.1 stale-toggle bug bite hardest on starter-profile bars. Unify. Low.
14. **The text-format option list is duplicated** in `Options_Visuals.lua` and
    `Options_Bars.lua` (byte-identical today, the latter plus an "Inherit" row).
    A seventh format added to Visuals will silently not appear as a group
    override. Low.
15. **`schemaVersion` is hand-synced twice** (`ns.DEFAULTS.schemaVersion` and
    `CURRENT_SCHEMA` in DB.lua) with nothing enforcing agreement; and
    `starterPrompted` / `v1ImportPrompted` / `backups` live in SavedVariables
    without being declared in `ns.DEFAULTS`, even though `ns:DBSet` treats the
    schema as authoritative. Low.
16. **Auto-track duplicate matching is by name only.** A curated bar tracking a
    bare spell id, or an aura group such as `@Stunned`, does not suppress its
    spell in an auto group with Skip Spells I Already Track on. Matching by name
    is what the player means by "I already track that"; ids and groups would need
    `ns:GetTrackedAuraNames` to resolve names through `GetSpellInfo`, which is
    not safe to call for arbitrary ids on a 4 Hz path without caching.
17. **Auto groups are invisible while empty**, so they are positioned by
    unlocking frames rather than by using test mode (there are no real auras for
    test mode to show). If this proves awkward in play, filling the slots with
    dummy bars while unlocked is the natural follow-up.
18. **Switching an auto group straight from a target feed to a player feed
    leaves Only Mine ticked.** `autoOnlyMine` is only seeded the first time
    Auto Track is set (while it is still nil); the seeding guard cannot tell a
    value it seeded from one the player deliberately chose, so it never
    re-seeds on a later feed change. Real but cosmetic - the player unticks it
    once - and re-seeding on every feed change would clobber a deliberate
    choice instead.
19. **Options shell differs structurally from EbonClearance.** BarWarden creates
    each category frame parented to `UIParent` and gives it a body via
    `content:SetAllPoints(child)`; EC parents category frames to
    `InterfaceOptionsFramePanelContainer` and applies **no** addon-owned
    geometry to them at all, with bodies being either the category frame itself
    or a ScrollFrame scroll child. EC's shape has no addon-owned anchor between
    panel and body that Blizzard's options machinery can disturb. Adopting it
    would remove a whole class of layout bug (see the v2.1.1 detach entry
    below), but it touches all five panels, so it is a deliberate refactor
    rather than a patch. Med effort, low risk, good payoff.

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

- **v2.1.1 Bar Control page detaching (found in play, not by the audit).**
  Blizzard's `FauxScrollFrame_Update` hides the **whole scroll frame**, not just
  its scrollbar, when the list fits without scrolling. Both lists in
  `Options_Bars.lua` anchor the rest of their column to that scroll frame
  (`addGroupBtn` -> `groupSettingsHeader` -> the settings block), so the moment
  it was hidden the dependants resolved against a stranded rect and rendered at
  the panel origin - visually "the menu contents fell out of the window", with
  **no Lua error**. Trigger was a list going from 7 items to 6
  (`MAX_GROUP_ROWS`/`MAX_BAR_ROWS` are 6), which is why it looked like a delete
  bug and why adding a group "fixed" it. Fixed with `KeepListFrameShown`: keep
  the frame shown, hide only the scrollbar (carries an `EC-TRAP:` marker,
  because the `Show()` looks redundant). The sibling addon EbonClearance is
  immune structurally - its category frames are parented to
  `InterfaceOptionsFramePanelContainer` with no addon-owned geometry, panel
  bodies are either the category frame itself or a ScrollFrame's scroll child
  (never `SetAllPoints` between panel and body), and its auto-hide hides the
  scrollbar only. Worth copying that shape if the options shell is ever
  reworked; see also backlog item 19.

- **v2.1.1 whole-addon audit.** Three parallel subsystem passes (engine, data,
  UI) plus a cross-cutting sweep, every finding re-verified against source.
  Data safety: `/bw restore` overwrote `frames` with no backup (the only
  destructive path that did not) and the ring was never popped, so a mistaken
  restore was permanent; delete confirmations re-read the live selection at
  accept time, so clicking another row behind the non-modal popup deleted the
  wrong group or bar, with no backup taken. Broken settings: `RefreshAllBars`
  had no `enabled` check and ran one line after `RebuildAllFrames` at login, so
  the Enabled tickbox never stuck (four sites disagreed on its meaning - now one
  `ns:IsBarEnabled`); `BuildSettings` skipped the applier on a nil `get()`, so
  toggles showed the previous selection's state; `CheckBuff` passed a hardcoded
  `false` for `filterMine`, making Only Mine a no-op on buffs. Engine: a static
  bar with linger entered `LINGERING` with no OnUpdate to end it;
  `HideBarForConditions` only tore down `ACTIVE` bars; `UpdateResourceBar`
  bypassed `ns:GetBarTextFormat`. Frames: `SetFrameScale` did not re-anchor, so
  changing scale moved the group (a side effect of the v2.0.2 anchor rework);
  `DisableDragReorder` never restored `EnableMouse(false)`, so locked bars ate
  clicks. Lifecycle: `SetEnabled(true)` did not rebuild, so `/bw enable` after a
  disabled login showed nothing; `/bw reset` claimed to reset positions and did
  not. Presets: Weakened Soul tracked as a buff (impossible), healer HoTs pinned
  to `unit = "player"`, `AppendClassStarter` bypassed `MAX_FRAMES`. Also
  retired the dead `showEmpty` option, deleted the duplicate `ns:ApplySettings`
  stub (the real one in Core won only by TOC order) plus `ns:CreateFrame`,
  `ThrottledHandler` and `ShouldHideWhenInactive`, guarded the unguarded
  `LSMDropdownItems` file-scope call (it would have taken the whole Visuals
  panel down with LSM absent, contradicting its own EC-TRAP contract), stopped a
  global `_` write on a 4 Hz path, hoisted the per-event mode-set tables off the
  `SPELL_UPDATE_COOLDOWN` path, cleared per-unit throttle keys on unregister,
  and corrected six pre-v2 Help answers.

- **v2.1.0 stack visibility + group overrides.** Stack counts were read and
  stored correctly (`bar.stacks` in every activation branch) but only ever
  rendered into `bar.timeText` under the global `NAME_STACKS`/`STACKS` formats,
  so the default `NAME_DURATION` showed nothing - a permanent 9-stack buff drew
  a solid bar with no number. Added `bar.stackText`, an icon-corner badge
  parented to `bar.icon` (a child frame draws above the bar's own OVERLAY, so a
  bar-parented fontstring would hide behind the icon) and reparented to the bar
  when the icon is off, rendered from the single `ns:RenderBarStacks` with the
  pure `ns:ShouldShowStackBadge` predicate. Also fixed: static (permanent-aura)
  bars have no OnUpdate, so their text was written once at activation and a
  later stack change never redrew - now `ns:UpdateStaticBarText` is called from
  the already-active path too. Text format and hide-when-inactive gained group
  overrides via `ns:GetBarTextFormat` / `ns:ResolveHideWhenInactive` (see the
  ADDON_GUIDE "Group overrides" table for the precedence rules and why the
  hide-when-inactive resolver is an OR).

- **v2.0.2 group position drift.** `UpdateGroupLayout` re-anchored the group on
  every relayout using `GetLeft() * GetEffectiveScale() / uiScale`. `SetPoint`
  offsets are already in the frame's own scaled space, so this double-applied
  scale: each relayout multiplied the offset from the pinned corner by
  `group:GetScale()` and wrote it back to `groupData.position`, so a scaled
  group crept towards the corner on every bar activate/deactivate and the error
  persisted across reloads (scale 1.0 groups were unaffected). `SaveFramePosition`
  carried the same bad conversion and additionally forced `TOPLEFT`, pinning
  grow-up groups by the wrong edge. Fixed by anchoring against UIParent
  BOTTOMLEFT (screen origin, 0 in every frame's unit space) so edges pass
  through verbatim (`ns:NormalizeGroupAnchor`, Utils.lua), and by re-anchoring
  ONLY when the pinned corner must change - a pure size change needs none.
  `MigrateFrames` now backfills `growDirection`/`columns`/`position`. Covered by
  `tests/test_migration.lua`; frame geometry is not stubbed, so anchoring itself
  rides the in-game test. Already-drifted positions are unrecoverable (users
  re-drag once).

- **v2.0.1 Activity proc-count inflation.** `ActivityTracker.lua` detected new
  activity by diffing live state against `prev*` snapshots that
  `StartActivityTracking` wiped to empty on every login/reload/re-enable, so the
  first scan counted every already-active buff/enchant/totem/player-debuff as a
  fresh activation and bumped its all-time "Procs" total. Frequent `/reload`s
  compounded it into wildly high counts. Fixed with per-scanner `primed*`
  baseline guards: the first post-restart scan seeds the snapshot without
  recording, and only genuine transitions count thereafter (uptime was never
  affected). Covered by `tests/test_activity_tracker.lua`. Historical counts
  stay inflated; `Reset All` on the Activity tab gives a clean baseline.

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
