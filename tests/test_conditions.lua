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
    -- DB.lua supplies ns.DEFAULTS.visual (stackFontSize/stackColor), the
    -- addon-wide fallback ns:GetVisual() reads for GetStackFontSize/
    -- GetStackColor below.
    load_addon.load("DB.lua",         "BarWarden", ns)
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

-- --------------------------------------------------------------------------
-- ResolveHideWhenInactive: the group switch wins once it has been touched, in
-- BOTH directions. An untouched group leaves the decision to each bar. It is
-- deliberately not an OR - that could only add hiding, so a group whose bars
-- all set the flag themselves could never be revealed from the group control.
-- --------------------------------------------------------------------------

local function barIn(groupIndex, barConditions)
    return { frameIndex = groupIndex, barData = { conditions = barConditions } }
end

-- Untouched group (the common case): each bar decides for itself.
function M.test_resolveHideWhenInactive_untouchedGroupDefersToBar()
    local ns = fresh()
    _G.BarWardenDB = { frames = { { groupConditions = {} } } }
    assertx.assertTrue(ns:ResolveHideWhenInactive(barIn(1, { hideWhenInactive = true })))
    assertx.assertFalse(ns:ResolveHideWhenInactive(barIn(1, { hideWhenInactive = false })))
    assertx.assertFalse(ns:ResolveHideWhenInactive(barIn(1, {})))
    _G.BarWardenDB = nil
end

-- Group ticked: hides every bar, including ones written with an explicit false.
function M.test_resolveHideWhenInactive_groupOnHidesAll()
    local ns = fresh()
    _G.BarWardenDB = { frames = { { groupConditions = { hideWhenInactive = true } } } }
    assertx.assertTrue(ns:ResolveHideWhenInactive(barIn(1, { hideWhenInactive = false })))
    assertx.assertTrue(ns:ResolveHideWhenInactive(barIn(1, {})))
    _G.BarWardenDB = nil
end

-- Group unticked: reveals every bar, overriding bars that hide on their own.
-- This is the case an OR could never express.
function M.test_resolveHideWhenInactive_groupOffRevealsAll()
    local ns = fresh()
    _G.BarWardenDB = { frames = { { groupConditions = { hideWhenInactive = false } } } }
    assertx.assertFalse(ns:ResolveHideWhenInactive(barIn(1, { hideWhenInactive = true })))
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

-- --------------------------------------------------------------------------
-- ShouldHideEmptyGroup: whether an empty group's FRAME hides (title and all),
-- as opposed to ResolveHideWhenInactive above which is about individual bars.
-- Same ~= nil, group-authoritative shape: once touched, Hide When Inactive
-- wins outright in both directions regardless of lock state or group type.
-- Untouched (nil) must reproduce the behaviour that existed before this
-- setting had any say over the frame: an auto group stays up unlocked and
-- hides locked; an ordinary group always hides when empty.
-- --------------------------------------------------------------------------

-- Ticked: hides, whether locked or unlocked, auto or ordinary group.
function M.test_shouldHideEmptyGroup_tickedHidesRegardlessOfLockOrType()
    local ns = fresh()
    local frameData = { groupConditions = { hideWhenInactive = true } }
    assertx.assertTrue(ns:ShouldHideEmptyGroup(frameData, true, true))
    assertx.assertTrue(ns:ShouldHideEmptyGroup(frameData, true, false))
    assertx.assertTrue(ns:ShouldHideEmptyGroup(frameData, false, true))
    assertx.assertTrue(ns:ShouldHideEmptyGroup(frameData, false, false))
end

-- Unticked: stays up, whether locked or unlocked, auto or ordinary group.
-- This is the case the owner could not previously express at all.
function M.test_shouldHideEmptyGroup_untickedKeepsGroupUpRegardlessOfLockOrType()
    local ns = fresh()
    local frameData = { groupConditions = { hideWhenInactive = false } }
    assertx.assertFalse(ns:ShouldHideEmptyGroup(frameData, true, true))
    assertx.assertFalse(ns:ShouldHideEmptyGroup(frameData, true, false))
    assertx.assertFalse(ns:ShouldHideEmptyGroup(frameData, false, true))
    assertx.assertFalse(ns:ShouldHideEmptyGroup(frameData, false, false))
end

-- Untouched, auto group: reproduces today's behaviour exactly - visible
-- unlocked (so it can still be found and arranged), hidden locked.
function M.test_shouldHideEmptyGroup_untouchedAutoGroupFollowsLockState()
    local ns = fresh()
    local frameData = { groupConditions = {} }
    assertx.assertFalse(ns:ShouldHideEmptyGroup(frameData, true, false))
    assertx.assertTrue(ns:ShouldHideEmptyGroup(frameData, true, true))
