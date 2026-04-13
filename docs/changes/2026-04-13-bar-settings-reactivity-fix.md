# Per-Bar Editor Reactivity Fix (RCA log)

**Date:** 2026-04-13
**Baseline:** Post-Phase-4-Visuals working tree (uncommitted from prior session).
**Scope:** [Core.lua](../../Core.lua) + [Options_Bars.lua](../../Options_Bars.lua)
per-bar editor callbacks + [README.md](../../README.md).

---

## Why this change exists

In-game testing of v1.4.0+ revealed that most per-bar editor toggles did
not react "live" to user interaction. A user would tick *Hide When
Inactive* and the bar would not hide until the user also tapped
*unrelated* control (e.g. *Show Bar Name*) which happened to trigger a
refresh as a side effect.

The user explicitly reported:
- *Hide When Inactive* → nothing happens until another toggle is
  interacted with.
- *In Group* / *In Raid* → appeared reactive (coincidence: caught by
  the 250 ms scan loop).
- Text-field changes required pressing Enter; checkbox flips took no
  effect until a second interaction.

## Root cause (two compounding issues)

### Issue 1: ~18 of ~25 per-bar callbacks wrote the DB and did nothing else

Per-bar editor callbacks in
[Options_Bars.lua](../../Options_Bars.lua) were inconsistent:

| Group | Refresh behaviour (pre-fix) |
|---|---|
| Bar enabled | custom Show/Hide logic (reactive) |
| Bar Name | `ns:RebuildAllFrames()` (heavy but reactive) |
| Spell / Track Mode / Target / Only Mine | `ns:ScanAllBars()` (reactive) |
| Show Bar Name / Show Icon / Bar Darkness / Crop Icon | `ns:RebuildAllFrames()` (heavy but reactive) |
| Color Override | `ns:RefreshAllBars()` (reactive) |
| **Combat Only / OOC Only / In Group / In Raid / Hide When Inactive / Show Empty / Health Below % / Require Buff / Linger Time / Sparkle Alert / Alert Threshold / Colour by Time / High Threshold / Med Threshold / Glow on Ready / Glow Duration** | **NOTHING** |

The last 16 callbacks just wrote the DB. The background scan loop
([Core.lua](../../Core.lua) `OnUpdate`) runs every 250 ms and calls
`ns:ScanAllBars()`, which re-evaluates tracker conditions — but **only
re-runs state transitions, not visibility re-evaluation for already-
inactive bars**. So the 250 ms loop happened to make some condition
toggles look reactive (because they kept filtering the tracker
evaluation) but not others (because they only apply on state change).

### Issue 2: `ns:RefreshAllBars` didn't honour `hideWhenInactive`

The engine applies `hideWhenInactive` only during the
active → inactive transition
([BarEngine.lua:102-111](../../BarEngine.lua)). `ns:RefreshAllBars` in
[Core.lua](../../Core.lua) set alpha but never called `bar:Hide()` or
`bar:Show()`. So even after fixing Issue 1, toggling *Hide When
Inactive* on a bar currently sitting inactive + visible would not
have hidden it — the engine wouldn't reach its state-transition code
path and `RefreshAllBars` didn't apply the flag itself.

---

## What's changing

### [Core.lua](../../Core.lua) — two small additions

**1. `ns:RefreshAllBars` now applies `hideWhenInactive` on the spot.**
The active branch explicitly `:Show()`s the bar and sets active alpha.
The inactive branch checks `conditions.hideWhenInactive`: if true, it
`:Hide()`s the bar; otherwise it `:Show()`s and sets inactive alpha.
Group layout is updated afterwards (unchanged). This means any code
path that calls `RefreshAllBars` now fully enforces the flag, no
longer just the transition code.

**2. New `ns:RefreshBarSettings()` helper.** Calls `RefreshAllBars()`
(immediate visual), then `ScanAllBars()` (re-evaluates tracker data
and condition filters within the same tick). This is the unified
entry point every per-bar editor callback uses now.

### [Options_Bars.lua](../../Options_Bars.lua) — uniform callback pattern

Every per-bar editor callback now follows the same shape:

```lua
local bar = frame:GetSelectedBar()
if bar then
    -- write DB fields ...
    ns:RefreshBarSettings()
end
```

