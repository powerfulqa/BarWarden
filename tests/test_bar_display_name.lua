-- tests/test_bar_display_name.lua
-- Covers ns.GetBarDisplayName (Bar.lua): a bar's own name always wins, and
-- when it has none, the display falls back to resolving barData.spellId
-- (or a bare-numeric barData.spellName, which getSpell/Trackers.lua and
-- ns:GetTrackedAuraNames already treat as an id - this has to agree with
-- them) through GetSpellInfo. Also covers the id->name cache this adds
-- (GetBarDisplayName runs from the scan loop's bar activation/deactivation
-- paths) and its invalidation via ns:InvalidateTrackedNames.

local assertx    = require("assert")
local load_addon = require("load_addon")
local mock       = require("mock_wow")

local M = {}

local function fresh()
    mock.reset()
    local ns = {}
    load_addon.load("Bar.lua", "BarWarden", ns)
    return ns
end

-- --------------------------------------------------------------------------
-- Core resolution rules
-- --------------------------------------------------------------------------

function M.test_nilBarDataReturnsEmptyStringNoError()
    local ns = fresh()
    assertx.assertEqual(ns.GetBarDisplayName(nil), "")
end

function M.test_ownNameWinsOverSpellId()
    local ns = fresh()
    mock.spellInfo[123] = { name = "Rupture", spellId = 123 }
    local name = ns.GetBarDisplayName({ name = "My Custom Bar", spellId = 123 })
    assertx.assertEqual(name, "My Custom Bar")
end

function M.test_emptyNameFallsBackToSpellId()
    local ns = fresh()
    mock.spellInfo[123] = { name = "Rupture", spellId = 123 }
    local name = ns.GetBarDisplayName({ name = "", spellId = 123 })
    assertx.assertEqual(name, "Rupture")
end

function M.test_missingNameFieldFallsBackToSpellId()
    local ns = fresh()
    mock.spellInfo[456] = { name = "Evasion", spellId = 456 }
    local name = ns.GetBarDisplayName({ spellId = 456 })
    assertx.assertEqual(name, "Evasion")
end

function M.test_bareNumericSpellNameResolvesLikeASpellId()
    local ns = fresh()
    -- getSpell (Trackers.lua) and ns:GetTrackedAuraNames both treat a bare
    -- numeric spellName as an id; GetBarDisplayName has to agree.
    mock.spellInfo[789] = { name = "Vanish", spellId = 789 }
    local name = ns.GetBarDisplayName({ spellName = "789" })
    assertx.assertEqual(name, "Vanish")
end

function M.test_unknownSpellIdFallsBackToEmptyString()
    local ns = fresh()
    -- GetSpellInfo returns nil for an id the client doesn't know (a
    -- private-server id, for example); that must not error or show "nil".
    local name = ns.GetBarDisplayName({ spellId = 999999 })
    assertx.assertEqual(name, "")
end

function M.test_nonNumericSpellNameWithNoBarNameStaysEmpty()
    local ns = fresh()
    -- A comma-separated or plain-name spellName is not a bare id, so there
    -- is nothing to resolve; behaviour is unchanged from before this fix.
    local name = ns.GetBarDisplayName({ spellName = "Rupture, Garrote" })
    assertx.assertEqual(name, "")
end

-- --------------------------------------------------------------------------
-- Cache: memoised by spell id, invalidated via ns:InvalidateTrackedNames
-- --------------------------------------------------------------------------

function M.test_resolvedNameIsCachedAcrossCalls()
    local ns = fresh()
    mock.spellInfo[123] = { name = "Rupture", spellId = 123 }
    local first = ns.GetBarDisplayName({ spellId = 123 })
    -- Change the mock after the first resolution; a cache hit should still
    -- return the memoised value rather than re-querying GetSpellInfo.
    mock.spellInfo[123] = { name = "Something Else", spellId = 123 }
    local second = ns.GetBarDisplayName({ spellId = 123 })
    assertx.assertEqual(first, "Rupture")
    assertx.assertEqual(second, "Rupture")
end

function M.test_unknownIdStaysEmptyUntilInvalidated()
    local ns = fresh()
    local before = ns.GetBarDisplayName({ spellId = 42 })
    assertx.assertEqual(before, "")

    -- The client "learns" the spell later; without invalidation the cached
    -- miss should still hold.
    mock.spellInfo[42] = { name = "Kick", spellId = 42 }
    local stillCached = ns.GetBarDisplayName({ spellId = 42 })
    assertx.assertEqual(stillCached, "")

    assertx.assertNotNil(ns.InvalidateBarDisplayNameCache,
        "ns:InvalidateBarDisplayNameCache should exist")
    ns:InvalidateBarDisplayNameCache()
    local afterInvalidate = ns.GetBarDisplayName({ spellId = 42 })
    assertx.assertEqual(afterInvalidate, "Kick")
end

return M
