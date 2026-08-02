-- tests/test_frame_manager.lua
-- Covers ns.CompareAppearance and ns.IsGroupEmptyForBackdrop, the pure
-- functions exposed off FrameManager.lua. Everything else in that file builds
-- real WoW frames (CreateFrame, GetTime-driven positioning), which is out of
-- scope for this harness and rides the in-game smoke test instead; these two
-- are exposed on `ns` specifically so this logic can be checked here.

local assertx    = require("assert")
local load_addon = require("load_addon")

local M = {}

local function fresh()
    local ns = {}
    load_addon.load("Utils.lua", "BarWarden", ns)
    load_addon.load("DB.lua", "BarWarden", ns)
    load_addon.load("FrameManager.lua", "BarWarden", ns)
    return ns
end

-- Lower appearanceOrder means "started earlier", so it sorts first.
function M.test_appearance_ordersOldestFirst()
    local ns = fresh()
    local older = { appearanceOrder = 1 }
    local newer = { appearanceOrder = 2 }
    assertx.assertTrue(ns.CompareAppearance(older, newer))
    assertx.assertFalse(ns.CompareAppearance(newer, older))
end

-- A resource bar (or anything that never went through ActivateBar /
-- ActivateStaticBar) carries no stamp at all and must sort last, not error.
function M.test_unstampedBarSortsLast()
    local ns = fresh()
    local stamped   = { appearanceOrder = 5 }
    local unstamped = {}
    assertx.assertTrue(ns.CompareAppearance(stamped, unstamped))
    assertx.assertFalse(ns.CompareAppearance(unstamped, stamped))
end

-- table.sort requires a strict weak ordering: two elements can never both
-- compare "less than" each other. Two unstamped bars used to be the risky
-- case (nothing to compare), so check that explicitly.
function M.test_twoUnstampedBars_neverBothCompareTrue()
    local ns = fresh()
    local x, y = {}, {}
    local xLessY = ns.CompareAppearance(x, y)
    local yLessX = ns.CompareAppearance(y, x)
    assertx.assertFalse(xLessY and yLessX, "comparator is not a strict weak ordering")
end

-- Sanity check against table.sort itself: mixed stamped/unstamped bars sort
-- into ascending appearance order with every unstamped bar trailing.
function M.test_sortWithMixedStamps()
    local ns = fresh()
    local bars = {
        { name = "c", appearanceOrder = 3 },
        { name = "unstamped1" },
        { name = "a", appearanceOrder = 1 },
        { name = "unstamped2" },
        { name = "b", appearanceOrder = 2 },
    }
    table.sort(bars, ns.CompareAppearance)
    assertx.assertEqual(bars[1].name, "a")
    assertx.assertEqual(bars[2].name, "b")
    assertx.assertEqual(bars[3].name, "c")
    -- The two unstamped bars trail, in some order; just confirm both are last.
    local tailNames = { bars[4].name, bars[5].name }
    table.sort(tailNames)
    assertx.assertEqual(tailNames[1], "unstamped1")
    assertx.assertEqual(tailNames[2], "unstamped2")
end

-- IsGroupEmptyForBackdrop: the v2.2.1 regression. An ordinary group's
-- emptiness is its configured bar count, same as before this was pulled out.
function M.test_isGroupEmptyForBackdrop_ordinaryGroup_noBars()
    local ns = fresh()
    local group = { isAutoGroup = false }
    local frameData = { bars = {} }
    assertx.assertTrue(ns.IsGroupEmptyForBackdrop(group, frameData, 0))
end

function M.test_isGroupEmptyForBackdrop_ordinaryGroup_withBars()
    local ns = fresh()
    local group = { isAutoGroup = false }
    local frameData = { bars = { { name = "Bar 1" } } }
    -- visibleCount = 0 on purpose: an ordinary group with a configured bar
    -- that just isn't showing right now still counts as "not empty" - it is
    -- keyed off configured bars, not what is currently on screen.
    assertx.assertFalse(ns.IsGroupEmptyForBackdrop(group, frameData, 0))
end

-- A pure auto group's frameData.bars is always the dormant hand-list (empty
-- for a group that has never been anything but auto-tracking), so #bars == 0
-- must NOT force the solid backdrop here - that was the v2.2.1 bug: Background
-- Opacity 0 still showed a solid black panel whenever the group had anything
-- in it, because this check looked at the wrong list.
function M.test_isGroupEmptyForBackdrop_autoGroup_slotsFilled()
    local ns = fresh()
    local group = { isAutoGroup = true }
    local frameData = { bars = {}, autoTrack = "player" }
    assertx.assertFalse(ns.IsGroupEmptyForBackdrop(group, frameData, 3))
end

-- An auto group with nothing currently on the unit still needs the solid
-- backdrop, or an unlocked-but-momentarily-empty group would vanish into the
-- user's own (possibly near-invisible) background alpha.
function M.test_isGroupEmptyForBackdrop_autoGroup_noneVisible()
    local ns = fresh()
    local group = { isAutoGroup = true }
    local frameData = { bars = {}, autoTrack = "player" }
    assertx.assertTrue(ns.IsGroupEmptyForBackdrop(group, frameData, 0))
end

return M
