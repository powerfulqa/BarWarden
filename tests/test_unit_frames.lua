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

-- With no portrait the bars sit at the body's left edge, which is the
-- backdrop's own inset rather than zero: X-Perl's frame artwork has a 4px
-- border, and bars drawn at x = 0 would sit on top of it.
function M.test_layout_barsStartAtBodyEdgeWithoutPortrait()
    local ns = fresh()
    local l = ns:ComputeUnitFrameLayout({ portrait = false, values = true }, 3)
    assertx.assertEqual(l.barsX, l.bodyX, "bars must start at the body edge with no portrait")
    assertx.assertEqual(l.portraitSize, 0)
end

function M.test_layout_portraitSizeMatchesBodyHeight()
    local ns = fresh()
    local l = ns:ComputeUnitFrameLayout({ portrait = true, values = false }, 4)
    -- The portrait spans the full header+bars stack, so its size must equal
    -- the height that stack occupies (the frame height minus the outer
    -- padding this function adds above AND below the body).
    assertx.assertEqual(l.portraitSize, l.height - 8)
end

-- The values column is sized from a measurement rather than a constant,
-- because a fixed width made the fontstring wrap and every row overlapped
-- the one beneath it. A measurement under the floor must still clamp up, and
-- anything above it must be honoured exactly.
function M.test_layout_valuesWidthHonoursMeasurement()
    local ns = fresh()
    local wide = ns:ComputeUnitFrameLayout({ portrait = false, values = true }, 2, 130)
    assertx.assertEqual(wide.valuesWidth, 130, "a measured width above the floor must be used as-is")

    local narrow = ns:ComputeUnitFrameLayout({ portrait = false, values = true }, 2, 5)
    assertx.assertTrue(narrow.valuesWidth > 5, "a measurement under the floor must clamp up")

    local unmeasured = ns:ComputeUnitFrameLayout({ portrait = false, values = true }, 2, nil)
    assertx.assertEqual(unmeasured.valuesWidth, narrow.valuesWidth,
        "no measurement yet must fall back to the same floor")

    assertx.assertTrue(wide.width > narrow.width,
        "a wider values column must widen the whole frame, not overflow it")
end

-- Hiding the values column must reclaim its width entirely, measurement or
-- not - otherwise turning the column off would leave a blank gutter.
function M.test_layout_valuesWidthIsZeroWhenHidden()
    local ns = fresh()
    local l = ns:ComputeUnitFrameLayout({ portrait = false, values = false }, 2, 200)
    assertx.assertEqual(l.valuesWidth, 0, "a hidden values column reserves no width")
end

-- The measured width is the widest VISIBLE row: a hidden slot's leftover
-- string must not stretch the frame. MAX_UNIT_FRAME_SLOTS fontstrings always
-- exist, and the unused ones keep whatever text they last held.
function M.test_measureValuesWidth_ignoresHiddenRows()
    local ns = fresh()
    local function fs(width, shown)
        return {
            GetStringWidth = function() return width end,
            IsShown = function() return shown end,
        }
    end
    local texts = { fs(40, true), fs(220, false), fs(75, true) }
    assertx.assertEqual(ns:MeasureUnitFrameValuesWidth(texts, 3), 75,
        "a hidden row's stale text must not widen the column")
end

function M.test_measureValuesWidth_roundsUpToWholePixels()
    local ns = fresh()
    local texts = { { GetStringWidth = function() return 61.2 end, IsShown = function() return true end } }
    assertx.assertEqual(ns:MeasureUnitFrameValuesWidth(texts, 1), 62,
        "a fractional width would differ on every compare and relayout every tick")
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

-- --------------------------------------------------------------------------
-- Values placement (ns:ResolveUnitFrameElements)
--
-- Two settings produce three outcomes, and the rule that showValues == false
-- beats any placement is the one worth pinning: a frame that kept drawing
-- numbers on its bars after the owner turned values off would look like the
-- tickbox was broken.
-- --------------------------------------------------------------------------

