-- tests/test_conditions.lua
-- Exercises each built-in visibility condition registered by Conditions.lua.
-- Conditions.lua captures `playerClass` as an upvalue at file-load time via
-- `local _, playerClass = UnitClass("player")`, so the test helper sets the
-- mock's class BEFORE loading the file, not between test cases.

local assertx    = require("assert")
local load_addon = require("load_addon")
local mock       = require("mock_wow")

local M = {}

local function fresh(class)
    mock.reset()
    mock.playerClass    = class or "ROGUE"
    mock.playerClassLoc = class and (class:sub(1, 1) .. class:sub(2):lower()) or "Rogue"

    local ns = {}
    load_addon.load("Utils.lua",      "BarWarden", ns)
    load_addon.load("Conditions.lua", "BarWarden", ns)
    return ns
end

-- --------------------------------------------------------------------------
-- Dispatch shape
-- --------------------------------------------------------------------------

function M.test_nilConditionsKeepsBarVisible()
    local ns = fresh()
    assertx.assertTrue(ns:EvaluateConditions(nil, nil))
end

function M.test_unrestrictedConditionsKeepsBarVisible()
    local ns = fresh()
    assertx.assertTrue(ns:EvaluateConditions(nil, {}))
end

-- --------------------------------------------------------------------------
-- requireClass
-- --------------------------------------------------------------------------

function M.test_requireClass_matchesPlayerClass()
    local ns = fresh("ROGUE")
    assertx.assertTrue(ns:EvaluateConditions(nil, { requireClass = "ROGUE" }))
end

function M.test_requireClass_rejectsMismatch()
    local ns = fresh("ROGUE")
    assertx.assertFalse(ns:EvaluateConditions(nil, { requireClass = "WARRIOR" }))
end

function M.test_requireClass_emptyStringIsNoop()
    local ns = fresh("ROGUE")
    assertx.assertTrue(ns:EvaluateConditions(nil, { requireClass = "" }))
end

-- --------------------------------------------------------------------------
-- combatOnly / outOfCombatOnly
-- --------------------------------------------------------------------------

function M.test_combatOnly_hiddenWhenOutOfCombat()
    local ns = fresh()
    mock.playerCombat = false
    assertx.assertFalse(ns:EvaluateConditions(nil, { combatOnly = true }))
end

function M.test_combatOnly_visibleWhenInCombat()
    local ns = fresh()
    mock.playerCombat = true
    assertx.assertTrue(ns:EvaluateConditions(nil, { combatOnly = true }))
end

function M.test_outOfCombatOnly_inverse()
    local ns = fresh()
    mock.playerCombat = false
    assertx.assertTrue(ns:EvaluateConditions(nil, { outOfCombatOnly = true }))
    mock.playerCombat = true
    assertx.assertFalse(ns:EvaluateConditions(nil, { outOfCombatOnly = true }))
end

-- --------------------------------------------------------------------------
-- requireBuff
-- --------------------------------------------------------------------------

function M.test_requireBuff_matchesByName()
    local ns = fresh()
    mock.buffs.player[1] = { name = "Slice and Dice", spellId = 5171 }
    assertx.assertTrue(ns:EvaluateConditions(nil, { requireBuff = "Slice and Dice" }))
end

function M.test_requireBuff_matchesBySpellIdString()
    local ns = fresh()
    mock.buffs.player[1] = { name = "Slice and Dice", spellId = 5171 }
    assertx.assertTrue(ns:EvaluateConditions(nil, { requireBuff = "5171" }))
end

function M.test_requireBuff_rejectsWhenAbsent()
    local ns = fresh()
    -- No buffs on player
    assertx.assertFalse(ns:EvaluateConditions(nil, { requireBuff = "Slice and Dice" }))
end

-- --------------------------------------------------------------------------
-- healthBelow
-- --------------------------------------------------------------------------

function M.test_healthBelow_visibleWhenBelowThreshold()
    local ns = fresh()
    mock.playerHealth    = 30
    mock.playerHealthMax = 100
    assertx.assertTrue(ns:EvaluateConditions(nil, { healthBelow = 35 }))
end

function M.test_healthBelow_hiddenAtOrAboveThreshold()
    local ns = fresh()
    mock.playerHealth    = 40
    mock.playerHealthMax = 100
    assertx.assertFalse(ns:EvaluateConditions(nil, { healthBelow = 35 }))
end

function M.test_healthBelow_tolerantOfZeroMax()
    -- UnitHealthMax returns 0 briefly during loading screens. Treat as visible.
    local ns = fresh()
    mock.playerHealth    = 0
    mock.playerHealthMax = 0
    assertx.assertTrue(ns:EvaluateConditions(nil, { healthBelow = 35 }))
end

-- --------------------------------------------------------------------------
-- Group / raid
-- --------------------------------------------------------------------------

function M.test_inGroup_requiresPartyMember()
    local ns = fresh()
    mock.partyMembers = 0
    assertx.assertFalse(ns:EvaluateConditions(nil, { inGroup = true }))
    mock.partyMembers = 2
    assertx.assertTrue(ns:EvaluateConditions(nil, { inGroup = true }))
end

function M.test_inRaid_requiresRaidMember()
    local ns = fresh()
    mock.raidMembers = 0
    assertx.assertFalse(ns:EvaluateConditions(nil, { inRaid = true }))
    mock.raidMembers = 10
    assertx.assertTrue(ns:EvaluateConditions(nil, { inRaid = true }))
end

