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
11. **Per-bar `scaleOverride` shifts row offsets.** `UpdateGroupLayout` applies
    `bar:SetScale` after `SetPoint`, so a scaled bar's row offset scales too -
    the same coordinate-space class as the v2.0.2 group drift. The editor tooltip
    warns about column overlap but not vertical drift. Low.
12. **Three divergent "new bar" constructors.** `NewBar` (Options_Bars),
    `Options_Stats`'s Create Bar, and `MakeFullBar` (ClassPresets) write
    different subsets of `conditions`/`display`. This divergence is what made the
    v2.1.1 stale-toggle bug bite hardest on starter-profile bars. Unify. Low.
13. **The text-format option list is duplicated** in `Options_Visuals.lua` and
    `Options_Bars.lua` (byte-identical today, the latter plus an "Inherit" row).
    A seventh format added to Visuals will silently not appear as a group
    override. Low.
14. **`schemaVersion` is hand-synced twice** (`ns.DEFAULTS.schemaVersion` and
    `CURRENT_SCHEMA` in DB.lua) with nothing enforcing agreement; and
    `starterPrompted` / `v1ImportPrompted` / `backups` live in SavedVariables
    without being declared in `ns.DEFAULTS`, even though `ns:DBSet` treats the
    schema as authoritative. Low.
15. **Auto-track duplicate matching still misses aura groups.** Matching is by
    resolved spell name: `ns:GetTrackedAuraNames` reads both `spellName` and
    `spellId` and resolves ids through `GetSpellInfo`, so a curated bar
    configured by name or by bare spell id suppresses correctly either way,
    provided the client can resolve that id: `GetSpellInfo` returns nil for
    an id the client's spell table does not know (a custom private-server id
    with no matching client patch, for example), and such a bar is skipped
    rather than suppressed, no differently from any other unresolved id.
    An aura group reference such as `@Stunned` still does not suppress,
    because it only expands to a list of ids at scan time
    (`getSpellTokens`), not inside `ns:GetTrackedAuraNames`. Resolving each id
    in the group through `GetSpellInfo` would fix it; the function is cached
    per group (`trackedNamesCache`, BarEngine.lua) and only recomputed on a
    bar edit, so the earlier "not safe on a 4 Hz path" objection to calling
    `GetSpellInfo` here does not apply.
16. **Auto groups with nothing to show still hide while frames are locked, by
    default.** An auto group holds slots rather than configured bars, so with
    nothing on the unit every slot is hidden and `AreAllBarsHidden`
    (BarEngine.lua) hides the whole group, same as it does for any other group
    with nothing visible; that is the default, since locked is the normal
    playing state. Unlocking frames reveals it, so it can still be positioned;
    there is no test mode for it, since there are no real auras for test mode
    to show. Since v2.2.5, the group's own Hide When Inactive toggle overrides
    the default in either direction (`ns:ShouldHideEmptyGroup`,
    Conditions.lua): untick it to keep the group and its name up even locked
    and empty, tick it to hide the group whether locked or unlocked. If
    positioning an empty auto group still proves awkward with that available,
    filling the slots with dummy bars while unlocked is the natural follow-up.
17. **Switching an auto group straight from a target feed to a player feed
    leaves Only Mine ticked.** `autoOnlyMine` is only seeded the first time
    Auto Track is set (while it is still nil); the seeding guard cannot tell a
    value it seeded from one the player deliberately chose, so it never
    re-seeds on a later feed change. Real but cosmetic - the player unticks it
    once - and re-seeding on every feed change would clobber a deliberate
    choice instead.
18. **Options shell differs structurally from EbonClearance.** BarWarden creates
    each category frame parented to `UIParent` and gives it a body via
    `content:SetAllPoints(child)`; EC parents category frames to
    `InterfaceOptionsFramePanelContainer` and applies **no** addon-owned
    geometry to them at all, with bodies being either the category frame itself
    or a ScrollFrame scroll child. EC's shape has no addon-owned anchor between
    panel and body that Blizzard's options machinery can disturb. Adopting it
    would remove a whole class of layout bug (see the v2.1.1 detach entry
    below), but it touches all five panels, so it is a deliberate refactor
    rather than a patch. Med effort, low risk, good payoff.
19. **Test mode has no guard in `ScanAutoGroup`.** `ScanBar` early-returns on
    `ns.testMode and bar.isTestBar`, but `ns:ScanAutoGroup` (BarEngine.lua) has
    no equivalent check. `ns:ActivateTestMode` activates any bar that passes
    `ns:IsBarEnabled`, which an occupied auto slot does, so it can briefly show
    a fake timer that the next real scan overwrites. Nothing breaks and
    nothing persists, but the Help "Can a group fill itself?" answer's claim
    that test bars do not appear in an auto group is only strictly true while
    the group is empty. Low, cosmetic.