Counts after the change:
- `ns:RefreshBarSettings` call sites: **26** (one per callback).
- `ns:ScanAllBars` direct calls: **0** (all absorbed into the helper).
- `ns:RebuildAllFrames` direct calls: **7** — all in group/bar CRUD
  (add/delete/rename/reorder). Those genuinely need a rebuild and are
  not per-bar *settings* changes.

### [README.md](../../README.md) — three field explanations added

A new **"Useful Per-Bar Options Explained"** subsection under
Bars/Groups documents:

- **Linger Time** — the 0-to-fade grace period after a cooldown
  expires; pairs with Glow on Ready.
- **Health Below %** — only shows the bar when player HP is under a
  threshold; useful for execute-range spells and panic buttons.
- **Require Buff** — only shows the bar while a named buff is on the
  player; useful for stealth abilities, bear-form cooldowns, and
  proc-reaction bars.

---

## Behavioural preservation

| Behaviour | Today | After |
|---|---|---|
| Bar add / delete / rename / reorder causes a full rebuild | `ns:RebuildAllFrames()` | unchanged |
| Bar enabled toggle has custom Show/Hide path | custom code | unchanged |
| Changing Spell / Track Mode / Target re-scans tracker data | `ns:ScanAllBars()` | `ns:RefreshBarSettings()` (wraps ScanAllBars + RefreshAllBars) |
| Condition toggles update visibility | inconsistent / none | `ns:RefreshBarSettings()` — uniform, immediate |
| Display toggles update visuals | inconsistent (Rebuild or nothing) | `ns:RefreshBarSettings()` — uniform, lighter than Rebuild |
| `hideWhenInactive = true` hides inactive bars | only during transitions | during any `RefreshAllBars` call — immediate |
| `hideWhenInactive = false` shows inactive bars | transition-bound | immediate |

No SavedVariables format change. No `ns.DEFAULTS` change. No other tabs
touched.

---

## How to RCA if something breaks

### Symptom: Toggling a per-bar setting has no visual effect

**Look at:** the callback in
[Options_Bars.lua](../../Options_Bars.lua). It should end with
`ns:RefreshBarSettings()`. If a new callback was added without it,
that's the miss.

### Symptom: "Hide When Inactive" toggles on/off but the bar stays visible

**Look at:** `ns:RefreshAllBars` in [Core.lua](../../Core.lua). The
inactive branch must check `bar.barData.conditions.hideWhenInactive`
and call `bar:Hide()` when true, `bar:Show()` + inactive alpha when
false. If someone reverts that branch to the v1.4.0 alpha-only form,
the bug returns.

### Symptom: Bars flicker or show then immediately hide

**Look at:** `ns:RefreshBarSettings` — does `ScanAllBars` run after
`RefreshAllBars`, not before? Order matters: Refresh sets visibility
based on current state; Scan updates the state. If scan runs first it
might re-enter inactive before the frame layout re-runs.

### Symptom: Bar count changes don't take effect until `/reload`

**Look at:** the group/bar CRUD sections (lines ~140-184, ~360-414).
Those still use `ns:RebuildAllFrames()` — if someone replaced those
with `ns:RefreshBarSettings()`, bars that were just added or deleted
won't materialise until a full rebuild.

### Symptom: Performance regression on Options open

`ns:RefreshBarSettings()` is called on every per-bar callback, which
fires once per user interaction. That's infrequent — should not
affect frame rate. The helper itself does `RefreshAllBars` (iterates
all groups + bars, applies visual config) + `ScanAllBars` (iterates
all bars, checks trackers). Both are O(n) in bar count. If n is
huge (>100 bars?) and users click rapidly, *could* matter. Real
complaint: profile the helper; if needed, throttle or batch.

### Quick revert

```bash
git checkout -- Core.lua Options_Bars.lua README.md
```

No other files change. Clean three-file revert.

---

## Verification performed

- `luac -p` clean on every `.lua` file.
- `grep -c "ns:RefreshBarSettings" Options_Bars.lua` → **26** call
  sites (one per per-bar editor callback).
- `grep -c "ns:ScanAllBars" Options_Bars.lua` → **0** (replaced by
  helper).