-- --------------------------------------------------------------------------
-- Player-state gates
-- --------------------------------------------------------------------------

function M.test_hideWhileMounted()
    local ns = fresh()
    mock.playerMounted = true
    assertx.assertFalse(ns:EvaluateConditions(nil, { hideWhileMounted = true }))
    mock.playerMounted = false
    assertx.assertTrue(ns:EvaluateConditions(nil, { hideWhileMounted = true }))
end

function M.test_hideWhileResting()
    local ns = fresh()
    mock.playerResting = true
    assertx.assertFalse(ns:EvaluateConditions(nil, { hideWhileResting = true }))
    mock.playerResting = false
    assertx.assertTrue(ns:EvaluateConditions(nil, { hideWhileResting = true }))
end

function M.test_hideInVehicle()
    local ns = fresh()
    mock.playerInVehicle = true
    assertx.assertFalse(ns:EvaluateConditions(nil, { hideInVehicle = true }))
    mock.playerInVehicle = false
    assertx.assertTrue(ns:EvaluateConditions(nil, { hideInVehicle = true }))
end

function M.test_onlyInInstance()
    local ns = fresh()
    mock.playerInInstance = false
    assertx.assertFalse(ns:EvaluateConditions(nil, { onlyInInstance = true }))
    mock.playerInInstance = true
    assertx.assertTrue(ns:EvaluateConditions(nil, { onlyInInstance = true }))
end

-- --------------------------------------------------------------------------
-- Short-circuit + composition
-- --------------------------------------------------------------------------

function M.test_shortCircuitOnFirstFailure()
    -- If requireClass fails, later (more expensive) checks must not determine
    -- the outcome. We can't directly observe short-circuit, but we CAN assert
    -- that a would-pass follow-up condition doesn't rescue a failing earlier one.
    local ns = fresh("ROGUE")
    mock.playerCombat = true
    assertx.assertFalse(
        ns:EvaluateConditions(nil, { requireClass = "WARRIOR", combatOnly = true }),
        "later passing condition should not override an earlier failure")
end

function M.test_allConditionsAndedTogether()
    local ns = fresh("ROGUE")
    mock.playerCombat = true
    mock.playerHealth = 50
    mock.playerHealthMax = 100
    assertx.assertTrue(ns:EvaluateConditions(nil, {
        requireClass = "ROGUE",
        combatOnly   = true,
        healthBelow  = 60,
    }))
end

-- --------------------------------------------------------------------------
-- Standalone helpers (not part of the registry)
-- --------------------------------------------------------------------------

function M.test_shouldHideWhenInactive()
    local ns = fresh()
    assertx.assertFalse(ns:ShouldHideWhenInactive(nil))
    assertx.assertFalse(ns:ShouldHideWhenInactive({}))
    assertx.assertTrue(ns:ShouldHideWhenInactive({ hideWhenInactive = true }))
end

-- --------------------------------------------------------------------------
-- ResolveHideWhenInactive: the group-level switch. Bars carry an explicit
-- false by default, so the group turning it on must still win (an OR), or the
-- group control would never do anything.
-- --------------------------------------------------------------------------

local function barIn(groupIndex, barConditions)
    return { frameIndex = groupIndex, barData = { conditions = barConditions } }
end

function M.test_resolveHideWhenInactive_barOwnSettingHides()
    local ns = fresh()
    _G.BarWardenDB = { frames = { { groupConditions = {} } } }
    assertx.assertTrue(ns:ResolveHideWhenInactive(barIn(1, { hideWhenInactive = true })))
    _G.BarWardenDB = nil
end

function M.test_resolveHideWhenInactive_groupSwitchHidesPlainBars()
    local ns = fresh()
    _G.BarWardenDB = { frames = { { groupConditions = { hideWhenInactive = true } } } }
    -- The default a new bar is written with.
    assertx.assertTrue(ns:ResolveHideWhenInactive(barIn(1, { hideWhenInactive = false })))
    assertx.assertTrue(ns:ResolveHideWhenInactive(barIn(1, {})))
    _G.BarWardenDB = nil
end

function M.test_resolveHideWhenInactive_offWhenNeitherSet()
    local ns = fresh()
    _G.BarWardenDB = { frames = { { groupConditions = {} } } }
    assertx.assertFalse(ns:ResolveHideWhenInactive(barIn(1, { hideWhenInactive = false })))
    assertx.assertFalse(ns:ResolveHideWhenInactive(barIn(1, {})))
    _G.BarWardenDB = nil
end

-- Only the bar's OWN group applies.
function M.test_resolveHideWhenInactive_isPerGroup()
    local ns = fresh()
    _G.BarWardenDB = { frames = {
        { groupConditions = { hideWhenInactive = true } },
        { groupConditions = {} },
    } }
    assertx.assertTrue(ns:ResolveHideWhenInactive(barIn(1, {})))
    assertx.assertFalse(ns:ResolveHideWhenInactive(barIn(2, {})))
    _G.BarWardenDB = nil
end

function M.test_resolveHideWhenInactive_safeWithoutData()
    local ns = fresh()
    assertx.assertFalse(ns:ResolveHideWhenInactive(nil))
    assertx.assertFalse(ns:ResolveHideWhenInactive({}))
end

function M.test_shouldShowEmpty_defaultsTrue()
    local ns = fresh()
    assertx.assertTrue(ns:ShouldShowEmpty(nil))
    assertx.assertTrue(ns:ShouldShowEmpty({}))
    assertx.assertFalse(ns:ShouldShowEmpty({ showEmpty = false }))
end

return M
