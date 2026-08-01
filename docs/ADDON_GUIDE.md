# BarWarden - Addon guide (contributor reference)

This is the prescriptive guide for working in the BarWarden codebase. If
you are an AI agent or a new contributor, read it before you touch code.
[CLAUDE.md](../CLAUDE.md) is the short entry point; this file is
authoritative for everything below.

BarWarden is a bar-tracking addon for **World of Warcraft 3.3.5a (Wrath
of the Lich King), Interface 30300**. It draws timer bars for spell
cooldowns, buffs, debuffs, procs, item cooldowns, weapon enchants,
totems, and class resources, grouped into movable on-screen containers
and configured through a tabbed Interface Options panel.

It shares a design language with its sibling addon **EbonClearance**
(same author): the same widget-factory + declarative-schema option
style, the same provenance/attribution discipline, the same brief
jargon-free player-facing text, and the same `EC-TRAP:` refactoring-trap
convention. The two read as one product family. See [NOTICE.md](../NOTICE.md).

---

## TL;DR conventions

- **Target is 3.3.5a / WotLK / Lua 5.1.** No `C_*` namespaces, no
  `C_Timer.After`, no `goto`, no `SetReverseFill`, no `GetNumGroupMembers`.
  Treat any retail-only API as absent unless you have grepped for it here.
- **Namespace, never globals.** Every file starts `local addonName, ns = ...`.
  Attach to `ns`; do not write `function Foo()` at file scope.
- **Chat output goes through `ns:Print`** (Core.lua). Never call
  `DEFAULT_CHAT_FRAME:AddMessage` directly outside the debug dump.
- **The bundled libraries are intentional.** LibStub, LibSharedMedia-3.0,
  LibDataBroker-1.1, and LibDBIcon-1.0 stay. Do not remove them; they
  degrade gracefully when absent (see the EC-TRAP sites).
- **No em dashes (U+2014) anywhere in the repo.** Not in code comments,
  docs, player-facing strings, or commit messages. Use ` - `, commas,
  colons, or parentheses. A grep for the character must return zero.
- **Player-facing text stays brief and jargon-free.** Lead with what
  happens; drop the mechanism. Internal comments may stay technical.
