# BarWarden

BarWarden is a customizable cooldown, buff, and debuff bar tracking addon for World of Warcraft 3.3.5a (Wrath of the Lich King). It displays timed bars for spells, buffs, debuffs, procs, and item cooldowns in movable frames that you arrange anywhere on screen. Each bar shows the spell name, remaining time, icon, and a spark indicator as the timer counts down.

---

## Installation

1. Download or clone this repository.
2. Copy the **inner `BarWarden` folder** — not the repository root — into your WoW AddOns directory:
   ```
   World of Warcraft/Interface/AddOns/BarWarden/
   ```
   The final path to the addon manifest must be:
   ```
   Interface/AddOns/BarWarden/BarWarden.toc
   ```
   > **Common mistake:** If you copy the entire repository folder, you end up with `AddOns/barwarden/BarWarden/BarWarden.toc` — one folder too deep. WoW will not detect the addon. Only the inner `BarWarden` folder belongs in AddOns.
3. Start or restart World of Warcraft.
4. At the character select screen, click **AddOns** and ensure **BarWarden** is checked.
5. Log in. The BarWarden minimap button will appear, and typing `/bw` will open the configuration panel.

---

## Getting Started

### Opening the options panel

- Click the **BarWarden minimap button** (a green leaf icon near your minimap).
- Or type `/bw` in chat.

### Creating your first frame

Frames are containers that hold bars. Think of a frame as a group — for example, "My Cooldowns" or "Target Debuffs".

1. Open the options panel (`/bw`).
2. Go to the **Bars/Groups** tab.
3. Click **New Frame**. A new frame appears on screen, labeled with a default name.
4. Rename it if you like, then click **Add Bar** to create your first tracking bar.

### Adding a bar

Each bar tracks one spell, buff, debuff, proc, or item:

