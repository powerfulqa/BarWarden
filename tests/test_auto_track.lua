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

-- --------------------------------------------------------------------------
-- GetTrackedAuraNames: what a bar somewhere else already covers
-- --------------------------------------------------------------------------

-- These cases drive BarWardenDB directly. It is a real global in the game, so
-- each case clears it again to keep the suites independent.
local function withDB(frames, fn)
    _G.BarWardenDB = { frames = frames }
    local ok, err = pcall(fn)
    _G.BarWardenDB = nil
    if not ok then error(err, 0) end
end

function M.test_trackedNames_collectsAuraBarsAcrossGroups()
    local ns = fresh()
    withDB({
        { bars = { { trackMode = "Buff",   spellName = "Slice and Dice" } } },
        { bars = { { trackMode = "Debuff", spellName = "Rupture"        } } },
        { bars = { { trackMode = "Proc",   spellName = "Clearcasting"   } } },
    }, function()
        local names = ns:GetTrackedAuraNames(nil)
        assertx.assertTrue(names["slice and dice"])
        assertx.assertTrue(names["rupture"])
        assertx.assertTrue(names["clearcasting"])
    end)
end

function M.test_trackedNames_lowerCasesForMatching()
    local ns = fresh()
    withDB({ { bars = { { trackMode = "Buff", spellName = "Slice And Dice" } } } },
    function()
        local names = ns:GetTrackedAuraNames(nil)
        assertx.assertTrue(names["slice and dice"], "names are keyed lower-cased")
    end)
end

function M.test_trackedNames_skipsTheAskingGroup()
    local ns = fresh()
    withDB({
        { bars = { { trackMode = "Buff", spellName = "Slice and Dice" } } },
        { bars = { { trackMode = "Buff", spellName = "Adrenaline Rush" } } },
    }, function()
        local names = ns:GetTrackedAuraNames(1)
        assertx.assertNil(names["slice and dice"], "a group never suppresses itself")
        assertx.assertTrue(names["adrenaline rush"])
    end)
end

function M.test_trackedNames_skipsNonAuraTrackModes()
    -- A cooldown bar named "Fire Blast" must not hide the buff Fire Blast.
    local ns = fresh()
    withDB({ { bars = {
        { trackMode = "Cooldown", spellName = "Fire Blast" },
        { trackMode = "Item",     spellName = "Healthstone" },
        { trackMode = "Totem",    spellName = "Searing Totem" },
    } } }, function()
        local names = ns:GetTrackedAuraNames(nil)
        assertx.assertNil(names["fire blast"])
        assertx.assertNil(names["healthstone"])
        assertx.assertNil(names["searing totem"])
    end)
end

function M.test_trackedNames_skipsDisabledBars()
    local ns = fresh()
    withDB({ { bars = {
        { trackMode = "Buff", spellName = "Slice and Dice", enabled = false },
    } } }, function()
        local names = ns:GetTrackedAuraNames(nil)
        assertx.assertNil(names["slice and dice"],
            "a bar you switched off is not something you are tracking")
    end)
end

function M.test_trackedNames_skipsOtherAutoGroups()
    local ns = fresh()
    withDB({
        { autoTrack = "playerBuffs", bars = { { trackMode = "Buff", spellName = "Kept Bar" } } },
    }, function()
        local names = ns:GetTrackedAuraNames(nil)
        assertx.assertNil(names["kept bar"],
            "an auto group's stored bars are dormant, not tracked")
    end)
end

function M.test_trackedNames_splitsCommaSeparatedLists()
    local ns = fresh()
    withDB({ { bars = {
        { trackMode = "Buff", spellName = "Slice and Dice, Adrenaline Rush" },
    } } }, function()
        local names = ns:GetTrackedAuraNames(nil)
        assertx.assertTrue(names["slice and dice"])
        assertx.assertTrue(names["adrenaline rush"], "each token counts separately")
    end)
end

function M.test_trackedNames_ignoresBareSpellIdBars()
    -- A bar tracking a bare spell id (no name typed in) is the normal shape
    -- for that setup: spellName stays nil. The gmatch guard checks
    -- type(bd.spellName) == "string" before ever touching it, so this must
    -- not error and must not count as tracking anything.
    local ns = fresh()
    withDB({ { bars = {
        { trackMode = "Buff", spellId = 11305, spellName = nil },
    } } }, function()
        local names = ns:GetTrackedAuraNames(nil)
        assertx.assertEqual(type(names), "table")
        assertx.assertEqual(next(names), nil, "a bare spell id tracks nothing by name")
    end)
end

function M.test_trackedNames_emptyWithoutDB()
    local ns = fresh()
    local names = ns:GetTrackedAuraNames(nil)
    assertx.assertEqual(type(names), "table")
    assertx.assertEqual(next(names), nil, "no saved variables yet means nothing tracked")
end

function M.test_auraTrackModesShared()
    local ns = fresh()
    assertx.assertTrue(ns.AURA_TRACK_MODES.Buff)
    assertx.assertTrue(ns.AURA_TRACK_MODES.Debuff)
    assertx.assertTrue(ns.AURA_TRACK_MODES.Proc)
    assertx.assertNil(ns.AURA_TRACK_MODES.Cooldown)
