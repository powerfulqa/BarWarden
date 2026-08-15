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
5. **Resource** trackers (Combo Points, Runic Power, Soul Shards, Runes,
   Health, Mana, Energy, Rage) are registered in `ns.RESOURCE_TRACK_MODES`
   and go through `ns:UpdateResourceBar(bar, current, max, icon, name,
   stacks)` instead. No `Bar_OnUpdate` is attached; the bar holds its fill
   level until the next scan or event refreshes it. Resource bars
   reinterpret the tuple: `remaining` becomes "current value", `duration`
   becomes "max value". Health/Mana/Energy/Rage guard against a zero max
   the same way `CheckRunicPower` always has (forced to 1, never 0), even
   though a real client never actually reports zero for the player's own
   pool - the guard only ever fires against a degenerate/mocked read.

Group relayouts are batched during a scan pass via `MarkGroupDirty` in
BarEngine. Call that; do not relayout per bar.

Any work added inside the scan loop multiplies by bar count times 4Hz.
Profile additions before you ship them.

### Sort Mode "As They Come"

`sortMode = "appearance"` orders a group's visible bars by when each one
last started, oldest first, instead of by remaining time or name. The stamp
lives on the bar object itself (`bar.appearanceOrder`), set by a file-local
`appearanceSeq` counter in BarEngine.lua. `ns:ActivateBar` and
`ns:ActivateStaticBar` both fire repeatedly on an already-active bar (a
timer refresh, a stack change), so each reads `bar.barState` *before*
overwriting it with `BAR_STATE.ACTIVE` and only stamps on the
INACTIVE/LINGERING -> ACTIVE transition; a refresh that leaves a bar ACTIVE
throughout never gets a new stamp, which is what lets it hold its slot.
`ns:DeactivateBar` and `ns:ReleaseBar` (BarPool.lua) both clear the stamp,
so a pool round-trip can never let a bar recycled into a different group
inherit another group's position.

`CompareAppearance` (FrameManager.lua, beside `CompareRemaining` and
`CompareAlpha`) reads that stamp; a bar with none (a resource bar, or
anything that never went through the activate path) sorts after every
stamped bar. It is the one comparator of the three exposed on `ns` (as
`ns.CompareAppearance`, not local-only like its siblings) specifically so
`tests/test_frame_manager.lua` can load FrameManager.lua under the test
harness and exercise it directly; the rest of that file builds real WoW
frames and stays untested here.

