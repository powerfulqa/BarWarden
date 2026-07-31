-- tests/test_stack_badge.lua
-- Covers ns:ShouldShowStackBadge, the pure decision behind the icon-corner
-- stack badge. The badge exists so a stacking aura shows its count whatever
-- the text format is; the frame work (anchoring, reparenting when the icon is
-- hidden) rides the in-game smoke test.

local assertx    = require("assert")
local load_addon = require("load_addon")

local M = {}

local function fresh()
    local ns = {}
    load_addon.load("Utils.lua", "BarWarden", ns)
    return ns
end

-- Multiples are what the player cares about: 2+ shows, 0 and 1 do not.
function M.test_badge_showsFromTwoStacks()
    local ns = fresh()
    assertx.assertTrue(ns:ShouldShowStackBadge(2, "NAME_DURATION", true, false))
    assertx.assertTrue(ns:ShouldShowStackBadge(9, "NAME_DURATION", true, false))
end

function M.test_badge_hiddenBelowTwoStacks()
    local ns = fresh()
    assertx.assertFalse(ns:ShouldShowStackBadge(0, "NAME_DURATION", true, false))
    assertx.assertFalse(ns:ShouldShowStackBadge(1, "NAME_DURATION", true, false))
    assertx.assertFalse(ns:ShouldShowStackBadge(nil, "NAME_DURATION", true, false))
end

-- The stack-bearing text formats already print the number, so the badge stands
-- down rather than showing it twice.
function M.test_badge_suppressedByStackTextFormats()
    local ns = fresh()
    assertx.assertFalse(ns:ShouldShowStackBadge(9, "NAME_STACKS", true, false))
    assertx.assertFalse(ns:ShouldShowStackBadge(9, "STACKS", true, false))
end

function M.test_badge_shownForOtherTextFormats()
    local ns = fresh()
    assertx.assertTrue(ns:ShouldShowStackBadge(9, "NAME_ONLY", true, false))
    assertx.assertTrue(ns:ShouldShowStackBadge(9, "DURATION", true, false))
end

-- Resource bars (combo points, runes) already read as current/max.
function M.test_badge_suppressedOnResourceBars()
    local ns = fresh()
    assertx.assertFalse(ns:ShouldShowStackBadge(5, "NAME_DURATION", true, true))
end

-- The global off switch wins over everything.
function M.test_badge_respectsGlobalToggle()
    local ns = fresh()
    assertx.assertFalse(ns:ShouldShowStackBadge(9, "NAME_DURATION", false, false))
end

-- A nil toggle means "not configured yet", which must behave as on (the
-- default is true, and MergeDefaults backfills it).
function M.test_badge_nilToggleDefaultsOn()
    local ns = fresh()
    assertx.assertTrue(ns:ShouldShowStackBadge(9, "NAME_DURATION", nil, false))
end

return M