- `grep -c "ns:RebuildAllFrames" Options_Bars.lua` → **7** (all in
  group/bar CRUD — intentionally preserved).
- ⏳ **In-game smoke test owed.**

## In-game smoke-test checklist

1. `/reload` — addon loads; no Lua error.
2. Select a bar in the Bars/Groups tab.
3. **Single-interaction reactivity test.** For each control in the
   Conditions section, change it **once** and confirm the live bars
   react immediately:
   - Combat Only: bar hides when out of combat.
   - Out of Combat Only: bar hides when in combat.
   - In Group / In Raid: bar visibility toggles with the current
     group state (test solo vs. group).
   - **Hide When Inactive**: for a bar whose cooldown is *not* active,
     ticking this box should hide it on the spot. Unticking should
     show it again at inactive alpha.
   - Show Empty: toggling should update visibility without
     needing to tap anything else.
   - Health Below %: type a number (e.g. `30`) and press Enter →
     bar hides unless your HP is under 30%.
   - Require Buff: type a buff name you currently have → bar shows;
     change to a buff you don't have → bar hides (expect an up-to-250ms
     scan delay for the data read).
4. **Single-interaction reactivity test for Display Options.** For
   each control, change it **once** and confirm the live bars react
   immediately:
   - Linger Time: change the value and expire a tracked cooldown →
     bar holds at 0 for that many seconds before fading.
   - Show Bar Name / Show Icon / Bar Darkness / Sparkle Alert /
     Colour by Time / thresholds / Glow on Ready / Glow Duration /
     Crop Icon: each should immediately reflect in the live bars.
5. **No regressions in group / bar CRUD**: adding, deleting,
   renaming, reordering groups and bars should work exactly as
   before (full rebuild).
6. **No regression in other tabs** (General, Visuals, Profiles,
   Stats).

---

## Follow-up polish: tooltips on Health Below, Require Buff, Linger Time

Checkboxes get free mouse-over tooltips via
`InterfaceOptionsCheckButtonTemplate.tooltipText`, but sliders and
editboxes don't — their frame templates don't have any hover behaviour
wired up. The three non-checkbox condition/display fields users were
most likely to wonder about (Health Below %, Require Buff, Linger
Time) had no discoverable explanation.

### What landed
- **[Widgets.lua](../../Widgets.lua)** — new local `AttachTooltip`
  helper that hooks `OnEnter`/`OnLeave` to show/hide `GameTooltip`
  with wrapped text. Uses `HookScript` so existing script handlers on
  the widget are preserved.
- **`ns:CreateSlider`** and **`ns:CreateEditBox`** signatures gained
  a trailing optional `tooltip` parameter. Backwards-compatible — all
  existing callers (which pass fewer args) still work unchanged.
- **[Options_Builder.lua](../../Options_Builder.lua)** — the `slider`
  and `editbox` BUILDERS now thread `entry.tooltip` through to the
  factory. Schemas can add `tooltip = "..."` alongside `label` on any
  slider or editbox entry.
- **[Options_Bars.lua](../../Options_Bars.lua)** — Health Below %,
  Require Buff, and Linger Time now have descriptive tooltips with
  concrete example spells (Kill Shot, Stealth, Glow on Ready pairing
  etc.) explaining when each is useful.

### Smoke test
Hover the mouse over each of those three fields in the per-bar
editor — a yellow tooltip should appear to the right of the control
within ~0.25 s and hide when the mouse leaves.

### Future opportunity
Other sliders and editboxes in the per-bar editor could benefit from
tooltips too (Bar Darkness, Alert Threshold, High/Med thresholds,
Glow Duration). The infrastructure is now in place — add a `tooltip`
string as the last arg to the relevant `ns:CreateSlider` /
`ns:CreateEditBox` calls (or `tooltip = "..."` in a schema entry).
Not done in this session to keep scope tight.

---

## Second follow-up polish: full-coverage tooltip pass

Taking the "future opportunity" above off the shelf in the same
session — added tooltips to every slider and edit box in the per-bar
editor and Visuals tab where the label alone wasn't self-evident.
Controls whose meaning is obvious from the label (Bar Height, Group
Width, Font Size, Active/Inactive Opacity, Background Opacity, Border
Opacity, Group Name, Bar Name) deliberately have **no tooltip** —
padding them with label-echoes would be noise, not help.

