# BarWarden

BarWarden is a customizable cooldown, buff, and debuff bar tracking addon for World of Warcraft 3.3.5a (Wrath of the Lich King). It displays timed bars for spells, buffs, debuffs, procs, and item cooldowns in movable, multi-column group frames that you can arrange anywhere on screen. Each bar shows the spell name, remaining duration, icon, and an animated spark indicator as the timer counts down.

---

## Features

- **6 tracking modes** — Cooldown, Buff, Debuff, Proc, Item, and Custom (Lua expression)
- **Unlimited groups** — Organize bars into named groups (up to 20 groups, 30 bars each)
- **Multi-column layout** — Display bars in 1-4 columns per group
- **13 bar textures** — Flat, Smooth, Gloss, Aluminum, Armory, Graphite, Otravi, Striped, Canvas, LiteStep, Glow, Metal, Leather, plus custom texture support
- **15 fonts** — 5 WoW built-in fonts + 10 custom fonts (Adventure, Bazooka, Cooline, Diogenes, Ginko, Heroic, Porky, Talisman, Transformers, Yellow Jacket)
- **3 style presets** — Rogue, NeedToKnow, and Minimalist one-click styles
- **3 color modes** — Class color, per-track-mode color, or custom color with optional per-bar overrides
- **Flexible text display** — Left/Center/Right alignment, 6 format options (Name + Duration, Name Only, Duration Only, Name + Stacks, Stacks Only, None)
- **Condition system** — Show/hide bars based on combat state, health threshold, group/raid membership, or required buff
- **Profile system** — Save, load, and switch between named configurations
- **Drag-to-reorder** — Unlock frames and drag bars to rearrange within a group
- **Spark animation** — Animated spark follows bar fill progress
- **Fade effects** — Smooth opacity transitions between active and inactive states
- **Bar linger** — Bars can remain visible for a configurable duration after expiring
- **Minimap button** — Draggable minimap icon for quick access to settings
- **Comma-separated tracking** — Track multiple spells on one bar (e.g. `Rupture, Garrote`)
- **Per-character saved variables** — Each character has independent settings

---

## Installation

1. Download or clone this repository.
2. Copy the **inner `BarWarden` folder** (not the repository root) into your WoW AddOns directory:
   ```
   World of Warcraft/Interface/AddOns/BarWarden/
   ```
   The final path to the addon manifest must be:
   ```
   Interface/AddOns/BarWarden/BarWarden.toc
   ```
   > **Common mistake:** If you copy the entire repository folder you end up with `AddOns/barwarden/BarWarden/BarWarden.toc` — one folder too deep. WoW will not detect the addon. Only the inner `BarWarden` folder belongs in AddOns.
3. Start or restart World of Warcraft.
4. At the character select screen, click **AddOns** and ensure **BarWarden** is checked.
5. Log in. The BarWarden minimap button will appear and typing `/bw` will open the configuration panel.

---

## Getting Started

### Opening the options panel

- Click the **BarWarden minimap button** near your minimap.
- Or type `/bw` in chat.

### Creating a group

Groups are containers that hold bars. Think of a group as a category — for example "Cooldowns", "Target Debuffs", or "Buffs".

1. Open the options panel (`/bw`).
2. Go to the **Bars / Groups** tab.
3. Click **Add**. A new group appears on screen with a default name.
4. Rename it in the Group Name field and adjust width, scale, columns, and background opacity.

### Adding a bar

Each bar tracks one spell, buff, debuff, proc, or item:

1. Select a group in the left panel, then click **Add Bar** in the right panel.
2. Set the **Track Mode** dropdown (Cooldown, Buff, Debuff, Proc, Item, or Custom).
3. Set the **Target** dropdown (player, target, focus, pet, mouseover).
4. Enter the spell name or ID in the **Spell Name or ID** field.
5. The bar activates automatically the next time the tracked event is detected.

### Moving groups

Groups are locked by default. To move them:

- Type `/bw lock` to unlock all groups, then drag them where you want.
- Type `/bw lock` again to re-lock.
- Enable **Snap to Grid** in the General tab for precise positioning.

---

## Slash Commands

| Command | Description |
|---------|-------------|
| `/bw` | Open the configuration panel |
| `/bw enable` | Enable the addon |
| `/bw disable` | Disable the addon |
| `/bw lock` | Toggle frame lock (locked frames cannot be dragged) |
| `/bw show` | Toggle visibility of all frames |
| `/bw reset` | Rebuild all frames (resets positions to saved values) |
| `/bw debug` | Print addon state to chat (DB status, bar count, config dump) |
| `/bw scan` | Live-test spell/item lookups for each bar (GetSpellInfo validation) |
| `/bw trackers` | Show live tracker state for all bars (active status, remaining time) |
| `/bw help` | Show command list in chat |

`/barwarden` is an alias for `/bw` and works identically.

---

## Tracking Modes

### Cooldown

Tracks a player spell's cooldown timer. Global cooldown (GCD) events under 1.5 seconds are automatically filtered out.

