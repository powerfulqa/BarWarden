# Class-resource tracker + starter profiles + post-review polish

**Date:** 2026-04-15
**Scope:** §A class starter profiles, §B class-resource tracker (combo points / runes / runic power / soul shards), and the follow-up polish session that closed rough edges and added competitive features.

## Why

Two gaps surfaced in a comparative review against ~40 other tracker addons (19 from GitHub + 21 from the local `3.3.5.a/` pack):

1. **No class-aware onboarding**. A fresh-install character saw a single Hearthstone-cooldown sample bar. Every comparable addon except WeakAuras ships or hardcodes class-specific defaults. New users had to manually build their first useful layout.
2. **No class-resource tracking**. BarWarden could track buffs, debuffs, items, enchants, totems, procs, cooldowns - but not the four resources unique to class power systems: combo points (Rogue / Cat Druid), runes (DK, 6 slots), runic power (DK), soul shards (pre-Cata Warlock). Every other resource (Eclipse, Maelstrom, totem slots) was already covered by the existing Buff / Totem modes.

These were addressed in the same session because §A (starter profiles) depends on §B (resource trackers): the DK preset ships rune bars + RP bar, Rogue ships a combo-point bar, Warlock ships a soul-shard bar.

## What changed

### §B - Class-resource tracker

- Four new trackers in `Trackers.lua`: `CheckComboPoints`, `CheckRunicPower`, `CheckSoulShards`, `CheckRunes`. Registered in `ns.TRACKERS` under the mode names `"Combo Points"`, `"Runic Power"`, `"Soul Shards"`, `"Runes"`.
- `ns.RESOURCE_TRACK_MODES` set + `ns:IsResourceTrackMode()` predicate. Distinguishes event-driven value-based resources (CP / RP / Shards / Runes) from time-based trackers (Cooldown / Buff / etc.).
- New `UpdateResourceBar` render path in `BarEngine.lua` for event-driven resources. Does not attach `Bar_OnUpdate` (prevents time-based depletion on static resource values). Bar fill is set once per scan from `current / max`.
- Three new events in `Events.lua`: `UNIT_COMBO_POINTS`, `RUNE_POWER_UPDATE`, `RUNE_TYPE_UPDATE`. Runic Power and Soul Shards rely on the existing 0.25s scan loop (intentional: avoids `UNIT_POWER` / `BAG_UPDATE` spam in combat).
- New `conditions.requireClass` field + `CheckRequireClass` function in `Conditions.lua`. Per-bar class gate so a DK's rune bar doesn't appear on a Mage copying a profile.
- Track-mode dropdown extended in `Options_Bars.lua` with the four new modes. `trackModeColors` defaults in `DB.lua` updated to match.

**Design decision: why 4 track modes vs. 1 "Resource" mode with sub-type.** The plan originally specified one `"Resource"` mode with a sub-type dropdown. Four distinct track modes match the existing Enchant MH / Enchant OH pattern better, need no sub-type schema field, and keep the per-bar editor simpler.

**Design decision: runes as a resource mode (post-§B).** The initial §B ship treated Runes as time-based (standard `ActivateBar` path, depleting bar, inactive when ready). Review found this UX-hostile: user couldn't see at a glance which runes were available. Fixed in the polish session: Runes is now in `RESOURCE_TRACK_MODES`, bar FILLS as the rune regenerates, stays full when ready. Text shows time-until-ready on countdown, blank when ready.

### §A - Class starter profiles

- New file `ClassPresets.lua`. Exports `ns.ClassPresets[classToken] = { groups = { ... } }` for all ten classes. ~10-15 bars per class, organised into 2-4 groups (Cooldowns / Procs / DoTs / Resources as applicable).
- `ns:LoadClassStarter(classToken)` replaces the active profile's `frames` with a defaults-filled deep copy of the preset. `ns:AppendClassStarter(classToken)` (polish session) appends instead of replacing.
- New dialogs `BARWARDEN_CONFIRM_STARTER` and `BARWARDEN_CONFIRM_STARTER_APPEND` in `Dialogs.lua`.
- Two buttons in `Options_Profiles.lua`: "Load Class Starter" (replace) and "Add Class Starter" (append).
- Resource bars in presets get `requireClass` set automatically (DK = runes + RP, Rogue = combo points, Warlock = shards).

**Design decision: class-level, not spec-level.** 3.3.5a has 30 specs. Shipping spec-level variants is 3× the curation work. Class-level presets cover the core kit; users can delete unused bars. `GetActiveTalentGroup()`-based variants deferred.

**Design decision: curation sources.** `!ElvinCDs/spells.lua` (CDs with metadata flags) + `EventAlert/EventAlertSpellArray.lua` (procs per class). `Forte_<Class>/Forte_<Class>.lua` and `ClassTimer/Bars/<Class>.lua` were cross-references. ECM and retail Cooldowns addons were ruled out - retail spell IDs don't port to 3.3.5a (ability overhauls between Wrath and Cata).

### Polish session (post-review)

**Rough-edge cleanup:**
- `BarPool.ReleaseBar` now clears `bar.isResourceBar` alongside other state clears. Prevents pool-reuse leak.
- Starter-profile Buff / Debuff / Proc entries switched from max-rank spell IDs to spell names via polymorphic `buff` / `debuff` / `proc` helpers. Level-agnostic matching so levelling characters' lower-rank spells fire the bars. Cooldowns stay as IDs (CDs don't vary by rank).

