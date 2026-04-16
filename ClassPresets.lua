local addonName, ns = ...

-- ============================================================================
-- ClassPresets.lua: per-class starter profiles
--
-- A curated minimum-viable bar layout per class. Loaded on demand via the
-- "Load Class Starter" button in Options_Profiles.lua. The loader replaces
-- the active profile's `frames` table with a deep-copied, defaults-filled
-- version of the preset below. Existing user bars are overwritten (the UI
-- shows a confirmation dialog before doing so).
--
-- Curation sources (all files in 3.3.5.a\):
--   * !ElvinCDs/spells.lua                  : per-class cooldown IDs + metadata
--   * EventAlert/EventAlertSpellArray.lua   : per-class proc IDs
--   * Forte_<Class>/Forte_<Class>.lua       : cross-reference for duration
--   * ClassTimer/Bars/<Class>.lua           : cross-reference for category
--
-- Spell IDs are 3.3.5a-era (WotLK). GetSpellInfo resolves them to names at
-- runtime; if a private server patches an ID we can update here without
-- touching the engine.
--
-- Positioning: each group anchors to CENTER of the screen at a distinct
-- (x, y) offset so a freshly-loaded preset doesn't dogpile every group on
-- top of each other. Users drag them into position after the load.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Partial-bar helpers. Each returns a minimal table with just the fields
-- that differ from BarWarden's per-bar defaults. MakeFullBar (in the loader
-- section below) expands these to full bar configs with requireClass set.
-- ----------------------------------------------------------------------------

local function cd(id, name)
    return { trackMode = "Cooldown", spellId = id, name = name or "" }
end

