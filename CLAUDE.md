# CLAUDE.md — BarWarden agent guide

This addon targets **WoW 3.3.5a (Wrath of the Lich King) — Interface 30300**.
Most online WoW addon docs (including the Wowhead Comprehensive Beginners
Guide #5338) describe **retail**. Treat retail-only APIs and helpers as
**absent** here unless you've grepped for them in the codebase.

The user works in **British English** (colour, behaviour, humanised) and
measures code quality against **qlty.sh**'s eight code smells:
identical/similar code, high function/file complexity, deeply nested
control flow, many returns, many parameters, complex boolean logic.

---

## 1. What's different about 3.3.5a (vs. retail / what the Wowhead guide assumes)

| Topic | 3.3.5a reality |
|---|---|
| Lua version | **5.1** (no `goto`, no `//`, no integer/float split). Anything Lua 5.2+ is unavailable. |
| `C_*` namespaces | **Do not exist.** No `C_Timer.After`, `C_Item`, `C_Spell`, `C_Container`. Use OnUpdate frames or `wait` patterns instead. |
| `GetItemCooldown` | **Exists** (was later moved to `C_Container` in retail). Use the bare global. |
| `SetReverseFill` on `StatusBar` | **Does not exist** (added in Cataclysm). Bars always fill left-to-right. |
| `GetSpecialization` / talents API | **Do not exist** in 3.3.5a form; use `GetTalentInfo(tab, index)` and `GetActiveTalentGroup()`. |
| Aura signature | `UnitBuff/UnitDebuff` returns 11 values: `name, rank, icon, count, dispelType, duration, expirationTime, source, isStealable, shouldConsolidate, spellId`. Retail dropped `rank`. |
| `GetSpellInfo` | Returns `name, rank, icon, cost, isFunnel, powerType, castingTime, minRange, maxRange, spellId`. **`rank` still present** (gone in retail). |
| Event names | `PARTY_MEMBERS_CHANGED` (3.3.5a) vs `GROUP_ROSTER_UPDATE` (Cata+). `RAID_ROSTER_UPDATE` still exists here. |
| Interface options panel | `InterfaceOptionsFrame_OpenToCategory(name)` — **must be called twice** in 3.3.5a; the first call only scrolls. See [Core.lua](Core.lua). |
| FontStrings inside `<StatusBar>` template | **Not registered as `_G` globals** in 3.3.5a. Always create them in Lua and store on the bar object. See the comment in [Bar.lua](Bar.lua) `CreateBarFrame`. |
| Group queries | `GetNumPartyMembers()` / `GetNumRaidMembers()` (not `GetNumGroupMembers`). |
| Texture coords | `SetTexCoord(0.08, 0.92, 0.08, 0.92)` is the standard icon trim (used in [Bar.lua](Bar.lua)). |

**When in doubt:** grep this codebase first; it's a working 3.3.5a addon, so any API used here is verified to exist on this client.

---

## 2. Project structure

```
BarWarden/
├── BarWarden.toc       Load order matters — see below
├── Templates.xml       StatusBar template referenced by Bar.lua
├── Utils.lua           Shared helpers (CopyTable, MergeDefaults, GetVisual, ...)
├── DB.lua              SavedVariables schema, defaults, migrations
├── Conditions.lua      Visibility condition evaluator
├── Events.lua          Central event dispatcher + factory wrappers
├── Bar.lua             Bar frame construction + visual config
├── BarPool.lua         Object pool for bar recycling
├── BarEngine.lua       State machine, OnUpdate, scan loop
├── Trackers.lua        Per-trackMode checkers (Cooldown/Buff/Debuff/Item/Enchant/Totem)
├── FrameManager.lua    Group frame creation, layout, positioning
├── DragReorder.lua     Drag-to-reorder with ghost bar + drop indicator
├── MinimapButton.lua   Minimap button + drag positioning
├── Widgets.lua         CheckBox/Slider/Dropdown/EditBox/Button factories
├── Dialogs.lua         StaticPopup definitions
├── Options.lua         Options panel frame + tab management
├── Options_*.lua       Per-tab UI (General/Bars/Visuals/Profiles/Stats)
├── Core.lua            ADDON_LOADED, slash commands, /bw enable/disable
└── BugReport.lua       Diagnostic report frame
```

Every Lua file follows the namespace pattern:
```lua
local addonName, ns = ...
```
`ns` is the shared addon table. **Do not introduce new globals** — attach
to `ns` instead.

### Load order rule
The `.toc` lists files in dependency order. `Utils.lua` and `DB.lua` come
early (Utils provides `ns:GetVisual()`, `ns:CopyTable`, `ns:MergeDefaults`
used everywhere; DB defines `ns.DEFAULTS` consumed by GetVisual). If you
add a file, place it after every file it depends on.

---

## 3. Established patterns (use these — don't reinvent)

### Lifecycle methods (Ace3-style)

[Core.lua](Core.lua) exposes three methods. Touch them when adding init
work or when a feature needs to react to enable/disable:

- `ns:OnInitialize()` — called once at ADDON_LOADED. Sets up DB, options
  panel, frames, minimap. **Does NOT register gameplay events.**
- `ns:OnEnable()` — called whenever the addon should become active
  (ADDON_LOADED-with-enabled, PLAYER_LOGIN, `/bw enable`,
  `ns:SetEnabled(true)`). Idempotent. Registers events + shows frames.
- `ns:OnDisable()` — called whenever the addon should go quiet
  (PLAYER_LOGOUT, `/bw disable`, `ns:SetEnabled(false)`). Idempotent.
  Unregisters events + hides frames.

Don't add ad-hoc init in `OnAddonLoaded`/`OnPlayerLogin`/`OnPlayerLogout`
handlers — extend the appropriate lifecycle method.

### Callback bus (`Register` / `Fire`)

Defined in [Utils.lua](Utils.lua). Pub/sub for cross-module notifications
that don't fit into events:

```lua
ns:RegisterCallback("OnProfileChanged", function(profileName)
    ns:DoSomething()
end)

ns:FireCallback("OnProfileChanged", selectedProfileName)
```

Firing with no subscribers is a no-op — safe to fire from anywhere.

**Existing callbacks:**
- `"OnProfileChanged"` — fires from profile load/reset in
  [Options_Profiles.lua](Options_Profiles.lua). Subscribed by
  `ns:OnInitialize` to call `ApplySettings` + `RebuildAllFrames`.

When adding a new "after X happens, also do Y" chain, prefer registering
a callback over inlining the chain at the call site.

### Visual config lookup
```lua
local visual = ns:GetVisual()
```
Defined in [Utils.lua](Utils.lua). **Never** write the old long form
(`BarWardenDB and BarWardenDB.visual or ns.DEFAULTS.visual`) — it was
deduplicated across 14 sites and we keep it that way.

### Declarative options schema (`ns:BuildSettings`)

[Options_Builder.lua](Options_Builder.lua) provides a schema walker:

```lua
local SCHEMA = {
    { type = "header", text = "Slash Commands", spacing = 24 },
    { type = "toggle", label = "Show Minimap Icon",
                       db = "global.minimapIcon",
                       refresh = "UpdateMinimapButtonVisibility" },
    { type = "toggle", label = "Lock All Frames",
                       get = function() return ns.db.global.locked end,
                       set = function(_, v) ... end },
    { type = "note",   text = "Help text", spacing = 6 },
}

frame.Refresh = ns:BuildSettings(frame, SCHEMA)
```

The walker creates one widget per entry, anchors each below the previous
(default 8px gap, override per entry with `spacing`), and returns a
Refresh closure that re-reads DB values back into the widgets.

**Currently used by:** [Options_General.lua](Options_General.lua) (Tab 1).

**Two ways to wire a setting:**
- `db = "path"` + `refresh = "Method"` — uses `ns:DBSet` under the hood
  (gets the strict registration-time validation for free)
- `get = fn` + `set = fn` — escape hatch for stateful behaviour (e.g.
  Lock toggle calls `Lock/UnlockAllFrames` in two branches; can't
  express that as a simple DB write)

**Supported entry types** (initial cut): `header`, `note`, `spacer`,
`toggle`. Other types (`slider`, `dropdown`, `editbox`, `color`,
`button`, `custom`) land when subsequent tab conversions need them —
add a `BUILDERS[type]` entry plus an `APPLIERS[type]` entry in
[Options_Builder.lua](Options_Builder.lua).

**When to use it:** new tab is a settings form (toggles/sliders/dropdowns
that read+write DB fields). **When NOT to use it:** stateful list UIs
([Options_Profiles.lua](Options_Profiles.lua) profile list) or
read-only displays ([Options_Stats.lua](Options_Stats.lua)) — these
stay imperative.

### DB-path widget callbacks (`ns:DBSet` / `ns:DBGet`)

Defined in [Widgets.lua](Widgets.lua). Eliminates the
`function(self, value) BarWardenDB.foo.bar = value; ns:RefreshAllBars() end`
boilerplate for simple options:

```lua
local slider = ns:CreateSlider(parent, "Bar Height", 4, 60, 1,
    ns:DBSet("visual.barHeight", "RefreshAllBars"))
```

`ns:DBSet(path, refreshMethod)` returns a widget callback that writes
`value` into `BarWardenDB.<dotted.path>` and (optionally) calls
`ns:<refreshMethod>()` after. **Strictly validated at registration time:**
the path's parent must resolve, the leaf must already be declared in
`ns.DEFAULTS`, and the refresh method (if given) must exist on `ns`.
Any failure raises a Lua error during `ns:OnInitialize`, so typos
surface at addon load (with `/console scriptErrors 1`) rather than as
silent no-ops on user click.

This makes [DB.lua](DB.lua)'s `ns.DEFAULTS` the single source of truth
for every option. **When adding a new setting:** add it to the right
sub-table of `ns.DEFAULTS` first, then wire the widget. Skipping the
defaults step will fire the validator at load.

`ns:DBGet(path, default)` is the read companion for Refresh handlers.

**Use it when** the callback only writes one DB field and (optionally)
calls one refresh method. **Don't use it when** the callback has
stateful side effects: showing/hiding other widgets, branching on the
new value, calling multiple refresh methods, etc. Examples that stay
imperative: the colour-mode dropdown that shows/hides the swatch
([Options_Visuals.lua](Options_Visuals.lua)), the texture dropdown that
shows/hides the custom-texture editbox, the lock toggle in
[Options_General.lua](Options_General.lua) (two-branch
LockAllFrames/UnlockAllFrames side effect).

### Event handlers
[Events.lua](Events.lua) uses `Dispatch("MethodName")`,
`DispatchUnit("MethodName")`, and `DispatchFixed("MethodName", arg)` to
forward to `ns:MethodName(...)`. **Do not add raw `local function OnFoo`
wrappers** unless the handler has bespoke logic (the only one is
`OnCombatStateChanged`, which auto-exits test mode on combat entry).

To add a new event:
1. Implement `function ns:OnSomething(...) end` in the appropriate file.
2. Add one row to `GAMEPLAY_EVENTS` in [Events.lua](Events.lua):
   `{ "EVENT_NAME", Dispatch("OnSomething") }` (or `DispatchUnit` /
   `DispatchFixed` if it takes a unit/fixed arg).

### Throttling
For high-frequency events, wrap with `ThrottledHandler(eventName, intervalSec, handler)`.
Currently used for `UNIT_HEALTH` at 0.25s.

### Visibility conditions
Add a check function in [Conditions.lua](Conditions.lua) and append it
to the local `CHECKS` table — the loop in `EvaluateConditions` picks it
up automatically. Order in the table is the short-circuit order.

### Tracker modes
Add a new `CheckXxx(barConfig)` in [Trackers.lua](Trackers.lua) returning
`(isActive, remaining, duration, icon, name, stacks)`. Register in
`ns.TRACKERS = { ... }` keyed by the trackMode string. `BarEngine` finds
it via `ns:CheckTracker(barConfig)`.

### Bar pool
Always borrow from [BarPool.lua](BarPool.lua) (`ns:AcquireBar` /
`ns:ReleaseBar`), never `CreateFrame("StatusBar", ...)` directly outside
of Bar.lua / BarPool.lua.

### SavedVariables
- `BarWardenDB` — per-character settings.
- `BarWardenAccountDB` — account-wide profiles.
- `ns.DEFAULTS` is the schema source of truth in [DB.lua](DB.lua).
- Bumping the schema means: add a `if savedVersion < N` block in
  `MigrateDB()` and bump `CURRENT_SCHEMA`. Never overwrite non-nil
  user data; only fill nil keys.
- `MergeDefaults` is for the `global` and `visual` config tables only —
  **never** call it on `frames` (it would inject sample-bar defaults
  into the user's array).

### Slash commands
All routed through `SlashHandler` in [Core.lua](Core.lua). Add new
subcommands as `elseif cmd == "name" then ...` branches. The `/bw help`
table at the top must be kept in sync.

---

## 4. Things to avoid

- **Globals.** If you write `function Foo()` instead of
  `function ns:Foo()`, you've polluted the global table and may collide
  with another addon. Always use `ns:` or `local function`.
- **Mocking the database in tests.** There are no tests; the verification
  loop is in-game. Don't fabricate one.
- **`pcall` swallowing real errors.** Only use `pcall` where Blizzard's
  API is genuinely unstable on bad input (e.g. profile import). Don't
  wrap normal logic.
- **`C_Timer.After`** — doesn't exist. Use an OnUpdate frame with an
  elapsed accumulator (see [Core.lua](Core.lua) periodic scan loop).
- **`SetReverseFill`** — doesn't exist. Don't write it; don't store a
  `direction` flag and pretend to handle it.
- **`GetNumGroupMembers`** — doesn't exist. Use `GetNumPartyMembers()`
  and `GetNumRaidMembers()`.
- **Single `InterfaceOptionsFrame_OpenToCategory(...)` call.** It opens
  to the *previous* category on the first call. Always call twice.
- **Reading FontStrings declared in a template via `_G[name .. "Text"]`**
  in 3.3.5a — they may not be registered. Create them in Lua and store
  on the frame.
- **Documentation-style comments stating the obvious** (`-- Set the alpha
  to the inactive value`). Comments must explain *why*, a non-obvious
  quirk, or a constraint. The recent humanisation pass removed banners
  like `-- ===== Print: Chat message helper =====` over two-line
  functions; don't reintroduce them.

---

## 5. Performance notes specific to this addon

- The OnUpdate scan loop in [Core.lua](Core.lua) runs every 0.25s. Any
  work added inside it multiplies by bar count × 4Hz. Profile additions.
- [BarEngine.lua](BarEngine.lua) batches group relayouts during a scan
  pass via `MarkGroupDirty` — call that, don't relayout per bar.
- Aura scans walk indices 1..40 and break on the first nil name. Don't
  iterate beyond a `name == nil` early-exit.
- Colour gradient stops in [Bar.lua](Bar.lua) (`COLOR_HIGH/MED/LOW`) are
  module-level constants — keep them out of per-tick functions.
- Stable-expiry caching in [Trackers.lua](Trackers.lua) prevents bar
  jitter from server expirationTime drift. Don't bypass it.

---

## 6. Verification (no test suite exists)

There are no unit tests. Verification = WoW client + behavioural diff.

1. **`luac -p file.lua`** catches syntax errors without launching the game.
2. **In-game smoke test**:
   - Login → bars render identically to before the change.
   - `/bw` → all 5 tabs open; settings reflect saved state.
   - Cast a tracked spell → cooldown bar appears, ticks, expires.
   - Apply a tracked buff/debuff/enchant/totem → matching tracker activates.
   - `/bw test` → fake 30s timers appear; entering combat auto-exits test mode.
   - Drag-reorder bars → ghost + drop indicator behave correctly.
   - `/reload` → state persists.
3. **Static cross-checks** to add to your verification:
   - `grep "BarWardenDB and BarWardenDB.visual or ns.DEFAULTS.visual"` →
     must be zero hits outside `ns:GetVisual()`.
   - `grep "function.*On[A-Z].*%(event"` in [Events.lua](Events.lua) →
     must only match `OnCombatStateChanged`.

---

## 7. Reference materials

- The Wowhead "Comprehensive Beginners Guide for WoW Addon Coding in Lua"
  (#5338) is **retail-flavoured** but the foundational sections
  (variable scoping, event-frame pattern, .toc structure, naming
  conventions, comment discipline) are accurate for 3.3.5a too. Skim it
  for the basics; ignore any `C_*` API or post-Cata helper it mentions.
- WoWWiki / wowpedia (`wowwiki.fandom.com`, `warcraft.wiki.gg`) — when
  reading API docs, check the version annotations. If a function is
  marked "Cataclysm+" or "Mists+" or "Removed in X.X", it's not in 3.3.5a.
- This codebase itself is the most reliable reference for what works
  on 3.3.5a — when adding a new API call, check whether the addon
  already uses it nearby first.
