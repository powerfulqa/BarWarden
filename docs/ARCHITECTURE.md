# Architecture (code map)

A bird's-eye map of where things live, for a contributor or AI agent landing in
the repo. This is a map, not a manual: it tells you which file to open, not how
every function works. For the deep reference (3.3.5a constraints, the scan loop,
gotchas, refactoring traps) read [ADDON_GUIDE.md](ADDON_GUIDE.md). For deferred
work and standing decisions, read [CODE_REVIEW.md](CODE_REVIEW.md).

BarWarden is a WoW 3.3.5a (WotLK, Lua 5.1) bar tracker: timer bars for spell
cooldowns, buffs, debuffs, procs, item cooldowns, weapon enchants, totems, and
class resources, grouped into movable containers and configured through a tabbed
Interface Options panel. It bundles LibStub / LibSharedMedia-3.0 /
LibDataBroker-1.1 / LibDBIcon-1.0 (kept on purpose; see ADDON_GUIDE).

## How the files fit together

The `.toc` ([BarWarden.toc](../BarWarden.toc)) is the load-order source of truth;
the list below groups files by role, not load order. Every file starts with
`local addonName, ns = ...` and shares state through that `ns` table. The only
true globals are `BarWardenDB`, `BarWardenAccountDB`, the slash-command handles,
and the `BARWARDEN_*` / `__BarWarden_*` provenance globals.

### Engine (no UI)

| File | Owns |
|------|------|
| [Utils.lua](../Utils.lua) | Shared helpers: `CopyTable` / `MergeDefaults` / `GetVisual`, the callback bus, `ns:After` (one-shot delay), `ns.COLORS` (the palette tokens), and the GCD threshold. Loads early. |
| [SharedMedia.lua](../SharedMedia.lua) | Optional LibSharedMedia integration (degrades gracefully when absent). |
| [DB.lua](../DB.lua) | `ns.DEFAULTS` (schema source of truth), `MigrateDB` + `CURRENT_SCHEMA`. |
| [AuraGroups.lua](../AuraGroups.lua) | Named aura equivalency groups (`@Stunned`, `@Bleeding`, ...). |
| [Conditions.lua](../Conditions.lua) | Visibility-condition registry + evaluator, plus the standalone resolvers every draw path must use: `ResolveHideWhenInactive` (group when set, else bar), `IsBarEnabled`, `IsSwitchBar` (group vs. bar Bar Style), and the stack-text display resolvers `GetStackFontSize` / `GetStackColor`. |
| [Bar.lua](../Bar.lua) / [BarPool.lua](../BarPool.lua) | Bar frame construction (`nameText` / `timeText` / `stackText`) + the object pool. Never `CreateFrame("StatusBar")` outside these. |
| [BarEngine.lua](../BarEngine.lua) | The scan loop, bar state machine, OnUpdate depletion, resource bars, and driving auto-tracking group slots (`ns:ScanAutoGroup`). |
| [Trackers.lua](../Trackers.lua) | Per-`trackMode` checkers (aura / cooldown / item / resource), plus the auto-tracking helpers: whole-unit aura collection (`ns:CollectAutoAuras`), slot placement for Keep Bars In Place (`ns:PlaceAutoAuras`), the cross-group tracked-name set (`ns:GetTrackedAuraNames`), and the skip-set builders (`ns:BuildAutoSkipSet` / `ns:BuildGroupSkipSet`). |
| [FrameManager.lua](../FrameManager.lua) / [DragReorder.lua](../DragReorder.lua) | Group frames + layout; drag-to-reorder. FrameManager also judges whether an auto-tracking group's start-up backdrop counts as empty (`ns.IsGroupEmptyForBackdrop`), since its slot count, not its configured bar count, is the only honest signal. It also owns the movable-frame machinery shared with unit frames: `ns:ApplySavedFramePosition`, `ns:OnFrameDragStart`/`ns:OnFrameDragStop`, `ns:RescaleFrame`, and `ns:ReleaseFrameBars`. |
| [UnitFrames.lua](../UnitFrames.lua) | The unit frame widget: portrait + name/level header + health/power bars + a values column, driven by a unit token (`ns:RebuildUnitFrames` / `ns:ScanUnitFrames`). A second, separate way to show the data a resource group already can - see ADDON_GUIDE's "Unit frames" section. Reuses `ns:CollectResources` (Trackers.lua) for data, `ns:UpdateResourceBar` (BarEngine.lua) and the bar pool for rendering, and FrameManager's shared positioning helpers above. |
| [ActivityTracker.lua](../ActivityTracker.lua) | Passive usage tracking + per-spell stats store. |
| [ClassPresets.lua](../ClassPresets.lua) | Per-class / per-spec starter profiles + the loaders. |

### Event hub & comms

| File | Owns |
|------|------|
| [Events.lua](../Events.lua) | The central event dispatcher: `GAMEPLAY_EVENTS` maps events to `ns:OnX` methods. Adding an event = a `ns:OnSomething` method + one row here, never a new frame. |
| [Comms.lua](../Comms.lua) | `ns.Comms` addon-to-addon transport + the version-update nudge. 3.3.5a-safe (no `RegisterAddonMessagePrefix`, no `GROUP_ROSTER_UPDATE`). |

### Interface Options (tabbed panel)

One file per tab. Each registers via `ns:RegisterOptionsTab(index, builder)`;
[Options.lua](../Options.lua) owns the shell, `TAB_NAMES`, and tab switching
(`ns:SelectOptionsTab`). [Options_Builder.lua](../Options_Builder.lua) is the
declarative settings-schema walker (`ns:BuildSettings`) and owns the
canonical `offsetX` indent constants (`ns.OFFSET_HEADER`, `ns.OFFSET_TOGGLE`,
and the rest of the per-widget-type set).