-- Polymorphic helpers: pass a number to use a specific spell ID, or a string
-- to use the spell name (rank-agnostic, preferred for buffs/debuffs/procs so
-- levelling characters' lower-rank spells still match).
local function buff(spell, displayName)
    if type(spell) == "number" then
        return { trackMode = "Buff", spellId = spell, name = displayName or "", unit = "player" }
    end
    return { trackMode = "Buff", spellName = spell, name = displayName or spell, unit = "player" }
end

local function debuff(spell, displayName)
    if type(spell) == "number" then
        return { trackMode = "Debuff", spellId = spell, name = displayName or "", unit = "target", onlyMine = true }
    end
    return { trackMode = "Debuff", spellName = spell, name = displayName or spell, unit = "target", onlyMine = true }
end

local function proc(spell, displayName)
    if type(spell) == "number" then
        return { trackMode = "Proc", spellId = spell, name = displayName or "", unit = "player" }
    end
    return { trackMode = "Proc", spellName = spell, name = displayName or spell, unit = "player" }
end

local function runeBar(slot)
    return { trackMode = "Runes", spellId = slot, name = "Rune " .. slot }
end

local function comboBar()
    return { trackMode = "Combo Points", name = "Combo Points" }
end

local function runicPowerBar()
    return { trackMode = "Runic Power", name = "Runic Power" }
end

local function soulShardsBar()
    return { trackMode = "Soul Shards", name = "Soul Shards" }
end

-- Resource bars need requireClass set so copying a preset across characters
-- doesn't leak, say, rune bars onto a Rogue's UI.
local RESOURCE_MODES = {
    ["Combo Points"] = true,
    ["Runes"]        = true,
    ["Runic Power"]  = true,
    ["Soul Shards"]  = true,
}

-- ----------------------------------------------------------------------------
-- Preset data. Each class has 2–4 groups; each group has ~4–8 bars.
-- ----------------------------------------------------------------------------

ns.ClassPresets = {

    -----------------------------------------------------------------
    DEATHKNIGHT = {
        description = "Death Knight: cooldowns, diseases, runes, runic power",
        groups = {
            {
                name = "DK Cooldowns",
                position = { point = "CENTER", relativePoint = "CENTER", x = -240, y = 120 },
                columns = 1,
                bars = {
                    cd(48707, "Anti-Magic Shell"),
                    cd(48792, "Icebound Fortitude"),
                    cd(47568, "Empower Rune Weapon"),
                    cd(49028, "Dancing Rune Weapon"),
                    cd(55233, "Vampiric Blood"),
                    cd(49222, "Bone Shield"),
                },
            },
            {
                name = "Diseases",
                position = { point = "CENTER", relativePoint = "CENTER", x = -240, y = -120 },
                columns = 1,
                bars = {
                    debuff("Frost Fever"),
                    debuff("Blood Plague"),
                },
            },
            {
                name = "Runes",
                position = { point = "CENTER", relativePoint = "CENTER", x = 240, y = 120 },
                columns = 2,
                width = 240,
                bars = {
                    runeBar(1), runeBar(2),
                    runeBar(3), runeBar(4),
                    runeBar(5), runeBar(6),
                },
            },
            {
                name = "Runic Power",
                position = { point = "CENTER", relativePoint = "CENTER", x = 240, y = -60 },
                columns = 1,
                bars = {
                    runicPowerBar(),
                },
            },
        },
    },

    -----------------------------------------------------------------
    DRUID = {
        description = "Druid: cooldowns, procs, DoTs, core buffs",
        groups = {
            {
                name = "Druid Cooldowns",
                position = { point = "CENTER", relativePoint = "CENTER", x = -240, y = 120 },
                columns = 1,
                bars = {
                    cd(22812, "Barkskin"),
                    cd(29166, "Innervate"),
                    cd(50334, "Berserk"),
                    cd(61336, "Survival Instincts"),
                    cd(22842, "Frenzied Regeneration"),
                    cd(48477, "Rebirth"),
                },
            },
            {
                name = "Druid Procs",
                position = { point = "CENTER", relativePoint = "CENTER", x = -240, y = -120 },
                columns = 1,
                bars = {
                    proc("Eclipse (Solar)"),
                    proc("Eclipse (Lunar)"),
                    proc("Nature's Grace"),
                    proc("Predator's Swiftness"),
                    proc("Clearcasting", "Omen of Clarity"),
                    proc("Owlkin Frenzy"),
                },
            },
            {
                name = "Target DoTs",
                position = { point = "CENTER", relativePoint = "CENTER", x = 240, y = 120 },
                columns = 1,
                bars = {
                    debuff("Moonfire"),
                    debuff("Insect Swarm"),
                    debuff("Rake"),
                    debuff("Rip"),
                },
            },
            {
                name = "Self HoTs",
                position = { point = "CENTER", relativePoint = "CENTER", x = 240, y = -120 },
                columns = 1,
                bars = {
                    buff("Rejuvenation"),
                    buff("Lifebloom"),
                    buff("Regrowth"),
                },
            },
        },
    },

    -----------------------------------------------------------------
    HUNTER = {
        description = "Hunter: cooldowns, procs, sting DoTs",
        groups = {
            {
                name = "Hunter Cooldowns",
                position = { point = "CENTER", relativePoint = "CENTER", x = -240, y = 120 },
                columns = 1,
                bars = {
                    cd(19263, "Deterrence"),
                    cd(23989, "Readiness"),
                    cd(3045,  "Rapid Fire"),
                    cd(34477, "Misdirection"),
                    cd(53271, "Master's Call"),
                    cd(19574, "Bestial Wrath"),
                },
            },
            {
                name = "Hunter Procs",
                position = { point = "CENTER", relativePoint = "CENTER", x = -240, y = -120 },
                columns = 1,
                bars = {
                    proc("Improved Steady Shot"),
                    proc("Lock and Load"),
                    proc("Rapid Killing"),
                },
            },
            {
                name = "Target DoTs",
                position = { point = "CENTER", relativePoint = "CENTER", x = 240, y = 120 },
                columns = 1,
                bars = {
                    debuff("Serpent Sting"),
                    debuff("Scorpid Sting"),
                    debuff("Black Arrow"),
                    debuff("Wyvern Sting"),
                },
            },
        },
    },

    -----------------------------------------------------------------
    MAGE = {
        description = "Mage: cooldowns, procs, self buffs",
        groups = {
            {
                name = "Mage Cooldowns",
                position = { point = "CENTER", relativePoint = "CENTER", x = -240, y = 120 },
                columns = 1,
                bars = {
                    cd(12051, "Evocation"),
                    cd(45438, "Ice Block"),
                    cd(66,    "Invisibility"),
                    cd(12472, "Icy Veins"),
                    cd(12042, "Arcane Power"),
                    cd(11129, "Combustion"),
                },
            },
            {
                name = "Mage Procs",
                position = { point = "CENTER", relativePoint = "CENTER", x = -240, y = -120 },
                columns = 1,
                bars = {
                    proc("Clearcasting"),
                    proc("Brain Freeze"),
                    proc("Fingers of Frost"),
                    proc("Hot Streak"),
                    proc("Missile Barrage"),
                    proc("Blazing Speed"),
                },
            },
            {
                name = "Target DoTs",
                position = { point = "CENTER", relativePoint = "CENTER", x = 240, y = 120 },
                columns = 1,
                bars = {
                    debuff("Ignite"),
                    debuff("Pyroblast"),
                    debuff("Living Bomb"),
                },
            },
        },
    },

    -----------------------------------------------------------------
    PALADIN = {
        description = "Paladin: cooldowns, procs, judgement",
        groups = {
            {
                name = "Paladin Cooldowns",
                position = { point = "CENTER", relativePoint = "CENTER", x = -240, y = 120 },
                columns = 1,
                bars = {
                    cd(642,   "Divine Shield"),
                    cd(498,   "Divine Protection"),
                    cd(31884, "Avenging Wrath"),
                    cd(48788, "Lay on Hands"),
                    cd(10308, "Hammer of Justice"),
                    cd(1044,  "Hand of Freedom"),
                    cd(6940,  "Hand of Sacrifice"),
                },
            },
            {
                name = "Paladin Procs",
                position = { point = "CENTER", relativePoint = "CENTER", x = -240, y = -120 },
                columns = 1,
                bars = {
                    proc("The Art of War"),
                    proc("Infusion of Light"),
                    proc("Sacred Shield"),
                    proc("Light's Grace"),
                },
            },
            {
                name = "Target Debuffs",
                position = { point = "CENTER", relativePoint = "CENTER", x = 240, y = 120 },
                columns = 1,
                bars = {
                    debuff("Repentance"),
                    debuff("Judgement of Wisdom"),
                    debuff("Judgement of Justice"),
                    debuff("Judgement of Righteousness"),
                },
            },
        },
    },

    -----------------------------------------------------------------
    PRIEST = {
        description = "Priest: cooldowns, procs, HoTs",
        groups = {
            {
                name = "Priest Cooldowns",
                position = { point = "CENTER", relativePoint = "CENTER", x = -240, y = 120 },
                columns = 1,
                bars = {
                    cd(586,   "Fade"),
                    cd(10890, "Psychic Scream"),
                    cd(14751, "Inner Focus"),
                    cd(6346,  "Fear Ward"),
                    cd(47788, "Guardian Spirit"),
                    cd(33206, "Pain Suppression"),
                    cd(10060, "Power Infusion"),
                },
            },
            {
                name = "Priest Procs",
                position = { point = "CENTER", relativePoint = "CENTER", x = -240, y = -120 },
                columns = 1,
                bars = {
                    proc("Borrowed Time"),
                    proc("Serendipity"),
                    proc("Surge of Light"),
                    proc("Holy Concentration"),
                },
            },
            {
                name = "Target DoTs",
                position = { point = "CENTER", relativePoint = "CENTER", x = 240, y = 120 },
                columns = 1,
                bars = {
                    debuff("Shadow Word: Pain"),
                    debuff("Devouring Plague"),
                    debuff("Vampiric Touch"),
                    debuff("Mind Flay"),
                },
            },
            {
                name = "Self HoTs",
                position = { point = "CENTER", relativePoint = "CENTER", x = 240, y = -120 },
                columns = 1,
                bars = {
                    buff("Renew"),
                    buff("Power Word: Shield"),
                    buff("Weakened Soul"),
                },
            },
        },
    },

    -----------------------------------------------------------------
    ROGUE = {
        description = "Rogue: cooldowns, bleeds, poisons, combo points",
        groups = {
            {
                name = "Rogue Cooldowns",
                position = { point = "CENTER", relativePoint = "CENTER", x = -240, y = 120 },
                columns = 1,
                bars = {
                    cd(5277,  "Evasion"),
                    cd(1766,  "Kick"),
                    cd(2094,  "Blind"),
                    cd(26889, "Vanish"),
                    cd(51690, "Killing Spree"),
                    cd(13750, "Adrenaline Rush"),
                    cd(51713, "Shadow Dance"),
                    cd(57934, "Tricks of the Trade"),
                },
            },
            {
                name = "Target Bleeds",
                position = { point = "CENTER", relativePoint = "CENTER", x = -240, y = -120 },
                columns = 1,
                bars = {
                    debuff("Rupture"),
                    debuff("Garrote"),
                    debuff("Deadly Throw"),
                    debuff("Deadly Poison"),
                    debuff("Expose Armor"),
                },
            },
            {
                name = "Self Buffs",
                position = { point = "CENTER", relativePoint = "CENTER", x = 240, y = 120 },
                columns = 1,
                bars = {
                    buff("Slice and Dice"),
                    buff("Cold Blood"),
                    buff("Cheating Death"),
                },
            },
            {
                name = "Combo Points",
                position = { point = "CENTER", relativePoint = "CENTER", x = 240, y = -60 },
                columns = 1,
                bars = {
                    comboBar(),
                },
            },
        },
    },

    -----------------------------------------------------------------
    SHAMAN = {
        description = "Shaman: cooldowns, totems, procs",
        groups = {
            {
                name = "Shaman Cooldowns",
                position = { point = "CENTER", relativePoint = "CENTER", x = -240, y = 120 },
                columns = 1,
                bars = {
                    cd(2894,  "Fire Elemental Totem"),
                    cd(30823, "Shamanistic Rage"),
                    cd(51533, "Feral Spirit"),
                    cd(51514, "Hex"),
                    cd(57994, "Wind Shear"),
                    cd(16190, "Mana Tide Totem"),
                    cd(55198, "Tidal Force"),
                },
            },
            {
                name = "Shaman Procs",
                position = { point = "CENTER", relativePoint = "CENTER", x = -240, y = -120 },
                columns = 1,
                bars = {
                    proc("Clearcasting", "Elemental Focus"),
                    proc("Maelstrom Weapon"),
                    proc("Tidal Waves"),
                },
            },
            {
                name = "Totems",
                position = { point = "CENTER", relativePoint = "CENTER", x = 240, y = 120 },
                columns = 1,
                bars = {
                    { trackMode = "Totem", spellId = 1, name = "Fire Totem" },
                    { trackMode = "Totem", spellId = 2, name = "Earth Totem" },
                    { trackMode = "Totem", spellId = 3, name = "Water Totem" },
                    { trackMode = "Totem", spellId = 4, name = "Air Totem" },
                },
            },
        },
    },

    -----------------------------------------------------------------
    WARLOCK = {
        description = "Warlock: cooldowns, procs, DoTs, soul shards",
        groups = {
            {
                name = "Warlock Cooldowns",
                position = { point = "CENTER", relativePoint = "CENTER", x = -240, y = 120 },
                columns = 1,
                bars = {
                    cd(47241, "Metamorphosis"),
                    cd(29858, "Soulshatter"),
                    cd(47883, "Soulstone"),
                    cd(17928, "Howl of Terror"),
                    cd(18708, "Fel Domination"),
                    cd(30283, "Shadowfury"),
                },
            },
            {
                name = "Warlock Procs",
                position = { point = "CENTER", relativePoint = "CENTER", x = -240, y = -120 },
                columns = 1,
                bars = {
                    proc("Backlash"),
                    proc("Empowered Imp"),
                    proc("Nightfall"),
                    proc("Molten Core"),
                    proc("Decimation"),
                    proc("Backdraft"),
                },
            },
            {
                name = "Target DoTs",
                position = { point = "CENTER", relativePoint = "CENTER", x = 240, y = 120 },
                columns = 1,
                bars = {
                    debuff("Unstable Affliction"),
                    debuff("Haunt"),
                    debuff("Curse of Agony"),
                    debuff("Corruption"),
                    debuff("Immolate"),
                    debuff("Curse of the Elements"),
                },
            },
            {
                name = "Soul Shards",
                position = { point = "CENTER", relativePoint = "CENTER", x = 240, y = -120 },
                columns = 1,
                bars = {
                    soulShardsBar(),
                },
            },
        },
    },

    -----------------------------------------------------------------
    WARRIOR = {
        description = "Warrior: cooldowns, procs, stance buffs",
        groups = {
            {
                name = "Warrior Cooldowns",
                position = { point = "CENTER", relativePoint = "CENTER", x = -240, y = 120 },
                columns = 1,
                bars = {
                    cd(871,   "Shield Wall"),
                    cd(12975, "Last Stand"),
                    cd(1719,  "Recklessness"),
                    cd(20230, "Retaliation"),
                    cd(55694, "Enraged Regeneration"),
                    cd(676,   "Disarm"),
                    cd(18499, "Berserker Rage"),
                    cd(1161,  "Challenging Shout"),
                },
            },
            {
                name = "Warrior Procs",
                position = { point = "CENTER", relativePoint = "CENTER", x = -240, y = -120 },
                columns = 1,
                bars = {
                    proc("Bloodsurge"),
                    proc("Sudden Death"),
                    proc("Sword and Board"),
                    proc("Taste for Blood"),
                },
            },
            {
                name = "Target Debuffs",
                position = { point = "CENTER", relativePoint = "CENTER", x = 240, y = 120 },
                columns = 1,
                bars = {
                    debuff("Sunder Armor"),
                    debuff("Hamstring"),
                    debuff("Mortal Strike"),
                    debuff("Shockwave"),
                    debuff("Devastate"),
                },
            },
        },
    },

}

-- ----------------------------------------------------------------------------
-- MakeFullBar: expand a partial-bar table to a complete BarWarden bar,
-- filling in all default fields. Resource bars get requireClass set to
-- `classToken` so they can't accidentally leak onto other classes.
-- ----------------------------------------------------------------------------

local function MakeFullBar(partial, classToken)
    local requireClass
    if RESOURCE_MODES[partial.trackMode] then
        requireClass = classToken
    end

    return {
        enabled   = true,
        trackMode = partial.trackMode,
        spellName = partial.spellName,
        spellId   = partial.spellId,
        itemId    = partial.itemId,
        name      = partial.name or "",
        unit      = partial.unit,
        onlyMine  = partial.onlyMine ~= false,
        conditions = {
            combatOnly       = false,
            outOfCombatOnly  = false,
            requireBuff      = nil,
            requireClass     = requireClass,
            healthBelow      = nil,
            inGroup          = false,
            inRaid           = false,
            hideWhileMounted = false,
            hideWhileResting = false,
            hideInVehicle    = false,
            onlyInInstance   = false,
            hideWhenInactive = partial.hideWhenInactive == true,
            showEmpty        = true,
        },
        display = {},
    }
end

-- ----------------------------------------------------------------------------
-- BuildGroupFromPreset: shared helper that turns a preset group spec into a
-- full runtime group (shape matches ns.db.frames[i]). `positionIndex` is
-- used for the fallback position if the preset didn't specify one.
-- ----------------------------------------------------------------------------

local function BuildGroupFromPreset(groupPreset, positionIndex, classToken)
    local defaultPos = { point = "CENTER", relativePoint = "CENTER", x = 0, y = -(positionIndex * 100) }
    local group = {
        name            = groupPreset.name or ("Group " .. positionIndex),
        enabled         = true,
        locked          = false,
        visible         = true,
        position        = groupPreset.position or defaultPos,
        width           = groupPreset.width or 200,
        columns         = groupPreset.columns or 1,
        sortMode        = groupPreset.sortMode or "manual",
        bgAlpha         = 0.6,
        borderAlpha     = 0.8,
        scale           = 1.0,
        groupConditions = {},
        bars            = {},
    }
    for _, barPreset in ipairs(groupPreset.bars) do
        group.bars[#group.bars + 1] = MakeFullBar(barPreset, classToken)
    end
    return group
end

-- ----------------------------------------------------------------------------
-- GetClassPresetSummary: returns (summaryString, groupCount, totalBars).
-- Used by the confirm dialogs in Options_Profiles.lua so the user sees what
-- the preset contains before accepting the load/append.
-- ----------------------------------------------------------------------------

function ns:GetClassPresetSummary(classToken)
    local preset = ns.ClassPresets and ns.ClassPresets[classToken]
    if not preset then return nil, 0, 0 end

    local groupCount = #preset.groups
    local totalBars = 0
    local names = {}
    for _, g in ipairs(preset.groups) do
        totalBars = totalBars + #g.bars
        names[#names + 1] = g.name or "Group"
    end

    local nameList = table.concat(names, ", ")
    local summary = string.format("%d groups, %d bars: %s", groupCount, totalBars, nameList)
    return summary, groupCount, totalBars
end

-- ----------------------------------------------------------------------------
-- LoadClassStarter: replace the active character's groups/bars with the
-- preset for `classToken` (e.g. "DEATHKNIGHT"). Falls back to the player's
-- own class if classToken is nil.
--
-- Returns true on success, false if no preset exists for the token.
-- Caller is responsible for showing a confirmation dialog; this function
-- overwrites ns.db.frames without asking.
-- ----------------------------------------------------------------------------

function ns:LoadClassStarter(classToken)
    if not classToken then
        _, classToken = UnitClass("player")
    end
    local preset = ns.ClassPresets[classToken]
    if not preset then
        if ns.Print then ns:Print("No starter profile for " .. tostring(classToken)) end
        return false
    end

    local newFrames = {}
    for i, groupPreset in ipairs(preset.groups) do
        newFrames[i] = BuildGroupFromPreset(groupPreset, i, classToken)
    end

    ns.db.frames = newFrames
    ns.db.activeProfile = nil  -- preset is not one of the named profiles
    ns:FireCallback("OnProfileChanged", nil)

    local totalBars = 0
    for _, g in ipairs(newFrames) do totalBars = totalBars + #g.bars end
    if ns.Print then
        ns:Print(string.format("Loaded %s starter profile (%d groups, %d bars).",
            classToken, #newFrames, totalBars))
    end
    return true
end

-- ----------------------------------------------------------------------------
-- AppendClassStarter: append the preset's groups onto the END of the active
-- character's existing frames. Existing bars are preserved; no deletion.
-- Useful when the user has a tuned layout but wants, say, the DK rune bars
-- added without starting from scratch.
-- ----------------------------------------------------------------------------

function ns:AppendClassStarter(classToken)
    if not classToken then
        _, classToken = UnitClass("player")
    end
    local preset = ns.ClassPresets[classToken]
    if not preset then
        if ns.Print then ns:Print("No starter profile for " .. tostring(classToken)) end
        return false
    end

    if type(ns.db.frames) ~= "table" then
        ns.db.frames = {}
    end

    local startIndex = #ns.db.frames
    local addedBars = 0
    for i, groupPreset in ipairs(preset.groups) do
        local targetIndex = startIndex + i
        ns.db.frames[targetIndex] = BuildGroupFromPreset(groupPreset, targetIndex, classToken)
        addedBars = addedBars + #ns.db.frames[targetIndex].bars
    end

    ns.db.activeProfile = nil
    ns:FireCallback("OnProfileChanged", nil)

    if ns.Print then
        ns:Print(string.format("Appended %s starter profile (%d groups, %d bars added).",
            classToken, #preset.groups, addedBars))
    end
    return true
end