end

-- --------------------------------------------------------------------------
-- ns:PlaceAutoAuras: Keep Bars In Place slot assignment
--
-- These are plain data tests: no mock auras, no live frames, just tables in
-- the shape ns:CollectAutoAuras already returns (soonest-expiring first).
-- --------------------------------------------------------------------------

function M.test_placeAutoAuras_emptyOrNilInputsReturnEmptyTable()
    local ns = fresh()
    assertx.assertEqual(type(ns:PlaceAutoAuras(nil, nil, 5)), "table")
    assertx.assertEqual(next(ns:PlaceAutoAuras(nil, nil, 5)), nil)
    assertx.assertEqual(next(ns:PlaceAutoAuras(nil, {}, 5)), nil)
    assertx.assertEqual(next(ns:PlaceAutoAuras({ [1] = "A" }, nil, 5)), nil)
end

function M.test_placeAutoAuras_heldAuraKeepsSlotWhileOthersChurn()
    local ns = fresh()
    -- Sorted soonest-first: C, B, A - but A is held in slot 1, so it must not
    -- move there even though it is now the last to expire.
    local auras = { aura("C", 3, 3), aura("B", 2, 5), aura("A", 1, 100) }
    local held  = { [1] = "A" }
    local out = ns:PlaceAutoAuras(held, auras, 3)
    assertx.assertEqual(out[1].name, "A", "the held name stays in its slot")
    assertx.assertEqual(out[2].name, "C", "free slots fill soonest-expiring first")
    assertx.assertEqual(out[3].name, "B")
end

function M.test_placeAutoAuras_fadeFreesSlotForNewAura()
    local ns = fresh()
    -- A held in slot 1 has faded and is no longer in auras; B held in slot 2
    -- is still up. The new aura C takes the freed slot 1, not slot 3.
    local auras = { aura("C", 3, 3), aura("B", 2, 5) }
    local held  = { [1] = "A", [2] = "B" }
    local out = ns:PlaceAutoAuras(held, auras, 2)
    assertx.assertEqual(out[1].name, "C", "a faded slot is freed for the lowest new aura")
    assertx.assertEqual(out[2].name, "B", "the still-held aura does not move")
end

function M.test_placeAutoAuras_duplicateNamesDoNotDoubleClaim()
    local ns = fresh()
    -- Two slots both remember "X" (two different casters had it before, Only
    -- Mine off), but only one aura named X currently exists. The first slot
    -- wins it; the second must not also grab it and must be treated as free.
    local auras = { aura("X", 1, 10) }
    local held  = { [1] = "X", [2] = "X" }
    local out = ns:PlaceAutoAuras(held, auras, 2)
    assertx.assertEqual(out[1].name, "X")
    assertx.assertNil(out[2], "the second slot's claim is not honoured twice")
end

function M.test_placeAutoAuras_duplicateNamesLeaveSlotFreeForAnotherAura()
    local ns = fresh()
    local auras = { aura("X", 1, 10), aura("Y", 2, 20) }
    local held  = { [1] = "X", [2] = "X" }
    local out = ns:PlaceAutoAuras(held, auras, 2)
    assertx.assertEqual(out[1].name, "X")
    assertx.assertEqual(out[2].name, "Y", "the freed second slot takes the next aura in order")
end

function M.test_placeAutoAuras_truncatesToSlotCount()
    local ns = fresh()
    local auras = {
        aura("A", 1, 10), aura("B", 2, 20), aura("C", 3, 30),
        aura("D", 4, 40), aura("E", 5, 50),
    }
    local out = ns:PlaceAutoAuras(nil, auras, 2)
    assertx.assertEqual(out[1].name, "A")
    assertx.assertEqual(out[2].name, "B")
    assertx.assertNil(out[3], "never places more than slotCount, and never above it")
end

function M.test_placeAutoAuras_heldShorterThanSlotCount()
    local ns = fresh()
    -- held only knows about slot 1; slots 2 and 3 are simply unheld and fill
    -- like normal.
    local auras = { aura("A", 1, 10), aura("B", 2, 20), aura("C", 3, 30) }
    local held  = { [1] = "A" }
    local out = ns:PlaceAutoAuras(held, auras, 3)
    assertx.assertEqual(out[1].name, "A")
    assertx.assertEqual(out[2].name, "B")
    assertx.assertEqual(out[3].name, "C")
end

function M.test_placeAutoAuras_sortedOrderChangesButHeldAurasStayPut()
    local ns = fresh()
    -- This is the motivating case: all three names are held, so a refresh
    -- that reorders the sorted feed (C now outlasts A and B) must not move
    -- any bar. Every held name is still found and returned to its own slot.
    local auras = { aura("B", 2, 5), aura("A", 1, 10), aura("C", 3, 100) }
    local held  = { [1] = "A", [2] = "B", [3] = "C" }
    local out = ns:PlaceAutoAuras(held, auras, 3)
    assertx.assertEqual(out[1].name, "A")
    assertx.assertEqual(out[2].name, "B")
    assertx.assertEqual(out[3].name, "C")
end

return M
