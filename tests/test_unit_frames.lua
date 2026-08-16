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

-- The same clipping trap the header had: numbers taller than their row were
-- cut off, so the Values Size slider appeared to stop working past about 12.
function M.test_barHeight_growsToFitTheValuesFont()
    local ns = fresh()
    local l = ns:ComputeUnitFrameLayout({ barHeight = 10, valueFontSize = 20 }, 2)
    assertx.assertTrue(l.barHeight >= 20,
        "a row must be at least as tall as the numbers in it")
end

-- Raising the floor must not become a ceiling: an explicit Bar Height above
-- what the font needs is still the owner's choice and must be honoured.
function M.test_barHeight_valuesFontOnlyRaisesTheFloor()
    local ns = fresh()
    local l = ns:ComputeUnitFrameLayout({ barHeight = 30, valueFontSize = 10 }, 2)
    assertx.assertEqual(l.barHeight, 30,
        "a small font must not shrink an explicitly tall bar")
end

-- The portrait spans exactly the header plus the bar stack, so the two
-- columns line up top and bottom. This is what removing the portrait's own
-- border was for; if the arithmetic drifts they stop aligning and the fix
-- silently regresses.
function M.test_portrait_spansExactlyTheBodyHeight()
    local ns = fresh()
    for _, barCount in ipairs({ 1, 3, 7 }) do
        local l = ns:ComputeUnitFrameLayout({ portrait = true, header = true }, barCount)
        local barsBottom = l.barsTop + barCount * l.barHeight + (barCount - 1) * l.barSpacing
        -- The portrait starts at the same y the header does (UF_PADDING down
        -- from the top), so its bottom edge is padding + portraitSize.
        local portraitBottom = (l.barsTop - l.headerHeight) + l.portraitSize
        assertx.assertEqual(portraitBottom, barsBottom,
            barCount .. " bars: portrait and bar stack must end level")
    end
end

-- --------------------------------------------------------------------------
-- Row planning (ns:UnitFrameRowStyle / ns:PlanUnitFrameRows)
--
-- This is what makes the widget read as a unit frame instead of a stack of
-- identical bars: health and power get a full row each, runes share one row,
-- and combo points divide a row into lit and unlit segments.
-- --------------------------------------------------------------------------

function M.test_rowStyle_poolsGetTheirOwnRow()
    local ns = fresh()
    for _, key in ipairs({ "health", "mana", "rage", "energy", "focus", "runicpower" }) do
        assertx.assertEqual(ns:UnitFrameRowStyle(key), "PRIMARY", key)
    end
end

-- "runicpower" starts with "rune" but is a genuine pool. Getting this wrong
-- turns runic power into a one-segment sliver.
function M.test_rowStyle_runicPowerIsNotARune()
    local ns = fresh()
    assertx.assertEqual(ns:UnitFrameRowStyle("runicpower"), "PRIMARY")
    for slot = 1, 6 do
        assertx.assertEqual(ns:UnitFrameRowStyle("rune" .. slot), "SEGMENT")
    end
    assertx.assertEqual(ns:UnitFrameRowStyle("runepair2"), "SEGMENT")
end

function M.test_rowStyle_comboPointsAndShardsSplit()
    local ns = fresh()
    assertx.assertEqual(ns:UnitFrameRowStyle("combopoints"), "SPLIT")
    assertx.assertEqual(ns:UnitFrameRowStyle("soulshards"), "SPLIT")
end

-- An unknown resource must get a normal bar rather than disappearing.
function M.test_rowStyle_unknownDefaultsToItsOwnRow()
    local ns = fresh()
    assertx.assertEqual(ns:UnitFrameRowStyle("holypower"), "PRIMARY")
    assertx.assertEqual(ns:UnitFrameRowStyle(nil), "PRIMARY")
end

