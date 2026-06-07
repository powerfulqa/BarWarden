# Phase 4 - Options_Visuals.lua Declarative Conversion (RCA log)

**Date:** 2026-04-13
**Baseline:** v1.4.0 (commit `046c930`)
**Scope:** Extend [Options_Builder.lua](../../Options_Builder.lua) with
four more widget types + widget refs + `onChange` hook; rewrite
[Options_Visuals.lua](../../Options_Visuals.lua) as a declarative
`SCHEMA` walked by `ns:BuildSettings`.

---

## Why this change exists

Phase 4 was introduced in v1.4.0 and proved against the tiny
[Options_General.lua](../../Options_General.lua) tab (95 lines, 3
toggles). The plan (see
[mossy-baking-clover.md](file:///C:/Users/ch/.claude/plans/mossy-baking-clover.md))
deferred the real line-count win - the 409-line Visuals tab - to a
separate session so regressions wouldn't pile up.

This session converts Visuals.

Goal: ~270 lines of imperative widget construction + ~95 lines of
imperative Refresh collapse into a ~70-entry SCHEMA table plus a small
increase (~100 lines) in Options_Builder to support the four new
widget types.

Net expected: ~−200 lines; zero user-visible change.

---

## Design decisions (frozen at plan approval)

### Widget-ref mechanism

`ns:BuildSettings(parent, schema, widgetRefs?)` populates
`widgetRefs[entry.id] = widget` for every schema entry with an `id`.
The caller owns the table; cross-widget coordination is done by
closing over it.

### `onChange(value)` hook

A schema entry can include `onChange = function(value) ... end`.
The builder invokes it in **both** contexts:
- After a user-driven DBSet write (BUILDER wraps the widget callback)
- After a Refresh APPLIER syncs the widget to the current value

Firing in both sites keeps coupled widgets consistent on first open
as well as during interaction.

### APPLIER signature extended

From `applier(widget, value)` to `applier(widget, value, entry)`.
Backwards-compatible: the existing `APPLIERS.toggle` ignores the
third arg.

---

## Preservation requirements

| Behaviour | Today (file:line) | After |
|---|---|---|
| Sliders write DB + call RefreshAllBars | scattered in Options_Visuals.lua | schema `db` + `refresh` |
| Fade Speed slider has NO refresh | [Options_Visuals.lua:275-276](../../Options_Visuals.lua#L275-L276) | schema entry omits `refresh` |
| Dropdowns walk items on Refresh to match DB value | [Options_Visuals.lua:283-355](../../Options_Visuals.lua) | `APPLIERS.dropdown` |
| Color swatch writes r/g/b without clobbering alpha | [Options_Visuals.lua:103-110](../../Options_Visuals.lua#L103-L110) | `BUILDERS.color` preserves a |
| Color Mode "CUSTOM" shows swatch, otherwise hides | [Options_Visuals.lua:90-97, 323-327](../../Options_Visuals.lua) | `onChange` hook + widget refs |
| Texture "Custom" shows editbox + warning | [Options_Visuals.lua:138-150, 306-313](../../Options_Visuals.lua) | `onChange` hook + widget refs |
| OnShow adapts width, trims height, refreshes | [Options_Visuals.lua:33-48](../../Options_Visuals.lua#L33-L48) | preserved; `widgets.fadeSpeed` replaces forward-declared local |
| suppressCallbacks guards SetValue/SetChecked during Refresh | wrapper in the current OnShow | builder's Refresh closure self-brackets |

---

## How to RCA if something breaks

### Symptom: Visuals tab is blank or throws on open

**Look at:**
- `ns:BuildSettings` error on unknown entry type - check the type
  string in each schema entry.
- `ns:DBSet` strict validator error - a typoed path. Check the
  specific entry the error message names.
- A BUILDER returned nil - check the builder implementation for the
  type the error message names.

### Symptom: A specific slider/dropdown/etc. doesn't do anything on change

**Look at:** the schema entry. Confirm:
- `db` path is correct and the leaf exists in `ns.DEFAULTS`
- `refresh = "RefreshAllBars"` is present (or intentionally omitted
  for Fade Speed)
- For sliders: `min`, `max`, `step` match the original code's values

### Symptom: Dropdown Refresh doesn't show the current selection

**Look at:** `APPLIERS.dropdown` in
[Options_Builder.lua](../../Options_Builder.lua). It walks
`entry.items` comparing `item.value == value` and calls
`UIDropDownMenu_SetSelectedID` + `UIDropDownMenu_SetText`. If a
dropdown shows blank, verify the schema entry's `items` table matches
the original code's static table.

### Symptom: Color Mode doesn't show/hide the swatch (or Texture doesn't toggle its editbox)

**Look at:** the `onChange` closure on the relevant dropdown entry.
It must capture the file-scope `widgets` table. The walker fires it
after DB write AND after each Refresh pass. If either firing site is
missed, coupling desyncs.

### Symptom: Visuals tab has dead space at the bottom again

**Look at:** the OnShow handler. It should reference
`widgets.fadeSpeed` (not the old `fadeSpeedSlider` forward-declared
local). If the schema's last entry isn't the Fade Speed slider
anymore, update the OnShow reference.

### Symptom: First-open colorSwatch is hidden even though Color Mode is CUSTOM

**Look at:** the `onChange` hook firing during Refresh. In
`ns:BuildSettings`, each APPLIER must fire `entry.onChange(value)`
after applying. If that firing site is missing, coupled widgets stay
in their initial (hidden) state until the user interacts.

### Quick revert

```bash
git checkout -- Options_Builder.lua Options_Visuals.lua
# Optionally also remove the new RCA log:
# git clean -f docs/changes/2026-04-13-phase4-visuals-tab.md
```

No other files change. Quick single-pair revert.

---

## What landed

### [Options_Builder.lua](../../Options_Builder.lua) - extended
- Header-comment block updated to describe the new types + `opts`.
- New `BuildSetCallback(entry)` helper unifies user-change callback
  construction across all DB-backed builders, wiring `entry.onChange`
  after the DB write.
- **New BUILDERS**: `slider`, `dropdown`, `editbox`, `color`. Each
  supports `db` + `refresh` happy-path OR `get` + `set` escape hatch.
- **New APPLIERS**: `slider`, `dropdown`, `editbox`, `color`. APPLIER
  signature extended to `(widget, value, entry)` - backwards-compatible
  (existing `toggle` APPLIER ignores the third arg).
- `ns:BuildSettings(parent, schema, widgetRefs?, opts?)`:
  - New third param `widgetRefs` table populated with `[entry.id] =
    widget` for any entry with an `id`. Used by `onChange` closures and
    by `anchorTo`.
  - New fourth param `opts = { firstX?, firstY? }` overrides the first-
    widget placement defaults (16, -80). Visuals uses `firstY = -10`
    because its scroll frame already sits below the panel header.
  - New per-entry fields: `offsetX` (horizontal offset on the anchor),
    `anchorTo = "<id>"` (override "anchor to previous" for branches).
  - Refresh closure now also fires `entry.onChange(value)` after each
    APPLIER so state-coupled widgets sync on initial open too.

### [Options_Visuals.lua](../../Options_Visuals.lua) - rewritten
- Imperative widget construction (~270 lines) collapsed into a ~145-line
  SCHEMA table. Imperative Refresh function (~95 lines) removed entirely
  - the builder generates it.
- Forward-declared `local fadeSpeedSlider` removed; OnShow now reads
  `widgets.fadeSpeed` from the widget-ref table.
- State coupling expressed via `onChange` hooks on `colorModeDD` and
  `textureDD`. Both fire during user interaction AND during Refresh,
  so coupled widgets (`colorSwatch`, `customTexBox`, `fallbackWarning`)
  stay consistent on first open as well as during typing.
- `textHeader` uses `anchorTo = "textureDD"` so the Text Options
  section re-anchors to the texture dropdown, skipping the
  conditionally-shown `customTexBox` + `fallbackWarning` branch.
  Behaviour identical to the original imperative code.
- Section headers are re-skinned to `GameFontNormalLarge` after build
  (the default builder uses `GameFontNormal`). Done by scanning
  `content:GetRegions()` for matching text.
- The 7 static item tables (`colorModeItems`, `textureItems`, etc.)
  remain at function scope, unchanged.

### Side-effect fix: v1.4.0 Options_General spacing bug

While switching `Options_Builder.lua` to **leading-gap** semantic (an
entry's `spacing` = gap above that entry), I caught an existing bug in
v1.4.0: the walker was using `prev`'s trailing `spacing` for the
current entry's anchor, which meant each entry's `spacing` value
affected the **next** entry, not itself. Options_General's schema
(authored with leading-gap intent) rendered with visibly-wrong gaps:

| Gap | Intended (v1.3.0 imperative) | v1.4.0 actual | Now (v1.5.x) |
|---|---|---|---|
| Minimap → Header  | 24 | 8  | **24** ✓ |
| Header → Note     | 6  | 24 | **6**  ✓ |
| Note → Disabled   | 16 | 6  | **16** ✓ |

User had casually said v1.4.0 "looks good" which masked the issue.
The fix restores the intended v1.3.0 layout. No schema changes needed
in Options_General.lua - the values were already authored with leading
semantic.

### Line counts (this tab pair)

| File | Before | After | Delta |
|---|---|---|---|
| Options_Builder.lua | 156 | 349 | +193 |
| Options_Visuals.lua | 392 | 317 | -75 |
| **Total** | **548** | **666** | **+118** |

The builder grew more than Visuals shrank because it now supports 4
new widget types plus widget refs + onChange + opts + anchorTo +
offsetX - all reusable surface area for future tab conversions. The
real payoff arrives when Options_Bars's per-bar editor converts next,
reusing the now-mature builder without adding new mechanism.

### Verification performed

- All 23 `.lua` files parse clean under `luac -p`.
- `grep "ns:CreateSlider\|ns:CreateDropdown\|ns:CreateEditBox\|ns:CreateColorSwatch" Options_Visuals.lua`
  → 0 hits (all construction moved into the builder).
- `grep "local fadeSpeedSlider" Options_Visuals.lua` → 0 hits
  (forward-declared upvalue replaced by widget-ref lookup).
- `grep -c "^BUILDERS\." Options_Builder.lua` → 8 (4 original + 4 new).
- `grep -c "^APPLIERS\." Options_Builder.lua` → 5 (toggle + 4 new;
  static types header/note/spacer have no applier).
- ⏳ **In-game smoke test still owed.**

### Smoke-test checklist

1. `/reload` - addon loads, no Lua error.
2. `/bw` → **Visuals** tab. Every section header visible at the larger
   font size. Every control present in the same visual order as v1.4.0.
3. **Per-control drive test** - for each of the 20 interactive widgets,
   change the value, confirm the live bars react, then reopen the tab
   and confirm the value persists.
4. **State-coupling test**:
   - Color Mode → `Custom Color` makes the swatch appear; switching
     away hides it.
   - Bar Texture → `Custom` makes the custom filename editbox + the
     orange fallback warning appear; switching away hides both.
   - Close the panel with Color Mode set to `Custom Color` and re-open
     → the swatch is already visible (Refresh-side onChange firing).
   - Same for Texture = `Custom`.
5. **Scroll region** - no dead space below Fade Speed slider.
6. **General tab** - the Slash Commands header now sits 24 px below
   the Minimap toggle (was 8 px in v1.4.0). The help text sits 6 px
   below the header (was 24 px in v1.4.0). The version footer sits
   16 px below the help text (was 6 px in v1.4.0). This is the
   v1.3.0 imperative layout, restored.
7. **Bars / Profiles / Stats** tabs unchanged.
8. **Profile load** - load a profile whose visual settings differ;
   open Visuals → all controls reflect the loaded values, coupled
   widgets show/hide correctly.

### Known limitation worth flagging

`BUILDERS.color` does NOT perform registration-time validation on its
`db` path (unlike `ns:DBSet` which does). A typoed path in a future
color schema entry would silently no-op. For Visuals the one use
(`visual.defaultColor`) is correct. If a second color widget is added
to any schema, consider adding registration-time validation to
`BUILDERS.color`.

### Quick revert

```bash
git checkout -- Options_Builder.lua Options_Visuals.lua
```

Options_Visuals.lua reverts to its v1.4.0 state; Options_Builder.lua
reverts to its v1.4.0 state; Options_General.lua is unaffected by the
revert but its layout will revert to the v1.4.0 visually-buggy spacing
because the builder reverts too.
