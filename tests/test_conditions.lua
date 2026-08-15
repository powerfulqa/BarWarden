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

-- conditionsFailed is the most authoritative input: a group whose Combat
-- Only (or any other) condition currently fails must hide, full stop. It
-- beats the auto-group unlocked carve-out below, which was written for a
-- group that is empty because nothing matched, not because the user's own
-- condition said "hide this". Locked/unlocked and auto/ordinary should not
-- matter once conditionsFailed is true.
function M.test_shouldHideEmptyGroup_conditionsFailedHidesAutoGroupRegardlessOfLock()
    local ns = fresh()
    local frameData = { groupConditions = {} }
    assertx.assertTrue(ns:ShouldHideEmptyGroup(frameData, true, true, true))
    assertx.assertTrue(ns:ShouldHideEmptyGroup(frameData, true, false, true))
end

function M.test_shouldHideEmptyGroup_conditionsFailedHidesOrdinaryGroup()
    local ns = fresh()
    local frameData = { groupConditions = {} }
    assertx.assertTrue(ns:ShouldHideEmptyGroup(frameData, false, true, true))
    assertx.assertTrue(ns:ShouldHideEmptyGroup(frameData, false, false, true))
end

-- conditionsFailed wins even over an explicit hideWhenInactive = false: the
-- condition is the more specific instruction ("hide this exact group right
-- now") than the general "don't hide me when idle" default.
function M.test_shouldHideEmptyGroup_conditionsFailedBeatsExplicitHideWhenInactiveFalse()
    local ns = fresh()
    local frameData = { groupConditions = { hideWhenInactive = false } }
    assertx.assertTrue(ns:ShouldHideEmptyGroup(frameData, true, true, true))
    assertx.assertTrue(ns:ShouldHideEmptyGroup(frameData, true, false, true))
    assertx.assertTrue(ns:ShouldHideEmptyGroup(frameData, false, false, true))
end

-- conditionsFailed false (or omitted, as every call above this section makes
-- it) must reproduce the existing truth table exactly - nothing already
-- tested changes.
function M.test_shouldHideEmptyGroup_conditionsNotFailedReproducesExistingTable()
    local ns = fresh()
    local ticked   = { groupConditions = { hideWhenInactive = true } }
    local unticked = { groupConditions = { hideWhenInactive = false } }
    local untouched = { groupConditions = {} }

    assertx.assertTrue(ns:ShouldHideEmptyGroup(ticked, true, false, false))
    assertx.assertFalse(ns:ShouldHideEmptyGroup(unticked, true, true, false))
    assertx.assertFalse(ns:ShouldHideEmptyGroup(untouched, true, false, false))
    assertx.assertTrue(ns:ShouldHideEmptyGroup(untouched, true, true, false))
    assertx.assertTrue(ns:ShouldHideEmptyGroup(untouched, false, false, false))
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

-- --------------------------------------------------------------------------
-- GetBarGlowOnReady / GetBarPulseOnReady / GetBarLingerTime: most-specific-
-- wins (bar, then group, then off), the same per-level shape as
-- GetStackFontSize/GetStackColor above rather than IsSwitchBar's group-
-- authoritative one. Reuses switchBarIn for the same reason those two do.
-- --------------------------------------------------------------------------

function M.test_getBarGlowOnReady_barWinsOverGroup()
    local ns = fresh()
    _G.BarWardenDB = { frames = { { glowOnReady = false } } }
    assertx.assertTrue(ns:GetBarGlowOnReady(switchBarIn(1, { glowOnReady = true })))
    _G.BarWardenDB = nil
end

function M.test_getBarGlowOnReady_groupWinsWhenBarHasNone()
    local ns = fresh()
    _G.BarWardenDB = { frames = { { glowOnReady = true } } }
    assertx.assertTrue(ns:GetBarGlowOnReady(switchBarIn(1, { glowOnReady = false })))
    _G.BarWardenDB = nil
end

function M.test_getBarGlowOnReady_offWhenNeitherSet()
    local ns = fresh()
    _G.BarWardenDB = { frames = { {} } }
    assertx.assertFalse(ns:GetBarGlowOnReady(switchBarIn(1, { glowOnReady = false })))
    _G.BarWardenDB = nil
end

-- Safe without data: nil bar, nil barData, missing frameIndex and a missing
-- group entry all fall through to false rather than erroring.
function M.test_getBarGlowOnReady_safeWithoutData()
    local ns = fresh()
    assertx.assertFalse(ns:GetBarGlowOnReady(nil))
    assertx.assertFalse(ns:GetBarGlowOnReady({}))
    assertx.assertFalse(ns:GetBarGlowOnReady({ frameIndex = 1, barData = {} }))

    _G.BarWardenDB = { frames = {} }
    assertx.assertFalse(ns:GetBarGlowOnReady(switchBarIn(1, {})))
    _G.BarWardenDB = nil
end

function M.test_getBarPulseOnReady_barWinsOverGroup()
    local ns = fresh()
    _G.BarWardenDB = { frames = { { pulseOnReady = false } } }
    assertx.assertTrue(ns:GetBarPulseOnReady(switchBarIn(1, { pulseOnReady = true })))
    _G.BarWardenDB = nil
end

function M.test_getBarPulseOnReady_groupWinsWhenBarHasNone()
    local ns = fresh()
    _G.BarWardenDB = { frames = { { pulseOnReady = true } } }
    assertx.assertTrue(ns:GetBarPulseOnReady(switchBarIn(1, { pulseOnReady = false })))
    _G.BarWardenDB = nil
end

function M.test_getBarPulseOnReady_offWhenNeitherSet()
    local ns = fresh()
    _G.BarWardenDB = { frames = { {} } }
    assertx.assertFalse(ns:GetBarPulseOnReady(switchBarIn(1, { pulseOnReady = false })))
    _G.BarWardenDB = nil
end

function M.test_getBarPulseOnReady_safeWithoutData()
    local ns = fresh()
    assertx.assertFalse(ns:GetBarPulseOnReady(nil))
    assertx.assertFalse(ns:GetBarPulseOnReady({}))
    assertx.assertFalse(ns:GetBarPulseOnReady({ frameIndex = 1, barData = {} }))

    _G.BarWardenDB = { frames = {} }
    assertx.assertFalse(ns:GetBarPulseOnReady(switchBarIn(1, {})))
    _G.BarWardenDB = nil
end

function M.test_getBarLingerTime_barWinsOverGroup()
    local ns = fresh()
    _G.BarWardenDB = { frames = { { lingerTime = 1 } } }
    assertx.assertEqual(ns:GetBarLingerTime(switchBarIn(1, { lingerTime = 3 })), 3)
    _G.BarWardenDB = nil
end

function M.test_getBarLingerTime_groupWinsWhenBarHasNone()
    local ns = fresh()
    _G.BarWardenDB = { frames = { { lingerTime = 2 } } }
    assertx.assertEqual(ns:GetBarLingerTime(switchBarIn(1, {})), 2)
    _G.BarWardenDB = nil
end

-- Regression: an auto slot's display always carries lingerTime = 0 (its only
-- seeded field - NewAutoBarData, FrameManager.lua) and an ordinary bar's
-- display defaults to the same 0 (NewBar, Options_Bars.lua). 0 is truthy in
-- Lua, so a bare `if disp.lingerTime then` would misread that untouched
-- default as an explicit bar override and the group's Linger Time would
-- never be reachable. This is the case that makes "an auto slot never has
-- its own value, so the group's always applies there" true.
function M.test_getBarLingerTime_barZeroDoesNotShadowGroup()
    local ns = fresh()
    _G.BarWardenDB = { frames = { { lingerTime = 2.5 } } }
    assertx.assertEqual(ns:GetBarLingerTime(switchBarIn(1, { lingerTime = 0 })), 2.5)
    _G.BarWardenDB = nil