This pairs with an auto-tracking group's `autoStableOrder` ("Keep Bars In
Place") without conflicting: `autoStableOrder` decides which physical bar
object (slot) holds a given aura's data across scans, so an aura that keeps
running never triggers a spurious deactivate/reactivate that would reset
its stamp; `sortMode = "appearance"` only decides how the currently-visible
bars are drawn given whatever stamps already exist. One controls slot
occupancy, the other draw order.

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
{ lingerTime = 0 }` only, so a slot's own glow on ready, pulse on ready and
linger are always absent, and the per-bar colour/scale overrides read as
absent too. There is also no UI path to set any of them directly, since the
per-bar editor closes for an auto group.

Since v2.4.0, Glow on Ready, Pulse on Ready and Linger Time are also
resolvable at group level (`ns:GetBarGlowOnReady` / `ns:GetBarPulseOnReady` /
`ns:GetBarLingerTime`, Conditions.lua - see the group-overrides table below),
so the Groups tab's Custom Bar Effects toggle is the only way to turn these
three on for an auto-tracking group. The per-bar colour/scale overrides have
no group-level equivalent and stay unreachable there. See CODE_REVIEW.md item
20.

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

#### The "resources" / "targetResources" / "totResources" feeds

Unlike the four aura feeds, `autoTrack = "resources"` (player),
`autoTrack = "targetResources"` (target, v2.5.0), and
`autoTrack = "totResources"` (target's target, v2.5.0) have no spell list at
all: all three are driven by the same `ns:CollectResources(opts)`
(Trackers.lua), parameterised by `opts.unit` ("player" by default, "target",
or "targettarget" - the standard 3.3.5a unit token for "my target's
target", also what Blizzard's own `TargetFrameToT` reads), which returns an
ordered array of
`{ key, label, current, max, icon, stacks?, trackMode? }` entries - Health
first (read off `opts.unit`), then that unit's current power type via
`UnitPowerType(unit)` (this is what makes the group follow a druid through
form changes live, on any of the three units), then class resources layered
on top, then any pinned extras from `groupData.autoPinnedResources`. A
resource that would otherwise appear twice (a Death Knight's Runic Power,
once as their current power type and once as an explicit class resource) is
de-duplicated by `key`, and anything with `max <= 0` is skipped (how a
resource the unit does not have reports). A `unit` that does not exist (no
target selected, or a target with no target of its own) collects nothing at
all - guarded by `UnitExists` up front, rather than relying on
`UnitHealth`/`UnitPowerMax` to degrade to 0 on their own - which flows into
the same "every slot empty" path `ScanAutoResourceGroup` already uses to
hide an idle group. Health and current-power-type generalise to all three
units for free: neither reads anything that depends on which specific unit
token was passed in, so no per-unit code exists for either step.

Class-resource applicability is CAPABILITY-PROBED, not `UnitClass(unit)`-
gated (v2.5.0 fix). It used to be: `UnitClass("player")` matched against
`"DEATHKNIGHT"` (Runes, Runic Power), `"WARLOCK"` (Soul Shards), or
`"ROGUE"`/`"DRUID"` (Combo Points). That broke down completely on Grimfall,
the classless private server BarWarden's owner plays on: `UnitClass("player")`
reports the SAME class token (DRUID) for every character there, while a
character can genuinely have mana, energy, rage AND six live runes at once.
Gating on the class token made Runes and Soul Shards permanently
uncollectable for anyone on that server, since the token they needed to
match never appeared. `HasRunes()`/`HasRunicPower()` (Trackers.lua, marked
`EC-TRAP` - do not reintroduce a class check) probe the actual API instead,
which is also more correct on a normal Blizzard server: it no longer depends
on `UnitClass` returning anything meaningful at all. It still splits by what
the resource actually is:
  * Runes and Runic Power are the PLAYER's own resource pools - the
    checkers behind them (`GetRuneCooldown`, `UnitPower("player", 6)`) always
    read the player's own runes/pool regardless of what `unit` names, so
    they are only ever collected for `unit == "player"`. `HasRunes()` treats
    `GetRuneCooldown`'s `duration` as the capability signal: a slot with no
    real rune data reads back duration 0, while a genuine rune - ready or on
    cooldown - always carries its real cooldown length. `GetRuneType` is not
    used as a signal; it returns a plausible-looking type even for a slot
    that does not exist. `HasRunicPower()` reads `UnitPowerMax("player", 6)`
    directly (not through `CheckRunicPower`, which forces a non-zero max as
    a display fallback for a hand-placed bar and so would report "has Runic
    Power" for everyone).
  * Soul Shards have no capability API at all - `GetItemCount` is a plain bag
    count, as truthful for "never picked one up" as for "cannot hold one".
    Showing "0 Soul Shards" to everyone would be noise, so the entry is
    gated on `GetItemCount(SOUL_SHARD_ITEM_ID) > 0`: it appears once a real
    shard is held and disappears once the last one is spent. There is no pin
    for this yet.
  * Combo Points sit in between: `GetComboPoints("player", "target")` is
    already, unconditionally, a "your points on your CURRENT target"
    reading - it never changes meaning depending on whether the player or
    target feed asks for it, so they are offered on BOTH (matching how
    Blizzard itself anchors `ComboFrame` to `TargetFrame`, not
    `PlayerFrame` - see "Hide Blizzard Player/Target Frame" below). They
    stop there: the `totResources` feed (`unit == "targettarget"`) does NOT
    get them, because `GetComboPoints` has no "on my target's target"
    reading to give at all - showing them there would just repeat the exact
    same player/target number under a label that implies it belongs to a
    third, different unit. This is the opposite generalisation problem from
    Runes/Runic Power above (which fail on `unit == "target"` because they
    read the PLAYER's own data): Combo Points fail on
    `unit == "targettarget"` because the API itself has nothing to say
    about that unit at all.

    Visibility (v2.5.0): shown while "in use" (`cur > 0`), or
    unconditionally once the owner ticks "Keep Combo Points Visible" (the
    `combopoints` key in `autoPinnedResources`). There is no class gate any
    more: `GetComboPoints` already reads back a genuine 0 for a character
    that cannot generate any, so `cur > 0` alone is the capability signal.
    The one residual imperfection this accepts: pinning "Keep Combo Points
    Visible" for a character that structurally never generates any still
    shows a static 0/5 bar, because Combo Points have no zero-max signal the
    way a power pool does (`UnitPowerMax(unit, powerType) <= 0` is what
    makes pinning Rage for a Mage a no-op). That is accepted as a harmless,
    opt-in cosmetic case, and the only way to let a classless server's
    non-Rogue/Druid characters pin Combo Points they can genuinely generate.

    Ordering fix: when pinned, Combo Points are added by the pinned-extras
    loop below, not by the "currently in use" check above - `addEntry`'s
    `seen` guard means whichever add runs first claims the slot, so adding
    Combo Points early unconditionally (whether pinned or just active) used
    to always plant them right after Health/current-power, ignoring
    whatever order the owner ticked the pins in. The "in use" check above
    now skips entirely while `combopoints` is pinned, leaving the ordered
    loop to place it. Runic Power, Runes and Soul Shards have the same
    shape (added in a fixed spot ahead of the ordered loop) but no pin
    tickbox exists for them yet, so the bug cannot surface for them today;
    a future pin for any of them needs the same treatment, not a bare
    addition to `PINNABLE_POWER_TYPES`.

Pinning applies identically to all three feeds: `opts.pinned` reads off
`unit` too (via the same `addPowerType` helper the current-power-type step
uses), so "Keep Rage Visible" on a target-resources group pins the TARGET's
rage, and on a target's-target group pins THAT unit's rage - never the
player's. The existing zero-max guard in `addEntry` already makes pinning a
power the unit does not have a no-op, so none of the three feeds needs an
extra carve-out to keep that safe.

**The pinned tickboxes are additive, never a removal switch** (v2.5.0
wording fix). "Keep Mana/Rage/Energy/Combo Points Visible" read, before this
fix, as the on/off switch for whether the resource ever shows - a druid in
caster form unticking "Keep Mana Visible" and still seeing mana confused
that reading, when the actual behaviour (mana is the current power type, so
it shows regardless of the tickbox) was always correct. The labels and
tooltips now say plainly that the resource already appears on its own
whenever the unit is using it, and the tickbox only keeps it up the rest of
the time - matching what the code has always done; no behaviour changed.

**Group Name Follows Target** (`autoTitleFollowsUnit`, v2.5.0) lets the
target and target's-target resource groups show the unit's own name as the
title instead of the group's configured name - offered only on those two
feeds (`AUTO_TARGET_RESOURCE_ONLY_WIDGET_IDS`, Options_Bars.lua): a
player-resources group following "you" would just repeat its own name back.
nil by default, so an existing group is unaffected until ticked.
`ns:ResolveGroupTitleName(groupData, unitName)` (FrameManager.lua) is the
pure decision: the unit's name when the option is on and a name was
resolved, else the group's own configured name - including when no unit is
selected at all (nil/empty `unitName`), so the title never goes blank while
Show Group Name is ticked, it just reverts to the label the owner gave the
group. It composes with Show Group Name rather than replacing it: that
toggle still owns whether the title shows AT ALL
(`frame.titleText:Show()`/`Hide()`, CreateTitleBar); this one only changes
WHAT TEXT it carries while visible. Kept current by
`ns:ScanAutoResourceGroup` (BarEngine.lua), which reads `UnitName(unit)`
every scan (there is no event at all for "your target's target changed",
same gap `ns:OnUnitDisplayPowerChanged` above already lives with) but only
calls `group.titleText:SetText` when the resolved name actually differs
from `group.lastTitleName`, a runtime-only cache field - so an unchanged
title never touches the fontstring on the 4 Hz scan loop, keeping this off
the true per-frame path even though the CHECK itself runs every scan.

**Show Target Level** (`autoTitleShowsLevel`, v2.5.0) is a second, nested
tickbox next to Group Name Follows Target: it only does anything while that
one is ALSO ticked and a unit is actually resolved (not the group-name
fallback), and appends a compact, colour-escaped level to the title -
`ns:ResolveGroupTitleName(groupData, unitName, unit)` (FrameManager.lua)
takes the raw unit token as a third argument for exactly this, since the
level needs its own `UnitLevel`/`UnitClassification` reads that have nothing
to do with the already-resolved name string. The actual text/colour is built
by `ns:FormatUnitLevelSuffix(unit)`, a small pure helper `ResolveGroupTitleName`
delegates to (kept separate so the string building - not just the branch
that decides whether to call it - is independently testable):
  * A plain number for a normal unit (`"80"`); `UnitLevel`'s own `-1` ("too
    high to determine") becomes `"??"`, the game's own convention for a
    boss whose level cannot be read.
  * `UnitClassification(unit)` adds a mark: `+` for `elite`/`worldboss`
    (matching how the game marks those units elsewhere), `R` for `rare`,
    and both together (`R+`) for `rareelite`. A plain `normal` unit gets no
    mark.
  * Coloured via `GetQuestDifficultyColor(level)`, resolved defensively as
    `GetQuestDifficultyColor or GetDifficultyColor` since 3.3.5a may expose
    it under either name depending on the server, with a hardcoded red for
    the unresolvable (`-1`) boss case (there is no meaningful level to hand
    the colour function) and a plain white fallback if neither global
    exists or the call errors - guarding the API return rather than
    trusting it, per the 3.3.5a/private-server rule.
  * Degrades to nothing (the bare name, no stray marker) when there is no
    unit, no `UnitLevel` global at all, or `UnitLevel` reports `0` - never a
    real level on 3.3.5a, so treated the same as "unavailable" rather than
    shown literally.
Nil (off) by default, same reasoning as Group Name Follows Target itself:
defaulting it on would silently change the title of anyone who had already
ticked that one, the first time they updated.

**Keeping `totResources` current.** `PLAYER_TARGET_CHANGED` only ever tells
the addon that the PLAYER's own target changed; there is no client event at
all for "your target's target changed" while your own target stays the
same (a boss switching aggro between two tanks, for instance - nothing
fires). `ns:OnTargetChanged` (BarEngine.lua) rescans both the `"target"` and
`"targettarget"` auto groups the moment the player's own target changes
(retargeting almost always changes who `"targettarget"` resolves to as
well), and `ns:OnUnitDisplayPowerChanged` reacts to a `"targettarget"`
`UNIT_DISPLAYPOWER` the same way it already does for `"target"`. Neither of
those reaches the "your target switched what IT is attacking" case, though
- that one has no event on this client at all, and is left entirely to the
0.25s scan loop (`ns:ScanAllBars`, Core.lua), which rescans every auto group
unconditionally regardless of any event. This is not a gap being patched
around; it is the actual, complete answer for that one transition.
`UNIT_POWER` stays unregistered for the same firehose reason as always (see
the comment above `ns:OnComboPointsChanged`, BarEngine.lua) - nothing about
a third unit changes that trade-off.

**Pinned-resource order (v2.5.0).** `autoPinnedResources` used to be a plain
set (`{ mana = true }`); it is now an ordered list of `{ key, color? }`
entries, so the pinned extras appear in the order the tickboxes were
ticked, not a fixed order. `ns:NormalizePinnedResources` (Trackers.lua) is
the single place that shape decision lives: it accepts either shape and
always returns a fresh ordered list, falling back to a deterministic
alphabetical order for the legacy set (matching the `table.sort()` this
replaced, so an upgrading profile's bars do not visibly reshuffle just from
loading the new code) - no `ns:MigrateFrames` migration was needed, since
every read site normalizes on demand instead. `ns:TogglePinnedResource(pinned,
key, ticked)` is the pure state transition behind each tickbox: it always
removes any existing entry for `key` first, then re-appends it when ticked,
so unticking and re-ticking a resource moves it to the end rather than back
to its old slot. `ns:SetPinnedResourceColor(pinned, key, color)` writes the
colour swatch's value onto the matching entry the same way. All three are
pure and covered by `test_resources.lua`.

`ns:ScanAutoGroup` branches on `def.kind == "resource"` straight after the
group-conditions gate and hands off to a local `ScanAutoResourceGroup`,
which maps `entries[i]` to `group.bars[i]` directly - no expiry, no
held/keepNames placement, since the collector's order is already
deterministic. Every occupied slot goes through `ns:UpdateResourceBar`,
never `ns:ActivateBar`: a resource has no expiry, so it must never pick up
the countdown path or a linger. The `stacks`/`trackMode` fields exist only
for the six DK rune entries, so `UpdateResourceBar`'s `trackMode == "Runes"`
special case (the "Ns" countdown-to-ready text) still renders correctly
inside an auto group, not just on a hand-placed Runes bar.
`ScanAutoResourceGroup` also stamps `bd.resourceKey = e.key` onto each
occupied slot (nil'd again when a slot empties), which is how
`ns:GetResourcePowerColor` / `ns:GetPinnedResourceColor` (Conditions.lua,
see "Resource bar default colours" below) know which resource a given bar
represents without threading the collector's entry through the whole call
chain.

The group's Value Text setting (`autoResourceValueText`: nil/current-max,
`"PERCENT"`, `"BOTH"`) is read directly inside `ns:UpdateResourceBar` off
`bar.frameIndex -> BarWardenDB.frames[...]`, the same group-reach pattern as
every resolver in the table below - but as a direct read, not a dedicated
resolver function, because (like `iconOnly`) it has no per-bar equivalent to
resolve against.

Max Bars and Keep Bars In Place stay visible for the resources feed even
though the collector's order is already fully deterministic and Keep Bars
In Place is never consulted for it - hiding exactly the four aura-only
settings (Skip If It Lasts Over, Only Mine, Include Always On, Skip Spells I
Already Track) was the deliberate scope, not "hide anything unused".

`ns:InvalidateTrackedNames()` (BarEngine.lua) clears the per-group
tracked-name cache built by `ns:GetTrackedAuraNames`. It is called from
`ns:RefreshBarSettings` (Core.lua) - which the `autoSkipTracked` toggle's
`set` calls too, alongside every other Group Conditions toggle - from the bar
Enabled checkbox handler in [Options_Bars.lua](../Options_Bars.lua), from the
alt-click ban handler on a bar's icon in [Bar.lua](../Bar.lua), and from the
banned-spells management list's mutations (also Options_Bars.lua); those are
the only call sites, so anything else that can change what counts as
"already tracked" or what is banned needs its own call.

That cache (`trackedNamesCache`, keyed by frame index) holds only the
expensive half: one group's `ns:GetTrackedAuraNames` result. The cheap half -
honouring `autoSkipTracked` and folding in `autoBanned` - is never cached;
`ns:ScanAutoGroup` calls `ns:BuildGroupSkipSet(groupData, tracked)`
(Trackers.lua) fresh every scan, so the setting and the ban list are always
current even if the tracked-name cache happens to still be warm. An earlier
version merged both halves into the one cached value, which meant unticking
`autoSkipTracked` had no effect until something else invalidated the cache;
`ns:BuildGroupSkipSet` exists specifically so that rule is a pure, tested
function rather than logic buried in the scan loop.

### Bar naming: `ns.GetBarDisplayName`

`ns.GetBarDisplayName` (Bar.lua) returns `barData.name` when set; otherwise
it resolves one from the spell: `barData.spellId`, or a bare-numeric
`barData.spellName` (the same numeric-string-as-id rule `getSpell`,
Trackers.lua, and `ns:GetTrackedAuraNames` already apply, so all three have
to agree), through `GetSpellInfo`. A bar configured entirely by spell ID and
never given its own name shows the resolved spell name instead of a blank
row or a stale "Bar N" placeholder, both on screen and in the Options Bars
tab's list (`UpdateBarList`). `GetSpellInfo` returns nil for an id the
client's spell table does not know (a private-server id, for example);
that falls back to the same empty string this function always returned, not
an error or a literal "nil".

`GetBarDisplayName` runs from the bar activation/deactivation paths on the
4 Hz scan loop, so the resolved name is memoised by spell id in a small
cache local to Bar.lua - a sibling to `trackedNamesCache` above, and
invalidated the same way: `ns:InvalidateTrackedNames()` also wipes it, so
every call site listed above that already invalidates the tracked-name
cache keeps this one current too, with no separate call needed. Never
written back into `barData`; persisting a client-side lookup into
SavedVariables would bake in whatever the client could resolve at save
time and break if the id later resolved differently.

Eleven keys on a group, all nil on a normal group (the last three are
resources-only, described further above under "The resources feed"):

| Key | Effect |
|---|---|
| `autoTrack` | Feed name (`playerBuffs`, `playerDebuffs`, `targetBuffs`, `targetDebuffs`, `resources`, `targetResources`, `totResources`), or nil for a normal group |
| `autoMaxBars` | Pre-allocated slots, capped at `MAX_BARS_PER_FRAME` |
| `autoMaxDuration` | Skip auras whose full duration exceeds this (the Groups tab's Skip If It Lasts Over slider, seconds, 0-3600). Tests full duration, not time left, on purpose - see `ns:CollectAutoAuras` above. 0 = no limit |
| `autoIncludePermanent` | Keep auras with no duration instead of dropping them. Off by default. `ns:CollectAutoAuras` marks each entry `permanent`; permanent entries sort into a stable block above every timed entry (tied broken by name, since they all share expiry 0) and `ns:ScanAutoGroup` routes them through `ns:ActivateStaticBar` instead of `ns:ActivateBar`, the same no-countdown path a switch-mode bar takes |
| `autoOnlyMine` | Count only your own casts. Seeded on for the two target feeds, off for the two player feeds when Auto Track is first set; the seed only fires once, so switching feeds afterwards leaves whatever the player has |
| `autoSkipTracked` | Skip spells a bar in another group already tracks (matched by name via `ns:GetTrackedAuraNames`) |
| `autoStableOrder` | Keep Bars In Place: an aura stays in the slot it first appeared in for as long as it lasts, instead of the soonest-expiring sort reshuffling every slot on each tick or refresh. Only a fade frees a slot. `ns:ScanAutoGroup` builds the held-name list from the live slots and hands it to `ns:PlaceAutoAuras` (Trackers.lua), the tested half that decides the new placement; the untested half is just reading `bar.barData` to build that list |
| `autoBanned` | Per-group spell bans set by alt-left-clicking a bar's icon (`bar.isAutoBar` only), keyed by lower-cased spell name: `{ [name] = { name = "Blade Flurry", id = 13877 } }`, `id` optionally nil. Nil (not `{}`) once every ban is removed, so `ns:BuildAutoSkipSet` keeps its cheap no-skip path. `ns:BuildGroupSkipSet` (Trackers.lua) folds this in unconditionally via `ns:BuildAutoSkipSet`, always returning a fresh table so the caller's own copy is never mutated, so a ban applies even with `autoSkipTracked` off. Managed from the "Hidden In This Group" list under Auto Track in Options_Bars.lua, which only shows/enables for a group with an AURA feed picked - a resource has nothing to ban, so it hides the same as no feed at all |
| `autoPinnedResources` | Any resources feed only (v2.5.0: now an ORDERED list, `{ { key = "mana", color = {r,g,b}? }, ... }`, in tick order; a group saved before this existed still carries the legacy set, `{ mana = true }` - `ns:NormalizePinnedResources` (Trackers.lua) accepts either shape, so no migration was needed). Resources the user ticked to always show even when not the unit's current power type, passed as `ns:CollectResources`'s `opts.pinned` and read against `opts.unit` (player, target, or targettarget). Each entry's optional `color` is the most specific level `ns:GetPinnedResourceColor` (Conditions.lua) resolves - see "Resource bar default colours" below. `mana`/`rage`/`energy` (`PINNABLE_POWER_TYPES`, Trackers.lua) and `combopoints` are the pinnable keys; `focus` was removed in v2.5.0 (see CHANGELOG) - a legacy save with `focus` still pinned just finds no match there and is silently dropped, no migration needed |
| `autoResourceValueText` | Resources-feed only: nil/`""` (current/max, e.g. "3000/4500"), `"PERCENT"` ("67%"), or `"BOTH"` ("3000/4500 (67%)"). Read directly inside `ns:UpdateResourceBar` (BarEngine.lua) |
| `autoResourceShowIcon` | Resources-feed only (v2.5.0): nil/unset defers to the addon-wide Show Icon default (so an upgrading group looks exactly as it did before this tickbox existed); `true`/`false` overrides it for every bar in this group. Read directly inside `ApplyVisualConfig` (Bar.lua), the same direct-read shape as `autoResourceValueText` above, since like it there is no per-bar equivalent to resolve against for an auto slot |
| `autoTitleFollowsUnit` | `targetResources`/`totResources` only (v2.5.0). nil by default. When true, the group's title shows the feed's unit name instead of the group's own configured name - see "Group Name Follows Target" below |
| `autoTitleShowsLevel` | `targetResources`/`totResources` only (v2.5.0). nil by default. When true AND `autoTitleFollowsUnit` resolved a unit name, the title also shows that unit's level - see "Show Target Level" below |

`iconOnly` used to live in this table as `autoIconOnly`, gated to
auto-tracking groups only. It is now a general Bar Overrides setting (see
the "Group overrides" table below) so a hand-made group can use it too; the
v2.2.0 `ns:MigrateFrames` pass (DB.lua) renames any existing `autoIconOnly`
value across without a schema bump.

Drag-reorder is gated off for auto groups in `ns:EnableDragReorder`
([DragReorder.lua](../DragReorder.lua)), and `ns:ReleaseBar` (BarPool.lua)
clears drag handlers so a pooled bar cannot carry them into a slot it is
recycled into.

A group whose Sort Mode is not Manual gets its bars wired the same as any
other (unlike an auto group), but a reorder attempt is refused live, at the
moment the drag threshold is crossed (`IsManualSort`, DragReorder.lua) or in
the Options Bars-tab list drag's `OnDragStart` (Options_Bars.lua): a sorted
group re-derives its on-screen order on every layout, so a drop there would
land in an unrelated slot and even a "successful" reorder would have no
visible effect. Both paths explain the refusal once per attempt through
`ns:ExplainSortedDragRefusal`, rather than letting the gesture do nothing
with no feedback. Checked live rather than baked in once at
`ns:EnableDragReorder` time because the Sort Mode dropdown does not call it
back; a group can flip sorted while already unlocked.

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
| Whether an empty group's frame hides | `ns:ShouldHideEmptyGroup(frameData, isAutoGroup, isLocked, conditionsFailed)` ([Conditions.lua](../Conditions.lua)) | conditionsFailed, then group when set, else lock/type default (see below) |
| Switch mode (on/off, no countdown) | `ns:IsSwitchBar(bar)` ([Conditions.lua](../Conditions.lua)) | group (`group.barStyle`) when set, else bar (`display.switchMode`) |
| Bar texture / colour | resolved inside [Bar.lua](../Bar.lua) `ApplyVisualConfig` | bar then group then global; a **resource** bar additionally slots in `ns:GetPinnedResourceColor` and `ns:GetResourcePowerColor` (both [Conditions.lua](../Conditions.lua)) between the per-bar override and the group colour, and between the group colour and the global default respectively - see "Resource bar default colours" below |
| Icon Only (square icon grid, no bar/text) | read directly as `group.iconOnly` in `ApplyVisualConfig` (Bar.lua) and `ns:UpdateGroupLayout` (FrameManager.lua); no resolver function, no bar-level override | group only (boolean, not an Inherit tri-state) |
| Resource bar icon shown | read directly as `group.autoResourceShowIcon` in `ApplyVisualConfig` (Bar.lua), same direct-read shape as Icon Only above | bar (`display.showIcon`, practically never set for an auto slot) then group (resources feed only) then global (`visual.showIcon`) |
| Stack text size | `ns:GetStackFontSize(bar)` ([Conditions.lua](../Conditions.lua)) | bar (`display.stackFontSize`) then group (`group.stackFontSize`) then global (`visual.stackFontSize`) |
| Stack text colour | `ns:GetStackColor(bar)` ([Conditions.lua](../Conditions.lua)), returns a `{ r, g, b }` table | bar (`display.stackColor`) then group (`group.stackColor`) then global (`visual.stackColor`) |
| Glow on ready | `ns:GetBarGlowOnReady(bar)` ([Conditions.lua](../Conditions.lua)) | bar (`display.glowOnReady`, truthy) then group (`group.glowOnReady`) then off |
| Pulse on ready | `ns:GetBarPulseOnReady(bar)` ([Conditions.lua](../Conditions.lua)) | bar (`display.pulseOnReady`, truthy) then group (`group.pulseOnReady`) then off |
| Linger time | `ns:GetBarLingerTime(bar)` ([Conditions.lua](../Conditions.lua)) | bar (`display.lingerTime`, only when `> 0`) then group (`group.lingerTime`, only when `> 0`) then 0 |

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

The same toggle also governs `ns:ShouldHideEmptyGroup`, which decides whether
an *empty* group's frame (title and all) hides - a different question from
`ResolveHideWhenInactive` above, which is only about individual bars.
`AreAllBarsHidden` (BarEngine.lua) calls it once it has already established
every bar/slot in the group is hidden. Precedence, most authoritative first:

1. `conditionsFailed` (the group's own Combat Only / Hide Mounted / etc
   conditions currently fail) - hide, always, whatever the lock state or
   group type. `AreAllBarsHidden` computes this itself by calling
   `ns:EvaluateConditions(nil, groupData.groupConditions)`, the same call
   `ScanBar`/`ns:ScanAutoGroup` already make to gate the bars, so
   `ShouldHideEmptyGroup` stays a pure decision function rather than
   re-evaluating conditions itself. Added in v2.4.0: before this, an
   auto-tracking group whose condition failed still passed the unlocked
   carve-out below, because "every slot hidden" read as "nothing matched
   yet" instead of "the owner said hide this".
2. `groupConditions.hideWhenInactive ~= nil` (touched) - honoured outright:
   ticked hides the frame regardless of lock state, unticked keeps it up
   regardless of lock state (this is the case that used to have no control
   at all - Show Group Name only draws a title inside a group that is
   already visible, so it could never rescue a group the lock state had
   just hidden).
3. Untouched (`nil`) - reproduces the behaviour that predates the setting
   having any say here: an auto-tracking group (slots fed from whatever is
   on the unit, so "empty" is its normal idle state) stays up while
   unlocked and hides once locked; an ordinary group never had that
   carve-out and always hides when empty.

The decision lives in Conditions.lua rather than BarEngine.lua because
BarEngine.lua's frame-heavy locals cannot load under the test harness, and
the decision itself is pure data - see `test_conditions.lua`'s
`test_shouldHideEmptyGroup_*` cases for the full truth table.

`ns:IsSwitchBar` mirrors that same group-over-bar shape for switch mode:
`group.barStyle == "SWITCH"` or `"COUNTDOWN"` overrides every bar in the group
in either direction, and an untouched group (`nil` / `""`) leaves it to the
bar's own `display.switchMode`. Switch mode writes no new rendering: it routes
into `ns:ActivateStaticBar` ([BarEngine.lua](../BarEngine.lua)), the same full
fill / no-OnUpdate / blank-timer path a permanent aura already uses, so an
active tracked thing reads as filled and an inactive one is the ordinary dim
empty bar.

`ns:GetStackFontSize` / `ns:GetStackColor` are the one pair of resolvers that
go three levels deep (bar, then group, then global) rather than the usual
group-then-bar shape above, because Stack Text Size/Colour exist at all three
of bar, group, and the Visuals tab. Both are nil-safe at every step (nil
bar, nil `barData`, nil `display`, missing `frameIndex`, or an absent group
all fall through to the next level), so a still-building bar reads the
addon-wide default instead of erroring. The Custom Stack Text toggle on both
the Groups tab (`GROUP_SETTINGS_SCHEMA`) and the bar editor (`EDITOR_SCHEMA`)
writes/clears `stackFontSize`/`stackColor` (`display.*` for the bar) together,
same toggle-reveals-swatch mechanism as Custom Bar Colour.

`ns:GetBarGlowOnReady` / `ns:GetBarPulseOnReady` / `ns:GetBarLingerTime`
(v2.4.0) are most-specific-wins like the stack pair, but the bar side of that
precedence is a plain always-present checkbox/slider rather than a field
gated behind its own per-bar "Custom" toggle, so "the bar has its own value"
has to be read as **truthy**, not merely non-nil: `disp.glowOnReady` /
`disp.pulseOnReady` win only when `true` (an untouched, still-`false` bar
defers to the group; a bar cannot force the effect off against a group that
has it on - the trade-off of not having a per-bar nil state to spend). Linger
time additionally has to guard on `> 0`, not truthiness alone, because 0 is
both the field's schema default (`NewBar`, Options_Bars.lua, and
`NewAutoBarData`, FrameManager.lua) and its existing "off" sentinel at every
other read site (`Bar_OnUpdate`/`ScanBar` both gate on `lingerTime > 0`) - and
0 is truthy in Lua, so a bare `if disp.lingerTime then` would treat every
untouched bar as having its own override and the group's Linger Time would
never be reachable. The Custom Bar Effects toggle on the Groups tab
(`GROUP_SETTINGS_SCHEMA`) writes/clears all three group keys together, same
mechanism as Custom Stack Text.

**Bar Alerts** (v2.4.0) has no group-level override, unlike everything else
in this section, so its two resolvers are plain bar-only helpers rather than
entries in the table above - but they live in Conditions.lua for the same
reason: pure arithmetic that the test harness needs to reach without loading
BarEngine.lua's frame-heavy locals.

`ns:IsBarAlerting(display, remaining, duration)` decides whether a bar is
inside its expiry alert window. `display.sparkleAlert` is still the master
on/off (unrenamed from the original sparkle-only feature; it is in saved
variables and the bug report). `display.alertUnit` picks how the threshold
is read: nil/`"SECONDS"` compares `remaining` to `display.sparkleThreshold`
(default 5) exactly as the original inline check did; `"PERCENT"` compares
`remaining` to `duration * display.alertPercent / 100` (default 20). A nil
or non-positive `duration` (a permanent/static bar - see
`ns:ActivateStaticBar`/`UpdateResourceBar`, BarEngine.lua, both of which set
`bar.duration = nil`) returns false in percent mode rather than dividing by
zero: that kind of bar has no "full length" to take a percentage of.

`ns:GetBarAlertColor(display, remaining, duration)` resolves the alert
colour for `ns.GetTimeBasedColor` (Bar.lua): nil unless the bar is currently
alerting (calls `IsBarAlerting` itself, so callers never re-derive the
window) AND `display.alertAction` is `"COLOUR"` or `"BOTH"` (nil/`"SPARKLE"`
is sparkle-only and never returns a colour). `GetTimeBasedColor` checks this
resolver before its own `colorByTime` gradient, so an explicit alert colour
wins over the ambient one and - just as importantly - still works on a bar
with Colour by Time switched off entirely, which is the common case for a
bar that only wants one cue near the end rather than a gradient for its
whole active life. `Bar_OnUpdate` (BarEngine.lua) gates the sparkle/pulse
half the same way: it only flashes the alpha while `IsBarAlerting` is true
AND the action includes Sparkle, so a Colour-only bar changes colour without
ever flashing.

**Resource bar default colours** (v2.5.0) give a resource bar (health, the
current power type, a pinned extra) the game's own conventional colour - a
blue mana bar, a yellow energy bar, a red rage bar - instead of the
addon-wide default, without overriding anything the owner has actually set.
Two resolvers, both in Conditions.lua for the same reason as the Bar Alerts
pair (pure arithmetic `GetBarColor`, Bar.lua, consults; frame-heavy code
never touches them):

- `ns:GetResourceKeyDefaultColor(key)` maps a resource key straight to a
  colour, with no bar involved: the power-type keys (`mana`, `rage`,
  `focus`, `energy`, `runicpower`) go through the client's own
  `PowerBarColor` table first (keyed by the same string tokens
  `UnitPowerType`'s second return uses - Blizzard's own UnitFrame.lua reads
  it the same way), falling back to a hardcoded `RESOURCE_COLOR_FALLBACK`
  table when `PowerBarColor` is absent or missing that token. `health` and
  `soulshards` are not power types at all, so they always use the fallback
  table (health's green is the plain WoW convention, not tied to Colour
  Mode's CLASS option). Combo points have no single conventional colour
  (they render as pips, not a status bar) and return nil, falling through to
  the addon-wide default like any other bar. Pulled out as its own function
  (v2.5.0) so the pinned-resource colour swatch (Options_Bars.lua) can show
  the SAME starting colour the bar itself would draw, with no live bar
  object needed - see "Colour swatches default to the resource's own colour"
  further below.
- `ns:GetResourcePowerColor(bar)` reads `bar.barData.resourceKey` (stamped
  by `ScanAutoResourceGroup`, BarEngine.lua, onto every occupied resource
  slot) and, for a rune (`bar.barData.runeType` set), returns that rune's
  TYPE colour (`RUNE_TYPE_COLORS`); otherwise delegates to
  `ns:GetResourceKeyDefaultColor` above. See "Death Knight runes coloured by
  type" further below for the rune half.
- `ns:GetPinnedResourceColor(bar)` resolves the colour swatch under a
  pinned resource's own tickbox (Options_Bars.lua), reading
  `groupData.autoPinnedResources` through `ns:NormalizePinnedResources`
  (Trackers.lua) so both the ordered shape and the colour-less legacy set
  are handled identically.

`GetBarColor` (Bar.lua) slots both in among the pre-existing per-bar/
per-group/global levels, gated on `bar.isResourceBar` so an ordinary bar's
resolution is completely unchanged. Precedence, most specific first: (1)
per-bar `display.colorOverride` (pre-existing; practically unreachable for
an auto slot, which has no per-bar editor of its own, but still honoured),
(2) `ns:GetPinnedResourceColor`, (3) the group's Custom Bar Colour
(pre-existing `group.barColor`), (4) `ns:GetResourcePowerColor`, (5) the
addon-wide Colour Mode default (pre-existing). Levels (2) and (4) are the
only two new to a resource bar; a non-resource bar reaches the same three
pre-existing levels it always did.

**Colour swatches default to the resource's own colour** (v2.5.0). Each
pinned resource's colour swatch (`grpAutoPinManaColor` and its siblings,
Options_Bars.lua) used to open on one fixed placeholder blue regardless of
which resource it belonged to, so the panel did not match what the bar
actually drew until the owner picked a colour themselves.
`BUILDERS.color` (Options_Builder.lua) resolves a widget's initial colour
from `entry.get()`; that `get` is `getPinnedResourceColor(g, key)`
(Options_Bars.lua), which now falls back to
`ns:GetResourceKeyDefaultColor(key)` (Conditions.lua) - the same by-key
resolver `ns:GetResourcePowerColor` reads for the bar itself - instead of a
fixed constant, whenever the entry has no colour of its own yet. A key with
no conventional colour (`combopoints`) still falls back to the old fixed
placeholder, since there is nothing more specific to show.

**Death Knight runes coloured by type** (v2.5.0). Each rune has its own
colour by type (blood red, frost blue, unholy green, with death runes
distinct too), which `ns:CollectResources` did not used to thread through
as part of the entry, so every rune bar fell all the way through to the
addon-wide default. 3.3.5a's FrameXML (`RuneFrame.lua`) does define this
exact palette, but as a file-local `runeColors` table with no addon-visible
equivalent of `PowerBarColor` for rune types, so it cannot be read live the
way the power-type colours above are; `RUNE_TYPE_COLORS` (Conditions.lua)
hardcodes the same four values Blizzard's own client uses: Blood `{1, 0,
0}`, Unholy `{0, 0.5, 0}`, Frost `{0, 1, 1}`, Death `{0.8, 0.1, 1}` (a
magenta/purple, not white - matching Blizzard's own choice rather than an
invented one). `CheckRunes` (Trackers.lua) now returns the rune's type
(1-4, from `GetRuneType`) as a seventh value; `ns:CollectResources` carries
it on each `rune1`..`rune6` entry as `runeType`, and
`ScanAutoResourceGroup` (BarEngine.lua) stamps it onto `bd.runeType`
alongside `bd.resourceKey`, clearing it when the slot empties. This sits at
the same precedence level as the power-type default above (4): a per-bar
override, a pinned resource colour, or the group's Custom Bar Colour all
still win over it, exactly like any other resource bar.

Adding a new group override means: the widget in
[Options_Bars.lua](../Options_Bars.lua) `GROUP_SETTINGS_SCHEMA` (with an
"Inherit (default)" entry that stores nil), a resolver, and updating **every**
read site - `ResolveHideWhenInactive` replaced five separate
`cond.hideWhenInactive` reads across BarEngine/Core/FrameManager.

**Hide Blizzard Player Frame** (v2.5.0, `global.hidePlayerFrame`,
[Options_General.lua](../Options_General.lua)) and **Hide Blizzard Target
Frame** (v2.5.0, `global.hideTargetFrame`, same file) are addon-wide rather
than group overrides - a resource group duplicates the default unit frame it
mirrors, but hiding that frame is a global act and a second resource group
must not fight the first (or the other setting) over it - so neither has a
per-group entry in the table above. They are two entirely independent
settings over two independent frame lists: ticking one never touches the
other's frames. Both share one resolver, `ns:ResolvePlayerFrameHidden(wantHidden)`,
which lives in Conditions.lua for the same reason as the Bar Alerts pair:
pure arithmetic the test harness can reach without the frame-heavy code that
actually touches `PlayerFrame`/`TargetFrame`. `wantHidden` already folds in
`global.enabled`, so a disabled addon never keeps either frame hidden.

Each setting reaches more than just the frame named in its label:
`PLAYER_HIDE_FRAME_NAMES` (Core.lua) is `{ "PlayerFrame", "RuneFrame" }` and
`TARGET_HIDE_FRAME_NAMES` is `{ "TargetFrame", "ComboFrame" }` - the short
lists of standalone satellites each setting applies to. `RuneFrame` (the
Death Knight rune display) and `ComboFrame` (the combo-point display) are
each their own top-level frame on 3.3.5a, not a child of `PlayerFrame`/
`TargetFrame` respectively, so hiding the parent alone left them on screen.
Everything else that visually rides along with either frame (portrait,
health/mana bars, group indicator, PvP icon, level text, the alternate
power bar some forms use, the target's cast bar) is a genuine XML child of
it, and a hidden parent already makes WoW treat every child as invisible
regardless of the child's own `Show()`/`Hide()` state, so none of those
need an entry here. Checked further for each:
  * PlayerFrame: the pet frame and the totem frame are independent UI the
    player controls separately and are not anchored to `PlayerFrame`, so
    they are out of scope on purpose, not an oversight.
  * TargetFrame: `TargetFrameToT` (target-of-target) is a comparable
    standalone satellite, and is STILL left OUT of `TARGET_HIDE_FRAME_NAMES`
    even now that a `totResources` group (v2.5.0; see "The 'resources' /
    'targetResources' / 'totResources' feeds" above) exists to replace what
    it shows. The reason changed, not the answer: hiding `TargetFrame` is
    one tickbox, and building a `totResources` group is a separate, opt-in
    action the owner has to take on a specific group - nothing here can
    tell whether a matching group exists for this character, so folding
    `TargetFrameToT` into this tickbox would let someone lose
    target-of-target just by ticking "declutter the target portrait", with
    no replacement built. The tooltip (Options_General.lua) says
    explicitly that target-of-target is not touched by this setting.

`ns:ApplyPlayerFrameHidden` / `ns:ApplyTargetFrameHidden` (Core.lua) do the
impure half and are deliberately reversible: each only ever calls `Hide()` /
`Show()` on the names in its own list (never `UnregisterAllEvents()` -
undoing that would mean hand-re-registering every event Blizzard put on the
frame, long, version-specific, and easy to get subtly wrong). Both share
one `ApplyFrameHidden(name, wantFn)` helper, `wantFn` being whichever
want-function owns that frame, so the shared code stays a single
implementation without the two settings' frames ever being able to cross
over. Because Blizzard's own code re-`Show()`s these frames constantly
(`UNIT_HEALTH`, entering the world, a target change, and more), staying
hidden needs a `HookScript("OnShow", ...)` per frame that re-checks the
live setting and re-hides on the spot - see the `EC-TRAP:` on that hook in
Core.lua, since `HookScript` cannot be removed and the hook can look
redundant next to the `Hide()` call beside it. Both apply functions are
called together from `ns:OnInitialize` via `ns:OnEnable` (login), from each
toggle's own `set` (Options_General.lua), and from `ns:OnEnable`/
`ns:OnDisable` (`/bw enable`/`disable`).

Neither frame is built on a secure template in 3.3.5a, so `Hide()`/`Show()`
take effect immediately regardless of combat state - there is no deferral,
and `ns:ResolvePlayerFrameHidden` (Conditions.lua) takes only `wantHidden`,
not an `inCombat` argument. An earlier version DID gate on
`InCombatLockdown()` and defer the hide, on the theory that a secure frame
might make `Hide()` unsafe mid-fight; it did not, since neither frame is
secure (the `pcall` around `Hide()`/`Show()` in `ApplyFrameHidden` is the
genuine safety net for that assumption), and the gate instead made the
`OnShow` hook decline to re-hide the frame on every `Show()` Blizzard fired
while in combat, which is most of what combat does to these frames: ticking
Hide Blizzard Target Frame and then entering combat brought the frame
straight back for the rest of the fight. Because of this,
`ns:OnCombatStateChanged` (BarEngine.lua) no longer re-applies either hide
on `PLAYER_REGEN_ENABLED`: with nothing ever deferred, that call had
nothing left to pick up.

### Declarative options schema (`ns:BuildSettings`)

[Options_Builder.lua](../Options_Builder.lua) walks a schema table and
builds one widget per entry, chaining each below the previous, and returns
**two** values: a Refresh closure that re-reads DB values into the widgets,
and a Reflow function that re-anchors the currently VISIBLE widgets to close
any gap a hidden one would otherwise leave.

```lua
local SCHEMA = {
    { type = "header", text = "Slash Commands", spacing = 24 },
    { type = "toggle", label = "Show Minimap Icon",
                       db = "global.minimapIcon",
                       refresh = "UpdateMinimapButtonVisibility" },
    { type = "note",   text = "Help text", spacing = 6 },
}
frame.Refresh, frame.Reflow = ns:BuildSettings(frame, SCHEMA)
```

Used by [Options_General.lua](../Options_General.lua) (its schema has no
reveal pattern, so it only keeps Refresh), and, capturing both return
values for their reveal-pattern settings (a master toggle or dropdown that
shows/hides sub-settings),
[Options_Visuals.lua](../Options_Visuals.lua) (Color Mode and Bar Texture)
and [Options_Bars.lua](../Options_Bars.lua) (Group Settings and the bar
editor).

The vertical chain is reflowable, not fixed at build time: a widget hidden
via `widget:Hide()` (a master toggle or dropdown revealing sub-settings via
its `onChange`) is skipped entirely on the next reflow, and the widgets that
were chained below it re-anchor to whichever visible widget now precedes
them, closing the gap. Only the VERTICAL position ever moves this way -
`offsetX` stays exactly the absolute column it always was (see below), and
an `anchorTo` entry is never folded into the chain by a reflow; it keeps
following its named target, hidden or not (see `anchorTo` below).

Refresh calls Reflow itself at the end of every pass, since its own
`onChange` hooks are what usually drive visibility. That covers a Refresh
triggered by selecting a different group/bar or reopening a panel, but NOT a
live user click: clicking a checkbox fires its `set` callback (and then
`onChange`) directly, bypassing Refresh's schema walk entirely. Any
show/hide helper that calls `widget:Show()`/`Hide()` from an `onChange` must
therefore call the panel's own Reflow itself right afterwards - see
Options_Bars.lua for `reflowGroupSettings`/`reflowEditorSettings` for the
pattern (a master toggle's `onChange`, plus the forward-declared upvalues
needed because the show/hide helper is defined - and can fire - before the
`ns:BuildSettings` call that assigns it).

Reflow returns the screen-space `GetBottom()` of the last widget it
positioned (or nil if nothing in the schema is visible) - the true bottom of
the live content regardless of which entry the schema lists last, useful for
a scroll child's height fitter that would otherwise need a hand-picked
sentinel widget that might itself be one of the hidden ones (see
`fitEditorHeight` in Options_Bars.lua, whose old sentinel - the Stack Text
Colour swatch - is exactly a widget Custom Stack Text can hide).

Two ways to wire a setting:

- `db = "path"` + `refresh = "Method"` - uses `ns:DBSet` under the hood
  (gets strict registration-time validation for free).
- `get = fn` + `set = fn` - escape hatch for stateful behaviour (a
  toggle that branches, calls multiple refreshers, or shows/hides other
  widgets).

Supported entry types: `header`, `note`, `spacer`, `toggle`, `slider`,
`dropdown`, `editbox`, `color`. Sliders and editboxes accept an optional
`tooltip`. A slider also accepts an optional `format = function(num) ->
string`, applied to the live value label and the Low/High end labels alike
(e.g. `ns.FormatSettingDuration`, [Utils.lua](../Utils.lua), for a
seconds-based slider) so the whole control reads in real units instead of a
bare number; omit it and the slider keeps the old `%d` / `%.2f` rendering.
Add new types by extending the `BUILDERS` + `APPLIERS` dispatch tables.

Cross-widget coordination: `id = "<name>"` exposes a widget via an
optional `widgetRefs` table; `onChange = fn` fires after user writes and
after Refresh (call the panel's own Reflow return value here too if it
Shows()/Hides() another widget by id); `anchorTo = "<id>"` overrides "anchor
to previous"; `opts = { firstX, firstY }` (4th arg) overrides first-widget
placement.

`offsetX` is an **absolute** indent from the panel's left edge (added to
`firstX`), not a nudge from the previous widget - two schema entries with
the same `offsetX` land in the same column no matter what is above them.
The one exception: an entry with `anchorTo` keeps a **relative** nudge from
the named widget instead of an absolute indent, since it is deliberately
anchored off that widget's frame rather than off the panel edge (see
`anchorTo` below).
Each widget template pads its visible content differently, so use the
matching constant for the entry's type rather than a bespoke number:
`ns.OFFSET_HEADER` (2), `ns.OFFSET_DROPDOWN` (-14), `ns.OFFSET_TOGGLE`
(-4), `ns.OFFSET_SLIDER` (8), `ns.OFFSET_EDITBOX` / `ns.OFFSET_COLOR` (2).
Only hand-pick a value for an entry that is deliberately indented as a
sub-item of the setting above it (a threshold slider that only matters
while its toggle is ticked, for instance) - comment it as such so it
survives the next cleanup pass.

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

`UNIT_POWER` is deliberately never registered: it fires on every tick of
every power bar, a firehose in raid combat, which is why Runic Power and
Soul Shards (and, since v2.5.0, the resources auto-track group's Health/
Mana/Energy/Rage/Focus reads) rely on the 0.25s scan loop instead. Do not
register it to "fix" a resource group feeling one tick slow; that is the
trade-off this comment exists to protect. `UNIT_DISPLAYPOWER` (the unit's
CURRENT power type changing - a druid's form, a shaman's Ghost Wolf) is the
one exception: it fires only a handful of times per fight, so it is cheap
enough to register outright, and `ns:OnUnitDisplayPowerChanged`
(BarEngine.lua) rescans auto groups on it so a resources group's power slot
never even shows the wrong resource for one 0.25s tick after a form change.

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
subcommands as `SLASH_COMMANDS.name = function() ... end` entries and keep
the `/bw help` table in sync. `/bw` (and `/barwarden`) with no argument, or
any string that is not a known key in `SLASH_COMMANDS`, opens the options
panel via `ns:OpenOptions`.

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

Covered: `CopyTable` / `MergeDefaults` / `FormatUptime` /
`FormatSettingDuration` / Base64 / Serialize / profile export-import /
callback bus / `GetVisual` caching (test_utils); every schema migration
and the "frames not clobbered"
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
- Drag-reorder bars: ghost + drop indicator behave in a Manual-sort group;
  a sorted group refuses the drag and prints the explanation once.
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
| [Options.lua](../Options.lua) `ns:OpenOptions` | `InterfaceOptionsFrame_OpenToCategory(target)` called twice (looks like a copy-paste bug) | 3.3.5a quirk: the first call only scrolls, the second opens. Every options-opening call site (including `ns:OpenHelpEntry`'s deep-link) routes through here or `ns:SelectOptionsTab`, so the category name and the double call live in one place. Do not dedupe. |
| [Trackers.lua](../Trackers.lua) `CheckItem` | bare `GetItemCooldown(...)` (looks like it should be `C_Container.GetItemCooldown`) | `GetItemCooldown` is the correct bare global on 3.3.5a. Do not "modernise". |
| [Conditions.lua](../Conditions.lua) | `GetNumPartyMembers()` / `GetNumRaidMembers()` (looks like it should be `GetNumGroupMembers`) | Those are the 3.3.5a group queries; `GetNumGroupMembers` is Cataclysm+, absent here. |
| [FrameManager.lua](../FrameManager.lua) `IsGroupEmptyForBackdrop` | the auto-group branch looks redundant with the `#frameData.bars == 0` check below it | `frameData.bars` is always the dormant hand-bar list for a pure auto-tracking group (kept for when Auto Track is switched off), so that check is permanently true and tells us nothing. Collapsing the two branches back into one reintroduces the v2.2.1 bug: Background Opacity ignored, stuck at solid black on any populated auto-tracking group. |
| [FrameManager.lua](../FrameManager.lua) `ns:UpdateGroupLayout` | the re-anchor sits AFTER `SetHeight`/`SetWidth` (looks like it should read the frame's edges first, so it keeps the corner the user is currently looking at) | Reading first is right only while the size is not also changing, which is every relayout of a settled group - so both orderings agree there and the wrong one never showed itself. They diverge exactly where it matters: `ns:RebuildAllFrames` lays out a frame `ns:CreateGroupFrame` stubbed at `SetHeight(30)`, and an auto-tracking group is laid out with every slot still hidden. Repinning from that geometry pinned the wrong edge by (final height minus the size it was read at) and saved it, which is the v2.2.3 bug. Resize first so the frame grows away from the corner it is already held by. The mismatch guard above it is the v2.0.2 drift fix and must stay. |
| [Trackers.lua](../Trackers.lua) `ns:CollectResources` / `HasRunes` / `HasRunicPower` | no `UnitClass("player")` check gates Runes/Runic Power/Soul Shards/Combo Points (looks like the class check was simply forgotten) | v2.5.0 classless-server fix. The owner plays on Grimfall, where `UnitClass("player")` reports the SAME class token for every character while a character can genuinely have any combination of resources at once; gating on the token made Runes/Soul Shards permanently uncollectable for anyone there. Each resource is now gated on whether the game reports it as actually present (`GetRuneCooldown` duration, `UnitPowerMax("player", 6)`, `GetItemCount`, `GetComboPoints`'s own value), not on the class token. Do not reintroduce a `UnitClass` gate here. |
| [Options_Bars.lua](../Options_Bars.lua) `KeepListFrameShown` | the `Show()` right after `FauxScrollFrame_Update` (looks redundant) | Blizzard's `FauxScrollFrame_Update` hides the whole scroll frame, not just its scrollbar, when the list fits without scrolling, and the rest of the column anchors to that frame. Removing the `Show()` re-breaks the Bar Control page whenever a list drops from 7 items to 6 (the dependants strand at the panel origin until something re-shows the frame). |
| [Comms.lua](../Comms.lua) | `SetItemRef` reassigned wholesale (looks like it should be `hooksecurefunc`'d like everything else) | Replaced on purpose: the stock 3.3.5a handler passes unknown link types to `SetHyperlink`, which errors on the addon's custom `bwupdate:` link. Returning early avoids that path; every other link is forwarded to the original untouched. Do not swap this to a hook. |
| [Core.lua](../Core.lua) `ns:ApplyPlayerFrameHidden` | the `PlayerFrame:HookScript("OnShow", ...)` looks redundant next to the `Hide()` call right above it | It is not a duplicate: `Hide()` only takes effect for the instant it runs, while Blizzard re-`Show()`s `PlayerFrame` on a long list of events for the rest of the session. `HookScript` cannot be removed, so the hook - not the `Hide()` call - is what keeps the frame down after the first time, and it re-checks the live setting on every call rather than being installed only while the setting is on. Deleting it "as a duplicate" brings the frame back the next time Blizzard shows it. |

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