1. In the **Bars/Groups** tab, select a frame and click **Add Bar**.
2. Set the **Track Mode** (see [Tracking Modes](#tracking-modes) below).
3. Enter the spell name or spell ID in the **Spell** field.
4. Click **Save**. The bar will activate the next time the tracked event is active.

### Moving frames

Frames are locked by default. To move them:

- Type `/bw lock` to unlock all frames, then drag them where you want.
- Type `/bw lock` again to re-lock.

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
| `/bw debug` | Print addon state to chat (useful for bug reports) |
| `/bw help` | Show this command list in chat |

`/barwarden` is an alias for `/bw` and works identically.

---

## Tracking Modes

### Cooldown

Tracks a spell's cooldown timer. The bar fills as the cooldown expires. Global cooldown (GCD) events under 1.5 seconds are automatically filtered out so the bar only activates for meaningful cooldowns.

**Example:** Track Kidney Shot (Rogue finishing move).
- Track Mode: `Cooldown`
- Spell: `Kidney Shot` or `408`

### Buff

Tracks a buff on the player. The bar shows the remaining duration of the buff.

**Example:** Track Slice and Dice.
- Track Mode: `Buff`
- Spell: `Slice and Dice`

### Debuff

Tracks a debuff on the current target. By default only debuffs cast by you are tracked. Toggle **Only Mine** off to track debuffs from any source.

**Example:** Track Rupture on your target.
- Track Mode: `Debuff`
- Spell: `Rupture`

### Proc

Tracks short-duration proc buffs (typically 3–15 seconds). Procs are treated the same as buffs internally but are intended for reactive abilities that require fast recognition.

**Example:** Track the Art of War proc (Paladin).
- Track Mode: `Proc`
- Spell: `The Art of War`

### Item

Tracks an item's cooldown by item ID. The bar fills as the item becomes available again.

**Example:** Track Hyperspeed Accelerators (engineering glove tinker).
- Track Mode: `Item`
- Spell: `54998` (item ID)

To find an item ID, hover over it in your bags and look it up on a WoW database site.

### Custom

Tracks any condition using a Lua expression. The expression must return up to six values: `isActive, remaining, duration, icon, name, stacks`. Use this for advanced tracking not covered by the other modes.

**Example:** Show a bar when your target is below 20% health.
```lua
local hp = UnitHealth("target")
local max = UnitHealthMax("target")
if max > 0 and hp / max < 0.2 then
    return true, hp / max * 10, 10, nil, "Execute Range"
end
```

Available globals in custom expressions: `UnitBuff`, `UnitDebuff`, `UnitHealth`, `UnitHealthMax`, `UnitPower`, `UnitPowerMax`, `GetSpellCooldown`, `GetItemCooldown`, `GetTime`, `UnitExists`, `UnitIsUnit`.

---

## Visual Settings

Open the **Visuals** tab in the options panel to configure how bars look.

### Bar textures

| Texture | Description |
|---------|-------------|
| Flat | Solid single-color fill |
| Glow | Soft gradient with a glow effect |
| Metal | Metallic sheen |
| Leather | Earthy, textured look |

### Presets

Apply a preset to quickly configure bar size, icon, text, and texture:

| Preset | Bar size | Icon | Text | Spark |
|--------|----------|------|------|-------|
| Rogue | 160 × 14 | Yes | Yes | No |
| NeedToKnow | 220 × 22 | Yes | Yes | Yes |
| Minimalist | 180 × 8 | No | No | No |

### Color modes

| Mode | Description |
|------|-------------|
| Class | Bars use your character's class color |
| Track Mode | Each tracking mode (Cooldown, Buff, etc.) has its own color |
| Custom | All bars use a single color you choose |

---

## Frame Groups

A **frame** is a container that holds one or more bars. Each frame can be independently positioned, scaled, and shown or hidden.

### Creating and managing frames

All frame management is in the **Bars/Groups** tab:

- **New Frame** — Create a new empty frame.
- **Duplicate** — Copy a frame and all its bars to a new frame offset slightly on screen.
- **Delete** — Remove a frame and all its bars permanently.

### Locking and unlocking

Locked frames cannot be dragged. Use `/bw lock` or the checkbox in the General tab to toggle.

When unlocked, you can drag frames freely. Enable **Snap to Grid** in General settings to snap positions to a configurable grid increment.

### Scaling

Each frame has an independent scale (0.5× to 2.0×). Set it per-frame in the Bars/Groups tab.

### Reordering bars

While frames are unlocked, you can drag individual bars up and down within a frame to reorder them.

---

## Profile System

Profiles let you save your entire configuration under a name and switch between setups — for example, a raiding layout vs. a PvP layout.

All profile management is in the **Profiles** tab:

1. **Save Profile** — Enter a name and click Save. The current settings (frames, bars, visuals) are stored under that name.
2. **Load Profile** — Select a saved profile from the list and click Load. Your current settings are replaced.
3. **Import / Export** — Use the text box to copy a profile as text (Export) or paste one in from another character (Import).
4. **Reset to Defaults** — Wipe all frames and profiles and return to factory defaults.

Profiles are saved per-character in `BarWardenDB` inside `WTF/Account/.../SavedVariables/`.

---

## Troubleshooting

**Addon does not appear in the Interface > AddOns menu**

The most common cause is incorrect folder nesting. Verify the path is:
```
Interface/AddOns/BarWarden/BarWarden.toc
```
Not:
```
Interface/AddOns/barwarden/BarWarden/BarWarden.toc   (wrong — extra level)
```

**Bars are not showing**

1. Check the addon is enabled — type `/bw enable`.
2. Check frames are visible — type `/bw show`.
3. A frame may be positioned off-screen. Type `/bw reset` to rebuild frames at their saved positions.
4. Make sure you have cast the tracked spell at least once this session so WoW provides cooldown data.

**Minimap button is missing**

Open the options panel with `/bw`, go to the **General** tab, and ensure **Show Minimap Icon** is checked.

**Lua errors in chat**

Type `/bw debug` and note the output. Include this output when reporting issues. To reset to factory defaults, delete `WTF/Account/<your-account>/SavedVariables/BarWardenDB.lua` and reload.

---

## Requirements

- World of Warcraft 3.3.5a (Interface version 30300)
- No external library dependencies

---

*Author: Serv — Version 1.0.0*
