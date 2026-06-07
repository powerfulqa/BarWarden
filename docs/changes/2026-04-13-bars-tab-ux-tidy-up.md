# Bars Tab + Visuals Tab - UX Tidy-Up (RCA log)

**Date:** 2026-04-13 (follow-up to the Bars responsive fix earlier the
same day).
**Scope:** Three small UX tweaks reported during in-game smoke testing.

If a regression is suspected, use the "How to RCA" section.

---

## Why this change exists

After the responsive-layout fix landed, the user in-game-tested the
Bars tab and the Visuals tab. Three cosmetic issues surfaced:

1. **"Add Bar" / "Delete Bar" button labels** are redundant - the
   Bars scroll list already sits under a "Bars" header, so "Bar" is
   implicit. The labels were padding the button row for no gain.

2. **Bar list rows too wide with trailing whitespace.** The row
   displayed Name (90 px) + Mode (60 px) + Target (50 px) + Spell
   (stretched to row end) for a total row width of 360 px. The spell
   column was nearly always redundant with the bar name (e.g. a bar
   named "Slice and Dice" with spell name "Slice and Dice" shows the
   same text twice, with lots of trailing space after it).

3. **Visuals tab has dead space at the bottom.** The scroll-child
   frame's height was hard-coded at `SetHeight(1200)` but the actual
   controls only need ~700-800 px, leaving ~400 px of empty scroll
   space below the last slider.

## What changed

### 1. [Options_Bars.lua](../../Options_Bars.lua) - button rename + shrink
- Line 357: `"Add Bar"` button, width 70 → `"Add"`, width 50.
- Line 369: `"Delete Bar"` button, width 70 → `"Delete"`, width 50.
- "Bar" is implicit from the section header immediately above, matching
  the Groups panel which already uses `"Add"` / `"Delete"` labels.
- Up / Down buttons unchanged.

### 2. [Options_Bars.lua](../../Options_Bars.lua) - remove spell column
- Lines 305 + 310: `barScrollFrame:SetSize(360, ...)` and
  `row:SetSize(360, ...)` → both now `220`. Width = 4 margin + 90 name
  + 4 gap + 60 mode + 4 gap + 50 target + 4 margin = 216, rounded to 220.
- Lines 345-349 (was): `spellText` FontString construction block -
  **deleted entirely**. `row.spellText` is no longer assigned.
- Line 791 (was): `row.spellText:SetText(b.spellName or "")` inside
  `UpdateBarList` - **deleted**. The three remaining assignments
  (`nameText`, `modeText`, `targetText`) stay.
- The spell name is still editable in the **per-bar editor** (the form
  below the list). Only the redundant list-column display is gone.

### 3. [Options_Visuals.lua](../../Options_Visuals.lua) - auto-size content height
- Lines 24-28: forward-declared `local fadeSpeedSlider` before the
  existing `frame:SetScript("OnShow", ...)` so the closure captures it
  as an upvalue. The slider's own declaration lower down (line 275)
  dropped its `local` keyword to assign to the forward-declared binding.
- Lines 35-42: extended the OnShow handler with height-sizing logic:
  reads `fadeSpeedSlider:GetBottom()` and `content:GetTop()`, sets
  `content:SetHeight(contentTop - lastBottom + 20)` for a 20 px bottom
  margin. Guarded by `if lastBottom and contentTop and contentTop > lastBottom`
  so a pre-layout OnShow (where GetBottom may return nil) falls back to
  the initial `content:SetHeight(1200)` silently.
- Initial `content:SetHeight(1200)` retained as the pre-layout fallback.

---

## Files modified

| File | Change |
|---|---|
| [Options_Bars.lua](../../Options_Bars.lua) | Button text+width, row width, spell column removed (2 sites) |
| [Options_Visuals.lua](../../Options_Visuals.lua) | Forward-declared `fadeSpeedSlider`; OnShow trims content height |

**No other files touched.** No `.toc`, DB schema, Phase 1-4 helpers, or
other tabs changed.

---

## Preservation requirements (behavioural diff)