[General](../Options_General.lua) ·
[Bars / Groups](../Options_Bars.lua) ·
[Visuals](../Options_Visuals.lua) ·
[Profiles](../Options_Profiles.lua) ·
[Activity Tracker](../Options_Stats.lua) ·
[Help](../Options_Help.lua) ·
[Frames](../Options_Frames.lua)

### Other UI & utility

| File | Owns |
|------|------|
| [PanelInfra.lua](../PanelInfra.lua) | Reactive-layout layer: `ns.GetPanelWidth`, the width registry + `ns:ApplyWidth`, `ns.SETTINGS_MAX_WIDTH` (the shared control-width cap), and the `InterfaceOptionsFramePanelContainer` OnSizeChanged reflow. Loads before the panels. |
| [Widgets.lua](../Widgets.lua) | Widget factories (`CreateCheckbox` / `CreateSlider` / `CreateDropdown` (tooltip-aware) / `CreateEditBox` / `CreateButton` / `CreateColorSwatch`), `ns:DBSet`/`DBGet`, and `ns:CreateHelpIcon` (the `[?]` deep-link). |
| [MinimapButton.lua](../MinimapButton.lua) | LibDataBroker launcher + LibDBIcon-managed minimap button. |
| [Dialogs.lua](../Dialogs.lua) | `StaticPopup` definitions (keyed `BARWARDEN_*`) + `ns:EnsurePopupsTopmost` / `ns:RaiseFrameAboveOptions` (keep popups + the colour picker above the options window). |
| [BugReport.lua](../BugReport.lua) | Diagnostic snapshot builder + display frame (`/bw bugreport`). |
| [Core.lua](../Core.lua) | Lifecycle (`OnInitialize`/`OnEnable`/`OnDisable`), the `/bw` slash router, `ns:Print`, the provenance globals + watermark, and `ns:ApplyPlayerFrameHidden` / `ns:ApplyTargetFrameHidden` (the reversible Hide Blizzard Player Frame / Hide Blizzard Target Frame apply/hook, independent settings over independent frame lists). |

## Boundaries (the things that must stay true)

Invariants an agent should not "simplify" across. Many are pinned in code with
`EC-TRAP:` markers; run `grep -rn "EC-TRAP:"` before touching anything that looks
like dead code or a bug.

- **One scan loop / OnUpdate.** It lives in `Core.lua` and drives `BarEngine`. Features do not create their own per-frame loops.
- **Cross-file state goes through `ns`.** New globals are not added (locked by `tests/test_hygiene.lua`).
- **SavedVariables change only via `MigrateDB` + `CURRENT_SCHEMA`** (additive; only fill nil keys, never overwrite user data).
- **Chat output only through `ns:Print`.** Never `DEFAULT_CHAT_FRAME:AddMessage` directly outside the debug dump.
- **Bars come from `BarPool`,** never a raw `CreateFrame("StatusBar")`.
- **Colours come from `ns.COLORS`** (the shared palette), not new inline hex.
- **No em dashes (U+2014) anywhere** (locked by `tests/test_hygiene.lua`). British English.

## Where do I make change X?

| I want to... | Open |
|--------------|------|
| Change when a bar is shown / hidden | `Conditions.lua` (`ns:RegisterCondition`) |
| Add a tracking mode | `Trackers.lua` (`ns.TRACKERS`; resource modes also `ns.RESOURCE_TRACK_MODES`) |
| Change bar look / colour | `Bar.lua` / the Visuals tab / `ns.COLORS` |
| Add a settings checkbox | the relevant `Options_*.lua` + a default in `ns.DEFAULTS` (`DB.lua`) |
| Add a whole new options tab | new `Options_*.lua` + `ns:RegisterOptionsTab` + a `TAB_NAMES` entry in `Options.lua` |
| React to a new game event | a `ns:OnSomething` method + a row in `GAMEPLAY_EVENTS` (`Events.lua`), not a new frame |
| Add a `/bw` subcommand | `SLASH_COMMANDS` in `Core.lua` (+ a README row + the runnable list in `Options_General.lua`) |
| Add an aura `@group` token | `AuraGroups.lua` |
| Add / edit a class starter preset | `ClassPresets.lua` |
| Add a Help FAQ entry or a `[?]` icon | `Options_Help.lua` (`HELP_ENTRIES`) + `ns:CreateHelpIcon` |
| Send an addon-to-addon message | `ns.Comms` in `Comms.lua` |
| Add a unit frame for a new unit (pet, focus, ...) | `UnitFrames.lua` (`UNIT_TOKENS` / `UNIT_FRAME_KEYS` / `UNIT_FRAME_DEFAULT_POSITIONS`) + a `ns.DEFAULTS.unitFrames` entry (`DB.lua`) + a row in `FRAME_SECTIONS` (`Options_Frames.lua`). The settings block itself is generated - do not hand-copy one. Only the player frame gets resource tick boxes; see CODE_REVIEW item 25 |

## Verifying a change

From the repo root:

```
lua tests/run.lua          # all logic suites (frame code rides the in-game smoke test)
luac -p *.lua              # syntax-check shipped files (luac5.1 in CI)
luacheck *.lua             # lint (non-blocking; config in .luacheckrc)
stylua --check *.lua       # formatting (config in stylua.toml; do not format Libs/)
```

CI ([.github/workflows/tests.yml](../.github/workflows/tests.yml)) runs the syntax
check + test suite on every push (luacheck non-blocking); the release workflow
re-runs them at the tag gate. See [CLAUDE.md](../CLAUDE.md) for the release process.
