# Bars Tab - Responsive Per-Bar Editor Fix (RCA log)

**Date:** 2026-04-13
**Scope:** [Options_Bars.lua](../../Options_Bars.lua) per-bar editor
only (lines ~416-530 before this change).
**Status:** in progress - see "What landed" section at the bottom.

If a regression is suspected on the Bars tab after this change, use the
"How to RCA" section as a starting point.

---

## Why this change exists

In-game smoke testing at 1920×1080 default UI scale with no
third-party UI-enlarging addon loaded revealed that the **Track Mode**
and **Target** dropdowns in the per-bar editor clip at the right edge
of the InterfaceOptionsFrame panel and are unreachable. The Target
dropdown in particular is unusable - you can't change which unit a bar
tracks.

The dev machine had a third-party addon enlarging the
InterfaceOptionsFrame, which masked the issue.

---

## Root cause (pre-fix state)

The per-bar editor in [Options_Bars.lua](../../Options_Bars.lua) had:

- `ec:SetWidth(340)` / `ec:SetHeight(500)` hard-coded
  ([lines 428-429](../../Options_Bars.lua#L428-L429)).
- Track Mode dropdown anchored at `barNameEdit:TOPRIGHT +20, +16`
  ([line 510](../../Options_Bars.lua#L510)) - effectively x ≈ 160
  inside a 340 px content area.
- Target dropdown stacked below Track Mode
  ([line 521](../../Options_Bars.lua#L521)) - same x.
- WoW dropdowns created via `UIDropDownMenuTemplate` with
  `UIDropDownMenu_SetWidth(150)` ([Widgets.lua:51-77](../../Widgets.lua))
  have an invisible ~25 px padding on each side. The visual extent of
  a 150 px dropdown is therefore ~200 px.
- Anchor at x ≈ 160 + visual extent 200 = reaches x ≈ 360, clipping
  the 340 px content area by 20 px. With the scroll viewport slightly
  narrower than the content (UIPanelScrollFrameTemplate reserves
  ~24 px on the right for the scrollbar), the actual clipping is
  worse.

---

## What's changing (intent, before code lands)

Two behaviour-preserving changes to [Options_Bars.lua](../../Options_Bars.lua)
only. Plan file: [mossy-baking-clover.md](file:///C:/Users/ch/.claude/plans/mossy-baking-clover.md).

### Change A - content adapts to parent width (OnShow)

Mirror the pattern already in
[Options_Visuals.lua:25-33](../../Options_Visuals.lua#L25-L33): on the
tab's `OnShow`, read `editorScroll:GetWidth()` and resize `ec` to
match. The tab's `Refresh()` is called in the same handler so displayed
values refresh alongside.

### Change B - single-column vertical flow

Move Track Mode and Target dropdowns out of their right-of-barName
horizontal position into a vertical column below Spell. The layout
order becomes:

```
Enabled
Bar Name
Spell
Track Mode   <-- was beside Bar Name
Target       <-- was beside Spell
Only Mine    <-- re-anchored to Target
Conditions header
...
```

All anchors become top-to-bottom `TOPLEFT → BOTTOMLEFT` flows, matching
the shape the Conditions and Display sections already use.

### Change C - bump content height

`ec:SetHeight(500)` becomes `ec:SetHeight(620)` to accommodate the two
extra vertical entries (~60 px of dropdown + gap each = ~120 px added;
620 gives a safe margin).

---

## Preservation requirements (behavioural diff)

These must remain equivalent after the change:

| Behaviour | Today (file:line) | After |
|---|---|---|
| Changing Track Mode writes `bar.trackMode` and calls `ns:ScanAllBars()` | [Options_Bars.lua:503-508](../../Options_Bars.lua#L503-L508) | Same callback body; only the anchor changes |
| Changing Target writes `bar.unit`, clears `bar.target` legacy, calls `ns:ScanAllBars()` | [Options_Bars.lua:513-519](../../Options_Bars.lua#L513-L519) | Same callback body |
| Only Mine toggle writes `bar.onlyMine` and calls `ns:ScanAllBars()` | [Options_Bars.lua:493-499](../../Options_Bars.lua#L493-L499) | Same callback body; re-anchored to targetDD |
| Conditions section follows after Only Mine | [Options_Bars.lua:527](../../Options_Bars.lua#L527) | Unchanged - `condHeader` still anchors to `onlyMineCB:BOTTOMLEFT`, which now sits below Target instead of below Spell |
| Bar editor's Refresh logic reads the same fields | (search for `frame.Refresh` in Options_Bars.lua) | Unchanged |
| Editor scroll frame has vertical scrolling | [Options_Bars.lua:423](../../Options_Bars.lua#L423) | Unchanged |

---

## How to RCA if something breaks

### Symptom: Bars tab fails to open, Lua error on show

**Look at:** the new `OnShow` handler on `frame`. Two common failure
modes:
1. `editorScroll` was declared `local` inside a narrower scope than
   the OnShow - should be declared at the same block level as the
   OnShow hook.
2. `frame` already had an OnShow (e.g. set earlier in `CreateBarsTab`);
   using `SetScript` overwrites. If so, read the previous OnShow and
   compose them.

### Symptom: Track Mode or Target dropdown still clips

**Look at:** the new anchor for `trackModeDD`. The `-16` x offset
compensates for the dropdown's invisible left padding so the dropdown
label (above the arrow) still lines up with other left-aligned
controls. If the -16 is wrong, the dropdown appears shifted left or
its label overlaps the content edge. Adjust the number, don't revert.

### Symptom: Only Mine checkbox has wrong position

**Look at:** the new `onlyMineCB:SetPoint` anchor. It should be
`TOPLEFT, targetDD, "BOTTOMLEFT", 16, -6`. The `+16` re-aligns with
other left-aligned controls (undoing the `-16` from trackModeDD so
onlyMineCB sits at the same x as barNameEdit/spellEdit).

### Symptom: Conditions section overlaps the dropdowns or sits too low

**Look at:** [Options_Bars.lua:527](../../Options_Bars.lua#L527).
`condHeader:SetPoint("TOPLEFT", onlyMineCB, "BOTTOMLEFT", 0, -12)` is
unchanged - if it visually looks wrong, the cause is upstream (Only
Mine is misplaced, or the dropdowns are taller than expected).

### Symptom: Content is cut off at the bottom (Display section unreachable by scroll)

**Look at:** `ec:SetHeight(620)` at
[Options_Bars.lua:429](../../Options_Bars.lua#L429). If controls were
added below the original estimate, bump the height. The ScrollFrame
accepts any height.

### Symptom: Content has dead space on the right when panel is wide

**Look at:** the new OnShow handler. `editorScroll:GetWidth()` should
return a real number > 100; if it returns 0, the handler is firing
before the parent is sized. Move it to fire on `OnSizeChanged` as well,
or defer with a one-frame delay.

### Quick revert

`git checkout -- Options_Bars.lua` restores the pre-fix state. No
other files change, so this is a clean single-file revert.

---

## What landed

### Files modified
- [`Options_Bars.lua`](../../Options_Bars.lua) - three surgical edits:

  | Line (after) | What |
  |---|---|
  | [428-429](../../Options_Bars.lua#L428-L429) | `ec:SetHeight(500)` → `ec:SetHeight(620)`. The initial `ec:SetWidth(340)` stays as a safe fallback; the OnShow handler resizes it to match the scroll viewport at show time. |
  | [497-527](../../Options_Bars.lua#L497-L527) | Track Mode dropdown re-anchored from `barNameEdit:TOPRIGHT +20, +16` to `spellEdit:BOTTOMLEFT -16, -18` (single-column). Target dropdown's relation to Track Mode is unchanged. Only Mine checkbox re-anchored from `spellEdit:BOTTOMLEFT 0, -6` to `targetDD:BOTTOMLEFT +16, -6` (the `+16` reverses the `-16` from the dropdowns so it left-aligns with the edit boxes). |
  | [939-947](../../Options_Bars.lua#L939-L947) | New `frame:SetScript("OnShow", ...)` block just before `return frame`. Reads `editorScroll:GetWidth()`, sets `ec:SetWidth(w)`, and calls `self:Refresh()` if defined. Mirrors the Visuals tab pattern. |

### Files NOT changed
- No other `.lua` file touched
- `.toc`, `Templates.xml`, textures, fonts untouched
- DB schema, `ns.DEFAULTS` untouched
- All Phase 1-3 / Phase 4 helpers untouched

### Verification performed
- `luac -p Options_Bars.lua` - parses clean
- All 22 `.lua` files parse clean under `luac -p`
- `grep "ec:SetWidth\|ec:SetHeight" Options_Bars.lua` shows the new values
  (including the `ec:SetWidth(w)` inside OnShow)
- `grep "trackModeDD:SetPoint\|targetDD:SetPoint\|onlyMineCB:SetPoint"` shows
  the new anchor chain:
  ```
  505: trackModeDD:SetPoint("TOPLEFT", spellEdit,   "BOTTOMLEFT", -16, -18)
  516: targetDD:SetPoint   ("TOPLEFT", trackModeDD, "BOTTOMLEFT",   0, -18)
  527: onlyMineCB:SetPoint ("TOPLEFT", targetDD,    "BOTTOMLEFT",  16,  -6)
  ```
- ⏳ **In-game smoke test still owed.** See the plan's verification
  section for the exact checklist.

### Smoke-test checklist for next in-game session

1. `/reload` - addon loads, no Lua error popup.
2. `/bw` → Bars/Groups → select a group → select a bar.
3. At **1920×1080 default UI scale, no third-party UI-enlarging
   addon loaded**:
   - Enabled checkbox: visible, clickable.
   - Bar Name edit: visible, editable.
   - Spell edit: visible, editable.
   - **Track Mode dropdown**: fully visible; its label aligns with the
     edit-box labels above; the expanded option list appears fully
     on-screen (not clipped at the right edge).
   - **Target dropdown** - the one that was broken - fully visible;
     expand → all of `player/target/focus/pet/mouseover` are visible
     and clickable.
   - Only Mine checkbox: visible, left-aligned under Target.
   - Conditions section header + controls follow underneath without
     overlap.
   - Display section reachable via vertical scroll; nothing cut off
     at bottom.
4. **Behavioural diff** - change Track Mode to each option in turn
   and confirm the live bar updates. Change Target from `player` to
   `target` and confirm the bar now reads the target's auras.
5. **Other tabs unaffected** - open General, Visuals, Profiles, Stats
   in turn; nothing should look different.
6. **Wider panel test** (if you reload the UI-enlarging addon on your
   other machine): content widens to match; no dead space on the right.

### If something looks off

Refer to the "How to RCA" section above. Most likely regressions:
- **Dropdown label misaligned** → the `-16` on trackModeDD needs a
  small adjustment (try `-20` or `-12`). Pure visual polish, not
  behavioural.
- **Conditions overlap Target** → `ec:SetHeight(620)` is too low,
  bump to 660 or 700.
- **OnShow fires before parent sized** → the `w > 100` guard should
  protect against this; if it still bites, add an `OnSizeChanged`
  handler on `frame` calling the same resize logic.

### Quick revert
`git checkout -- Options_Bars.lua` restores the pre-fix state.