| Behaviour | Today | After |
|---|---|---|
| "Add" button creates a new bar in the selected group | ✅ same handler body | same |
| "Delete" button opens confirm popup, deletes on accept | ✅ same handler body | same |
| Bar list highlights the selected bar | ✅ `row.selected` still set | same |
| Bar list shows name / mode / target | ✅ three `:SetText` calls | same |
| Bar list shows spell name | ❌ removed intentionally | **gone** - accepted trade-off per user decision; spell is still editable in the editor below |
| Visuals tab controls render identically | ✅ same anchoring, same widget construction | same |
| Visuals tab Refresh re-reads DB values | ✅ unchanged | same |
| Visuals tab scroll region fills with content | was padded to 1200 with dead space below | now sized to last widget + 20 px |

---

## How to RCA if something breaks

### Symptom: Bar list is empty or rows show blank names

**Look at:** [Options_Bars.lua](../../Options_Bars.lua) `UpdateBarList`
(search for `row.nameText:SetText`). The three remaining `SetText`
calls must survive. If `row.nameText` / `modeText` / `targetText` are
nil, the row construction block was broken - inspect the FontString
creation near line 327-343.

### Symptom: Bar list rows look weirdly narrow or selected-highlight is wrong

**Look at:** the `row:SetSize(220, ...)` at line 313 and
`barScrollFrame:SetSize(220, ...)` at 308. Both must match. If they
disagree, highlight textures clip or extend past the row.

### Symptom: Add or Delete button text is cut off

**Look at:** the width argument in the `ns:CreateButton` calls at
lines 357 and 369. "Add" fits comfortably in 50 px; "Delete" just
fits. If a future addition like "Delete All" needs more, bump to 60.

### Symptom: Visuals tab has a Lua error on open

**Look at:** the `fadeSpeedSlider` forward declaration at
[Options_Visuals.lua:28](../../Options_Visuals.lua#L28). If someone
added `local` to the assignment at line 275, the closure captures the
outer forward declaration which never gets set. The guard
`if fadeSpeedSlider then` prevents a crash but the height trim silently
does nothing - the tab still shows the old 1200 px dead space.

### Symptom: Visuals tab still has dead space at the bottom

**Look at:**
1. `fadeSpeedSlider:GetBottom()` may return nil on the very first
   OnShow before the layout pass. Opening the panel once, closing it,
   opening it again should trigger a correct resize. If it's
   permanently broken, print the values of `lastBottom` and
   `contentTop` to diagnose.
2. If a new widget was added **below** `fadeSpeedSlider`, the trim
   will cut it off. Update the OnShow handler to use the new "last"
   widget.

### Symptom: Visuals tab content is cut off at the bottom (fade speed slider missing)

**Look at:** the `+ 20` margin in the `content:SetHeight` call at
[Options_Visuals.lua:41](../../Options_Visuals.lua#L41). If the fade
speed slider renders taller than expected (e.g. with a large UI scale),
the 20 px might not be enough. Bump to 40.

### Quick revert

- Buttons + spell column: `git checkout -- Options_Bars.lua`
- Visuals height: `git checkout -- Options_Visuals.lua`
- Both are self-contained single-file changes with no cross-file
  dependencies.

---

## Verification performed

- `luac -p` clean on every `.lua` file
- grep confirms:
  - "Add" / "Delete" at [Options_Bars.lua:357, :369](../../Options_Bars.lua#L357-L369)
  - Row width 220 at [Options_Bars.lua:308, :313](../../Options_Bars.lua#L308-L313)
  - No more `spellText` references anywhere in `Options_Bars.lua`
  - Forward declaration + assignment of `fadeSpeedSlider` in
    `Options_Visuals.lua` at lines 28, 275, 277, 278
- ⏳ **In-game smoke test still owed.**

### Smoke-test checklist

1. `/reload` - addon loads, no Lua error popup.
2. `/bw` → Bars/Groups tab:
   - The right-side buttons now read **Add / Delete / Up / Down**.
   - Add a new bar → new row appears.
   - Delete a bar → confirm popup, row removes.
   - Bar list rows show Name / Mode / Target only - no spell column,
     no trailing whitespace.
   - Row selection highlight fits the new narrower row.
3. `/bw` → Visuals tab:
   - All controls render as before.
   - Scroll to the bottom - the last visible control ("Fade Speed"
     slider) should sit near the bottom of the scroll area with a
     small margin, not with a large empty space below it.
   - Close and reopen the panel; the tighter scroll region persists.
4. Other tabs (General, Profiles, Stats) unchanged.