end

-- Untouched, ordinary group: reproduces today's behaviour exactly - there was
-- never a lock-based carve-out for a non-auto group, so it always hides.
function M.test_shouldHideEmptyGroup_untouchedOrdinaryGroupAlwaysHides()
    local ns = fresh()
    local frameData = { groupConditions = {} }
    assertx.assertTrue(ns:ShouldHideEmptyGroup(frameData, false, false))
    assertx.assertTrue(ns:ShouldHideEmptyGroup(frameData, false, true))
end

-- Nil-safe: nil frameData, a frameData with no groupConditions, and no data
-- at all must all fall through to the untouched default rather than erroring.
function M.test_shouldHideEmptyGroup_safeWithoutData()
    local ns = fresh()
    assertx.assertFalse(ns:ShouldHideEmptyGroup(nil, true, false))
    assertx.assertTrue(ns:ShouldHideEmptyGroup(nil, true, true))
    assertx.assertTrue(ns:ShouldHideEmptyGroup(nil, false, false))
    assertx.assertFalse(ns:ShouldHideEmptyGroup({}, true, false))
    assertx.assertTrue(ns:ShouldHideEmptyGroup({}, false, true))
end

-- --------------------------------------------------------------------------
-- IsBarEnabled: a bar switched off in the editor must never be drawn. Four
-- sites used to decide this independently and disagreed.
-- --------------------------------------------------------------------------

function M.test_isBarEnabled_defaultsEnabled()
    local ns = fresh()
    assertx.assertTrue(ns:IsBarEnabled({ barData = {} }))
    assertx.assertTrue(ns:IsBarEnabled({ barData = { enabled = true } }))
end

function M.test_isBarEnabled_falseDisables()
    local ns = fresh()
    assertx.assertFalse(ns:IsBarEnabled({ barData = { enabled = false } }))
end

-- Only an explicit false disables; a missing bar or barData is treated as
-- enabled so a half-built bar is never silently hidden.
function M.test_isBarEnabled_safeWithoutData()
    local ns = fresh()
    assertx.assertTrue(ns:IsBarEnabled(nil))
    assertx.assertTrue(ns:IsBarEnabled({}))
end

-- --------------------------------------------------------------------------
-- IsSwitchBar: the group's Bar Style wins once set, in BOTH directions,
-- mirroring ResolveHideWhenInactive's group-over-bar shape. An untouched
-- group ("" / nil barStyle) leaves the decision to bar.display.switchMode.
-- --------------------------------------------------------------------------

local function switchBarIn(groupIndex, display)
    return { frameIndex = groupIndex, barData = { display = display } }
end

-- Group set to SWITCH overrides a bar that never opted in.
function M.test_isSwitchBar_groupSwitchOverridesBar()
    local ns = fresh()
    _G.BarWardenDB = { frames = { { barStyle = "SWITCH" } } }
    assertx.assertTrue(ns:IsSwitchBar(switchBarIn(1, {})))
    assertx.assertTrue(ns:IsSwitchBar(switchBarIn(1, { switchMode = false })))
    _G.BarWardenDB = nil
end

-- Group set to COUNTDOWN overrides a bar that opted into switch mode itself.
function M.test_isSwitchBar_groupCountdownOverridesBar()
    local ns = fresh()
    _G.BarWardenDB = { frames = { { barStyle = "COUNTDOWN" } } }
    assertx.assertFalse(ns:IsSwitchBar(switchBarIn(1, { switchMode = true })))
    _G.BarWardenDB = nil
end

-- Untouched group (no barStyle): each bar decides for itself, both ways.
function M.test_isSwitchBar_untouchedGroupDefersToBar()
    local ns = fresh()
    _G.BarWardenDB = { frames = { {} } }
    assertx.assertTrue(ns:IsSwitchBar(switchBarIn(1, { switchMode = true })))
    assertx.assertFalse(ns:IsSwitchBar(switchBarIn(1, { switchMode = false })))
    assertx.assertFalse(ns:IsSwitchBar(switchBarIn(1, {})))
    _G.BarWardenDB = nil
end

-- Safe without data: nil bar, nil barData and nil display all return false.
function M.test_isSwitchBar_safeWithoutData()
    local ns = fresh()
    assertx.assertFalse(ns:IsSwitchBar(nil))
    assertx.assertFalse(ns:IsSwitchBar({}))
    assertx.assertFalse(ns:IsSwitchBar({ frameIndex = 1, barData = {} }))
end