20. **Per-bar display settings never reach an auto slot.** `NewAutoBarData`
    (FrameManager.lua) supplies `display = { lingerTime = 0 }` only, so a
    slot's own glow on ready, pulse on ready, linger, and the per-bar
    colour/scale overrides never apply to an auto bar, since they are read
    from `bar.barData.display`. Group-level and addon-wide visuals still
    apply; this is intended, and ADDON_GUIDE's auto-tracking section says so.
    **Partly resolved in v2.4.0**: glow on ready, pulse on ready and linger
    now have a group-level equivalent (`ns:GetBarGlowOnReady` /
    `ns:GetBarPulseOnReady` / `ns:GetBarLingerTime`, Conditions.lua, plus the
    Groups tab's Custom Bar Effects toggle), which an auto-tracking group can
    use since it has no bar list of its own to set them on. The per-bar
    colour/scale overrides have no group-level equivalent and remain
    unreachable there. Low.

21. **Nothing calls `ns:DeleteFrame`.** The Bars tab's Delete button deletes a
    group inline (`table.remove` + `frame:Refresh()` + `ns:RebuildAllFrames()`,
    Options_Bars.lua), so `ns:DeleteFrame` (FrameManager.lua) is unreachable.
    It is not wrong, just a second way to do the same thing that no longer
    matches the one in use - the same drift that got `ns:CreateFrame` removed in
    v2.1.1. Either route the button through it or delete it. Low.
22. **`frame:Refresh()` runs before `ns:RebuildAllFrames()` on the delete path.**
    In that window `BarWardenDB.frames` has been renumbered but `ns.groupFrames`
    still holds the old frames at their old indices, so anything index-keyed
    that ran there would read one group's frame against another's data - and
    `ns:UpdateGroupLayout` writes `position` by `group.frameIndex`. Nothing in
    the refresh path currently touches a group frame (every widget callback is
    behind `ns.suppressCallbacks`, and the two `ns:ScanAutoGroup` calls are
    click handlers), so this is latent, not live. Swapping the two calls closes
    it. Verified during the v2.2.3 investigation. Low, but sharp.
23. **`ns:RebuildAllFrames` leaks a frame per group per rebuild.** 3.3.5a cannot
    destroy a frame, so `DestroyGroupFrame` hides it, clears its points and
    drops the reference, and the next `ns:CreateGroupFrame` builds a fresh frame
    reusing the same global name. The orphans are inert (hidden, unanchored, no
    bars, not in `ns.groupFrames`, and `ns:ReleaseBar` re-parents their bars), so
    the cost is memory in a long session with many settings changes, not
    behaviour. Fixing it means pooling group frames the way bars are pooled. Low.

24. **Unit frames (v2.6.0) ship player-only, with no conditions, cap slider,
    or profile export.** `UnitFrames.lua` builds the widget and the Frames
    tab for `unit = "player"` only; target/target's-target/pet/focus/party
    frames need only a new `UNIT_TOKENS`/`UNIT_FRAME_KEYS` entry, a
    `ns.DEFAULTS.unitFrames` entry, and a Frames-tab toggle, since the
    widget itself is already unit-token-driven. Also deferred: per-bar
    visibility conditions on a unit frame (bar groups' `conditions` table has
    no equivalent here yet) and a user-facing cap on `MAX_UNIT_FRAME_SLOTS`
    (the fixed value already has ample headroom for every feed
    `ns:CollectResources` can produce). **Profile export/import is now
    done**: `ns:CaptureProfileData` / `ns:ApplyProfileData` (DB.lua) drive
    every call site from one `PROFILE_SECTIONS` list, which is what stops the
    next added section going missing the way `unitFrames` did. None of these block the current slice;
    listed so a later session extending unit frames does not have to
    rediscover the boundary. Low priority, low-med effort per item.

25. **Target frame: do NOT copy the player frame's resource controls.**
    Planned next, and the owner has been explicit that it is not a
    duplicate. The player frame exposes a per-resource tick list because a
    player on a classless server has several pools at once and wants to
    choose between them. A target frame should behave like Blizzard's own:
    show what the target actually has, which is health plus its current
    power type, and nothing else.

    Concretely, that means the target's config should NOT carry
    `hiddenResources`, `pairRunes`, or a pin list, and `ScanUnitFrame` must
    not pass pins for it. `ns:CollectResources` already does the right
    thing unasked: runes, runic power and soul shards are gated on
    `unit == "player"` (they are the player's own pools, see that
    function's comment), and combo points are deliberately excluded for
    `targettarget`. So a target frame that passes no pins and no hidden set
    gets exactly the Blizzard-standard health-plus-power shape for free.

    The temptation when adding the frame will be to lift the whole player
    config block for symmetry. Resist it: the extra controls would each be
    a setting that either does nothing or shows a bar the target cannot
    have. Everything else - portrait, name, level, fonts, opacity, bar look
    and height - SHOULD be shared, and the widget is already unit-token
    driven, so this is about which config keys exist, not about a second
    widget. Medium effort, and it blocks nothing today.

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
G. **Auto-track skip set checks bar existence, not visibility.** The `Skip Spells
   I Already Track` filter (`ns:GetTrackedAuraNames`, Trackers.lua) asks whether a
   bar for a spell exists in another group, not whether it is currently visible.
   Testing visibility would make spells flicker between groups on every condition
   change (a spell hides when its group hides, then appears in auto-track, then hides
   again when the group shows). The cost is that a spell tracked only in a
   conditionally-hidden group (for example, a buff in a Combat Only group) is
   suppressed from auto-track while the group is hidden. Owner considered the
   alternative behaviour and chose to keep this. Won't-fix.
H. **`ns:BuildSettings`'s `offsetX` is absolute except through `anchorTo`.**
   Every ordinary entry's `offsetX` is an absolute indent from the panel's left
   edge (added to `firstX`); an entry with `anchorTo = "<id>"` is the one
   deliberate exception, keeping the old relative-nudge-from-that-widget
   semantics instead, because it is a branch off the main chain (a
   conditionally hidden sub-item, or a section header re-anchoring past one)
   rather than a row in the panel's own column. Documented in ADDON_GUIDE.md
   and in the `anchorTo` comment in Options_Builder.lua. Do not "fix" an
   `anchorTo` entry's `offsetX` to read like an absolute indent.
I. **Bar Style dropdown has no `[?]` help icon.** Every other Group Settings
   section header gets one via `ns:CreateHelpIcon`, but `ns:CreateDropdown`
   (Widgets.lua) builds the dropdown's text label as a private local
   fontstring and never exposes it on the returned frame, so there is no
   widget to anchor a help icon next to the visible "Bar Style" text - only
   the wide `UIDropDownMenuTemplate` box itself, which would put the icon in
   the wrong place. Adding one needs `ns:CreateDropdown` to expose the label
   frame first. Deferred, not forgotten.
J. **`UnitClass("player")` is not a trustworthy signal in `ns:CollectResources`
   (v2.5.0 fix).** The owner plays on Grimfall, a classless private server
   where every character reports the same class token while genuinely having
   any combination of runes/rage/energy/mana/soul shards at once. Gating
   Runes/Runic Power/Soul Shards on a class token made them permanently
   uncollectable there. `HasRunes`/`HasRunicPower` (Trackers.lua, `EC-TRAP`
   marked) now probe the actual API instead, and Soul Shards/Combo Points
   read their own values directly. Standing constraint: any future
   auto-detected resource in `ns:CollectResources` must be gated on a
   capability probe, never on `UnitClass`. The one accepted cosmetic
   trade-off: pinning "Keep Combo Points Visible" for a character that
   structurally cannot generate any still shows a static 0/5 bar, since
   `GetComboPoints` has no zero-max signal the way a power pool does. This
   does not touch `Conditions.lua`'s `requireClass` bar condition or
   `ClassPresets.lua`'s per-bar `requireClass` stamping, which are explicit,
   opt-in, user-facing class checks rather than automatic resource
   detection, and remain unaffected.

## Resolved (kept for the record)

- **v2.4.0 drag-reorder was wrong under a sorted group.** The in-game ghost
  drag (`CalcDropIndex`, DragReorder.lua) and the Options Bars-tab list drag
  (`ComputeDropIndex`, Options_Bars.lua) both mapped the drop position onto
  `frameData.bars`, the stored order, but a group's Sort Mode
  (`remaining`/`alpha`/`appearance`) re-derives the on-screen order on every
  layout, so a drop landed in an unrelated slot, and even a "successful"
  manual reorder had no visible effect there anyway. Fixed by refusing the
  reorder for a non-Manual group instead of letting the gesture fail
  silently: `IsManualSort` (DragReorder.lua) is checked live, at the moment
  the drag threshold is actually crossed, rather than baked in once at
  `ns:EnableDragReorder` wiring time, because the Sort Mode dropdown only
  calls `ns:UpdateGroupLayout` and can flip a group sorted while it is
  already unlocked. Both paths explain the refusal once per attempt through
  the shared `ns:ExplainSortedDragRefusal`. An auto-tracking group already
  left its bars unwired for a different, older reason (`isAutoGroup`, its
  stored `bars` are dormant while it fills itself), so the two guards never
  fight: an auto group's bars never reach the sorted check because they
  never get mouse handlers at all. Frame-only fix with no automated
  surface; verified in-game per the smoke-test checklist. Was backlog
  item 11.

- **v2.2.4 Background/Border Opacity 0 stuck solid black on an empty group
  forever.** `ns:UpdateGroupLayout` (FrameManager.lua) forced the backdrop to
  a hardcoded solid 0.85 for any empty group, never consulting `bgAlpha` -
  correct for a brand-new group at the screen centre (otherwise it is
  invisible and the owner cannot find or drag it), wrong for a group the
  owner had already positioned and deliberately made transparent, which then
  stayed at 0.85 on every relayout no matter what the sliders said. Narrowed
  with a new `HasRealAnchor` helper: the override now only fires while a
  group is both empty AND still on `NewGroup`'s (Options_Bars.lua) CENTER
  creation placeholder. `ns:NormalizeGroupAnchor` (Utils.lua) is the only
  thing that ever writes a corner point ("TOPLEFT"/"BOTTOMLEFT") - from a
  drag, a growth-direction flip, a scale change, `/bw reset`, or
  `ns:MigrateFrames`'s position backfill - so a corner point is a reliable
  "this group has a real anchor" signal regardless of which of those wrote
  it, including the mismatch-repin inside `ns:UpdateGroupLayout` itself
  resolving a brand-new group's placeholder on its first layout pass, before
  the owner has touched anything. Border Opacity was never overridden this
  way (`SetBackdropBorderColor` only ever reads `borderAlpha` directly), so
  no equivalent fix was needed there. Covered by
  `tests/test_frame_manager.lua`.

- **v2.2.3 group position shifted on a layout rebuild.** `ns:UpdateGroupLayout`
  re-anchored the group BEFORE applying the size it had just computed, so the
  edges it read were whatever the frame happened to measure a moment earlier.
  That is the same size on a settled group, which is why the ordering looked
  right and never showed itself on the relayout path. It is not the same size on
  the two paths that matter: `ns:RebuildAllFrames` lays out a frame
  `ns:CreateGroupFrame` stubbed at `SetHeight(30)`, and an auto-tracking group is
  laid out with every slot still hidden. Whenever the pinned corner had to change
  (a grow-up group carrying a TOPLEFT anchor, which is what `/bw reset` and
  `ns:MigrateFrames`'s position backfill both write, or a new group still on its
  CENTER anchor), the wrong edge was pinned by (final height minus the size it
  was read at) and written straight to SavedVariables, so the group jumped that
  far and stayed there - further the taller it was. Fixed by resizing first and
  re-anchoring after; the frame grows away from the corner it is already held by,
  so the edge then pinned is the one the saved anchor asked for. The
  re-anchor-only-on-mismatch guard from v2.0.2 is untouched, so nothing is
  re-derived on the hot path. Carries an `EC-TRAP:` marker (indexed in
  ADDON_GUIDE) because reverting to read-edges-first reads as the obvious
  "keep the corner the user is looking at" intent. Covered by
  `tests/test_frame_manager.lua`, which drives `ns:UpdateGroupLayout` through a
  stub group modelling WoW's grow-away-from-the-pinned-corner rule; the three
  no-repin cases pass both before and after, which is what proves the v2.0.2
  guard survived.

- **v2.2.2 starter prompt still offered over a real auto-tracking layout.**
  `ns:HasExistingLayout` (Utils.lua) judged an existing layout by configured
  bar count / group count, so a group set to Auto Track - whose saved `bars`
  array stays empty by design - read as a fresh install, and the first-login
  starter prompt could still appear over it. Fixed by also treating any group
  with `autoTrack` set as a protected layout. The prompt only ever appends
  (`ns:AppendClassStarter`), never replaces, so no data was ever actually at
  risk; the bug was the prompt appearing at all. Covered by
  `tests/test_migration.lua`.

- **v2.2.1 Background Opacity stuck solid on a populated auto-tracking group.**
  The group backdrop's emptiness check used `#frameData.bars == 0`, but
  `frameData.bars` is only ever the dormant hand-added bar list a group keeps
  for when Auto Track is switched back off - permanently zero for a pure auto
  group, so the solid start-up backdrop never cleared no matter how many auto
  slots were filled. Split into `IsGroupEmptyForBackdrop` (FrameManager.lua):
  an auto-tracking group's emptiness is `visibleCount == 0` (what its slots
  are actually showing), an ordinary group's stays keyed off its configured
  bar count. Carries an `EC-TRAP:` marker (indexed in ADDON_GUIDE) since
  collapsing the two branches back into one reintroduces exactly this bug.
  Covered by `tests/test_frame_manager.lua`.

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
  reworked; see also backlog item 18.

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