end

function M.test_getBarLingerTime_offWhenNeitherSet()
    local ns = fresh()
    _G.BarWardenDB = { frames = { {} } }
    assertx.assertEqual(ns:GetBarLingerTime(switchBarIn(1, {})), 0)
    _G.BarWardenDB = nil
end

-- Safe without data: nil bar, nil barData, missing frameIndex and a missing
-- group entry all fall through to 0 rather than erroring.
function M.test_getBarLingerTime_safeWithoutData()
    local ns = fresh()
    assertx.assertEqual(ns:GetBarLingerTime(nil), 0)
    assertx.assertEqual(ns:GetBarLingerTime({}), 0)
    assertx.assertEqual(ns:GetBarLingerTime({ frameIndex = 1, barData = {} }), 0)

    _G.BarWardenDB = { frames = {} }
    assertx.assertEqual(ns:GetBarLingerTime(switchBarIn(1, {})), 0)
    _G.BarWardenDB = nil
end

-- --------------------------------------------------------------------------
-- IsBarAlerting / GetBarAlertColor: Bar Alerts (v2.4.0). Pure arithmetic over
-- remaining/duration plus the action-variant colour resolver; no group
-- override exists for this feature, so these are plain bar-only helpers
-- (see the doc comment in Conditions.lua for why they live here anyway).
-- --------------------------------------------------------------------------