-- The headline result: a death knight's nine entries become four rows.
function M.test_plan_runesCollapseToASingleRow()
    local ns = fresh()
    local entries = {
        { key = "health", current = 100, max = 100 },
        { key = "runicpower", current = 50, max = 100 },
        { key = "rune1" }, { key = "rune2" }, { key = "rune3" },
        { key = "rune4" }, { key = "rune5" }, { key = "rune6" },
    }
    local plan = ns:PlanUnitFrameRows(entries, 16)

    assertx.assertEqual(#plan.rows, 3, "health, runic power, and ONE rune row")
    assertx.assertEqual(#plan.slots, 8, "every rune still gets its own slot")

    -- All six runes on the last row, each a sixth of the width.
    local runeRow = plan.slots[3].row
    for i = 3, 8 do
        assertx.assertEqual(plan.slots[i].row, runeRow, "rune " .. i .. " must share the row")
        assertx.assertTrue(plan.slots[i].width < 0.2,
            "a rune segment must be a fraction of the bar, not the whole thing")
    end
    assertx.assertEqual(plan.slots[1].width, 1, "health takes the full width")
end

-- Segments must tile left to right without overlapping or running past the
-- end of the bar.
function M.test_plan_segmentsTileWithoutOverlap()
    local ns = fresh()
    local entries = {}
    for i = 1, 6 do entries[i] = { key = "rune" .. i } end
    local plan = ns:PlanUnitFrameRows(entries, 16)

    local prevEnd = 0
    for i, s in ipairs(plan.slots) do
        assertx.assertTrue(s.offset >= prevEnd - 0.0001,
            "segment " .. i .. " must start at or after the previous one ends")
        prevEnd = s.offset + s.width
    end
    assertx.assertTrue(prevEnd <= 1.0001, "segments must not run past the bar: " .. prevEnd)
    assertx.assertTrue(prevEnd > 0.95, "segments must fill the bar, not leave it mostly empty")
end

-- One combo-points entry becomes five drawable segments. This is the only
-- case where slots and entries are not one-to-one.
function M.test_plan_comboPointsExpandIntoSegments()
    local ns = fresh()
    local plan = ns:PlanUnitFrameRows({ { key = "combopoints", current = 3, max = 5 } }, 16)

    assertx.assertEqual(#plan.rows, 1)
    assertx.assertEqual(#plan.slots, 5, "five points, five segments")
    for i, s in ipairs(plan.slots) do
        assertx.assertEqual(s.entryIndex, 1, "every segment points at the one entry")
        assertx.assertEqual(s.segIndex, i)
        assertx.assertEqual(s.segMax, 5)
    end
end

-- A private server reporting a nonsense max must not be able to ask for
-- hundreds of slivers and drain the bar pool.
function M.test_plan_splitSegmentsAreCapped()
    local ns = fresh()
    local plan = ns:PlanUnitFrameRows({ { key = "combopoints", current = 0, max = 9999 } }, 16)
    assertx.assertTrue(#plan.slots <= 10, "expected a cap, got " .. #plan.slots)
    assertx.assertTrue(#plan.slots > 0)
end

function M.test_plan_secondaryRowsAreShorterThanPrimary()
    local ns = fresh()
    local plan = ns:PlanUnitFrameRows({
        { key = "health", current = 1, max = 1 },
        { key = "rune1" },
    }, 20)
    assertx.assertEqual(plan.rows[1].height, 20, "a pool keeps the configured height")
    assertx.assertTrue(plan.rows[2].height < 20,
        "a rune strip must not carry the same weight as health")
end

-- Which rows show numbers. A rune strip shows none; a combo strip shows one
-- set for the whole row rather than a digit per segment.
function M.test_plan_runeRowShowsNoNumbers()
    local ns = fresh()
    local plan = ns:PlanUnitFrameRows({ { key = "rune1" }, { key = "rune2" } }, 16)
    assertx.assertEqual(plan.rows[1].valueEntry, nil)
end

function M.test_plan_splitRowShowsOneSetOfNumbers()
    local ns = fresh()
    local plan = ns:PlanUnitFrameRows({ { key = "combopoints", current = 2, max = 5 } }, 16)
    assertx.assertEqual(plan.rows[1].valueEntry, 1)
end

function M.test_plan_primaryRowShowsItsOwnNumbers()
    local ns = fresh()
    local plan = ns:PlanUnitFrameRows({
        { key = "health", current = 1, max = 1 },
        { key = "mana", current = 1, max = 1 },
    }, 16)
    assertx.assertEqual(plan.rows[1].valueEntry, 1)
    assertx.assertEqual(plan.rows[2].valueEntry, 2)
end

-- Rows must stack without overlapping, whatever mix of heights they carry.
function M.test_plan_rowsStackWithoutOverlap()
    local ns = fresh()
    local plan = ns:PlanUnitFrameRows({
        { key = "health", current = 1, max = 1 },
        { key = "rune1" }, { key = "rune2" },
        { key = "combopoints", current = 1, max = 5 },
        { key = "mana", current = 1, max = 1 },
    }, 18)

    local prevBottom = nil
    for i, row in ipairs(plan.rows) do
        if prevBottom then
            assertx.assertTrue(row.top >= prevBottom,
                "row " .. i .. " starts at " .. row.top .. ", previous ended at " .. prevBottom)
        end
        prevBottom = row.top + row.height
    end
    assertx.assertEqual(plan.height, prevBottom, "reported height must match the last row's bottom")
end

-- A frame only reserves so many pooled bars, and the draw loops stop at that
-- number. The plan must therefore respect the budget itself, at a ROW
-- boundary: a truncated rune strip would draw four of six segments with no
-- sign two were missing, which is the same silent drop as a resource group
-- overflowing its Max Bars.
function M.test_plan_respectsTheSlotBudget()
    local ns = fresh()
    local entries = {
        { key = "health", current = 1, max = 1 },
        { key = "mana",   current = 1, max = 1 },
    }
    for i = 1, 6 do entries[#entries + 1] = { key = "rune" .. i } end

    local plan = ns:PlanUnitFrameRows(entries, 16, nil, 4)
    assertx.assertTrue(#plan.slots <= 4, "expected the budget respected, got " .. #plan.slots)
end

function M.test_plan_dropsAnOversizedRowWholeRatherThanHalfDrawn()
    local ns = fresh()
    -- Two pools then five combo segments, with room for only three more
    -- slots: the combo row does not fit, so it must not appear at all.
    local entries = {
        { key = "health",      current = 1, max = 1 },
        { key = "mana",        current = 1, max = 1 },
        { key = "combopoints", current = 2, max = 5 },
    }
    local plan = ns:PlanUnitFrameRows(entries, 16, nil, 5)

    assertx.assertEqual(#plan.slots, 2, "only the two pools should fit")
    assertx.assertEqual(#plan.rows, 2, "the combo row must be dropped whole, not part-drawn")
    for _, s in ipairs(plan.slots) do
        assertx.assertEqual(s.segIndex, nil, "no partial combo segment may survive")
    end
end

function M.test_plan_noBudgetMeansNoCap()
    local ns = fresh()
    local entries = {}
    for i = 1, 6 do entries[i] = { key = "rune" .. i } end
    local plan = ns:PlanUnitFrameRows(entries, 16, nil, nil)
    assertx.assertEqual(#plan.slots, 6, "nil budget must not truncate")
end

function M.test_plan_emptyEntriesPlanNothing()
    local ns = fresh()
    local plan = ns:PlanUnitFrameRows({}, 16)
    assertx.assertEqual(#plan.rows, 0)
    assertx.assertEqual(#plan.slots, 0)
    assertx.assertEqual(plan.height, 0)
end

-- The layout accepts a plan table and uses its height, so segment rows
-- actually shrink the frame rather than the frame staying sized for one
-- full-height row per resource.
function M.test_layout_acceptsAPlanAndUsesItsHeight()
    local ns = fresh()
    local flat = {}
    for i = 1, 8 do flat[i] = { key = "res" .. i, current = 1, max = 1 } end
    local runes = {
        { key = "health", current = 1, max = 1 },
        { key = "runicpower", current = 1, max = 1 },
    }
    for i = 1, 6 do runes[#runes + 1] = { key = "rune" .. i } end

    local flatPlan  = ns:PlanUnitFrameRows(flat, 16)
    local runePlan  = ns:PlanUnitFrameRows(runes, 16)
    local flatBox   = ns:ComputeUnitFrameLayout({ header = true }, flatPlan)
    local runeBox   = ns:ComputeUnitFrameLayout({ header = true }, runePlan)

    assertx.assertTrue(runeBox.height < flatBox.height,
        "the same eight resources must make a SHORTER frame once runes share a row")
end

-- --------------------------------------------------------------------------
-- Position storage (ns:UnitFramePosition / ns:SaveUnitFramePosition)
--
-- All four party frames share ONE settings block, so that nobody sets the
-- bar height four times - but they cannot share a position. If they did,
-- each drag would overwrite the last and all four would pile onto one spot,
-- which reads in game as "dragging does not save" rather than as a bug in
-- where positions are kept.
-- --------------------------------------------------------------------------

local POS = { point = "CENTER", relativePoint = "CENTER", x = 10, y = 20 }

function M.test_position_ordinaryFrameUsesTheSharedField()
    local ns = fresh()
    local cfg = {}
    ns:SaveUnitFramePosition(cfg, "target", POS)
    assertx.assertEqual(cfg.position, POS, "a frame with its own config writes cfg.position")
    assertx.assertEqual(ns:UnitFramePosition(cfg, "target"), POS)
end

function M.test_position_partyFramesAreKeptApart()
    local ns = fresh()
    local cfg = {}
    local a = { point = "LEFT", relativePoint = "LEFT", x = 1, y = 1 }
    local b = { point = "LEFT", relativePoint = "LEFT", x = 2, y = 2 }

    ns:SaveUnitFramePosition(cfg, "party1", a)
    ns:SaveUnitFramePosition(cfg, "party2", b)

    assertx.assertEqual(ns:UnitFramePosition(cfg, "party1"), a)
    assertx.assertEqual(ns:UnitFramePosition(cfg, "party2"), b,
        "dragging party2 must not overwrite party1")
    assertx.assertEqual(cfg.position, nil,
        "a shared-config frame must not write the shared position field")
end

function M.test_position_unsetPartyFrameHasNoPosition()
    local ns = fresh()
    assertx.assertEqual(ns:UnitFramePosition({}, "party3"), nil)
    assertx.assertEqual(ns:UnitFramePosition({ positions = {} }, "party3"), nil)
end

function M.test_position_nilConfigIsSafe()
    local ns = fresh()
    assertx.assertEqual(ns:UnitFramePosition(nil, "player"), nil)
    -- Must not error: a drag can land while the config is momentarily absent
    -- (mid-profile-load, for instance).
    ns:SaveUnitFramePosition(nil, "player", POS)
end

return M