function M.test_valuePlacement_defaultsToColumn()
    local ns = fresh()
    local e = ns:ResolveUnitFrameElements({ showValues = true })
    assertx.assertTrue(e.values, "no placement set must mean the column")
    assertx.assertTrue(not e.valuesOnBar)
end

function M.test_valuePlacement_onBarSuppressesTheColumn()
    local ns = fresh()
    local e = ns:ResolveUnitFrameElements({ showValues = true, valuePlacement = "ONBAR" })
    assertx.assertTrue(e.valuesOnBar, "on-bar placement must be reported")
    assertx.assertTrue(not e.values, "the column must not also be drawn")
end

function M.test_valuePlacement_showValuesOffBeatsAnyPlacement()
    local ns = fresh()
    for _, placement in ipairs({ "COLUMN", "ONBAR" }) do
        local e = ns:ResolveUnitFrameElements({ showValues = false, valuePlacement = placement })
        assertx.assertTrue(not e.values, placement .. ": column must be off")
        assertx.assertTrue(not e.valuesOnBar, placement .. ": on-bar must be off")
    end
end

-- --------------------------------------------------------------------------
-- Header collapse (ns:ResolveUnitFrameElements / ns:ComputeUnitFrameLayout)
--
-- The header band is not itself a setting: it exists if the name or the
-- level does. With both off it must collapse rather than leave an empty
-- strip across the top of the frame.
-- --------------------------------------------------------------------------

function M.test_header_presentWhenEitherNameOrLevelShows()
    local ns = fresh()
    assertx.assertTrue(ns:ResolveUnitFrameElements({ showName = true, showLevel = false }).header,
        "a name alone still needs a header")
    assertx.assertTrue(ns:ResolveUnitFrameElements({ showName = false, showLevel = true }).header,
        "a level alone still needs a header")
end

function M.test_header_collapsesWhenBothAreOff()
    local ns = fresh()
    local e = ns:ResolveUnitFrameElements({ showName = false, showLevel = false })
    assertx.assertTrue(not e.header, "nothing to put in the header means no header")

    local collapsed = ns:ComputeUnitFrameLayout(e, 3)
    assertx.assertEqual(collapsed.headerHeight, 0)
    local withHeader = ns:ComputeUnitFrameLayout({ header = true }, 3)
    assertx.assertTrue(collapsed.height < withHeader.height,
        "a collapsed header must actually shorten the frame")
end

-- Callers predating the name toggle pass element tables with no `header`
-- key at all (the older tests here included). Nil must read as "there is a
-- header", or every such frame would silently lose its title band.
function M.test_header_absentKeyIsTreatedAsPresent()
    local ns = fresh()
    local l = ns:ComputeUnitFrameLayout({ portrait = false, values = false }, 2)
    assertx.assertTrue(l.headerHeight > 0, "a missing header flag must not collapse the header")
end

-- The header band grows with the name font. A flat height silently capped
-- the Name Size slider: past about 12 the text drew taller than the band and
-- was clipped, so the slider looked broken rather than limited.
function M.test_header_growsWithTheNameFont()
    local ns = fresh()
    local small = ns:ComputeUnitFrameLayout({ header = true, nameFontSize = 10 }, 2)
    local big   = ns:ComputeUnitFrameLayout({ header = true, nameFontSize = 22 }, 2)

    assertx.assertTrue(big.headerHeight > small.headerHeight,
        "a bigger name font must get a taller header band")
    assertx.assertTrue(big.headerHeight >= 22,
        "the band must be at least as tall as the font in it")
    assertx.assertTrue(big.barsTop > small.barsTop,
        "a taller band must push the bars down rather than overlap them")
end