-- Master toggle off (or absent) always reads as not alerting, regardless of
-- how the rest of `display` is configured.
function M.test_isBarAlerting_offWhenMasterToggleOff()
    local ns = fresh()
    assertx.assertFalse(ns:IsBarAlerting({ sparkleAlert = false, sparkleThreshold = 5 }, 1, 10))
    assertx.assertFalse(ns:IsBarAlerting({ sparkleAlert = false }, 100, 10))
end

function M.test_isBarAlerting_safeWithoutData()
    local ns = fresh()
    assertx.assertFalse(ns:IsBarAlerting(nil, 5, 10))
    assertx.assertFalse(ns:IsBarAlerting({ sparkleAlert = true }, nil, 10))
end

-- Seconds mode (nil alertUnit, or "SECONDS") must match today's exact
-- behaviour: true at and below the threshold, false above it.
function M.test_isBarAlerting_secondsMode_matchesTodayAtThreshold()
    local ns = fresh()
    local disp = { sparkleAlert = true, sparkleThreshold = 5 }
    assertx.assertTrue(ns:IsBarAlerting(disp, 5, 30), "at threshold")
    assertx.assertTrue(ns:IsBarAlerting(disp, 4, 30), "below threshold")
    assertx.assertFalse(ns:IsBarAlerting(disp, 6, 30), "above threshold")
end

function M.test_isBarAlerting_secondsMode_defaultsToFiveSeconds()
    local ns = fresh()
    local disp = { sparkleAlert = true }
    assertx.assertTrue(ns:IsBarAlerting(disp, 5, 30))
    assertx.assertFalse(ns:IsBarAlerting(disp, 5.1, 30))
end

-- Percent mode scales with duration: the same 20% threshold reads as a
-- couple of seconds on a short buff and minutes on a long one.
function M.test_isBarAlerting_percentMode_shortDuration()
    local ns = fresh()
    local disp = { sparkleAlert = true, alertUnit = "PERCENT", alertPercent = 20 }
    -- 20% of 10s = 2s
    assertx.assertTrue(ns:IsBarAlerting(disp, 2, 10), "at 20% of a 10s buff")
    assertx.assertFalse(ns:IsBarAlerting(disp, 3, 10), "above 20% of a 10s buff")
end

function M.test_isBarAlerting_percentMode_longDuration()
    local ns = fresh()
    local disp = { sparkleAlert = true, alertUnit = "PERCENT", alertPercent = 20 }
    -- 20% of 1800s (30 min) = 360s
    assertx.assertTrue(ns:IsBarAlerting(disp, 300, 1800), "well inside the window on a 30 minute buff")
    assertx.assertFalse(ns:IsBarAlerting(disp, 400, 1800), "still outside the window on a 30 minute buff")
end

function M.test_isBarAlerting_percentMode_defaultsToTwentyPercent()
    local ns = fresh()
    local disp = { sparkleAlert = true, alertUnit = "PERCENT" }
    assertx.assertTrue(ns:IsBarAlerting(disp, 20, 100))
    assertx.assertFalse(ns:IsBarAlerting(disp, 21, 100))
end

-- A permanent/static bar (no meaningful "full length") never alerts in
-- percent mode rather than dividing by zero or reading as always-on.
function M.test_isBarAlerting_percentMode_nilOrZeroDurationNeverAlerts()
    local ns = fresh()
    local disp = { sparkleAlert = true, alertUnit = "PERCENT", alertPercent = 20 }
    assertx.assertFalse(ns:IsBarAlerting(disp, 1, nil))
    assertx.assertFalse(ns:IsBarAlerting(disp, 0, 0))
    assertx.assertFalse(ns:IsBarAlerting(disp, 1, -5))
end

-- GetBarAlertColor: nil unless the bar is actually alerting AND the action
-- includes colour. Sparkle-only never returns a colour even while alerting.
function M.test_getBarAlertColor_nilWhenActionIsSparkleOnly()
    local ns = fresh()
    local disp = { sparkleAlert = true, sparkleThreshold = 5, alertAction = "SPARKLE" }
    assertx.assertNil(ns:GetBarAlertColor(disp, 3, 30))
end

