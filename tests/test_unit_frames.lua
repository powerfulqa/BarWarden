-- tests/test_unit_frames.lua
-- Pure-logic coverage for UnitFrames.lua: which optional elements a unit
-- frame shows (ns:ResolveUnitFrameElements), its layout arithmetic
-- (ns:ComputeUnitFrameLayout), and the values-column formatter
-- (ns:FormatUnitFrameValue). Frame construction itself (ns:BuildUnitFrame /
-- ns:ScanUnitFrames, both CreateFrame-driven) has no test surface here and
-- rides the in-game smoke test, same carve-out as FrameManager.lua's own
-- CreateGroupFrame.

local assertx    = require("assert")
local load_addon = require("load_addon")

local M = {}

local function fresh()
    local ns = {}
    load_addon.load("Utils.lua", "BarWarden", ns)
    load_addon.load("UnitFrames.lua", "BarWarden", ns)
    return ns
end

-- --------------------------------------------------------------------------
-- ns:ResolveUnitFrameElements
-- --------------------------------------------------------------------------

function M.test_resolveElements_defaultsAllOn()
    local ns = fresh()
    local e = ns:ResolveUnitFrameElements({
        enabled = true, scale = 1.0,
        showPortrait = true, showLevel = true, showValues = true,
    })
    assertx.assertTrue(e.portrait)
    assertx.assertTrue(e.level)
    assertx.assertTrue(e.values)
end

function M.test_resolveElements_eachToggleIndependentlyOff()
    local ns = fresh()
    local noPortrait = ns:ResolveUnitFrameElements({ showPortrait = false })
    assertx.assertFalse(noPortrait.portrait)
    assertx.assertTrue(noPortrait.level)
    assertx.assertTrue(noPortrait.values)

    local noLevel = ns:ResolveUnitFrameElements({ showLevel = false })
    assertx.assertTrue(noLevel.portrait)
    assertx.assertFalse(noLevel.level)
    assertx.assertTrue(noLevel.values)

    local noValues = ns:ResolveUnitFrameElements({ showValues = false })
    assertx.assertTrue(noValues.portrait)
    assertx.assertTrue(noValues.level)
    assertx.assertFalse(noValues.values)
end

-- A nil cfg (not yet built, or read defensively before the DB loads) reads
-- as "show everything", matching ns.DEFAULTS.unitFrames.player - never an
-- error and never a frame that silently starts with everything hidden.
function M.test_resolveElements_nilCfgDefaultsAllOn()
    local ns = fresh()
    local e = ns:ResolveUnitFrameElements(nil)
    assertx.assertTrue(e.portrait)
    assertx.assertTrue(e.level)
    assertx.assertTrue(e.values)
end

-- --------------------------------------------------------------------------
-- ns:ComputeUnitFrameLayout
-- --------------------------------------------------------------------------

local ALL_ON  = { portrait = true,  level = true, values = true }
local ALL_OFF = { portrait = false, level = false, values = false }

function M.test_layout_widthGrowsWithPortraitAndValues()
    local ns = fresh()
    local bare    = ns:ComputeUnitFrameLayout(ALL_OFF, 2)
    local withPortrait = ns:ComputeUnitFrameLayout({ portrait = true, values = false }, 2)
    local withValues    = ns:ComputeUnitFrameLayout({ portrait = false, values = true }, 2)
    local withBoth       = ns:ComputeUnitFrameLayout(ALL_ON, 2)

    assertx.assertTrue(withPortrait.width > bare.width, "portrait must widen the frame")
    assertx.assertTrue(withValues.width > bare.width, "a values column must widen the frame")
    assertx.assertTrue(withBoth.width > withPortrait.width, "both together must widen further than either alone")
    assertx.assertTrue(withBoth.width > withValues.width, "both together must widen further than either alone")
end

function M.test_layout_barsStartAtZeroWithoutPortrait()
    local ns = fresh()
    local l = ns:ComputeUnitFrameLayout({ portrait = false, values = true }, 3)
    assertx.assertEqual(l.barsX, 0, "bars must start flush left with no portrait")
    assertx.assertEqual(l.portraitSize, 0)
end

function M.test_layout_portraitSizeMatchesBodyHeight()
    local ns = fresh()
    local l = ns:ComputeUnitFrameLayout({ portrait = true, values = false }, 4)
    -- The portrait spans the full header+bars stack, so its size must equal
    -- the height that stack occupies (the frame height minus the fixed
    -- outer padding this function also adds).
    assertx.assertEqual(l.portraitSize, l.height - 4)
end

function M.test_layout_heightGrowsWithBarCount()
    local ns = fresh()
    local two  = ns:ComputeUnitFrameLayout(ALL_ON, 2)
    local five = ns:ComputeUnitFrameLayout(ALL_ON, 5)
    assertx.assertTrue(five.height > two.height, "more resource rows must need more height")
end

-- A zero (or negative) bar count must not collapse to an empty/degenerate
-- layout - a unit frame with nothing collected yet still needs to draw a
-- one-row-tall stack the first time bars populate.
function M.test_layout_zeroBarCountFloorsToOneRow()
    local ns = fresh()
    local zero = ns:ComputeUnitFrameLayout(ALL_ON, 0)
    local one  = ns:ComputeUnitFrameLayout(ALL_ON, 1)
    assertx.assertEqual(zero.height, one.height)
end

function M.test_layout_valuesColumnWidthIsZeroWhenHidden()
    local ns = fresh()
    local l = ns:ComputeUnitFrameLayout({ portrait = false, values = false }, 2)
    assertx.assertEqual(l.valuesWidth, 0)
end

-- --------------------------------------------------------------------------
-- ns:FormatUnitFrameValue
-- --------------------------------------------------------------------------

function M.test_formatValue_normalFractionShowsAmountAndPercent()
    local ns = fresh()
    local text = ns:FormatUnitFrameValue(3000, 4500)
    assertx.assertEqual(text, "3000 / 4500 (67%)")
end

function M.test_formatValue_fullBarShows100Percent()
    local ns = fresh()
    assertx.assertEqual(ns:FormatUnitFrameValue(100, 100), "100 / 100 (100%)")
end

function M.test_formatValue_emptyBarShows0Percent()
    local ns = fresh()
    assertx.assertEqual(ns:FormatUnitFrameValue(0, 100), "0 / 100 (0%)")
end

-- No real max (a malformed read - ns:CollectResources itself already skips
-- anything with max <= 0, so this is a defensive guard, not a case that
-- should occur in practice) falls back to the bare current number instead
-- of dividing by zero.
function M.test_formatValue_noMaxFallsBackToBareCurrent()
    local ns = fresh()
    assertx.assertEqual(ns:FormatUnitFrameValue(42, nil), "42")
    assertx.assertEqual(ns:FormatUnitFrameValue(42, 0), "42")
    assertx.assertEqual(ns:FormatUnitFrameValue(42, -5), "42")
end

function M.test_formatValue_nilCurrentTreatedAsZero()
    local ns = fresh()
    assertx.assertEqual(ns:FormatUnitFrameValue(nil, 100), "0 / 100 (0%)")
end

-- A stale server read reporting current above max (a shield-buffed heal,
-- for instance) must clamp its percent to 100 rather than printing "104%".
function M.test_formatValue_currentAboveMaxClampsPercent()
    local ns = fresh()
    local text = ns:FormatUnitFrameValue(120, 100)
    assertx.assertTrue(text:find("(100%)", 1, true) ~= nil, "expected the percent to clamp: " .. text)
end

return M
