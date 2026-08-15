# BarWarden

[![Download Latest](https://img.shields.io/github/v/release/powerfulqa/BarWarden?label=Download&style=for-the-badge)](https://github.com/powerfulqa/BarWarden/releases/latest/download/BarWarden.zip) [![Downloads](https://img.shields.io/github/downloads/powerfulqa/BarWarden/total?style=for-the-badge&logo=github)](https://github.com/powerfulqa/BarWarden/releases)

BarWarden is a bar tracking addon for World of Warcraft 3.3.5a (Wrath of the Lich King). It lets you create timer bars that track your spell cooldowns, buffs, debuffs, procs, and item cooldowns. You can organise bars into groups, move them anywhere on screen, and customise how they look.

When a spell goes on cooldown or a buff is applied, the matching bar fills up and counts down so you always know exactly when something is ready or about to expire.

---

## What Can It Do?

- **Track your abilities** with 16 different modes: Cooldown, Buff, Debuff, Proc, Item, Enchant MH, Enchant OH, Totem, Combo Points, Runes, Runic Power, Soul Shards, Health, Mana, Energy, and Rage
- **Spec-aware starter profiles** for all 30 WotLK talent specs - one-click load of curated cooldowns, procs, and resources tailored to your active spec (falls back to class-level if no talents are spent)
- **Class resource trackers** for Combo Points (rogue/druid), Runes (DK), Runic Power (DK), and Soul Shards (warlock) that fill as the resource builds rather than counting down
- **Organise bars into groups** like "Cooldowns", "Target Debuffs", or "Buffs" (up to 20 groups, 30 bars each)
- **Multi-column layouts** so you can display bars in 1 to 10 columns per group
- **Sort bars dynamically** by remaining time, alphabetically, manual order, or As They Come (each bar keeps the spot it first appeared in until it fades) per group
- **Growth direction** per group: bars can grow downward (default) or upward from the anchor point
- **Colour-by-time** bars transition green to yellow to red as the timer counts down (per-bar, configurable thresholds)
- **Glow on ready** bars flash when a cooldown finishes or a buff expires so you know the spell is available
- **Pulse on ready** optionally flashes the spell icon at the centre of the screen when a cooldown completes, so you notice even if the bar is at the edge of your view
- **Bar Alerts** flash the bar, turn it a colour you pick, or both once the timer gets close to running out. Set the threshold as a fixed number of seconds or as a percent of the buff's full length, so the same setting works for a short cooldown and a half-hour buff alike
- **Cooldown spiral overlay** on bar icons gives a second visual read of the remaining time
- **Aura equivalency groups** like `@Stunned`, `@Bleeding`, `@Silenced`, `@Feared`, `@Rooted` - one bar tracks any spell in that group
- **Auto-tracking groups** - point a group at all buffs or all debuffs, on you
  or on your target, and it fills itself. No need to name the spell, so boss
  debuffs and unfamiliar procs get a bar too. Leave out long buffs like food
  and flasks, cap how many show at once, and optionally skip anything you
  already track elsewhere. Bring back things with no timer, like class buffs,
  if you want them included, and keep each bar in the same spot instead of
  letting them reorder as timers count down. Alt-click a bar's icon to hide
  just that spell from that group, with a list to bring one back or clear
  them all.
- **Resource groups** - point a group at "Health and power" instead, and it
  shows your health, whatever power you are currently using (it follows a
  druid through every form change live), and your class resources, with
  nothing to name by hand. Bars use the game's own colours by default (blue
  mana, red rage, yellow energy, and so on). Pin extra resources you always
  want visible, in the order you tick them, each with its own colour if you
  want one, and pick how the numbers are shown: amount and total, percent,
  or both.
- **LibSharedMedia support** gives access to textures and fonts from all LSM-compatible addons on your client, plus BarWarden's own 13 bar textures and 15 fonts
- **5 duration display styles**: seconds with decimal, whole seconds, min:sec, short text, or auto-adapting
- **Colour your bars** by class, by tracking mode, or pick your own colour (with per-bar overrides)
- **Per-bar text and icon control** so each bar can show or hide its name and spell icon independently
- **Per-bar scale override** for bars that need to stand out larger (or shrink smaller) than their group default
- **Icon crop** trims border pixels to prevent stretching on non-square bars
- **Per-group conditions** hide an entire group at once (hide when inactive, combat only, mounted, resting, vehicle, instance only) instead of ticking every bar individually
- **Set conditions** on bars so they only show in combat, below a health threshold, in a group, for a specific class, and more
- **Smart visibility** hides bars automatically while mounted, resting, in a vehicle, or only shows them inside dungeons and raids
- **Auto-prompt on first login** offers to load your spec starter profile when you log in on a fresh character with no bars configured
- **Test mode** shows all bars with fake 30s timers so you can preview your layout without triggering spells
- **Account-wide profiles** so you can save a setup on one character and load it on another
- **Copy and paste bars** between groups with the Dupe/Paste buttons
- **Drag bars to reorder** them within a group when frames are unlocked
- **Animated spark** that follows the bar as it counts down
- **Bar linger effect** so bars stay visible briefly after a cooldown or buff expires
- **Minimap button** you can drag around your minimap for quick access
- **Track multiple spells on one bar** using commas, like `Rupture, Garrote`
- **Settings saved per character** so each of your characters can have their own layout
- **Activity Tracker** passively monitors every cooldown, buff, debuff, enchant, and totem on your character - discover what to track, then create bars directly from the stats screen
- **Create Bar from stats** select any discovered spell in the Activity Tracker and add it as a bar to any group with one click
- **Live search** on the Activity Tracker so you can filter hundreds of detected effects by name
- **Bug report command** generates a copyable diagnostic snapshot for easy troubleshooting
- **Minimap button right-click** to quickly enable or disable the addon
- **Live-reactive settings** - changes in the options panel apply to the bars on the spot, no disable/re-enable needed
- **Update reminder** tells you in chat when someone in your group or guild is running a newer BarWarden, with a copyable download link (toggle in the General tab)
- **Inline help tooltips** on most per-bar and visual settings - hover any slider, dropdown, or text field for a plain-English explanation
- **Spell tooltip on icon hover** optionally shows the full spell or item tooltip when you mouse over a bar's icon (toggle in Visuals tab)
- **In-game Help tab** with a collapsible FAQ covering tracking modes, conditions, profiles, and troubleshooting, plus `[?]` icons next to the main settings that jump straight to the matching answer

---

## Installation

1. Download or clone this repository.
2. Copy the repository folder into your WoW AddOns directory and make sure it is named `BarWarden`:
   ```
   World of Warcraft/Interface/AddOns/BarWarden/
   ```
   The path to the `.toc` file should look like this:
   ```
   Interface/AddOns/BarWarden/BarWarden.toc
   ```
3. Start or restart World of Warcraft.
4. At the character select screen, click **AddOns** and make sure **BarWarden** is ticked.
5. Log in. You will see a BarWarden minimap button appear, and you can type `/bw` to open the settings.

---

## Getting Started

### Opening the settings

- **Left-click** the BarWarden minimap button near your minimap.
- **Right-click** the minimap button to quickly enable or disable the addon (the icon desaturates when disabled).
- Or type `/bw` in chat.

Once the panel is open, **hover the mouse over any slider, dropdown, or text field** that isn't self-evident for a tooltip explaining what it does. Most edits commit as soon as you click away from the field, so you don't need to remember to press Enter on every change.

### Creating a group

Groups are containers that hold your bars. Think of a group as a category, for example "Cooldowns", "Target Debuffs", or "Buffs".

1. Open the settings panel with `/bw`.
2. Go to the **Bars / Groups** tab.
3. Click **Add** to create a new group. It will appear on screen with a default name.
4. Give it a name in the Group Name field and tweak the width, scale, and columns to your liking.

### Adding a bar

Each bar tracks one spell, buff, debuff, proc, or item:

1. Select a group on the left, then click **Add** on the right.
2. Pick a **Track Mode** from the dropdown (Cooldown, Buff, Debuff, Proc, Item, Enchant MH, Enchant OH, or Totem).
3. Choose a **Target** (player, target, focus, pet, or mouseover).
4. Type the spell name or spell ID into the **Spell Name or ID** field.
5. The bar will start tracking automatically the next time that spell or effect is active.

### Moving groups around

Groups are locked in place by default so you don't accidentally move them during gameplay. To reposition them:

- Type `/bw lock` to unlock everything, then drag groups wherever you want.
- Type `/bw lock` again to lock them back in place.

---

## Slash Commands

| Command | What it does |
|---------|-------------|
| `/bw` | Opens the settings panel |
| `/bw enable` | Turns the addon on |
| `/bw disable` | Turns the addon off |
| `/bw lock` | Toggles frame lock (locked frames cannot be dragged) |
| `/bw reset` | Rebuilds all frames and resets positions |
| `/bw test` | Toggle test mode (fake 30s timers on all bars) |
| `/bw debug` | Prints addon state to chat (handy for bug reports) |
| `/bw scan` | Tests spell lookups for each bar and prints results |
| `/bw trackers` | Shows live tracker state for all bars |
| `/bw stats` | Shows per-bar activation counts and uptime |
| `/bw bugreport` | Opens a copyable diagnostic report window |
| `/bw help` | Lists all available commands |
| `/bw restore` | Puts back your previous layout from the last backup |
| `/bw importv1` | Imports bars from a separate BarWarden install |
| `/bw commtest` | Self-tests the version-update messaging (diagnostic) |

You can also use `/barwarden` instead of `/bw` if you prefer.

---

## Tracking Modes

### Cooldown

Tracks when one of your spells is on cooldown. The bar fills and counts down until the spell is ready again. Short global cooldown (GCD) triggers under 1.5 seconds are automatically ignored so the bar only reacts to real cooldowns.

**Example:** Track Evasion.
- Track Mode: `Cooldown` | Target: `player` | Spell: `Evasion`

### Buff

Tracks a buff on you or another unit. The bar shows how long the buff has left and its stack count.

**Example:** Track Slice and Dice on yourself.
- Track Mode: `Buff` | Target: `player` | Spell: `Slice and Dice`

You can track multiple buffs on one bar by separating them with commas: `Slice and Dice, Recuperate`

### Debuff

Tracks a debuff on your target or another unit. By default it only shows debuffs you applied. Untick **Only Mine** if you want to see debuffs from all sources.

**Example:** Track Rupture on your target.
- Track Mode: `Debuff` | Target: `target` | Spell: `Rupture`

### Proc

Tracks short-lived proc buffs on your character. This works the same as Buff mode but always targets yourself, making it handy for reactive abilities.

**Example:** Track the Art of War proc (Paladin).
- Track Mode: `Proc` | Spell: `The Art of War`

### Item

Tracks an item's cooldown using its item ID or name. Useful for trinkets, engineering tinkers, or your Hearthstone.

**Example:** Track Hearthstone cooldown.
- Track Mode: `Item` | Spell: `6948`

To find an item ID, hover over the item and look it up on a WoW database site like Wowhead.

### Enchant

Tracks temporary weapon enchants like poisons, sharpening stones, or shaman weapon buffs. Select **Enchant MH** for your mainhand or **Enchant OH** for your offhand. The Spell field is not used for enchants. Use the Bar Name field to label it (e.g. "Deadly Poison").

**Example:** Track mainhand and offhand poisons.
- Track Mode: `Enchant MH` | Bar Name: `Deadly Poison`
- Track Mode: `Enchant OH` | Bar Name: `Instant Poison`

### Totem

Tracks active totems by name or slot number (1-4). Useful for shamans tracking totem uptime.

**Example:** Track Mana Tide Totem.
- Track Mode: `Totem` | Spell: `Mana Tide Totem`

You can also use a slot number: `1` for Fire, `2` for Earth, `3` for Water, `4` for Air.

### Class Resources

Four resource trackers for class-specific mechanics. Unlike time-based trackers, these **fill as the resource builds** rather than counting down. The bar shows current / maximum and updates event-driven.

- **Combo Points** - Rogue and Druid (cat form). Fills from 0 to 5 as combo points accumulate on your target.
- **Runes** - Death Knight. Tracks one of six rune slots; fills as the rune regenerates, stays full when ready, shows countdown text while on cooldown. Use `1-6` in the Spell field for the slot.
- **Runic Power** - Death Knight. Fills from 0 to 100 (or higher with talents).
- **Soul Shards** - Warlock. Tracks current soul shard count in your bag.

**Example:** Track combo points on your current target.
- Track Mode: `Combo Points`

Class resource bars are pre-populated by the class starter profiles - see the Profiles tab.

### Character Resources

Four more resource trackers, this time for the plain stats every character has. Same fill-not-countdown rendering as Class Resources above; the Spell/Target fields are not used.

- **Health** - fills with your current health.
- **Mana**, **Energy**, **Rage** - fill with the matching power pool, whether or not it is the one you are currently using.

**Example:** Track your own health.
- Track Mode: `Health`

See **Resource Groups** below for a group that shows these (and your class resources) automatically, without adding any bars by hand.

### Resource Groups

Set a group's Auto Track to "Health and power" and it fills itself: Health
first, then whatever power you are currently using (this is what makes it
follow a druid through Bear, Cat, and Caster form live), then your class
resources if you have any (combo points, runes, runic power, soul shards),
with nothing to name by hand. Bars use the game's own colours by default -
a blue mana bar, a red rage bar, a yellow energy bar, and so on - the same
convention Blizzard's own frames use.

"Health and power (target)" does the same for whatever you have targeted:
its health, then its current power. Combo Points show here too, alongside
the player resource group, since they are always your points on your
current target either way you look at them. A target with nothing selected
just shows nothing, the same as an empty group.

- **Always Show Mana / Rage / Energy** - pin a power you always want
  visible, even when it is not the one you are currently using. Bars appear
  in the order you tick them, top to bottom; unticking one and re-ticking it
  later moves it to the end rather than back to where it used to be. Each
  pin gets its own colour swatch, which beats both the group's Custom Bar
  Colour and the default power colour above. Works the same on the target
  resource group, pinning the target's power instead of yours.
- **Show Icon** - show or hide the resource icon on this group's bars.
- **Value Text** - how each bar's number is shown: Current / Max (`4200/5100`),
  Percent (`82%`), or Both (`4200/5100 (82%)`).

Unlike an aura-tracking group, there is nothing to skip by duration, filter
to your own casts, or ban one spell from: those settings hide for a
resources group since none of them apply.

A resource group shows the same health and power the default player frame
already does, and a target resource group shows the same thing the default
target frame does. If you'd rather not see either twice, tick Hide Blizzard
Player Frame and/or Hide Blizzard Target Frame on the General tab - they
are independent, so you can hide either one on its own.

### Aura Equivalency Groups

Instead of listing every crowd-control spell by hand, you can use a single group token. These expand automatically at scan time:

| Token | Matches |
|-------|---------|
| `@Stunned` | All stuns (Cheap Shot, Kidney Shot, Hammer of Justice, etc.) |
| `@Bleeding` | All bleeds (Rupture, Garrote, Rip, Rend, Deep Wounds, etc.) |
| `@Silenced` | All silences (Counterspell, Silence, Spell Lock, etc.) |
| `@Incapacitated` | All incapacitates (Sap, Gouge, Repentance, etc.) |
| `@Feared` | All fears (Fear, Scare Beast, Psychic Scream, etc.) |
| `@Rooted` | All roots (Frost Nova, Entangling Roots, Freezing Trap, etc.) |
| `@MovementSlowed` | All slows (Hamstring, Piercing Howl, Frostbolt, etc.) |
| `@Disarmed` | All disarms (Disarm, Dismantle, etc.) |

**Example:** One bar that shows any stun on your target.
- Track Mode: `Debuff` | Target: `target` | Spell: `@Stunned`

You can combine group tokens with regular spell names using commas: `@Stunned, Blind`.

---

## Settings Tabs

### General

- Turn the addon on or off
- Lock or unlock all group frames
- Show or hide the minimap button
- Get notified when a newer version is available
- Hide the default player frame (handy if you use a Resource Group and don't
  want your health and power shown twice), and the Death Knight rune display
  along with it
- Hide the default target frame the same way, independently, including the
  combo point display
- A full list of slash commands, each with a Run button to fire it straight from the panel

### Bars / Groups

**Left panel (Group settings):**
- Add, Delete, or Duplicate groups
- Group Name and Show Group Name toggle
- Width, Scale, Columns
- Background Opacity, Border Opacity
- Sort Mode (Manual, Remaining Time, Alphabetical, As They Come)
- Growth Direction (Down, Up)
- Bar Overrides: Bar Texture, Text Format, Bar Style (Countdown, On or Off), Custom Bar Colour, Show Icons Only (a compact grid of spell icons instead of bars, sized with the Width slider), Custom Stack Text (its own size and colour for the stack count), and Custom Bar Effects (Glow on Ready, Pulse on Ready, Linger Time), all for the whole group at once - Custom Bar Effects is also the only way to turn these on for an auto-tracking group
- Auto Track: fill the group from buffs or debuffs, or from health and power (yours or your target's), instead of adding bars by hand. Either Health and power choice adds its own Always Show Mana/Rage/Energy tickboxes (in the order you tick them, each with an optional colour swatch), a Show Icon toggle, and a Value Text dropdown (amount and total, percent, or both) in place of the buff/debuff-only settings
- Group Conditions (Hide When Inactive, Combat Only, Out of Combat Only, Hide Mounted, Hide Resting, Hide In Vehicle, Only In Instance)

**Right panel (Bar list and editor):**
- Add, Delete, reorder (Up/Dn), and copy/paste (Dupe/Paste) bars
- Configure bar name, spell name or ID, track mode, and target unit
- Toggle "Only Mine" filtering for debuffs
- Set conditions: Combat Only, Out of Combat Only, In Group, In Raid, Hide While Mounted, Hide While Resting, Hide In Vehicle, Only In Instance, Hide When Inactive, Health Below %, Require Buff, Require Class
- Per-bar display options: Linger Time, Show Bar Name, Show Icon, Show as On or Off, Bar Darkness, Sparkle Alert with Alert When (seconds or percent), Alert Style (sparkle, colour, or both) and Alert Colour, Colour Override, Colour by Time with high/med thresholds, Glow on Ready with duration, Pulse on Ready, Crop Icon, Scale Override, Custom Stack Text (its own size and colour for the stack count)

#### Useful Per-Bar Options Explained

- **Linger Time** - number of seconds a bar keeps showing at 0 after its
  cooldown or buff has expired, before it fades out. Handy when paired
  with *Glow on Ready* so you can clearly see *the moment* a spell came
  off cooldown. `0` means the bar disappears the instant the timer runs
  out. Example: set to `2` on a Kick bar so you notice immediately when
  interrupt is back.
- **Health Below %** - only show the bar when your own HP drops below
  this percentage. Useful for execute-range spells (Hammer of Wrath,
  Kill Shot, Execute) or panic buttons (Healthstone, Nitro Boosts) so
  they stay out of the way until they're actually relevant. Leave
  empty to disable. Example: `30` for a Hammer of Wrath bar, `50` for
  Healthstone.
- **Require Buff** - only show the bar while you have the named buff
  active. Accepts a buff name or a spell ID. Useful for state-gated
  abilities: stealth-only cooldowns that only show while stealthed,
  bear-form abilities that only show in bear form, proc reactions
  that only show while the proc is up. Leave empty to disable.
  Example: `Stealth` on Ambush, `Clearcasting` on your next free cast.
- **Require Class** - pin a bar to a specific class so it only shows
  when played on (for example) a Rogue. Used internally by the class
  starter profiles so copying a preset across characters doesn't leak
  rune bars onto non-DK characters. Accepts a class token like
  `ROGUE`, `DEATHKNIGHT`, `WARLOCK`, etc.
- **Scale Override** - per-bar scale multiplier. Leave at 1.0 to match
  the group's scale; set higher to make a critical cooldown stand out,
  or lower to tuck ambient trackers into the corner.

### Visuals

Global settings that apply to all bars.

**Bar Dimensions:** Bar Height, Bar Spacing

**Bar Visuals:** Colour Mode (Class, Track Mode, Custom), Default Colour swatch, Per-Bar Colour Override, Bar Texture (13 built-in textures + LibSharedMedia textures + custom path)

**Text Options:** Text Position (Left, Right), Font (15 built-in + LibSharedMedia fonts), Font Size, Text Format (Name+Duration, Name Only, Duration Only, Name+Stacks, Stacks Only, None), Duration Style (seconds.ms, seconds, min:sec, short text, auto), Show Stack Count (the number on a bar's icon when something stacks two or more times, whatever the text format), Stack Text Size, Stack Text Colour

Groups can override the **Text Format**, the bar texture and colour, and the
**Bar Style** for their own bars (Bar Control > Groups > Bar Overrides). Bar
Style picks Countdown (the default, ticks down) or On or Off (fills while the
tracked thing is active, empty the rest of the time, no countdown); it can
also be set per bar with **Show as On or Off** above. The same section has
a **Show Icons Only** toggle that draws a plain grid of spell icons for that 
group instead of bars, no bar or text underneath; size the icons with the Width 
slider. A **Custom Stack Text** toggle gives the group (or, in the bar
editor, a single bar) its own Stack Text Size and Stack Text Colour instead
of the addon-wide default; a bar's own setting wins over its group's, which
wins over the Visuals tab. A **Custom Bar Effects** toggle does the same for
Glow on Ready, Pulse on Ready and Linger Time, and is the only way to set
these for an auto-tracking group, since it has no bar list of its own to set
them on. **Hide When Inactive**
under Group Conditions controls the whole group once you use it: ticked hides
every bar while it has nothing to show, unticked keeps them all visible even
where individual bars are set to hide. Leave it alone and each bar decides for
itself.

**Icon:** Icon Size, Icon Position (Left, Right), Crop Icons, Cooldown Spiral overlay

**Bar Opacity:** Active Opacity, Inactive Opacity

### Profiles

Save and Load bar layouts. Profiles are account-wide.

- Save your current setup under a name
- Load a saved profile to switch layouts
- Delete or rename profiles
- Export and import profiles to share between characters
- Reset everything back to factory defaults

**Class Starter Profiles** - pre-curated bar loadouts for all 10 WotLK classes, drawn from the common cooldowns, procs, and resources that matter for each class.

- **Load Class Starter** - replaces your current groups with the preset for your class (or a class you pick)
- **Append Class Starter** - adds the preset's groups alongside your existing ones
- A preview dialog lists what will be added before you commit
- Resource bars (combo points, runes, etc.) are automatically gated to the right class so copying a preset across characters doesn't leak them

### Activity Tracker

Passive monitoring of everything happening on your character. BarWarden automatically detects every cooldown you use, every buff you gain, every debuff you apply, weapon enchants, and totems - no configuration needed.

- **Category filter** dropdown: All, Auras (buffs + debuffs), Buffs, Target Debuffs, Cooldowns, Enchants, Totems
- **Search box** next to the filter - type part of a spell name to narrow the list live
- **Click any column header** (Name / Procs / Uptime, session or all-time) to sort the list - click again to flip ascending/descending; an arrow next to the active column shows the current direction
- **Hover an icon** in the list to see the full WoW spell tooltip
- **Spell icons** displayed alongside each entry for quick identification
- **Live auto-refresh** - the stats panel updates itself every 2 seconds while visible, so session duration, activations, and uptime totals tick live without clicking around
- **Session stats** (activations and uptime) reset every login or `/reload`
- **All-time stats** persist across sessions in SavedVariables
- **Sortable** - defaults to most-active first; click any column header to re-sort
- **Create Bar button** - select any spell, pick a group, and create a pre-configured bar with one click
- **Reset Session** clears current session data
- **Reset All** clears everything (with confirmation)
- Also available via `/bw stats` in chat
- Stores up to 200 unique spells; oldest entries are automatically evicted

### Help

A built-in FAQ covering Getting Started, Tracking Modes, Conditions, Visuals, Profiles, the Activity Tracker, and Troubleshooting. Click a section to expand it. The `[?]` icons next to the main settings jump straight to the matching answer.

---

## Available Bar Textures

| Texture | Description |
|---------|-------------|
| Flat | Solid single-colour fill |
| Smooth | Smooth gradient finish |
| Gloss | Glossy, reflective look |
| Aluminium | Metallic aluminium |
| Armory | WoW Armoury style |
| Graphite | Dark graphite |
| Otravi | Classic Otravi bar texture |
| Striped | Horizontal striped pattern |
| Canvas | Textured canvas material |
| LiteStep | LiteStep UI style |
| Glow | Soft gradient glow |
| Metal | Metal plate |
| Leather | Earthy leather texture |

---

## Troubleshooting

**Addon does not appear in the AddOns menu**

Make sure the path is `Interface/AddOns/BarWarden/BarWarden.toc`. If the folder you copied has a different name (like `barwarden-main` from a GitHub download), rename it to `BarWarden`.

**Bars are not showing**

1. Make sure the addon is enabled: `/bw enable`
2. Your group might have been dragged off screen. Type `/bw reset` to rebuild everything.
3. Check that the bar is enabled and has a valid spell name entered.

**A spell is not being tracked**

Some private servers use different spell IDs than you might expect. Try using the spell name (like `Evasion`) instead of a numeric ID. You can run `/bw scan` to see exactly what the game returns for each bar's spell lookup.

**Minimap button is missing**

Open `/bw`, go to the **General** tab, and tick **Show Minimap Icon**.

**Lua errors showing up**

Type `/bw bugreport` to generate a copyable diagnostic report you can paste into a bug report. You can also try `/bw debug` for a quick chat dump. If things are really broken, you can reset to factory defaults by deleting `WTF/Account/<your-account>/SavedVariables/BarWardenDB.lua` and reloading.

---

## Requirements

- World of Warcraft 3.3.5a (Interface version 30300)
- LibSharedMedia-3.0 is bundled (optional; texture and font dropdowns fall back to built-in lists if LSM is unavailable)

---

*Author: Serv*
