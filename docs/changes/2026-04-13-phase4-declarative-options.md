# Phase 4 — Declarative Options Refactor (RCA log)

**Date:** 2026-04-13
**Scope this session:** [Options_General.lua](../../Options_General.lua) only (smallest tab; ~95 lines).
**Status:** in progress — see "What landed" section at the bottom.

If a regression is suspected after this change, use the "How to RCA"
section as a starting point.

---

## Why this change exists

Phases 1-3 (Ace3-pattern lifts) added three building blocks:
`ns:OnInitialize/OnEnable/OnDisable`, the `RegisterCallback`/`FireCallback`
bus, and `ns:DBSet`/`ns:DBGet`. The original Ace3-pattern-lifts plan
[(C:\Users\ch\.claude\plans\ace3-pattern-lifts.md)](file:///C:/Users/ch/.claude/plans/ace3-pattern-lifts.md)
deferred a "Phase 4" — converting the imperative widget construction in
the Options_*.lua tabs to a data-driven schema (AceConfig style, but
homegrown — no library dependency).

This session implements Phase 4 for **only one tab** as a controlled
trial. If it lands cleanly and exercises well in-game, future sessions
can convert [Options_Visuals.lua](../../Options_Visuals.lua) (~409
lines) and the per-bar editor section of
[Options_Bars.lua](../../Options_Bars.lua) using the same machinery.

---

## What's changing (intent, before code lands)

### New file: `Options_Builder.lua`

A small declarative-options walker. Public API:

```lua
ns:BuildSettings(parent, schema)
    -> refreshFunction
```

Walks `schema` (an array of entries), creates a widget for each entry
under `parent`, anchors each below the previous, and returns a Refresh
function that re-reads DB values back into the live widgets.

**Supported entry types** (start small, add only what's needed):

| `type` | Required fields | Optional fields |
|---|---|---|
| `header` | `text` | `spacing` |
| `note` | `text` (string OR `function() return string`) | `style` (`"normal"` / `"disabled"`), `spacing` |
| `spacer` | `height` | — |
| `toggle` | `label`, EITHER `db` (+ optional `refresh`) OR (`get` + `set`) | `tooltip`, `spacing` |

This is a **deliberately minimal** initial cut. Other widget types
(`slider`, `dropdown`, `editbox`, `color`, `button`, `custom`) will be
added in subsequent sessions when needed by Options_Visuals or
Options_Bars. Adding a type is a small, isolated change to the BUILDERS
and APPLIERS dispatch tables in Options_Builder.lua.

### Conversion: Options_General.lua

Three controls (Enable, Lock, Show Minimap) + Slash Commands header +
help text + version footer become a SCHEMA table walked by
`ns:BuildSettings`.

**Key preservation requirements** (for behavioural-diff RCA):

| Behaviour | Currently in (file:line) | Must still happen after |
|---|---|---|
| Enable toggle calls `ns:SetEnabled(checked)` AND `ns:RebuildAllFrames()` if newly enabled | [Options_General.lua:19-23](../../Options_General.lua#L19-L23) | Same call sequence in the `set` closure of the schema entry |
| Lock toggle writes `BarWardenDB.global.locked` AND calls Lock/UnlockAllFrames | [Options_General.lua:32-39](../../Options_General.lua#L32-L39) | Same — uses `get`/`set` escape hatch (not DB path) because of the two-branch side effect |
| Minimap toggle uses `ns:DBSet("global.minimapIcon", "UpdateMinimapButtonVisibility")` | [Options_General.lua:48-49](../../Options_General.lua#L48-L49) | Same — passes `db` + `refresh` to schema, walker calls `ns:DBSet` |
| Initial Y offset of first widget is -80 (sits below panel title + subtitle from Options.lua) | [Options_General.lua:12, :25](../../Options_General.lua#L12) | Walker uses 16, -80 for the first widget anchor |
| Subsequent widgets gap -8 vertically | [Options_General.lua:40, :51](../../Options_General.lua#L40) | Walker default `spacing = 8` |
| Help section gap -24 (visual section break) | [Options_General.lua:57](../../Options_General.lua#L57) | Schema entry uses `spacing = 24` for the header |
| Help text gap -6 below header | [Options_General.lua:61](../../Options_General.lua#L61) | Schema entry uses `spacing = 6` |
| Version text gap -16 | [Options_General.lua:70](../../Options_General.lua#L70) | Schema entry uses `spacing = 16` |
| Version text uses `GameFontDisableSmall` (subdued) | [Options_General.lua:69](../../Options_General.lua#L69) | Schema `note` entry sets `style = "disabled"` |
| Help text JustifyH = "LEFT" | [Options_General.lua:62](../../Options_General.lua#L62) | `note` builder always sets LEFT (no need for a flag) |
| Refresh reads `g.enabled`, `g.locked`, `g.minimapIcon` and SetChecked on the three toggles | [Options_General.lua:76-82](../../Options_General.lua#L76-L82) | Walker's auto-Refresh handles all three (DBGet for `db`-style; calls `get` for closure-style) |

### TOC change

`Options_Builder.lua` must load **after** `Widgets.lua` (uses
`ns:DBSet`/`ns:DBGet`/`ns:CreateXxx`) and **before** `Options_General.lua`
(which calls `ns:BuildSettings`). Insertion point: between `Options.lua`
and `Options_General.lua`.

### What does NOT change in this session

- Other Options_*.lua files — all untouched.
- Public `ns` API surface — `BuildSettings` is added; nothing existing is
  removed or renamed.
- DB schema — no defaults added, no migrations.
- The 15 existing `ns:DBSet` call sites — all stay as-is.
- The Phase 1-3 helpers — `OnInitialize`/`OnEnable`/`OnDisable`,
  `RegisterCallback`/`FireCallback`, `DBSet`/`DBGet` — all unchanged.

---

## How to RCA if something breaks

### Symptom: Options panel "General" tab is blank or fails to open

**Look at:**
- The Lua error popup (turn on with `/console scriptErrors 1`). The
  `DBSet` strict validation will surface bad paths/refresh-method names
  here. The walker also throws on unknown `type` values in the schema.
- [Options_Builder.lua](../../Options_Builder.lua) `ns:BuildSettings`:
  is the dispatch table missing the type the schema is asking for?
- The .toc load order: confirm `Options_Builder.lua` appears before
  `Options_General.lua`.

### Symptom: Enable toggle doesn't enable/disable the addon

**Look at:**
- The `set` closure in the SCHEMA's enable-toggle entry in
  [Options_General.lua](../../Options_General.lua). It must call
  `ns:SetEnabled(checked)` and conditionally `ns:RebuildAllFrames()`.
- That the walker is actually wiring the closure into the widget's
  `OnClick` hook (via the `ns:CreateCheckbox` factory).

### Symptom: Lock toggle doesn't lock/unlock frames

**Look at:**
- The `set` closure in the SCHEMA's lock-toggle entry. Must:
  1. Write `BarWardenDB.global.locked = checked`
  2. Call `ns:LockAllFrames()` if checked, `ns:UnlockAllFrames()` if not
- Both branches matter — single-branch `if checked then Lock else end`
  is a regression.

### Symptom: Minimap toggle stops working

**Look at:**
- The `db` + `refresh` fields in the SCHEMA's minimap-toggle entry.
  Must be `db = "global.minimapIcon"` and
  `refresh = "UpdateMinimapButtonVisibility"`.
- That the strict `DBSet` validator passed at load (no popup error).

### Symptom: Toggles show stale values when reopening the tab

**Look at:**
- The `frame.Refresh` function returned by `ns:BuildSettings` — must
  walk every entry that has a `db` or `get` and update the widget.
- The `ns.suppressCallbacks = true/false` bracketing must surround the
  refresh loop so SetChecked/SetValue calls don't write back to DB.

### Symptom: Layout looks wrong (widgets overlap, gaps wrong)

**Look at:**
- The `spacing` field in each schema entry. Default 8 for normal flow;
  the help-section header should be 24, help text 6, version 16.
- The first widget should anchor at `(16, -80)` to `frame.TOPLEFT`. The
  walker's "first widget" branch handles this.

### Symptom: Refresh doesn't fire after profile load

**Look at:**
- This change does NOT subscribe the General tab's Refresh to
  `OnProfileChanged`. The existing flow has each tab's `frame.Refresh`
  called by the central `ns:RefreshOptions` ([Options.lua:101-116](../../Options.lua#L101-L116)).
  That continues to work because the schema walker still installs a
  `frame.Refresh` of the same shape.

### Quick revert

Every change in this session is in:
1. New file `Options_Builder.lua`
2. One line in `BarWarden.toc`
3. Rewritten contents of `Options_General.lua`

To revert: `git checkout -- BarWarden.toc Options_General.lua && rm Options_Builder.lua`.
The Phase 1-3 work is in different files and survives the revert.

---

## What landed

### Files added
- [`Options_Builder.lua`](../../Options_Builder.lua) — 155 lines.
  Schema walker (`ns:BuildSettings`) + `BUILDERS` and `APPLIERS`
  dispatch tables. Initial supported entry types: `header`, `note`,
  `spacer`, `toggle`.

### Files modified
- [`BarWarden.toc`](../../BarWarden.toc) — one-line insertion adding
  `Options_Builder.lua` between `Options.lua` and `Options_General.lua`.
- [`Options_General.lua`](../../Options_General.lua) — rewritten from
  imperative widget construction (95 lines) to a declarative `SCHEMA`
  table walked by `ns:BuildSettings` (93 lines). The line count is
  near-parity for this small tab; the win is architectural — the schema
  is data that can be scanned, edited, and extended without touching
  layout logic.
- [`CLAUDE.md`](../../CLAUDE.md) — section 3 documents
  `ns:BuildSettings` + the two wiring styles (`db`+`refresh` vs
  `get`+`set` escape hatch).

### Files NOT changed
- All other Options_*.lua tabs (`Bars`, `Visuals`, `Profiles`, `Stats`)
  — untouched.
- Phase 1-3 helpers (`OnInitialize`/`OnEnable`/`OnDisable`,
  callback bus, `DBSet`/`DBGet`) — untouched.
- DB schema, `ns.DEFAULTS` — untouched.

### Verification performed
- All 22 `.lua` files parse clean under `luac -p`.
- `Options_General.lua` and `Options_Builder.lua` both present in `.toc`.
- The three SCHEMA toggle entries map 1:1 to the three pre-existing
  controls; the `set` closures preserve the original call sequences
  exactly (Enable: `SetEnabled` then conditional `RebuildAllFrames`;
  Lock: write DB then branch on Lock/Unlock; Minimap: `DBSet` with
  `UpdateMinimapButtonVisibility` refresh).
- Anchor offsets preserved: first widget at `(16, -80)`, default 8px
  gap, header gap 24, help-text gap 6, version-text gap 16.
- ⏳ **In-game smoke test still owed.** The walker has not been
  exercised in the WoW client.

### Smoke-test checklist for next in-game session

Run these in order; if any fails, follow the matching "How to RCA"
section above.

1. `/reload` — addon loads with no Lua error popup.
2. `/bw` — General tab opens. All three toggles visible. Help text
   visible. Version footer visible.
3. **Enable toggle**:
   - Toggle off → all bars hide, no events firing (verify with
     `/etrace` if installed).
   - Toggle on → bars return; the `RebuildAllFrames` side effect runs.
4. **Lock toggle**:
   - Toggle off → frames become movable (drag a group frame).
   - Toggle on → frames lock (drag does nothing).
5. **Minimap toggle**:
   - Toggle off → minimap button hides.
   - Toggle on → minimap button appears.
6. **Refresh persistence**:
   - Set all three to known states, close the panel, reopen → toggles
     reflect the saved states.
   - `/reload` → toggles still reflect the saved states.
7. **Visual layout**:
   - Three toggles flow vertically with consistent ~8px gaps.
   - "Slash Commands" header sits ~24px below the last toggle (visible
     section break).
   - Help text body sits ~6px below header.
   - Version footer sits ~16px below help text and is in subdued
     (disabled-style) colour.

### Estimated remaining work for full Phase 4

- [Options_Visuals.lua](../../Options_Visuals.lua) (~409 lines, the
  biggest win). Requires adding `slider`, `dropdown`, `editbox`,
  `color` builders, plus a `custom` escape hatch for the texture and
  color-mode dropdowns that show/hide other widgets. Estimated 200-line
  reduction; smoke-test surface is large because every visual control
  must be re-verified.
- The per-bar editor sub-panel of [Options_Bars.lua](../../Options_Bars.lua)
  (the master-detail list UI itself stays imperative — wrong shape for
  a schema).
- [Options_Profiles.lua](../../Options_Profiles.lua) and
  [Options_Stats.lua](../../Options_Stats.lua) intentionally stay
  imperative (stateful list / read-only data view; wrong fit).

Each of these is a separate session with its own RCA log.
