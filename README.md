# BarWarden

[![Download Latest](https://img.shields.io/github/v/release/powerfulqa/BarWarden?label=Download&style=for-the-badge)](https://github.com/powerfulqa/BarWarden/releases/latest/download/BarWarden.zip) [![Downloads](https://img.shields.io/github/downloads/powerfulqa/BarWarden/total?label=Downloads&style=for-the-badge)](https://github.com/powerfulqa/BarWarden/releases)

BarWarden is a bar tracking addon for World of Warcraft 3.3.5a (Wrath of the Lich King). It lets you create timer bars that track your spell cooldowns, buffs, debuffs, procs, and item cooldowns. You can organise bars into groups, move them anywhere on screen, and customise how they look.

When a spell goes on cooldown or a buff is applied, the matching bar fills up and counts down so you always know exactly when something is ready or about to expire.

---

## What Can It Do?

- **Track your abilities** with 5 different modes: Cooldown, Buff, Debuff, Proc, and Item
- **Organise bars into groups** like "Cooldowns", "Target Debuffs", or "Buffs" (up to 20 groups, 30 bars each)
- **Multi-column layouts** so you can display bars in 1 to 4 columns per group
- **13 bar textures** to choose from, including Flat, Smooth, Gloss, Aluminium, and more
- **15 fonts** including 5 built-in WoW fonts and 10 custom ones like Adventure, Heroic, and Transformers
- **Colour your bars** by class, by tracking mode, or pick your own colour (with per-bar overrides)
- **Per-bar text and icon control** so each bar can show or hide its name and spell icon independently
- **Set conditions** on bars so they only show in combat, below a health threshold, in a group, and more
- **Account-wide profiles** so you can save a setup on one character and load it on another
- **Drag bars to reorder** them within a group when frames are unlocked
- **Animated spark** that follows the bar as it counts down
- **Smooth fading** between active and inactive states
- **Bar linger effect** so bars stay visible briefly after a cooldown or buff expires
- **Minimap button** you can drag around your minimap for quick access
- **Track multiple spells on one bar** using commas, like `Rupture, Garrote`
- **Settings saved per character** so each of your characters can have their own layout

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

- Click the **BarWarden minimap button** near your minimap.
- Or type `/bw` in chat.

### Creating a group

Groups are containers that hold your bars. Think of a group as a category, for example "Cooldowns", "Target Debuffs", or "Buffs".

1. Open the settings panel with `/bw`.
2. Go to the **Bars / Groups** tab.
3. Click **Add** to create a new group. It will appear on screen with a default name.
4. Give it a name in the Group Name field and tweak the width, scale, and columns to your liking.

### Adding a bar

Each bar tracks one spell, buff, debuff, proc, or item:

1. Select a group on the left, then click **Add Bar** on the right.
2. Pick a **Track Mode** from the dropdown (Cooldown, Buff, Debuff, Proc, or Item).
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
| `/bw debug` | Prints addon state to chat (handy for bug reports) |
| `/bw scan` | Tests spell lookups for each bar and prints results |
| `/bw trackers` | Shows live tracker state for all bars |
| `/bw help` | Lists all available commands |

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

---

## Settings Tabs

### General

- Turn the addon on or off
- Lock or unlock all group frames
- Show or hide the minimap button

### Bars / Groups

**Left panel (Group settings):**
- Add, Delete, or Duplicate groups
- Set the group name, width, scale (0.5x to 2.0x), and columns (1 to 4)

**Right panel (Bar list and editor):**
- Add Bar, Delete Bar, and reorder bars with Up/Down buttons
- Configure bar name, spell name or ID, track mode, and target unit
- Toggle "Only Mine" filtering for debuffs
- Set conditions: Combat Only, Out of Combat Only, In Group, In Raid, Hide When Inactive, Show Empty, Health Below %, Require Buff
- Per-bar display options: Linger Time, Show Bar Name, Show Icon, Colour Override

### Visuals

**Bar Dimensions:**
Bar Height (4 to 60), Bar Spacing (0 to 30)

**Group Opacity:**
Background Opacity (0 to 1), Border Opacity (0 to 1)

**Bar Visuals:**
Choose between Class Colour, Track Mode Colour, or Custom Colour. When using Custom, a colour swatch lets you pick any colour. You can also enable per-bar colour overrides so individual bars can have their own colour. Pick from 13 bar textures or enter a custom texture path.

**Text Options:**
Pick a text position (Left or Right), choose from 15 fonts, set the font size (6 to 24), and pick a text format: Name + Duration, Name Only, Duration Only, Name + Stacks, Stacks Only, or None.

**Icon:**
Icon Size (0 to 60), Icon Position (Left or Right)

**Opacity:**
Set Active and Inactive opacity (0 to 1), toggle Fade When Inactive, and adjust the Fade Speed (0.1 to 2.0).

### Profiles

Save and Load bar layouts. Profiles are account-wide.

- Save your current setup under a name
- Load a saved profile to switch layouts
- Delete or rename profiles
- Export and import profiles to share between characters
- Reset everything back to factory defaults

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

Type `/bw debug` and include the output if you need to report a problem. If things are really broken, you can reset to factory defaults by deleting `WTF/Account/<your-account>/SavedVariables/BarWardenDB.lua` and reloading.

---

## Requirements

- World of Warcraft 3.3.5a (Interface version 30300)
- No external library dependencies

---

*Author: Serv*