function M.test_getBarAlertColor_nilWhenNotAlerting()
    local ns = fresh()
    local disp = { sparkleAlert = true, sparkleThreshold = 5, alertAction = "COLOUR" }
    assertx.assertNil(ns:GetBarAlertColor(disp, 10, 30))
end

function M.test_getBarAlertColor_returnsCustomColourWhenActionIsColour()
    local ns = fresh()
    local disp = {
        sparkleAlert = true, sparkleThreshold = 5, alertAction = "COLOUR",
        alertColor = { r = 0, g = 0, b = 1 },
    }
    local r, g, b = ns:GetBarAlertColor(disp, 3, 30)
    assertx.assertEqual(r, 0)
    assertx.assertEqual(g, 0)
    assertx.assertEqual(b, 1)
end

function M.test_getBarAlertColor_returnsColourWhenActionIsBoth()
    local ns = fresh()
    local disp = {
        sparkleAlert = true, sparkleThreshold = 5, alertAction = "BOTH",
        alertColor = { r = 0, g = 1, b = 0 },
    }
    local r, g, b = ns:GetBarAlertColor(disp, 3, 30)
    assertx.assertEqual(r, 0)
    assertx.assertEqual(g, 1)
    assertx.assertEqual(b, 0)
end

function M.test_getBarAlertColor_defaultsToRedWhenUnset()
    local ns = fresh()
    local disp = { sparkleAlert = true, sparkleThreshold = 5, alertAction = "COLOUR" }
    local r, g, b = ns:GetBarAlertColor(disp, 3, 30)
    assertx.assertEqual(r, 1)
    assertx.assertEqual(g, 0)
    assertx.assertEqual(b, 0)
end

-- Master toggle off beats an action of Colour/Both: the whole feature is
-- off, not just the sparkle half.
function M.test_getBarAlertColor_nilWhenMasterToggleOff()
    local ns = fresh()
    local disp = { sparkleAlert = false, alertAction = "COLOUR", alertColor = { r = 1, g = 1, b = 1 } }
    assertx.assertNil(ns:GetBarAlertColor(disp, 1, 30))
end

function M.test_getBarAlertColor_safeWithoutData()
    local ns = fresh()
    assertx.assertNil(ns:GetBarAlertColor(nil, 1, 30))
end

-- --------------------------------------------------------------------------
-- ResolvePlayerFrameHidden (Hide Blizzard Player Frame, Core.lua)
-- --------------------------------------------------------------------------

function M.test_resolvePlayerFrameHidden_hidesWhenWantedAndOutOfCombat()
    local ns = fresh()
    assertx.assertTrue(ns:ResolvePlayerFrameHidden(true, false))
end

function M.test_resolvePlayerFrameHidden_deferredWhileInCombat()
    local ns = fresh()
    assertx.assertFalse(ns:ResolvePlayerFrameHidden(true, true))
end

function M.test_resolvePlayerFrameHidden_falseWhenNotWanted()
    local ns = fresh()
    assertx.assertFalse(ns:ResolvePlayerFrameHidden(false, false))
end

function M.test_resolvePlayerFrameHidden_falseWhenNeitherWantedNorInCombat()
    local ns = fresh()
    assertx.assertFalse(ns:ResolvePlayerFrameHidden(false, true))
end

function M.test_resolvePlayerFrameHidden_nilSafe()
    local ns = fresh()
    assertx.assertFalse(ns:ResolvePlayerFrameHidden(nil, nil))
end

-- --------------------------------------------------------------------------
-- Resource bar default colours (v2.5.0): ns:GetResourcePowerColor (the
-- game's own power-type colour) and ns:GetPinnedResourceColor (a per-pinned-
-- resource override, one level more specific). Both feed GetBarColor
-- (Bar.lua), which is why they live here beside the other resolvers rather
-- than in frame code - see docs/ADDON_GUIDE.md's "Group overrides" table.
-- --------------------------------------------------------------------------

-- GetPinnedResourceColor needs ns:NormalizePinnedResources (Trackers.lua),
-- so this loads one file more than the plain `fresh()` above. Cross-file at
-- runtime only (a resolver in Conditions.lua calling a helper defined in
-- Trackers.lua, which loads after it per the .toc) - fine, since neither
-- call happens until the game is fully loaded; see GetTimeBasedColor's own
-- upvalue-hoist comment (BarEngine.lua) for the one case where load ORDER
-- actually would matter, which this is not.
local function freshWithTrackers()
    local ns = fresh()
    load_addon.load("Trackers.lua", "BarWarden", ns)
    return ns