-- No frameIndex: no group to consult, so the bar's own setting decides.
function M.test_isSwitchBar_noFrameIndexFallsBackToBar()
    local ns = fresh()
    _G.BarWardenDB = { frames = { { barStyle = "SWITCH" } } }
    assertx.assertTrue(ns:IsSwitchBar({ barData = { display = { switchMode = true } } }))
    assertx.assertFalse(ns:IsSwitchBar({ barData = { display = { switchMode = false } } }))
    _G.BarWardenDB = nil
end

-- --------------------------------------------------------------------------
-- GetStackFontSize / GetStackColor: bar overrides group overrides the
-- addon-wide default (Visuals tab), mirroring IsSwitchBar's per-level shape
-- but resolving a value instead of a boolean. Reuses switchBarIn since the
-- shape it builds (frameIndex + barData.display) is exactly what these
-- resolvers read too.
-- --------------------------------------------------------------------------

function M.test_getStackFontSize_barWinsOverGroupAndGlobal()
    local ns = fresh()
    _G.BarWardenDB = { frames = { { stackFontSize = 18 } }, visual = { stackFontSize = 12 } }
    assertx.assertEqual(ns:GetStackFontSize(switchBarIn(1, { stackFontSize = 24 })), 24)
    _G.BarWardenDB = nil
end

function M.test_getStackFontSize_groupWinsOverGlobalWhenBarHasNone()
    local ns = fresh()
    _G.BarWardenDB = { frames = { { stackFontSize = 18 } }, visual = { stackFontSize = 12 } }
    assertx.assertEqual(ns:GetStackFontSize(switchBarIn(1, {})), 18)
    _G.BarWardenDB = nil
end

function M.test_getStackFontSize_usesGlobalWhenNeitherSet()
    local ns = fresh()
    _G.BarWardenDB = { frames = { {} }, visual = { stackFontSize = 12 } }
    assertx.assertEqual(ns:GetStackFontSize(switchBarIn(1, {})), 12)
    _G.BarWardenDB = nil
end

-- Nil-safe at every step: nil bar, empty bar, missing frameIndex, and no
-- BarWardenDB at all must all fall through to the addon-wide default rather
-- than erroring.
function M.test_getStackFontSize_safeWithoutData()
    local ns = fresh()
    assertx.assertEqual(ns:GetStackFontSize(nil), 12)
    assertx.assertEqual(ns:GetStackFontSize({}), 12)
    assertx.assertEqual(ns:GetStackFontSize({ frameIndex = 1, barData = {} }), 12)

    _G.BarWardenDB = { frames = {} }
    assertx.assertEqual(ns:GetStackFontSize(switchBarIn(1, {})), 12)
    _G.BarWardenDB = nil
end

function M.test_getStackColor_barWinsOverGroupAndGlobal()
    local ns = fresh()
    _G.BarWardenDB = {
        frames = { { stackColor = { r = 0, g = 1, b = 0 } } },
        visual = { stackColor = { r = 1, g = 1, b = 1 } },
    }
    local color = ns:GetStackColor(switchBarIn(1, { stackColor = { r = 1, g = 0, b = 0 } }))
    assertx.assertEqual(color.r, 1)
    assertx.assertEqual(color.g, 0)
    assertx.assertEqual(color.b, 0)
    _G.BarWardenDB = nil
end

function M.test_getStackColor_groupWinsOverGlobalWhenBarHasNone()
    local ns = fresh()
    _G.BarWardenDB = {
        frames = { { stackColor = { r = 0, g = 1, b = 0 } } },
        visual = { stackColor = { r = 1, g = 1, b = 1 } },
    }
    local color = ns:GetStackColor(switchBarIn(1, {}))
    assertx.assertEqual(color.r, 0)
    assertx.assertEqual(color.g, 1)
    assertx.assertEqual(color.b, 0)
    _G.BarWardenDB = nil
end

function M.test_getStackColor_usesGlobalWhenNeitherSet()
    local ns = fresh()
    _G.BarWardenDB = { frames = { {} }, visual = { stackColor = { r = 1, g = 1, b = 1 } } }
    local color = ns:GetStackColor(switchBarIn(1, {}))
    assertx.assertEqual(color.r, 1)
    assertx.assertEqual(color.g, 1)
    assertx.assertEqual(color.b, 1)
    _G.BarWardenDB = nil
end

function M.test_getStackColor_safeWithoutData()
    local ns = fresh()
    assertx.assertNotNil(ns:GetStackColor(nil))
    assertx.assertNotNil(ns:GetStackColor({}))
    assertx.assertNotNil(ns:GetStackColor({ frameIndex = 1, barData = {} }))

    _G.BarWardenDB = { frames = {} }
    local color = ns:GetStackColor(switchBarIn(1, {}))
    assertx.assertEqual(color.r, 1)
    assertx.assertEqual(color.g, 1)
    assertx.assertEqual(color.b, 1)
    _G.BarWardenDB = nil
end

return M