-- A small font must not SHRINK the band below its floor, or the header would
-- look cramped at the default size.
function M.test_header_neverShrinksBelowItsFloor()
    local ns = fresh()
    local tiny = ns:ComputeUnitFrameLayout({ header = true, nameFontSize = 4 }, 2)
    local none = ns:ComputeUnitFrameLayout({ header = true }, 2)
    assertx.assertEqual(tiny.headerHeight, none.headerHeight,
        "a tiny font must fall back to the standard band height")
end

-- --------------------------------------------------------------------------
-- Opacity (ns:GetUnitFrameOpacity)
-- --------------------------------------------------------------------------

function M.test_opacity_defaultsToFullyOpaque()
    local ns = fresh()
    assertx.assertEqual(ns:GetUnitFrameOpacity(nil, "barOpacity"), 1.0)
    assertx.assertEqual(ns:GetUnitFrameOpacity({}, "barOpacity"), 1.0)
    -- A hand-edited or imported profile can carry anything at all here.
    assertx.assertEqual(ns:GetUnitFrameOpacity({ barOpacity = "half" }, "barOpacity"), 1.0)
end

function M.test_opacity_clampsToRange()
    local ns = fresh()
    assertx.assertEqual(ns:GetUnitFrameOpacity({ x = -3 }, "x"), 0)
    assertx.assertEqual(ns:GetUnitFrameOpacity({ x = 47 }, "x"), 1)
    assertx.assertEqual(ns:GetUnitFrameOpacity({ x = 0.4 }, "x"), 0.4)
end

-- Each part reads its OWN key, so fading one never drags another with it.
function M.test_opacity_partsAreIndependent()
    local ns = fresh()
    local cfg = { frameOpacity = 0.2, portraitOpacity = 1.0, barOpacity = 0.6, borderOpacity = 0.8 }
    assertx.assertEqual(ns:GetUnitFrameOpacity(cfg, "frameOpacity"), 0.2)
    assertx.assertEqual(ns:GetUnitFrameOpacity(cfg, "portraitOpacity"), 1.0)
    assertx.assertEqual(ns:GetUnitFrameOpacity(cfg, "barOpacity"), 0.6)
    assertx.assertEqual(ns:GetUnitFrameOpacity(cfg, "borderOpacity"), 0.8)
end

-- --------------------------------------------------------------------------
-- Portrait style (ns:ResolveUnitFrameElements)
-- --------------------------------------------------------------------------

function M.test_portraitStyle_defaultsToTheFlatPicture()
    local ns = fresh()
    assertx.assertTrue(not ns:ResolveUnitFrameElements({}).portrait3D)
    assertx.assertTrue(not ns:ResolveUnitFrameElements({ portraitStyle = "2D" }).portrait3D)
end

function M.test_portraitStyle_modelIsOptedIntoExplicitly()
    local ns = fresh()
    assertx.assertTrue(ns:ResolveUnitFrameElements({ portraitStyle = "3D" }).portrait3D)
end

-- --------------------------------------------------------------------------
-- Bar height (ns:ComputeUnitFrameLayout)
-- --------------------------------------------------------------------------

function M.test_barHeight_isHonouredAndClamped()
    local ns = fresh()
    local tall = ns:ComputeUnitFrameLayout({ barHeight = 24 }, 3)
    assertx.assertEqual(tall.barHeight, 24, "a sane height must be used as-is")

    -- A hand-edited or imported profile must not be able to produce a frame
    -- with zero-height rows or one taller than the screen.
    local silly = ns:ComputeUnitFrameLayout({ barHeight = 0 }, 3)
    assertx.assertTrue(silly.barHeight >= 8, "height must clamp up off zero")
    local huge = ns:ComputeUnitFrameLayout({ barHeight = 5000 }, 3)
    assertx.assertTrue(huge.barHeight <= 40, "height must clamp down")

    assertx.assertTrue(tall.height > ns:ComputeUnitFrameLayout({ barHeight = 10 }, 3).height,
        "taller bars must make a taller frame")
end

return M