end

local function resourceBarIn(groupIndex, resourceKey)
    return { frameIndex = groupIndex, isResourceBar = true,
             barData = { resourceKey = resourceKey, display = {} } }
end

function M.test_getResourcePowerColor_usesClientPowerBarColorWhenPresent()
    local ns = fresh()
    _G.PowerBarColor = { MANA = { r = 0.1, g = 0.2, b = 0.9 } }
    local r, g, b = ns:GetResourcePowerColor(resourceBarIn(1, "mana"))
    assertx.assertEqual(r, 0.1)
    assertx.assertEqual(g, 0.2)
    assertx.assertEqual(b, 0.9)
    _G.PowerBarColor = nil
end

function M.test_getResourcePowerColor_fallsBackWithoutClientTable()
    local ns = fresh()
    _G.PowerBarColor = nil
    local r, g, b = ns:GetResourcePowerColor(resourceBarIn(1, "rage"))
    assertx.assertEqual(r, 1)
    assertx.assertEqual(g, 0)
    assertx.assertEqual(b, 0)
end

function M.test_getResourcePowerColor_fallsBackWhenClientTableMissingKey()
    local ns = fresh()
    -- Client table exists but never mentions RAGE - must still fall back,
    -- not return nil/garbage.
    _G.PowerBarColor = { MANA = { r = 0, g = 0, b = 1 } }
    local r, g, b = ns:GetResourcePowerColor(resourceBarIn(1, "rage"))
    assertx.assertEqual(r, 1)
    assertx.assertEqual(g, 0)
    assertx.assertEqual(b, 0)
    _G.PowerBarColor = nil
end

function M.test_getResourcePowerColor_healthNeverReadsPowerBarColor()
    local ns = fresh()
    -- Health is not a power type at all; PowerBarColor is never consulted
    -- for it even if some client build happened to define a HEALTH entry.
    _G.PowerBarColor = { HEALTH = { r = 1, g = 1, b = 1 } }
    local r, g, b = ns:GetResourcePowerColor(resourceBarIn(1, "health"))
    assertx.assertEqual(r, 0)
    assertx.assertEqual(g, 1)
    assertx.assertEqual(b, 0)
    _G.PowerBarColor = nil
end

function M.test_getResourcePowerColor_nilForBarWithNoResourceKey()
    local ns = fresh()
    assertx.assertNil(ns:GetResourcePowerColor({ barData = {} }))
    assertx.assertNil(ns:GetResourcePowerColor(nil))
end

function M.test_getPinnedResourceColor_returnsStoredColor()
    local ns = freshWithTrackers()
    _G.BarWardenDB = { frames = { { autoPinnedResources = {
        { key = "mana", color = { r = 0.3, g = 0.4, b = 0.5 } },
    } } } }
    local r, g, b = ns:GetPinnedResourceColor(resourceBarIn(1, "mana"))
    assertx.assertEqual(r, 0.3)
    assertx.assertEqual(g, 0.4)
    assertx.assertEqual(b, 0.5)
    _G.BarWardenDB = nil
end

function M.test_getPinnedResourceColor_nilWhenEntryHasNoColor()
    local ns = freshWithTrackers()
    _G.BarWardenDB = { frames = { { autoPinnedResources = { { key = "mana" } } } } }
    assertx.assertNil(ns:GetPinnedResourceColor(resourceBarIn(1, "mana")))
    _G.BarWardenDB = nil
end

function M.test_getPinnedResourceColor_nilWhenNotPinned()
    local ns = freshWithTrackers()
    _G.BarWardenDB = { frames = { {} } }
    assertx.assertNil(ns:GetPinnedResourceColor(resourceBarIn(1, "mana")))
    _G.BarWardenDB = nil
end

function M.test_getPinnedResourceColor_toleratesLegacySetShape()
    local ns = freshWithTrackers()
    -- Legacy shape carries no colour data at all: must not error, just nil.
    _G.BarWardenDB = { frames = { { autoPinnedResources = { mana = true } } } }
    assertx.assertNil(ns:GetPinnedResourceColor(resourceBarIn(1, "mana")))
    _G.BarWardenDB = nil
end

function M.test_getPinnedResourceColor_safeWithoutData()
    local ns = freshWithTrackers()
    assertx.assertNil(ns:GetPinnedResourceColor(nil))
    assertx.assertNil(ns:GetPinnedResourceColor({ barData = {} }))
end

return M