### What got tooltips this pass

**[Options_Bars.lua](../../Options_Bars.lua)** — per-bar editor:
- **Spell Name or ID** — explains multi-spell comma syntax (`Rupture,
  Garrote`) and the "press Enter to apply" commit model.
- **Bar Darkness** — explains 0 (transparent background) vs 100
  (solid black).
- **Alert Threshold** — clarifies it only fires when Sparkle Alert
  is ticked, and lower = later warning.
- **High Threshold** (Colour by Time) — explains the green-to-yellow
  transition point.
- **Med Threshold** (Colour by Time) — explains the yellow-to-red
  transition and the yellow-zone relationship with High Threshold.
- **Glow Duration** — explains it pairs with Glow on Ready.

**[Options_Bars.lua](../../Options_Bars.lua)** — group editor:
- **Columns** — explains 1 = vertical stack, 2-4 = multi-column
  bar arrangement.

**[Options_Visuals.lua](../../Options_Visuals.lua)** — global visuals:
- **Bar Spacing** — explains vertical-pixels-between-stacked-bars;
  0 = bars touch.
- **Icon Size** — explains 0 = hide icons globally, per-bar override
  exists.
- **Fade Speed** — explains it only matters with Fade When Inactive
  ticked; lower = slower fade.
- **Custom Texture Filename** — explains the Blizzard path format,
  double-backslash escaping, fallback to Flat if file missing,
  Enter-to-apply.

**[Options_Bars.lua](../../Options_Bars.lua)** — previous tooltips
updated:
- **Health Below %**, **Require Buff** — appended "press Enter to
  apply" to match the other edit-box tooltips (the three edit boxes
  only commit on Enter, and this wasn't discoverable).

### Deliberately skipped (no tooltip added)

| Widget | Why not |
|---|---|
| Group Name, Bar Name (edit boxes) | Label unambiguous; common convention |
| Width, Scale, Background Opacity, Border Opacity (group sliders) | Label + range make intent clear |
| Bar Height, Font Size (Visuals) | Self-evident numeric settings |
| Active Opacity, Inactive Opacity (Visuals) | 0-1 range + "Opacity" is a known term |

### Verification
- All 23 `.lua` files parse clean under `luac -p`.
- Options_Visuals schema has tooltips on 4 new entries (Bar Spacing,
  Icon Size, Fade Speed, Custom Texture) plus the 3 pre-existing
  checkbox tooltips = 7 total.
- Options_Bars has tooltip args on 6 new widgets (Spell Name, Group
  Columns, Bar Darkness, Alert Threshold, High/Med Threshold, Glow
  Duration) + 3 previously-added (Health, Require Buff, Linger).
- Every checkbox in both files retains its pre-existing
  `tooltipText` (checkboxes use the template field rather than the
  new helper).

### Smoke test
Hover the mouse over each of the 13 newly-tooltipped widgets — each
should show a readable wrapped tooltip within ~0.25 s. The GameTooltip
anchor is always to the right of the widget; on the rightmost controls
the tooltip may extend past the panel edge, which is normal for WoW's
tooltip system.

---

## Third follow-up: stale name/icon on per-bar config edits

In-game testing of the reactivity fix surfaced one more case: editing
**Bar Name** updated everywhere *except the live bar* — the new name
showed up in the Bars-list row on the left and persisted across reloads,
but the rendered bar kept the old text until the user did something
that triggered an engine-side state transition (disable/enable the bar,
or wait for the tracker to fire).