**Competitive features:**
- **Cooldown spiral** on bar icons. Native `CreateFrame("Cooldown")` overlay in `Bar.lua`'s `CreateBarFrame`. Driven by `bar.cooldownFrame:SetCooldown(start, duration)` at `ActivateBar` time, hidden on resource bars. Global `visual.showCooldownSpiral` toggle (default true) + a checkbox in the Visuals tab.
- **Aura equivalency groups**. New `AuraGroups.lua` with ~8 universal groups (Bleeding, Stunned, Silenced, Incapacitated, Disarmed, MovementSlowed, Snared, CastSpeedSlowed). Parser extension in `getSpellTokens` (Trackers.lua) expands `@GroupName` tokens to the group's spell IDs. User types `@Stunned` in a bar's spell field and the bar fires on any listed stun.

**Architectural improvements:**
- `ns.SpellDurations[id] = seconds` override table. `CheckCooldown` prefers the override when present. Lets users fix server-specific CD quirks (e.g. buffed Empower Rune Weapon) without editing core.
- Extensible condition registry. `Conditions.lua` replaces local `CHECKS` array with `ns:RegisterCondition(name, checkFn)`. All seven built-in conditions register themselves at module load. Future conditions (smart-visibility, spec check, etc.) plug in without editing core.

**Lower-priority polish:**
- Starter-profile preview in confirm dialogs. Summary includes group count, bar count, and group names.
- Activity Tracker search filter. Text input next to the category dropdown filters discovered spells by substring.
- Per-bar scale override. New `display.scaleOverride` field (0.5 to 2.0). Applied in bar layout.

## Files touched

New:
- `ClassPresets.lua`
- `AuraGroups.lua`
- `docs/changes/2026-04-15-class-resource-and-starter-profiles.md`

Modified:
- `Trackers.lua` (resource trackers, `@GroupName` parsing, `ns.SpellDurations` override)
- `BarEngine.lua` (UpdateResourceBar, event handlers, rune mode dispatch)
- `Bar.lua` (cooldown spiral overlay)
- `Events.lua` (three new events)
- `Conditions.lua` (registry refactor, requireClass)
- `DB.lua` (resource trackModeColors, requireClass schema, showCooldownSpiral default, scaleOverride default)
- `Dialogs.lua` (two starter dialogs)
- `Options_Profiles.lua` (two starter buttons with preview)
- `Options_Bars.lua` (track-mode dropdown entries, scale-override slider)
- `Options_Visuals.lua` (showCooldownSpiral checkbox)
- `Options_Stats.lua` (search input)
- `FrameManager.lua` (per-bar scale application)
- `BarPool.lua` (isResourceBar pool-leak fix)
- `BarWarden.toc` (ClassPresets.lua, AuraGroups.lua load order)
- `CLAUDE.md` (new patterns documentation)

## Verification

Per CLAUDE.md's "no tests; verification is in-game" convention:

- `luac -p` on all 24+ top-level Lua files: clean.
- `grep` for em dashes across BarWarden code: zero in new content (established project convention; see `feedback_no_em_dashes.md` memory).
- Zero new globals leaked (all symbols scoped to `ns.` or `local`).
- In-game behavioural verification: DK preset loads 4 groups (DK Cooldowns / Diseases / Runes / Runic Power); rune bars fill as runes regenerate; Rogue preset loads combo-point bar that fills 0 to 5; Warlock preset loads soul-shard bar reflecting bag count; `/bw test` preserves existing behaviour (resource bars stay in live state).

## Known v1 limitations

- **Spec awareness deferred.** All presets are class-level. A Feral Druid and a Resto Druid load the same 14 bars, with Feral's unused HoT bars sitting idle (they won't fire for Feral anyway since HoTs aren't cast).
- **Runes use slot-order fallback** for users editing the bar manually. `barConfig.spellId = 1..6` selects the slot; tokens aren't supported for runes.
- **Rune type icons** rely on `GetRuneType(slot)`. If a private server doesn't implement `GetRuneType`, fallback to Blood rune icon.
- **Soul shard maximum** defaults to 10; user can override via `barConfig.maxValue` but the options UI doesn't expose it yet (edit bar JSON manually or wait for the per-bar-editor BuildSettings refactor).

## Follow-up / deferred

- `Options_Bars.lua` `CreateBarsTab` is still a 900+ line function. Refactoring the per-bar editor section to `BuildSettings` (matching the Phase 4 visuals-tab conversion) is flagged for a dedicated session: **"Options_Bars per-bar editor conversion to BuildSettings"**.
- Smart visibility conditions (mounted / resting / vehicle / instance-only, ECM pattern) remain deferred.
- Milestone ticks at 30s / 10s / 3s (CDLine pattern) remain deferred.
- Centre-screen pulse alert mode (Doom_CooldownPulse pattern) remains deferred.
- Raid-coordinator mode (Hermes pattern) remains deferred indefinitely (large scope shift, identity change).
- Audio features remain a hard non-goal per user direction (`feedback_no_audio.md`).
