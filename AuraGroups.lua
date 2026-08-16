-- AuraGroups.lua - Named aura equivalency groups (@Stunned, @Bleeding, ...).
-- Author:  Serv
-- Source:  https://github.com/powerfulqa/BarWarden
-- License: GNU GPL v3 (see LICENSE); attribution preservation is required.

local addonName, ns = ...

-- ============================================================================
-- AuraGroups.lua: named aura equivalency groups.
--
-- Each group is a list of spell IDs that share a category (stuns, bleeds,
-- silences, etc.). A bar's spell field can reference a group with `@Name`
-- and the tracker will match any aura whose spellId is in the list. Groups
-- compose with plain entries: `Rupture, @Stunned` matches Rupture OR any
-- listed stun.
--
-- Token expansion is done in Trackers.lua `getSpellTokens`; this file only
-- owns the data. To add a new group, append below. To extend a group, push
-- new IDs into the list.
--
-- IDs are 3.3.5a-era WoW. Private servers may have renumbered some of these;
-- users hitting false negatives should drop unmatched IDs and push their
-- server-specific equivalents.
-- ============================================================================

ns.AuraGroups = {
    -- Crowd-control stuns (bar the target can't act during).
    Stunned = {
        1833,   -- Cheap Shot
        8643,   -- Kidney Shot (rank 2)
        48657,  -- Kidney Shot (rank 3)
        853,    -- Hammer of Justice
        5211,   -- Bash (rank 1)
        6798,   -- Bash (rank 2)
        8983,   -- Bash (rank 3)
        7922,   -- Charge Stun
        12809,  -- Concussion Blow
        20549,  -- War Stomp (tauren racial)
        22570,  -- Maim
        46968,  -- Shockwave
        47481,  -- Gnaw (DK ghoul)
        49203,  -- Hungering Cold
        89,     -- Howl of Terror (fear, commonly grouped with stuns in PvP)
    },

    -- Silences: target can't cast, but can still move and melee.
    Silenced = {
        15487,  -- Silence (Priest)
        47476,  -- Strangulate
        18498,  -- Silenced - Gag Order (Warrior)
        1330,   -- Garrote - Silence
        25046,  -- Arcane Torrent (Rogue/blood elf variant)
        28730,  -- Arcane Torrent (mana)
        50613,  -- Arcane Torrent (runic)
        55021,  -- Silenced - Improved Counterspell
        31935,  -- Avenger's Shield
    },

    -- Bleed DoTs. Useful as a "keep at least one bleed up" proxy.
    Bleeding = {
        48672,  -- Rupture
        48676,  -- Garrote
        48574,  -- Rake
        48577,  -- Rip
        48568,  -- Lacerate
        48660,  -- Hemorrhage
        47465,  -- Rend (Warrior)
        12721,  -- Deep Wounds
        33745,  -- Lacerate (older rank)
        16511,  -- Hemorrhage (older rank)
    },

    -- Incapacitates: target can't do anything, and damage often breaks early.
    Incapacitated = {
        6770,   -- Sap (rank 1)
        51724,  -- Sap (rank 3)
        118,    -- Polymorph
        28272,  -- Polymorph (Pig)
        28271,  -- Polymorph (Turtle)
        61305,  -- Polymorph (Black Cat)
        61721,  -- Polymorph (Rabbit)
        61780,  -- Polymorph (Turkey)
        3355,   -- Freezing Trap
        14308,  -- Freezing Trap (rank 2)
        14309,  -- Freezing Trap (rank 3)
        20066,  -- Repentance
        9484,   -- Shackle Undead
        1776,   -- Gouge
        19386,  -- Wyvern Sting
        2637,   -- Hibernate
        710,    -- Banish
        51514,  -- Hex
    },

    -- Fear-type effects (target runs away uncontrollably).
    Feared = {
        5782,   -- Fear (Warlock)
        6215,   -- Fear
        8122,   -- Psychic Scream
        5484,   -- Howl of Terror
        17928,  -- Howl of Terror (rank 2)
        1513,   -- Scare Beast
        5246,   -- Intimidating Shout
    },

    -- Root / ground-pin effects (target can't move, can still cast and attack).
    Rooted = {
        122,    -- Frost Nova
        339,    -- Entangling Roots
        16922,  -- Starfire Stun (Improved Starfire; debatable but commonly grouped)
        33395,  -- Freeze (water elemental)
        45334,  -- Feral Charge Effect (root portion)
    },

    -- Movement-slow debuffs (target moves more slowly).
    MovementSlowed = {
        1715,   -- Hamstring
        50256,  -- Demoralizing Roar (not a slow, listed for reference; remove if false-positive)
        31589,  -- Slow (Mage)
        15407,  -- Mind Flay (Priest, snares)
        15571,  -- Frostbolt (rank 11 slow)
        12323,  -- Piercing Howl
        18118,  -- Aftermath
        19185,  -- Entrapment
        3409,   -- Crippling Poison
        25809,  -- Crippling Poison II
    },

    -- Disarm: target can't use their weapon for a few seconds.
    Disarmed = {
        676,    -- Disarm (Warrior)
        51722,  -- Dismantle (Rogue)
        64058,  -- Psychic Horror (the disarm portion)
    },
}