### Root cause
`bar.nameText` is only ever assigned a string in three places:
- [FrameManager.lua:447](../../FrameManager.lua#L447) — once at frame
  build time.
- Three sites in [BarEngine.lua](../../BarEngine.lua) — during state
  transitions (Activate, Deactivate, OnUpdate tick).

`ApplyVisualConfig` in [Bar.lua](../../Bar.lua) only ever handled text
*visibility*, *font*, and *positioning* — never the text *content*. So
`ns:RefreshAllBars` → `ApplyVisualConfig` reapplied the layout but
didn't sync the displayed string against the (just-changed) DB value.

While auditing this I caught the **same class of bug on the icon**:
[Bar.lua:251](../../Bar.lua#L251) had a guard `if not bar.iconTexture:GetTexture() then ...`
that only set the icon if there wasn't one already. So changing the
**Spell Name or ID** on an existing bar wouldn't update the displayed
icon until a state transition fired an engine-side icon write —
identical to the name issue, just rarer to hit.

### What landed
Both fixes inside [Bar.lua](../../Bar.lua) `ApplyVisualConfig`:

1. **Name sync.** Inside the `showNameText` branch, after positioning
   logic, added
   `bar.nameText:SetText(ns.GetBarDisplayName(bar.barData))` so every
   visual refresh syncs the displayed string to the current `bar.name`.
2. **Icon sync.** Removed the `not bar.iconTexture:GetTexture()` guard.
   Now `ResolveBarIcon(bar.barData)` is called every refresh and the
   resolved icon is applied. If resolution fails (invalid spell name,
   item info not loaded yet) the existing texture is left in place
   rather than blanked.

### Risk + mitigation
Both writes happen on every `RefreshAllBars` call, which fires from
every per-bar editor callback. That's user-frequency, so the extra
SetTexture / SetText cost is negligible. There's no flicker risk
because the engine's existing in-tick SetText/SetTexture calls write
the same value as `ApplyVisualConfig` would.

### How to RCA if name/icon staleness comes back
**Look at:** `ApplyVisualConfig` in [Bar.lua](../../Bar.lua) — the
`if showNameText then ... bar.nameText:SetText(...) end` block must
remain inside the showNameText branch (so hidden bars don't
needlessly write text). The icon `ResolveBarIcon` + `SetTexture`
must remain INSIDE the `if bar.iconTexture then` guard but not be
re-gated by `not :GetTexture()`.

### Smoke test
1. Select a bar.
2. Change **Bar Name** in the per-bar editor and press Enter — the
   name on the live bar should update on the spot, no need to
   disable/enable.
3. Change **Spell Name or ID** to a different spell and press Enter
   — the icon on the live bar should swap to the new spell's icon
   on the spot.

### Refinement: invalid-input feedback on the icon

Follow-up testing surfaced one more nuance: when the user typed an
*invalid* spell name (e.g. a typo like `rupt` instead of `Rupture`),
the previous valid icon stuck around. The "leave existing texture if
ResolveBarIcon returns nil" branch was conservative-by-default, but
for user-typed-invalid-input it's the wrong default — the user has no
visual signal that their input doesn't match anything BarWarden can
find.

Refined the icon branch in `ApplyVisualConfig` to distinguish:
- **Explicit-input invalid** — `barData` has a non-empty `spellName`
  or non-nil `spellId` / `itemId`, but `ResolveBarIcon` returns nil:
  clear the icon (`SetTexture(nil)`). Soft validation feedback.
- **No explicit input** — `barData` has no spell/item fields set
  (e.g. Enchant MH/OH which derives its icon from the equipped weapon
  via the engine): leave any existing texture in place so the engine-
  set weapon icon isn't blanked when the panel refreshes.

Trade-off accepted: very rare server-side spells that `GetSpellInfo`
can't resolve will appear "invalid" in the editor. In practice if
`GetSpellInfo` can't resolve the spell, the tracker also can't track
it, so the blank icon is correct feedback.

### Smoke test for the validation refinement
1. Select a bar with **Track Mode** = Cooldown / Buff / Debuff /
   Proc / Item.
2. Type a valid spell name like `Rupture`, press Enter — icon shows.
3. Type a valid different spell like `Envenom`, press Enter — icon
   swaps.
4. Type a partial / typo like `rupt`, press Enter — icon disappears
   (no match).
5. Re-enter the valid name, press Enter — icon comes back.
6. **Enchant test**: select an Enchant MH or OH bar with an active
   weapon enchant — confirm changing other settings on a *different*
   bar (which triggers RefreshBarSettings) does NOT blank the
   enchant bar's weapon icon.

---

## Fourth follow-up: editbox clear-to-empty didn't persist

### Symptom
User reported: enter a non-100 value into **Health Below %** or text
into **Require Buff**, press Enter — the bar hides as expected.
**Clearing the field and pressing Enter did not bring the bar back.**
After reload, the editbox repopulated with the old value — proof that
the DB-clear-to-nil write never stuck.

The callback logic itself was traced and confirmed correct:
`tonumber("")` → `nil` → `bar.conditions.healthBelow = nil` →
`RefreshBarSettings`. On paper it should work. But in-game it didn't,
and I couldn't diagnose the exact reason without an in-game print
probe.

### Fix
Upgraded `ns:CreateEditBox` in [Widgets.lua](../../Widgets.lua) to
commit **on focus loss as well as on Enter**, plus proper
snapshot-based Escape-to-revert. This makes the commit path robust
regardless of whether Enter reliably fires in the edge case the user
hit.

Final behaviour (after Escape simplification below):
- `OnEditFocusGained` — snapshot the current text.
- `OnEnterPressed` — `Commit()` (diff-check against snapshot; fire
  onChange if text changed; update snapshot), then `ClearFocus()`.
  ClearFocus triggers `OnEditFocusLost` which re-runs Commit, but
  snapshot now equals the current text so it's a no-op.
- `OnEditFocusLost` — `Commit()`. Gated by `ns.suppressCallbacks`
  so Refresh-driven `SetText` pathways don't loop back.
- `OnEscapePressed` — **not hooked**. Template's default
  `self:ClearFocus()` runs, which triggers `OnEditFocusLost` →
  `Commit`. Escape therefore commits the current text (same as
  Enter and click-away).

The snapshot pattern ensures `onChange` is fired **exactly once** per
real edit — whether the commit is triggered by Enter, click-away,
tab-away, Escape, or panel close.

### Escape semantics — why "revert" was dropped

First iteration of the fix added an `OnEscapePressed` hook that tried
to restore the snapshot via `SetText(snapshot)` before
`self:ClearFocus()`, intended to give "Escape = revert" behaviour.

In-game testing exposed a `HookScript` ordering quirk specific to WoW
3.3.5a: `InputBoxTemplate` has its own default `OnEscapePressed` that
fires `self:ClearFocus()`. `HookScript` appends our hook to run AFTER
the template's default. So the actual execution order on Escape was:
1. Template's default `ClearFocus()` fires.
2. `ClearFocus()` synchronously triggers `OnEditFocusLost`.
3. `OnEditFocusLost` runs `Commit()` on the current (user-typed) text.
4. Only then does our hook run `SetText(snapshot)` — too late; the
   commit has already fired with the unwanted text.

To properly implement Escape-revert in 3.3.5a, we'd need to
`SetScript` the OnEscapePressed (overriding the template's default so
we control the ClearFocus timing), not `HookScript`. User confirmed
that the resulting "Escape commits, same as Enter/click-away" is
acceptable UX ("I don't mind it like this"), so the hook was removed
entirely rather than fixed. Result: predictable "any exit commits"
semantics with no broken Escape-revert dead code.

### Affected call sites
All six `ns:CreateEditBox` callers inherit the new behaviour:
- `groupNameEdit`, `barNameEdit`, `spellEdit`, `healthEdit`,
  `requireBuffEdit` (Options_Bars.lua)
- `customTexBox` (Options_Visuals.lua schema → Options_Builder.lua)

All callbacks are idempotent (DB-write + refresh), so the belt-and-
suspenders double-fire on Enter (Commit then ClearFocus → Commit
no-op) is harmless.

### Smoke test
1. Select a bar. Type `30` in **Health Below %**, press Enter — bar
   hides (assuming HP > 30%).
2. Clear the field. **Press Enter OR click anywhere else** — bar
   comes back.
3. Reload — the editbox stays empty (DB was correctly cleared).
4. Repeat with **Require Buff**.
5. Escape test: type something, press **Escape** — the field commits
   the typed text (same as Enter and click-away). See "Escape
   semantics — why 'revert' was dropped" above for why Escape doesn't
   revert in the current implementation.
6. **Bar / Group Name edit**: same two-path commit applies — clear
   the name, click elsewhere (no Enter), confirm the name is cleared
   (you'll see the bar's displayed name go blank, matching the
   cleared DB).

### Quick revert
`git checkout -- Widgets.lua` restores the pre-fix editbox behaviour.