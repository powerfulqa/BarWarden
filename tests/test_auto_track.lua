-- tests/test_auto_track.lua
-- Covers ns:CollectAutoAuras, the pure half of auto-tracking groups: which
-- auras a self-filling group keeps, in what order, and how many.
--
-- The frame-driving half (ns:ScanAutoGroup) is not covered here; it needs a
-- live frame and rides the in-game smoke test, per existing policy.

local assertx    = require("assert")
local load_addon = require("load_addon")
local mock       = require("mock_wow")

local M = {}

local function fresh()
    mock.reset()
    local ns = {}
    load_addon.load("Utils.lua",      "BarWarden", ns)
    load_addon.load("AuraGroups.lua", "BarWarden", ns)
    load_addon.load("Trackers.lua",   "BarWarden", ns)
    return ns
end

-- Build one entry in the shape UnitBuff / UnitDebuff return on 3.3.5a.
local function aura(name, spellId, expirationTime, duration, caster, count)
    return {
        name           = name,
        spellId        = spellId,
        icon           = "icon",
        count          = count or 0,
        duration       = duration or 0,
        expirationTime = expirationTime or 0,
        caster         = caster or "player",
    }
end

-- --------------------------------------------------------------------------
-- Feed resolution
-- --------------------------------------------------------------------------

