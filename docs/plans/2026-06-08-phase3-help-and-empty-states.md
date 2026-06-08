# Phase 3 design - Help tab, deep-links, and empty-state messaging

> Approved design for Phase 3 of the EC design-language alignment
> ([2026-06-05-ec-design-alignment.md](2026-06-05-ec-design-alignment.md)).
> Reference: EbonClearance `EbonClearance_HelpPanel.lua` (the
> `EC_HELP_ENTRIES` table + `NS.OpenHelpEntry`) and
> `EbonClearance_PanelWidgets.lua` (`MakeHelpIcon`).

## Goal

Close the one real UX gap: BarWarden has tooltip-only help today. Add an
in-window **Help tab** with a searchable-by-eye collapsible FAQ, `[?]`
deep-link icons on the major section headers, and instructive
empty-state lines where lists currently render nothing.

## Decisions (locked)

- **Layout:** collapsible sections (mirror EC). Default Getting Started
  expanded, the rest collapsed. Deep-links auto-expand the owning section.
- **[?] icon scope:** a curated handful (~6-8) on the major section
  headers only.
- **Help lives as a 6th tab** in the existing options window (not a
  separate Interface Options sub-panel; the tabbed shell is correct for
  BarWarden). This differs from EC, where Help is its own sub-panel.

## New file: Options_Help.lua

Loads among the `Options_*` files in `BarWarden.toc` (after
`Options_Stats.lua`, before `Core.lua` which builds the panel in
`OnInitialize`).

- File-scope `HELP_ENTRIES`: an ordered flat list of two entry kinds:
  - Section marker: `{ section = "key", title = "Display" }`
  - Content entry: `{ id = "stable-id", q = "question", a = "answer" }`
- Sections (about 24 entries total, condensed from README.md):
  Getting Started, Tracking Modes, Conditions & Visibility, Visuals,
  Profiles & Starters, Activity Tracker, Troubleshooting.
- `CreateHelpTab(panel)` (registered via `ns:RegisterOptionsTab(6, ...)`)
  builds a `UIPanelScrollFrameTemplate` scroll frame (mirrors
  Options_Visuals) and renders section headers as clickable collapse
  toggles with content entries between them. Stores a render-item list
  (`tab._helpItems = { {kind="q", id=, widget=}, ... }`) so the deep-link
  can find an entry's widget by id.
- Exposes `ns.HELP_ENTRIES = HELP_ENTRIES` for the test, and
  `ns:OpenHelpEntry(id)`.

### ns:OpenHelpEntry(id)

1. Walk HELP_ENTRIES to find the section that owns `id`; set
   `BarWardenDB.global.helpCollapsed[section] = false` so it renders
   expanded.
2. Open the panel (double `InterfaceOptionsFrame_OpenToCategory`), then
   `ns:SelectOptionsTab(6)`.
3. Bump a generation counter; `ns:After(0.05, ...)` then scroll the Help
   scroll frame to the entry widget and flash-highlight it. The deferred
   task no-ops if a later `OpenHelpEntry` superseded it (rapid-click
   guard). Scroll offset uses EC's math:
   `offset = currentScroll + (scrollTop - widgetTop)`, clamped to
   `[0, GetVerticalScrollRange()]`.

## Supporting changes

- **Options.lua:** add `"Help"` to `TAB_NAMES`. Refactor the local
  `ShowTab` into an exposed `ns:SelectOptionsTab(index)` (sets the tab
  via `PanelTemplates_SetTab` + shows/hides content) and keep `ShowTab`
  calling it.
- **Utils.lua:** add `ns:After(seconds, fn)` - a one-shot delay using a
  pooled OnUpdate frame with an elapsed accumulator (no `C_Timer` on
  3.3.5a). Used by the deferred deep-link scroll.
- **Widgets.lua:** add `ns:CreateHelpIcon(parent, anchorWidget,
  anchorPoint, relPoint, xOff, yOff, entryId)` - a small `[?]` button
  that calls `ns:OpenHelpEntry(entryId)` on click and shows a "Open help"
  tooltip on hover. Mirrors EC's `MakeHelpIcon`.
- **DB.lua:** add `global.helpCollapsed = {}` to `ns.DEFAULTS` (UI state,
  per-character). Migration fills the nil key only.
- **Options_Bars.lua:** `[?]` on the Group Settings, Bar Editor, and
  Conditions headers; empty-state lines for an empty group list and an
  empty bar list.
- **Options_Visuals.lua:** `[?]` on the Bar Visuals header.
- **Options_Profiles.lua:** `[?]` on the Class Starters header.
- **Options_Stats.lua:** `[?]` on the Activity Tracker header;
  empty-state line for an empty stats list and a no-search-match line.

## Empty-state lines (greyed, lead with the action)

| Where | Text |
|---|---|
| Groups list, none yet | No groups yet. Click Add to create one. |
| Bar list, group has none | No bars in this group yet. Click Add to create one. |
| Stats list, no data | Activate bars and play to see tracking data here. |
| Stats list, search hides all | No effects match your search. |

## Testing

- `luac -p` on every changed/new `.lua`.
- New `tests/test_help.lua` (pure data, runs under the mock):
  - every content entry has non-empty `id`, `q`, `a`;
  - ids are unique;
  - every section marker has a `title`;
  - a fixed list of deep-link target ids (the ones wired to `[?]` icons)
    each resolves to a content entry - catches a `[?]` pointing at a
    missing or renamed entry.
  Add it to `TEST_FILES` in `tests/run.lua`.
- In-game smoke: Help tab opens; sections collapse/expand and the state
  persists across `/reload`; each `[?]` opens the panel, switches to
  Help, expands the section, scrolls to and flashes the entry; empty
  states show on an empty group, an empty bar list, an empty stats list,
  and a no-match search.

## Out of scope

- A search box inside the Help tab (eye-search of collapsible sections
  is enough for ~24 entries).
- Per-entry "Open panel" buttons (EC has them because Help is a separate
  sub-panel; BarWarden's settings are in the same window already).

## Delivery

One cohesive feature. Deploy to the `G:\` copy, smoke-test, then commit
to `main` only after in-game confirmation. The empty-state lines can be
split into their own commit if a quick low-risk landing is preferred.