- **Before you "simplify" anything that looks wrong, run
  `grep -rn "EC-TRAP:"`.** Each hit marks intentional code. See
  [Gotchas and refactoring traps](#gotchas-and-refactoring-traps).
- **Verify before commit:** `luac -p` on changed files, `lua tests/run.lua`,
  then the in-game smoke test.

---

## Client target: 3.3.5a

Most online WoW addon documentation describes **retail**. The Wowhead
"Comprehensive Beginners Guide for WoW Addon Coding in Lua" (#5338) is
retail-flavoured; its foundational sections (scoping, the event-frame
pattern, .toc structure, naming) are accurate for 3.3.5a, but ignore any
`C_*` API or post-Cataclysm helper it mentions.

What differs from retail / what the guide assumes:

| Topic | 3.3.5a reality |
|---|---|
| Lua version | **5.1** (no `goto`, no `//`, no integer/float split, no `<const>`). Anything Lua 5.2+ is unavailable. |
| `C_*` namespaces | **Do not exist.** No `C_Timer.After`, `C_Item`, `C_Spell`, `C_Container`. Use OnUpdate frames with an elapsed accumulator. |
| `GetItemCooldown` | **Exists as a bare global** (retail later moved it to `C_Container`). Use the bare global. |
| `SetReverseFill` on `StatusBar` | **Does not exist** (added in Cataclysm). Bars always fill left to right. |
| `GetSpecialization` / talent API | Do not exist in 3.3.5a form. Use `GetTalentInfo(tab, index)`, `GetTalentTabInfo(tab)`, and `GetActiveTalentGroup()`. |
| Aura signature | `UnitBuff/UnitDebuff` returns 11 values: `name, rank, icon, count, dispelType, duration, expirationTime, source, isStealable, shouldConsolidate, spellId`. Retail dropped `rank`. |
| `GetSpellInfo` | Returns `name, rank, icon, cost, isFunnel, powerType, castingTime, minRange, maxRange, spellId`. `rank` still present here. |
| Event names | `PARTY_MEMBERS_CHANGED` (not `GROUP_ROSTER_UPDATE`). `RAID_ROSTER_UPDATE` still exists. |
| Interface options panel | `InterfaceOptionsFrame_OpenToCategory(name)` **must be called twice**; the first call only scrolls. |
| FontStrings in a `<StatusBar>` template | **Not registered as `_G` globals** in 3.3.5a. Create them in Lua and store them on the bar object. |
| Group queries | `GetNumPartyMembers()` / `GetNumRaidMembers()` (not `GetNumGroupMembers`). |
| Icon trim | `SetTexCoord(0.08, 0.92, 0.08, 0.92)` is the standard border trim. |

**When in doubt, grep this codebase first.** It is a working 3.3.5a
addon, so any API used here is verified to exist on this client.

---

## Architecture

### Load order

The `.toc` lists files in dependency order. If you add a file, place it
after every file it depends on.

```
Libs/                  LibStub, then LibSharedMedia-3.0, LibDataBroker-1.1, LibDBIcon-1.0
Templates.xml          StatusBar template referenced by Bar.lua
Utils.lua              Shared helpers (CopyTable, MergeDefaults, GetVisual, Serialize, callback bus)
SharedMedia.lua        Optional LSM integration (registers BarWarden textures/fonts)
DB.lua                 SavedVariables schema, ns.DEFAULTS, migrations
AuraGroups.lua         Named aura equivalency groups (@Stunned, @Bleeding, ...)
Conditions.lua         Visibility condition registry + evaluator
Events.lua             Central event dispatcher + factory wrappers
Comms.lua              ns.Comms transport + version-update nudge (3.3.5a-safe)
ActivityTracker.lua    Passive usage tracking + per-spell stats store
Bar.lua                Bar frame construction + visual config
BarPool.lua            Object pool for bar recycling
BarEngine.lua          State machine, OnUpdate, scan loop, resource bars
Trackers.lua           Per-trackMode checkers
FrameManager.lua       Group frame creation, layout, positioning
DragReorder.lua        Drag-to-reorder with ghost bar + drop indicator
MinimapButton.lua      LibDataBroker launcher + LibDBIcon-managed icon
Widgets.lua            CheckBox/Slider/Dropdown/EditBox/Button factories
Dialogs.lua            StaticPopup definitions
ClassPresets.lua       Per-class starter profiles + loaders
Options.lua            Options panel frame + tab registration
Options_Builder.lua    Declarative options schema walker (ns:BuildSettings)
Options_General.lua    General tab
Options_Bars.lua       Bars / Groups tab (group-and-bar editor)
Options_Visuals.lua    Visuals tab
Options_Profiles.lua   Profiles tab
Options_Stats.lua      Activity Tracker stats tab
Options_Help.lua       Help / FAQ tab + [?] deep-link target (ns:OpenHelpEntry)
Core.lua               Lifecycle, ADDON_LOADED, slash commands, provenance
BugReport.lua          Diagnostic report frame
```

`Utils.lua` and `SharedMedia.lua` come early because `ns:GetVisual`,
`ns:CopyTable`, `ns:MergeDefaults` and the LSM helpers are used
everywhere. `DB.lua` defines `ns.DEFAULTS`, which `GetVisual` consumes,
so it follows.

### The layers

- **Core** owns the lifecycle and the slash router and stamps the
  provenance globals.
- **DB** is the single source of truth for the saved-variable schema and
  its migrations.
- **Events** is the hub: it maps WoW events to `ns:OnSomething` methods.
- **The bar engine** (Bar + BarPool + BarEngine + Trackers) is the
  gameplay core: it scans, decides which bars are active, and animates them.
- **FrameManager + DragReorder** own group frames and their layout.
- **Options_\*** are the per-tab UI, built on Widgets + Options_Builder.

### Lifecycle methods (Ace3-style, hand-rolled)

[Core.lua](../Core.lua) exposes three methods. Extend these rather than
adding ad-hoc init in raw event handlers.

- `ns:OnInitialize()` - called once at ADDON_LOADED. Sets up DB, the
  options panel, frames, the minimap button. **Does not register
  gameplay events.**
- `ns:OnEnable()` - called whenever the addon should become active
  (ADDON_LOADED-with-enabled, PLAYER_LOGIN, `/bw enable`,
  `ns:SetEnabled(true)`). Idempotent. Registers events and shows frames.
- `ns:OnDisable()` - called whenever the addon should go quiet
  (PLAYER_LOGOUT, `/bw disable`, `ns:SetEnabled(false)`). Idempotent.
  Unregisters events and hides frames.

### The scan loop and bar lifecycle

The heartbeat is an OnUpdate frame in [Core.lua](../Core.lua) that fires
every **0.25s** (there is no `C_Timer`). Each tick runs the scan pass in
[BarEngine.lua](../BarEngine.lua):

1. For each configured bar, evaluate its visibility conditions
   ([Conditions.lua](../Conditions.lua)). A failing condition hides the bar.
2. For visible bars, call `ns:CheckTracker(barConfig)` which dispatches
   to the right checker in [Trackers.lua](../Trackers.lua) by `trackMode`.
3. The checker returns `(isActive, remaining, duration, icon, name, stacks)`.
4. **Time-based** trackers (Cooldown, Buff, Debuff, Proc, Item, Enchant,
   Totem) go through `ActivateBar`, which attaches `Bar_OnUpdate` so the
   bar depletes as time passes.
5. **Resource** trackers (Combo Points, Runic Power, Soul Shards, Runes)
   are registered in `ns.RESOURCE_TRACK_MODES` and go through
   `ns:UpdateResourceBar(bar, current, max, icon, name, stacks)` instead.
   No `Bar_OnUpdate` is attached; the bar holds its fill level until the
   next scan or event refreshes it. Resource bars reinterpret the tuple:
   `remaining` becomes "current value", `duration` becomes "max value".

Group relayouts are batched during a scan pass via `MarkGroupDirty` in
BarEngine. Call that; do not relayout per bar.

Any work added inside the scan loop multiplies by bar count times 4Hz.
Profile additions before you ship them.

### Auto-tracking groups

A group with `autoTrack` set does not build bars from its `bars` array. It
builds `autoMaxBars` slots (`ns:BuildBarsForFrame`), each carrying a
runtime-only `barData` that is never written to SavedVariables, and
`ns:ScanAutoGroup` (BarEngine.lua) fills them each pass from
`ns:CollectAutoAuras` (Trackers.lua). The group's own `bars` array stays
intact in the DB and comes back untouched when `autoTrack` is cleared.

An auto slot is a real bar drawn through the same rendering path as any
other, so group-level and addon-wide visuals apply, so do the group's own
conditions, and so does layout. A slot's own `conditions` and `display`
tables are inert, not merely unused: `ScanBar` returns at the `bar.isAutoBar`
check (BarEngine.lua) well before the line that reads `BarConditionsMet`, and
`ns:ScanAutoGroup` evaluates `groupData.groupConditions` only, never a slot's
own conditions. `NewAutoBarData` (FrameManager.lua) seeds `display =
{ lingerTime = 0 }` only, so glow on ready, pulse on ready, linger, and the
per-bar colour/scale overrides read as absent too. There is also no UI path
to set either, since the per-bar editor closes for an auto group. See
CODE_REVIEW.md item 21.

Two invariants hold the design together:

- `bar.isAutoBar` makes `ScanBar` early-return, so the per-bar scanner and
  `ScanAutoGroup` never fight over the same frame.
- An empty slot is a **disabled** bar (`barData.enabled = false`). That routes
  it through the existing disabled-bar branch in `ns:DeactivateBar`, which
  hides it, so no new hide path was needed and an unfilled slot never leaves a
  blank row in the layout.

`ns.AURA_TRACK_MODES` (Utils.lua) is the shared definition of "this track mode
reads auras". Both the event dispatcher and the duplicate filter
(`ns:GetTrackedAuraNames`, Trackers.lua) read it; they have to agree or the
filter silently disagrees with the scanner.

`ns:InvalidateTrackedNames()` (BarEngine.lua) clears the per-group
tracked-name cache built by `ns:GetTrackedAuraNames`. It is called from
`ns:RefreshBarSettings` (Core.lua), from the bar Enabled checkbox handler in
[Options_Bars.lua](../Options_Bars.lua), from the alt-click ban handler on a
bar's icon in [Bar.lua](../Bar.lua), and from the banned-spells management
list's mutations (also Options_Bars.lua); those are the only call sites, so
anything else that can change what counts as "already tracked" or what is
banned needs its own call.

Eight keys on a group, all nil on a normal group:

| Key | Effect |
|---|---|
| `autoTrack` | Feed name (`playerBuffs`, `playerDebuffs`, `targetBuffs`, `targetDebuffs`), or nil for a normal group |
| `autoMaxBars` | Pre-allocated slots, capped at `MAX_BARS_PER_FRAME` |
| `autoMaxDuration` | Skip auras whose full duration exceeds this. 0 = no limit |
| `autoIncludePermanent` | Keep auras with no duration instead of dropping them. Off by default. `ns:CollectAutoAuras` marks each entry `permanent`; permanent entries sort into a stable block above every timed entry (tied broken by name, since they all share expiry 0) and `ns:ScanAutoGroup` routes them through `ns:ActivateStaticBar` instead of `ns:ActivateBar`, the same no-countdown path a switch-mode bar takes |
| `autoOnlyMine` | Count only your own casts. Seeded on for the two target feeds, off for the two player feeds when Auto Track is first set; the seed only fires once, so switching feeds afterwards leaves whatever the player has |
| `autoSkipTracked` | Skip spells a bar in another group already tracks (matched by name via `ns:GetTrackedAuraNames`) |
| `autoStableOrder` | Keep Bars In Place: an aura stays in the slot it first appeared in for as long as it lasts, instead of the soonest-expiring sort reshuffling every slot on each tick or refresh. Only a fade frees a slot. `ns:ScanAutoGroup` builds the held-name list from the live slots and hands it to `ns:PlaceAutoAuras` (Trackers.lua), the tested half that decides the new placement; the untested half is just reading `bar.barData` to build that list |
| `autoBanned` | Per-group spell bans set by alt-left-clicking a bar's icon (`bar.isAutoBar` only), keyed by lower-cased spell name: `{ [name] = { name = "Blade Flurry", id = 13877 } }`, `id` optionally nil. `ns:BuildAutoSkipSet` (Trackers.lua) merges this into the same skip set as "already tracked elsewhere" (`ns:GetTrackedAuraNames`), always returning a fresh table so the shared tracked-names cache is never mutated; `ns:ScanAutoGroup` folds it in unconditionally, so a ban applies even with `autoSkipTracked` off. Managed from the "Hidden In This Group" list under Auto Track in Options_Bars.lua |

Drag-reorder is gated off for auto groups in `ns:EnableDragReorder`
([DragReorder.lua](../DragReorder.lua)), and `ns:ReleaseBar` (BarPool.lua)
clears drag handlers so a pooled bar cannot carry them into a slot it is
recycled into.

---

## Required patterns

Use these. Do not reinvent them.

### Callback bus (`RegisterCallback` / `FireCallback`)

Defined in [Utils.lua](../Utils.lua). Pub/sub for cross-module
notifications that do not fit the event system.

```lua
ns:RegisterCallback("OnProfileChanged", function(profileName)
    ns:DoSomething()
end)

ns:FireCallback("OnProfileChanged", selectedProfileName)
```

Firing with no subscribers is a no-op. Existing callback:
`"OnProfileChanged"` fires from profile load/reset in
[Options_Profiles.lua](../Options_Profiles.lua) and from the class
starter loaders; `ns:OnInitialize` subscribes to call `ApplySettings` +
`RebuildAllFrames`. When adding an "after X, also do Y" chain, prefer a
callback over inlining at the call site.

### Visual config lookup

```lua
local visual = ns:GetVisual()
```

Defined in [Utils.lua](../Utils.lua). **Never** write the old long form
(`BarWardenDB and BarWardenDB.visual or ns.DEFAULTS.visual`); it was
deduplicated across 14 sites and we keep it that way.

### Group overrides (resolve, never read the global directly)

Some visual/behaviour settings can be overridden per group, so a setting that
takes a group override MUST be read through its resolver, never straight off
`ns:GetVisual()`:

| Setting | Resolver | Precedence |
|---------|----------|------------|
| Text format | `ns:GetBarTextFormat(bar)` ([BarEngine.lua](../BarEngine.lua)) | group (`group.textFormat`) then global |
| Hide when inactive | `ns:ResolveHideWhenInactive(bar)` ([Conditions.lua](../Conditions.lua)) | group when set, else bar (see below) |
| Switch mode (on/off, no countdown) | `ns:IsSwitchBar(bar)` ([Conditions.lua](../Conditions.lua)) | group (`group.barStyle`) when set, else bar (`display.switchMode`) |
| Bar texture / colour | resolved inside [Bar.lua](../Bar.lua) `ApplyVisualConfig` | bar then group then global |

A group reaches its data from a live bar via
`bar.frameIndex -> BarWardenDB.frames[bar.frameIndex]`.

`ResolveHideWhenInactive` gives the **group the final say once its switch has
been touched**, in both directions: `groupConditions.hideWhenInactive == true`
hides every bar in the group, `== false` keeps every bar visible even where the
bars set the flag themselves, and `nil` (never touched) leaves each bar to
decide. Note the check is `~= nil`, not truthiness - `false` is a real state
here, not "unset".

It was briefly an OR of bar-and-group (v2.1.0). That was wrong: an OR can only
ever *add* hiding, so a group whose bars all set the flag individually could
never be revealed from the group control, which is the entire reason the control
exists. Do not "simplify" it back.

`ns:IsSwitchBar` mirrors that same group-over-bar shape for switch mode:
`group.barStyle == "SWITCH"` or `"COUNTDOWN"` overrides every bar in the group
in either direction, and an untouched group (`nil` / `""`) leaves it to the
bar's own `display.switchMode`. Switch mode writes no new rendering: it routes
into `ns:ActivateStaticBar` ([BarEngine.lua](../BarEngine.lua)), the same full
fill / no-OnUpdate / blank-timer path a permanent aura already uses, so an
active tracked thing reads as filled and an inactive one is the ordinary dim
empty bar.

Adding a new group override means: the widget in
[Options_Bars.lua](../Options_Bars.lua) `GROUP_SETTINGS_SCHEMA` (with an
"Inherit (default)" entry that stores nil), a resolver, and updating **every**
read site - `ResolveHideWhenInactive` replaced five separate
`cond.hideWhenInactive` reads across BarEngine/Core/FrameManager.

### Declarative options schema (`ns:BuildSettings`)

[Options_Builder.lua](../Options_Builder.lua) walks a schema table and
builds one widget per entry, anchoring each below the previous, and
returns a Refresh closure that re-reads DB values into the widgets.

```lua
local SCHEMA = {
    { type = "header", text = "Slash Commands", spacing = 24 },
    { type = "toggle", label = "Show Minimap Icon",
                       db = "global.minimapIcon",
                       refresh = "UpdateMinimapButtonVisibility" },
    { type = "note",   text = "Help text", spacing = 6 },
}
frame.Refresh = ns:BuildSettings(frame, SCHEMA)
```

Used by [Options_General.lua](../Options_General.lua) and
[Options_Visuals.lua](../Options_Visuals.lua).

Two ways to wire a setting:

- `db = "path"` + `refresh = "Method"` - uses `ns:DBSet` under the hood
  (gets strict registration-time validation for free).
- `get = fn` + `set = fn` - escape hatch for stateful behaviour (a
  toggle that branches, calls multiple refreshers, or shows/hides other
  widgets).

Supported entry types: `header`, `note`, `spacer`, `toggle`, `slider`,
`dropdown`, `editbox`, `color`. Sliders and editboxes accept an optional
`tooltip`. Add new types by extending the `BUILDERS` + `APPLIERS`
dispatch tables.

Cross-widget coordination: `id = "<name>"` exposes a widget via an
optional `widgetRefs` table; `onChange = fn` fires after user writes and
after Refresh; `anchorTo = "<id>"` overrides "anchor to previous";
`offsetX` adjusts the horizontal anchor (dropdowns often need `-16`);
`opts = { firstX, firstY }` (4th arg) overrides first-widget placement.

`spacing` is **leading** (the gap above the entry), matching "this
widget sits N px below the previous."

Use it when a tab is a settings form. Do not use it for stateful list
UIs ([Options_Profiles.lua](../Options_Profiles.lua)), master-detail
layouts ([Options_Bars.lua](../Options_Bars.lua)), or read-only displays
([Options_Stats.lua](../Options_Stats.lua)); those stay imperative.

### Options tab registration (`ns:RegisterOptionsTab`)

Each `Options_*.lua` registers its builder:

```lua
ns:RegisterOptionsTab(tabIndex, CreateMyTab)
```

`CreateMyTab(panel)` receives the panel and returns the tab content
frame. [Options.lua](../Options.lua) iterates `ns.tabBuilders` during
`CreateOptionsPanel` and stores the results in `ns.optionsTabs`. This is
order-independent; prefer it over the old decorator-chain pattern.

### DB-path widget callbacks (`ns:DBSet` / `ns:DBGet`)

Defined in [Widgets.lua](../Widgets.lua). Eliminates the
write-one-field-then-refresh boilerplate:

```lua
local slider = ns:CreateSlider(parent, "Bar Height", 4, 60, 1,
    ns:DBSet("visual.barHeight", "RefreshAllBars"))
```

`ns:DBSet(path, refreshMethod)` returns a callback that writes `value`
into `BarWardenDB.<dotted.path>` and (optionally) calls
`ns:<refreshMethod>()`. **Strictly validated at registration time:** the
parent path must resolve, the leaf must already be declared in
`ns.DEFAULTS`, and the refresh method (if given) must exist on `ns`. Any
failure raises a Lua error during `ns:OnInitialize`, so typos surface at
load (with `/console scriptErrors 1`) rather than as silent no-ops.

This makes [DB.lua](../DB.lua)'s `ns.DEFAULTS` the single source of truth
for every option. **When adding a setting, add it to the right sub-table
of `ns.DEFAULTS` first, then wire the widget.** Skipping that fires the
validator at load. `ns:DBGet(path, default)` is the read companion for
Refresh handlers.

Use it when the callback only writes one DB field and optionally calls
one refresh method. Do not use it when the callback has stateful side
effects (showing/hiding other widgets, branching on the value, calling
multiple refreshers); those stay imperative.

### Per-bar live refresh (`ns:RefreshBarSettings`)

Defined in [Core.lua](../Core.lua). Every per-bar editor callback in
[Options_Bars.lua](../Options_Bars.lua) ends with `ns:RefreshBarSettings()`
so the UI stays uniformly reactive:

```lua
function ns:RefreshBarSettings()
    ns:RefreshAllBars()       -- visual config, alpha, hideWhenInactive
    if ns.ScanAllBars then
        ns:ScanAllBars()      -- re-evaluate tracker data + conditions
    end
end
```

`ns:RefreshAllBars` also applies `conditions.hideWhenInactive` on the
spot rather than deferring to the engine's state-transition path;
without that, toggling Hide When Inactive on an already-inactive bar
would not visibly change anything until the bar's state churned.

### EditBox commit semantics

`ns:CreateEditBox` ([Widgets.lua](../Widgets.lua)) commits on **any exit
from the field**: Enter, click-away, tab-away, Escape. It diff-checks
against a snapshot captured at `OnEditFocusGained` so the callback fires
exactly once per real edit. Escape does **not** revert; the `HookScript`
ordering versus `InputBoxTemplate`'s default `OnEscapePressed` makes a
clean revert infeasible without a full `SetScript` override. "Any exit
commits" is the simpler, consistent UX we kept.

### Event handlers

[Events.lua](../Events.lua) uses `Dispatch("MethodName")`,
`DispatchUnit("MethodName")`, and `DispatchFixed("MethodName", arg)` to
forward to `ns:MethodName(...)`. **Do not add raw `local function OnFoo`
wrappers** unless the handler has bespoke logic (the only one is
`OnCombatStateChanged`, which auto-exits test mode on combat entry).

To add an event:

1. Implement `function ns:OnSomething(...) end` in the right file.
2. Add one row to `GAMEPLAY_EVENTS`:
   `{ "EVENT_NAME", Dispatch("OnSomething") }` (or `DispatchUnit` /
   `DispatchFixed`).

For high-frequency events, wrap with
`ThrottledUnitHandler(eventName, intervalSec, handler)`, which rate-limits
**per unit** (key `event:unit`). Used for `UNIT_AURA` and `UNIT_HEALTH`. Per-unit
matters: a plain per-event throttle caught only the first unit in a burst and
left the other to the slower poll loop. (A per-event `ThrottledHandler` existed
until v2.1.1 and was removed - it had no call sites, since every throttled event
here needs the per-unit form.)

### Visibility conditions (extensible registry)

Register a check via `ns:RegisterCondition(name, checkFn)` in
[Conditions.lua](../Conditions.lua). The evaluator iterates the
registered list in registration order, so short-circuit order follows
the order of the `RegisterCondition` calls at the bottom of the file.

```lua
ns:RegisterCondition("requireClass", function(conditions)
    local required = conditions.requireClass
    if not required or required == "" then return true end
    local _, playerClass = UnitClass("player")
    return playerClass == required
end)
```

Each check returns `true` to KEEP the bar visible, `false` to hide it.
The per-bar `conditions` table stores arbitrary keys; the check reads
whatever key it needs. The full key list is in
[Per-bar conditions keys](#per-bar-conditions-keys).

### Tracker modes

Add a `CheckXxx(barConfig)` in [Trackers.lua](../Trackers.lua) returning
`(isActive, remaining, duration, icon, name, stacks)`. Register it in
`ns.TRACKERS = { ... }` keyed by the trackMode string; `BarEngine` finds
it via `ns:CheckTracker(barConfig)`. For event-driven / value-based
resources, also register the name in `ns.RESOURCE_TRACK_MODES` (see
[the scan loop](#the-scan-loop-and-bar-lifecycle)).

### Aura equivalency groups

[AuraGroups.lua](../AuraGroups.lua) exports `ns.AuraGroups = { [name] =
{ id1, id2, ... } }` (Stunned, Silenced, Bleeding, and so on). The
`getSpellTokens` helper in Trackers expands any comma-separated token
starting with `@` to the group's IDs, so a bar with spell field
`@Stunned` fires on any stun in the group, and `Rupture, @Stunned`
matches Rupture OR any stun. To add a group, extend `ns.AuraGroups`; no
parser changes needed.

### Spell duration overrides

`ns.SpellDurations = { [spellID] = seconds }` in
[Trackers.lua](../Trackers.lua) is an opt-in override consulted by
`CheckCooldown` **before** `GetSpellCooldown`'s returned duration.
Useful when a private server has patched a cooldown and the API returns
the old value (or zero). Empty by default; keys are numeric spell IDs.

### Class presets and starter profiles

[ClassPresets.lua](../ClassPresets.lua) exports
`ns.ClassPresets[classToken]` for each of the ten 3.3.5a classes, each
with a `groups` fallback and a `specs` table covering all 30 WotLK
specs. Loaders:

- `ns:LoadClassStarter(classToken?)` detects the active spec via
  `ns:DetectSpec()` and loads the spec-level preset (falling back to
  class-level), defaulting to the player's class. Replaces `ns.db.frames`.
- `ns:AppendClassStarter(classToken?)` same logic but concatenates onto
  `ns.db.frames`.
- `ns:DetectSpec()` returns `(classToken, specIndex, specName)` by
  counting talent points per tree via `GetTalentTabInfo(tab)`.

Both fire `"OnProfileChanged"` so the frame cache rebuilds. `MakeFullBar`
fills in default `conditions` and `display` tables. Resource-mode bars
get `conditions.requireClass = classToken` automatically so copying a DK
preset across profiles does not leak rune bars onto non-DK characters.

Use spell **names** for Buff/Debuff/Proc entries (rank-agnostic name
matching) and spell **IDs** for Cooldown entries (language-independent;
`GetSpellCooldown` accepts either).

### Bar pool

Always borrow from [BarPool.lua](../BarPool.lua) (`ns:AcquireBar` /
`ns:ReleaseBar`); never `CreateFrame("StatusBar", ...)` directly outside
Bar.lua / BarPool.lua.

---

## UI conventions

- Build widgets through the [Widgets.lua](../Widgets.lua) factories
  (`CreateCheckBox`, `CreateSlider`, `CreateDropdown`, `CreateEditBox`,
  `CreateButton`). Do not hand-roll `CreateFrame` widgets in the option
  tabs.
- `ns:CreateSlider` and `ns:CreateEditBox` accept an optional trailing
  `tooltip` argument. Add a tooltip where a label is not self-evident or
  where pairwise behaviour helps discoverability ("High Threshold pairs
  with Colour by Time"). Do not add label-echo tooltips on self-evident
  widgets.
- **Player-facing text stays brief and jargon-free.** Lead with what
  happens, drop the "why" and the mechanism, avoid code jargon. Use
  plain verbs, active voice, present tense. Internal comments may stay
  technical; the rule is about the surface the player reads.
- StaticPopups live in [Dialogs.lua](../Dialogs.lua), keyed
  `BARWARDEN_*`.

### Colour palette

Use `ns.COLORS` ([Utils.lua](../Utils.lua)) - do not invent new shades. This is
the same palette EbonClearance uses, so the two addons read as one family.

| Token            | Code         | Meaning         |
|------------------|--------------|-----------------|
| `ns.COLORS.title`    | `\|cff4db8ff` | Addon title     |
| `ns.COLORS.good`     | `\|cffb6ffb6` | Success / good  |
| `ns.COLORS.bad`      | `\|cffff4444` | Error / bad     |
| `ns.COLORS.warning`  | `\|cffffb84d` | Warning / note  |
| `ns.COLORS.emphasis` | `\|cffffff00` | Emphasis yellow |
| `ns.COLORS.prefix`   | `\|cff7fbfff` | Chat prefix     |
| `ns.COLORS.muted`    | `\|cff888888` | Muted / caption |

The olive byline colour (`|cff888866`) is a one-off for the options-panel
attribution line and is not a general token.

---

## Library rationale (decision record)

BarWarden bundles four libraries under `Libs/` and declares them as
`OptionalDeps`. **Keep them.** This is the analogue of EbonClearance's
"do not embed Ace3" decision record, reached the other way: the libs
earn their place.

- **LibStub** - the universal version-checked library loader every other
  lib depends on. Tiny, inert, required by the rest.
- **LibSharedMedia-3.0 (LSM)** - lets BarWarden offer the textures and
  fonts registered by every other LSM-aware addon on the client, on top
  of its own bundled media. This is real user value, not plumbing.
  Removing it would strand the texture/font dropdowns on the hardcoded
  lists. BarWarden degrades gracefully when LSM is absent (see the
  SharedMedia.lua EC-TRAP), so the dependency is soft.
- **LibDataBroker-1.1 (LDB)** + **LibDBIcon-1.0** - the standard,
  battle-tested minimap-button stack. Rolling our own (as EbonClearance
  does for its niche) would re-implement drag positioning, radius
  handling, and the broker object for no gain here. They also degrade
  gracefully when absent (see the MinimapButton.lua EC-TRAP).

What we did **not** adopt: Ace3. BarWarden hand-rolls its lifecycle
(`OnInitialize` / `OnEnable` / `OnDisable`), its callback bus, and its
options widgets. That keeps the dependency surface small and the option
panel native to Blizzard's Interface Options rather than AceConfig.

We also did **not** convert the versioned DB migration to a nil-default
style. BarWarden's `MigrateDB()` with a `CURRENT_SCHEMA` counter (see
[Saved variables](#saved-variables-and-migrations)) is explicit and
testable, and the migration test is the safety net that catches silent
data corruption on a schema bump.

---

## Performance rules for 3.3.5a

- The OnUpdate scan loop in [Core.lua](../Core.lua) runs every 0.25s.
  Work inside it multiplies by bar count times 4Hz. Profile additions.
- [BarEngine.lua](../BarEngine.lua) batches group relayouts during a
  scan pass via `MarkGroupDirty`. Call that; do not relayout per bar.
- Aura scans walk indices 1..`ns.MAX_AURA_INDEX` (40) and break on the
  first nil name. Do not iterate past a `name == nil` early-exit.
- Colour gradient stops in [Bar.lua](../Bar.lua) (`COLOR_HIGH/MED/LOW`)
  are module-level constants. Keep them out of per-tick functions.
- Stable-expiry caching in [Trackers.lua](../Trackers.lua) prevents bar
  jitter from server `expirationTime` drift. Do not bypass it.

---

## Saved variables and migrations

- `BarWardenDB` is per-character settings
  (`## SavedVariablesPerCharacter`).
- `BarWardenAccountDB` holds account-wide profiles
  (`## SavedVariables`).
- `ns.DEFAULTS` in [DB.lua](../DB.lua) is the schema source of truth.
- Bumping the schema means: add an `if savedVersion < N` block in
  `MigrateDB()` and bump `CURRENT_SCHEMA`. **Never overwrite non-nil
  user data; only fill nil keys.**
- `MergeDefaults` is for the `global` and `visual` config tables only.
  **Never** call it on `frames`; it would inject sample-bar defaults
  into the user's array.

The provenance globals are stamped from Core.lua at load:
`BARWARDEN_IDENT`, `BARWARDEN_AUTHOR`, `BARWARDEN_ORIGIN`,
`__BarWarden_origin`, `__BarWarden_author`, and `__BarWarden_watermark`
(a fingerprint of `BarWarden@<version>`). These, the `## Author:` TOC
line, the options-panel byline, the `BarWardenDB`/`BarWardenAccountDB`
names, the `/bw` slash command, and the `BarWarden:` export prefix are
attribution-preserved by [LICENSE](../LICENSE). Do not rename or blank them.

---

## Per-bar conditions keys

Defaults in `ns.DEFAULTS` mirror the per-bar struct created by `NewBar()`
in [Options_Bars.lua](../Options_Bars.lua).

| Key | Type | Effect |
|---|---|---|
| `combatOnly` | bool | Show only while `UnitAffectingCombat("player")`. |
| `outOfCombatOnly` | bool | Inverse of above. |
| `requireBuff` | string \| spellID | Show only while the named buff is on player. |
| `requireClass` | class token | Show only if player class matches. Used by resource bars in starter profiles to prevent cross-class leak. |
| `healthBelow` | number (0-100) | Show only when player HP% is below this. |
| `inGroup` | bool | Show only in a party. |
| `inRaid` | bool | Show only in a raid. |
| `hideWhileMounted` | bool | Hide while `IsMounted()`. |
| `hideWhileResting` | bool | Hide while in an inn or capital city (`IsResting()`). |
| `hideInVehicle` | bool | Hide while in a vehicle (`UnitInVehicle("player")`). |
| `onlyInInstance` | bool | Show only inside a dungeon, raid, arena, or battleground (`IsInInstance()`). |
| `hideWhenInactive` | bool | Fully hide (not just dim) when the tracker is inactive. Read via `ns:ResolveHideWhenInactive(bar)`, never directly - a group can switch it on for all its bars. |

`showEmpty` was retired in v2.1.1: nothing ever read it, so its checkbox had
never done anything and was indistinguishable from `hideWhenInactive`. Existing
saved values are left in place and ignored. Do not re-add a condition key
without a runtime reader.

**Anything that can show or hide a bar must go through the resolvers in
[Conditions.lua](../Conditions.lua)** - `ns:IsBarEnabled(bar)` and
`ns:ResolveHideWhenInactive(bar)`. Four call sites once decided "is this bar
enabled" independently and disagreed, so an unticked bar was hidden at build
time and shown again by the next refresh.

---

## Slash commands

All routed through `SlashHandler` in [Core.lua](../Core.lua). Add new
subcommands as `elseif cmd == "name" then ...` branches and keep the
`/bw help` table in sync. `/bw` (and `/barwarden`) with no argument opens
the options panel.

---

## Tooling and verification

Three layers, in order of cost and fidelity.

### Static syntax check

```
luac -p <file.lua>
```

Dev boxes usually have Lua 5.4; WoW runs 5.1. For parsing the difference
rarely bites (no `goto`, `//`, bitwise ops, or `<const>` here), so a 5.4
`luac -p` pass is fine locally. If a file fails in CI but passes locally,
drop to `lua5.1` to reproduce.

### Test suite

Pure-logic modules are covered by a standalone Lua suite that runs under
a WoW-globals mock in [tests/mock_wow.lua](../tests/mock_wow.lua). It does
**not** cover frame code, the scan loop, or anything that calls
`CreateFrame`; those stay in the in-game loop.

Run locally: `lua tests/run.lua` from the repo root. Exit 0 on all-pass,
1 on any failure. CI runs it under Lua 5.1 on every push and PR, and the
release workflow re-runs it so a tag that fails tests will not publish.

Covered: `CopyTable` / `MergeDefaults` / `FormatUptime` / Base64 /
Serialize / profile export-import / callback bus / `GetVisual` caching
(test_utils); every schema migration and the "frames not clobbered"
guarantee (test_db_migrations - this is the file that catches silent
data corruption on a schema bump); every built-in condition
(test_conditions); `CheckBuff` / `CheckDebuff` / `CheckCooldown`,
`getSpellTokens`, `@group` expansion, `smoothExpiry` monotonicity,
`SpellDurations` override (test_trackers_logic); `AuraGroups` structural
invariants (test_aura_groups); class-preset well-formedness
(test_class_presets); settings-schema invariants (test_settings_schema).

To add a test: pick the right `test_*.lua` (or add a new one to
`TEST_FILES` in [tests/run.lua](../tests/run.lua)); define `M.test_<name>`
that raises via `assertx.*` on failure; extend
[tests/mock_wow.lua](../tests/mock_wow.lua) if you read an unstubbed
global, keeping stubs data-driven (mutate `mock.<state>` from the test,
not via behavioural overrides). Modules with frame creation at file
scope (BarEngine, Events, Core) need a frame stub that does not exist
yet; keep those out of scope until that stub layer is built.

### In-game smoke test

- Login then `/reload`: bars render identically to before the change; no
  Lua error with `/console scriptErrors 1`.
- `/bw`: all tabs open; settings reflect saved state.
- Cast a tracked spell: cooldown bar appears, ticks, expires.
- Apply a tracked buff/debuff/enchant/totem: matching tracker activates.
- `/bw test`: fake 30s timers appear; entering combat auto-exits test mode.
- Drag-reorder bars: ghost + drop indicator behave.
- `/reload`: state persists.

### Static cross-checks

- `grep` for the U+2014 character: zero hits repo-wide.
- `grep "BarWardenDB and BarWardenDB.visual or ns.DEFAULTS.visual"`: zero
  hits outside `ns:GetVisual()`.
- `grep "function.*On[A-Z].*%(event"` in Events.lua: only matches
  `OnCombatStateChanged`.

---

## Gotchas and refactoring traps

These are intentional design choices that look like dead code, cruft, or
a bug and have lured (or could lure) someone into a wrong "fix". Each
carries an inline `-- EC-TRAP:` marker so it is grep-able. **Before you
simplify anything that looks wrong, run `grep -rn "EC-TRAP:"` and read
the marker.** Never remove an `EC-TRAP:` line as part of a cleanup. If
you add a similarly counter-intuitive construct, mark it the same way:
`-- EC-TRAP: <what it looks like>. Do NOT <change>. <pointer>.`

Current trap sites:

| File | Looks like | Why it stays |
|---|---|---|
| [SharedMedia.lua](../SharedMedia.lua) | `if not LSM then return end` bails the whole file (looks like the file is disabled / dead) | Optional-dep graceful degradation. Bar.lua and Options_Visuals.lua fall back to hardcoded media lists. Do not make LSM a hard requirement. |
| [MinimapButton.lua](../MinimapButton.lua) | `if not LDB or not LibDBIcon then return end` early-return (looks like a dead guard) | Graceful degradation when the bundled libs are missing. Do not hard-require them or delete the guard. |
| [Trackers.lua](../Trackers.lua) `CheckCooldown` | `if duration <= GCD_THRESHOLD then return false` (looks like it drops real short cooldowns) | Filters the global cooldown so bars react only to true cooldowns. |
| [Utils.lua](../Utils.lua) | `ns.GCD_THRESHOLD = 1.5` (looks like an arbitrary magic number) | The GCD floor. Lowering it spams bars on every global cooldown. |
| [Core.lua](../Core.lua) | `InterfaceOptionsFrame_OpenToCategory("BarWarden")` called twice (looks like a copy-paste bug) | 3.3.5a quirk: the first call only scrolls, the second opens. Do not dedupe. |
| [Options.lua](../Options.lua) | same double call in `ns:OpenOptions` | Same 3.3.5a quirk. Do not dedupe. |
| [Options_Help.lua](../Options_Help.lua) | same double call in `ns:OpenHelpEntry` | Same 3.3.5a quirk. Do not dedupe. |
| [Trackers.lua](../Trackers.lua) `CheckItem` | bare `GetItemCooldown(...)` (looks like it should be `C_Container.GetItemCooldown`) | `GetItemCooldown` is the correct bare global on 3.3.5a. Do not "modernise". |
| [Conditions.lua](../Conditions.lua) | `GetNumPartyMembers()` / `GetNumRaidMembers()` (looks like it should be `GetNumGroupMembers`) | Those are the 3.3.5a group queries; `GetNumGroupMembers` is Cataclysm+, absent here. |

---

## Comment discipline

Comments explain *why*, a non-obvious quirk, or a constraint. Do not
write documentation-style comments that state the obvious (`-- Set the
alpha to the inactive value`), and do not reintroduce banner comments
(`-- ===== Print: Chat message helper =====`) over short functions; a
humanisation pass removed those and we keep it that way.

---

## Reference materials

- This codebase is the most reliable reference for what works on 3.3.5a.
  When adding an API call, check whether the addon already uses it nearby.
- WoWWiki / wowpedia (`warcraft.wiki.gg`): check version annotations.
  Anything marked "Cataclysm+", "Mists+", or "Removed in X.X" is not here.
- Sibling addon EbonClearance shares this design language; see
  [NOTICE.md](../NOTICE.md) for the family relationship.