function M.test_unknownFeedReturnsEmpty()
    local ns = fresh()
    mock.buffs.player[1] = aura("Slice and Dice", 5171, 20, 20)
    local out = ns:CollectAutoAuras("notAFeed", {})
    assertx.assertEqual(#out, 0, "an unknown feed name should collect nothing")
end

function M.test_playerBuffsReadsPlayerBuffs()
    local ns = fresh()
    mock.buffs.player[1] = aura("Slice and Dice", 5171, 20, 20)
    local out = ns:CollectAutoAuras("playerBuffs", {})
    assertx.assertEqual(#out, 1)
    assertx.assertEqual(out[1].name, "Slice and Dice")
    assertx.assertEqual(out[1].spellId, 5171)
end

function M.test_targetDebuffsReadsTargetDebuffs()
    local ns = fresh()
    -- A buff on the player must not leak into a target-debuff feed.
    mock.buffs.player[1]   = aura("Slice and Dice", 5171, 20, 20)
    mock.debuffs.target[1] = aura("Rupture", 1943, 12, 12)
    local out = ns:CollectAutoAuras("targetDebuffs", {})
    assertx.assertEqual(#out, 1)
    assertx.assertEqual(out[1].name, "Rupture")
end

-- --------------------------------------------------------------------------
-- Duration filtering
-- --------------------------------------------------------------------------

function M.test_skipsPermanentAuras()
    local ns = fresh()
    -- A class aura carries no duration, so a bar for it would say nothing.
    mock.buffs.player[1] = aura("Righteous Fury", 25780, 0, 0)
    local out = ns:CollectAutoAuras("playerBuffs", {})
    assertx.assertEqual(#out, 0, "an aura with no duration should be skipped")
end

function M.test_skipsAurasLongerThanMaxDuration()
    local ns = fresh()
    mock.buffs.player[1] = aura("Flask of Endless Rage", 53760, 3600, 3600)
    mock.buffs.player[2] = aura("Slice and Dice", 5171, 20, 20)
    local out = ns:CollectAutoAuras("playerBuffs", { maxDuration = 300 })
    assertx.assertEqual(#out, 1)
    assertx.assertEqual(out[1].name, "Slice and Dice")
end

function M.test_maxDurationTestsFullDurationNotRemaining()
    -- A flask with 30 seconds left is still a flask. Filtering on remaining
    -- time would make long buffs appear exactly as they ran out.
    local ns = fresh()
    mock.now = 3570
    mock.buffs.player[1] = aura("Flask of Endless Rage", 53760, 3600, 3600)
    local out = ns:CollectAutoAuras("playerBuffs", { maxDuration = 300 })
    assertx.assertEqual(#out, 0, "a nearly-expired long buff must stay hidden")
end

function M.test_maxDurationZeroDisablesTheLimit()
    local ns = fresh()
    mock.buffs.player[1] = aura("Flask of Endless Rage", 53760, 3600, 3600)
    local out = ns:CollectAutoAuras("playerBuffs", { maxDuration = 0 })
    assertx.assertEqual(#out, 1, "maxDuration 0 means no limit")
end

-- --------------------------------------------------------------------------
-- Only Mine
-- --------------------------------------------------------------------------

function M.test_onlyMineKeepsPlayerPetAndVehicle()
    local ns = fresh()
    mock.debuffs.target[1] = aura("Rupture",      1943, 12, 12, "player")
    mock.debuffs.target[2] = aura("Pet Bite",     1000, 13, 12, "pet")
    mock.debuffs.target[3] = aura("Vehicle Ram",  1001, 14, 12, "vehicle")
    mock.debuffs.target[4] = aura("Someone Else", 1002, 15, 12, "party1")
    local out = ns:CollectAutoAuras("targetDebuffs", { onlyMine = true })
    assertx.assertEqual(#out, 3, "player, pet and vehicle casts are all yours")
    assertx.assertEqual(out[1].name, "Rupture")
end

function M.test_onlyMineFalseKeepsEveryCaster()
    local ns = fresh()
    mock.debuffs.player[1] = aura("Boss Debuff", 2000, 10, 10, "boss1")
    local out = ns:CollectAutoAuras("playerDebuffs", { onlyMine = false })
    assertx.assertEqual(#out, 1, "a boss debuff on you is exactly what you want to see")
end

-- --------------------------------------------------------------------------
-- Skip spells already tracked elsewhere
-- --------------------------------------------------------------------------

function M.test_skipNamesDropsMatchingAura()
    local ns = fresh()
    mock.buffs.player[1] = aura("Slice and Dice", 5171, 20, 20)
    mock.buffs.player[2] = aura("Adrenaline Rush", 13750, 30, 30)
    local out = ns:CollectAutoAuras("playerBuffs",
        { skipNames = { ["slice and dice"] = true } })
    assertx.assertEqual(#out, 1)
    assertx.assertEqual(out[1].name, "Adrenaline Rush")
end

function M.test_skipNamesIsCaseInsensitive()
    local ns = fresh()
    mock.buffs.player[1] = aura("SLICE AND DICE", 5171, 20, 20)
    local out = ns:CollectAutoAuras("playerBuffs",
        { skipNames = { ["slice and dice"] = true } })
    assertx.assertEqual(#out, 0)
end

function M.test_noSkipNamesKeepsDuplicates()
    -- The default: a spell shows in the feed even when a curated bar has it.
    local ns = fresh()
    mock.buffs.player[1] = aura("Slice and Dice", 5171, 20, 20)
    local out = ns:CollectAutoAuras("playerBuffs", {})
    assertx.assertEqual(#out, 1)
end

-- --------------------------------------------------------------------------
-- Ordering, truncation, stacks
-- --------------------------------------------------------------------------

function M.test_orderedSoonestExpiringFirst()
    local ns = fresh()
    mock.buffs.player[1] = aura("Third",  1, 30, 30)
    mock.buffs.player[2] = aura("First",  2, 10, 30)
    mock.buffs.player[3] = aura("Second", 3, 20, 30)
    local out = ns:CollectAutoAuras("playerBuffs", {})
    assertx.assertEqual(out[1].name, "First")
    assertx.assertEqual(out[2].name, "Second")
    assertx.assertEqual(out[3].name, "Third")
end

function M.test_truncatedToMaxBars()
    local ns = fresh()
    mock.buffs.player[1] = aura("A", 1, 40, 40)
    mock.buffs.player[2] = aura("B", 2, 10, 40)
    mock.buffs.player[3] = aura("C", 3, 20, 40)
    mock.buffs.player[4] = aura("D", 4, 30, 40)
    local out = ns:CollectAutoAuras("playerBuffs", { maxBars = 2 })
    assertx.assertEqual(#out, 2, "the list is cut to maxBars")
    assertx.assertEqual(out[1].name, "B", "and keeps the soonest-expiring ones")
    assertx.assertEqual(out[2].name, "C")
end

function M.test_carriesStackCount()
    local ns = fresh()
    mock.buffs.player[1] = aura("Sunder Armor", 7386, 20, 20, "player", 5)
    local out = ns:CollectAutoAuras("playerBuffs", {})
    assertx.assertEqual(out[1].count, 5)
end

function M.test_emptyWhenNothingQualifies()
    local ns = fresh()
    local out = ns:CollectAutoAuras("playerBuffs", {})
    assertx.assertEqual(#out, 0)
    assertx.assertEqual(type(out), "table", "always returns a table, never nil")
end

return M