**Example:** Track Evasion.
- Track Mode: `Cooldown` | Target: `player` | Spell: `Evasion`

### Buff

Tracks a buff on the specified unit. Shows remaining duration and stack count.

**Example:** Track Slice and Dice on yourself.
- Track Mode: `Buff` | Target: `player` | Spell: `Slice and Dice`

You can track multiple buffs on one bar with comma separation: `Slice and Dice, Recuperate`

### Debuff

Tracks a debuff on the specified unit. By default only debuffs cast by you are shown. Toggle **Only Mine** off to track debuffs from any source.

**Example:** Track Rupture on your target.
- Track Mode: `Debuff` | Target: `target` | Spell: `Rupture`

### Proc

Tracks short-duration proc buffs on the player. Identical to Buff mode but always targets the player.

**Example:** Track the Art of War proc.
- Track Mode: `Proc` | Spell: `The Art of War`

### Item

Tracks an item's cooldown by item ID or name.

**Example:** Track Hearthstone cooldown.
- Track Mode: `Item` | Spell: `6948`

### Custom

Tracks any condition using a sandboxed Lua expression. The expression must return: `isActive, remaining, duration, icon, name, stacks`.

**Example:** Show a bar when your target is below 20% health.
```lua
local hp = UnitHealth("target")
local max = UnitHealthMax("target")
if max > 0 and hp / max < 0.2 then
    return true, hp / max * 10, 10, nil, "Execute Range"
end
```

Available globals: `UnitBuff`, `UnitDebuff`, `UnitHealth`, `UnitHealthMax`, `UnitPower`, `UnitPowerMax`, `GetSpellCooldown`, `GetSpellInfo`, `GetItemCooldown`, `GetItemInfo`, `GetComboPoints`, `GetTime`, `UnitExists`, `UnitAffectingCombat`, `pairs`, `ipairs`, `tonumber`, `tostring`, `select`, `math`, `string`.

---

## Configuration Tabs

### General

- Enable/disable the addon globally
- Lock/unlock all group frames
- Show/hide all frames
- Toggle snap-to-grid with configurable grid size
- Show/hide the minimap button

### Bars / Groups

**Left panel — Group settings:**
- Add, Delete, Duplicate groups
- Group name, width, scale (0.5x-2.0x), columns (1-4), background opacity

**Right panel — Bar list and settings:**
- Add Bar, Delete Bar, reorder Up/Down
- Bar name, spell name or ID, track mode, target unit
- Only Mine filter (for debuffs)
- Conditions: Combat Only, Out of Combat Only, In Group, In Raid, Hide When Inactive, Show Empty, Health Below %, Require Buff
- Display overrides: Linger Time, Force Show Icon, Force Show Text, Color Override

### Visuals

**Frame Dimensions:**
- Bar Width (50-400), Bar Height (4-60), Border Size (0-8), Bar Spacing (0-30)

**Icon:**
- Icon Size (0-60), Icon Position (Left / Right)

**Bar Color:**
- Color Mode: Class Color, Track Mode Color, or Custom Color
- Default color swatch (for Custom mode)
- Allow per-bar color override toggle

**Text Options (two-column layout):**
- Show Bar Text toggle
- Text Position: Left, Center, Right, None
- Font: 15 fonts available
- Font Size: 6-24
- Text Format: Name + Duration, Name Only, Duration Only, Name + Stacks, Stacks Only, None

**Style Presets:** Rogue, NeedToKnow, Minimalist (one-click apply)

**Bar Texture:** 13 textures + Custom path option

**Opacity:**
- Active Opacity (0-1), Inactive Opacity (0-1)
- Fade When Inactive toggle, Fade Speed (0.1-2.0)

### Profiles

- Save current configuration under a name
- Load a saved profile (replaces current settings)
- Delete or rename profiles
- Reset to factory defaults

---

## Bar Textures

| Texture | Style |
|---------|-------|
| Flat | Solid single-color fill |
| Smooth | Smooth gradient finish |
| Gloss | Glossy, reflective look |
| Aluminum | Metallic aluminum |
| Armory | WoW Armory style |
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

Verify the path is `Interface/AddOns/BarWarden/BarWarden.toc` — not nested one level deeper.

**Bars are not showing**

1. Check the addon is enabled: `/bw enable`
2. Check frames are visible: `/bw show`
3. A group may be off-screen: `/bw reset` rebuilds all frames at saved positions.
4. Check that the bar is enabled and has a valid spell name entered.

**Spell not tracking**

Some private servers return different spell IDs. Use the spell name (e.g. `Evasion`) instead of the numeric ID. Run `/bw scan` to see what the game returns for each bar's spell lookup.

**Minimap button is missing**

Open `/bw`, go to **General**, and check **Show Minimap Icon**.

**Lua errors**

Type `/bw debug` and include the output when reporting issues. To reset to factory defaults, delete `WTF/Account/<account>/SavedVariables/BarWardenDB.lua` and reload.

---

## Requirements

- World of Warcraft 3.3.5a (Interface version 30300)
- No external library dependencies

---

*Author: Serv — Version 1.0.0*
