-- tests/test_resources.lua
-- Covers ns:CollectResources, the pure half of the automatic "resources"
-- auto-tracking feed: what shows, in what order, for a given class/power
-- combination and pinned selection.
--
-- The frame-driving half (ns:ScanAutoGroup's resource branch) is not covered
-- here; it needs a live frame and rides the in-game smoke test, matching how
-- ns:CollectAutoAuras/ns:ScanAutoGroup are already split in test_auto_track.lua.

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

local function findEntry(entries, key)
    for _, e in ipairs(entries) do
        if e.key == key then return e end
    end
    return nil
end

-- --------------------------------------------------------------------------
-- Health: always present, always first
-- --------------------------------------------------------------------------

function M.test_health_alwaysPresentAndFirst()
    local ns = fresh()
    mock.playerClass  = "MAGE"
    mock.playerHealth = 4200
    mock.playerHealthMax = 5100
    mock.powerType, mock.powerTypeToken = 0, "MANA"
    mock.power[0], mock.powerMax[0] = 3000, 4500

    local entries = ns:CollectResources()
    assertx.assertTrue(#entries > 0, "expected at least one entry")
    assertx.assertEqual(entries[1].key, "health")
    assertx.assertEqual(entries[1].current, 4200)
    assertx.assertEqual(entries[1].max, 5100)
end

-- --------------------------------------------------------------------------
-- Current power type follows UnitPowerType
-- --------------------------------------------------------------------------

function M.test_currentPowerType_followsUnitPowerType_mana()
    local ns = fresh()
    mock.playerClass = "MAGE"
    mock.powerType, mock.powerTypeToken = 0, "MANA"
    mock.power[0], mock.powerMax[0] = 3000, 4500

    local entries = ns:CollectResources()
    local mana = findEntry(entries, "mana")
    assertx.assertNotNil(mana, "current power type (mana) should be collected")
    assertx.assertEqual(mana.current, 3000)
    assertx.assertEqual(mana.max, 4500)
end

function M.test_currentPowerType_followsUnitPowerType_energy()
    -- Simulates a druid having just shifted into Cat Form: current power
    -- type flips to Energy. This is the "follows form changes live" case.
    local ns = fresh()
    mock.playerClass = "DRUID"
    mock.powerType, mock.powerTypeToken = 3, "ENERGY"
    mock.power[3], mock.powerMax[3] = 60, 100

    local entries = ns:CollectResources()
    local energy = findEntry(entries, "energy")
    assertx.assertNotNil(energy, "current power type (energy) should be collected")
    assertx.assertEqual(energy.current, 60)
    assertx.assertEqual(energy.max, 100)
    -- Rage (bear form) must not also appear just because the class can use it.
    assertx.assertNil(findEntry(entries, "rage"))
end

function M.test_currentPowerType_deathKnightRunicPower()
    local ns = fresh()
    mock.playerClass = "DEATHKNIGHT"
    mock.powerType, mock.powerTypeToken = 6, "RUNIC_POWER"
    mock.power[6], mock.powerMax[6] = 55, 100

    local entries = ns:CollectResources()
    local rp = findEntry(entries, "runicpower")
    assertx.assertNotNil(rp, "current power type (runic power) should be collected")
    assertx.assertEqual(rp.current, 55)
end

-- --------------------------------------------------------------------------
-- Class resources layered on top, without duplicating the power-type entry
-- --------------------------------------------------------------------------

function M.test_deathKnight_getsRunicPowerOnceAndSixRunes()
    local ns = fresh()
    mock.playerClass = "DEATHKNIGHT"
    mock.powerType, mock.powerTypeToken = 6, "RUNIC_POWER"
    mock.power[6], mock.powerMax[6] = 55, 100
    mock.runeCooldown = function(slot) return 0, 10, true end -- all runes ready

    local entries = ns:CollectResources()

    local rpCount = 0
    for _, e in ipairs(entries) do
        if e.key == "runicpower" then rpCount = rpCount + 1 end
    end
    assertx.assertEqual(rpCount, 1, "Runic Power must appear exactly once, not once per step")

    for slot = 1, 6 do
        local rune = findEntry(entries, "rune" .. slot)
        assertx.assertNotNil(rune, "expected rune slot " .. slot)
        -- The countdown-text hint must survive to the entry: UpdateResourceBar
        -- (BarEngine.lua) reads trackMode == "Runes" to show "Ns" instead of
        -- a plain current/max fraction.
        assertx.assertEqual(rune.trackMode, "Runes")
    end
end

function M.test_rogueGetsComboPoints()
    local ns = fresh()
    mock.playerClass = "ROGUE"
    mock.powerType, mock.powerTypeToken = 3, "ENERGY"
    mock.power[3], mock.powerMax[3] = 100, 100
    mock.comboPoints = 4

    local entries = ns:CollectResources()
    local cp = findEntry(entries, "combopoints")
    assertx.assertNotNil(cp)
    assertx.assertEqual(cp.current, 4)
    assertx.assertEqual(cp.max, 5)
end

function M.test_druidGetsComboPoints()
    local ns = fresh()
    mock.playerClass = "DRUID"
    mock.powerType, mock.powerTypeToken = 3, "ENERGY"
    mock.power[3], mock.powerMax[3] = 100, 100
    mock.comboPoints = 2

    local entries = ns:CollectResources()
    assertx.assertNotNil(findEntry(entries, "combopoints"))
end

function M.test_warlockGetsSoulShards()
    local ns = fresh()
    mock.playerClass = "WARLOCK"
    mock.powerType, mock.powerTypeToken = 0, "MANA"
    mock.power[0], mock.powerMax[0] = 1000, 2000
    mock.itemCount[6265] = 3

    local entries = ns:CollectResources()
    local shards = findEntry(entries, "soulshards")
    assertx.assertNotNil(shards)
    assertx.assertEqual(shards.current, 3)
end

function M.test_mageGetsNoClassResources()
    local ns = fresh()
    mock.playerClass = "MAGE"
    mock.powerType, mock.powerTypeToken = 0, "MANA"
    mock.power[0], mock.powerMax[0] = 3000, 4500

    local entries = ns:CollectResources()
    assertx.assertNil(findEntry(entries, "combopoints"))
    assertx.assertNil(findEntry(entries, "runicpower"))
    assertx.assertNil(findEntry(entries, "rune1"))
    assertx.assertNil(findEntry(entries, "soulshards"))
end

-- --------------------------------------------------------------------------
-- Pinned extras
-- --------------------------------------------------------------------------

function M.test_pinnedExtra_appears()
    local ns = fresh()
    mock.playerClass = "ROGUE"
    mock.powerType, mock.powerTypeToken = 3, "ENERGY"
    mock.power[3], mock.powerMax[3] = 100, 100
    -- Pin Mana even though a Rogue's current power is Energy; the mock does
    -- not enforce game realism, so an arbitrary non-zero pool is enough to
    -- prove a pinned resource surfaces independently of the current type.
    mock.power[0], mock.powerMax[0] = 10, 500

    local entries = ns:CollectResources({ pinned = { mana = true } })
    local mana = findEntry(entries, "mana")
    assertx.assertNotNil(mana, "pinned resource should appear")
    assertx.assertEqual(mana.current, 10)
end

function M.test_pinnedExtra_alreadyActiveDoesNotDuplicate()
    local ns = fresh()
    mock.playerClass = "MAGE"
    mock.powerType, mock.powerTypeToken = 0, "MANA"
    mock.power[0], mock.powerMax[0] = 3000, 4500

    -- Pinning the resource that is already the current power type must not
    -- add a second entry for it.
    local entries = ns:CollectResources({ pinned = { mana = true } })
    local count = 0
    for _, e in ipairs(entries) do
        if e.key == "mana" then count = count + 1 end
    end
    assertx.assertEqual(count, 1, "pinning the active power type must not duplicate it")
end

-- --------------------------------------------------------------------------
-- Pinned resources: order follows tick order (v2.5.0)
--
-- ns:NormalizePinnedResources / ns:TogglePinnedResource / ns:SetPinnedResourceColor
-- are the pure ordering layer CollectResources' pinned-extras step now goes
-- through, so a group's autoPinnedResources can carry sequence (and a
-- per-resource colour) instead of just an unordered set.
-- --------------------------------------------------------------------------

function M.test_pinnedOrder_newShapeFollowsListOrder()
    local ns = fresh()
    mock.playerClass = "MAGE"
    mock.powerType, mock.powerTypeToken = 0, "MANA"
    mock.power[0], mock.powerMax[0] = 3000, 4500
    -- Pin Energy before Focus: reversed from both the panel's own tickbox
    -- order (Mana, Rage, Energy, Focus) and alphabetical order, so only the
    -- list's own sequence could explain the result below.
    mock.power[3], mock.powerMax[3] = 50, 100
    mock.power[2], mock.powerMax[2] = 20, 100

    local pinned = { { key = "energy" }, { key = "focus" } }
    local entries = ns:CollectResources({ pinned = pinned })

    local energyIdx, focusIdx
    for i, e in ipairs(entries) do
        if e.key == "energy" then energyIdx = i end
        if e.key == "focus" then focusIdx = i end
    end
    assertx.assertNotNil(energyIdx, "expected energy to be collected")
    assertx.assertNotNil(focusIdx, "expected focus to be collected")
    assertx.assertTrue(energyIdx < focusIdx, "energy was pinned first, so it must appear first")
end

function M.test_pinnedOrder_reversedListReversesOutput()
    local ns = fresh()
    mock.playerClass = "MAGE"
    mock.powerType, mock.powerTypeToken = 0, "MANA"
    mock.power[0], mock.powerMax[0] = 3000, 4500
    mock.power[3], mock.powerMax[3] = 50, 100
    mock.power[2], mock.powerMax[2] = 20, 100

    -- Same two resources as above, ticked in the opposite order.
    local pinned = { { key = "focus" }, { key = "energy" } }
    local entries = ns:CollectResources({ pinned = pinned })

    local energyIdx, focusIdx
    for i, e in ipairs(entries) do
        if e.key == "energy" then energyIdx = i end
        if e.key == "focus" then focusIdx = i end
    end
    assertx.assertTrue(focusIdx < energyIdx, "focus was pinned first this time, so it must appear first")
end

function M.test_pinnedOrder_orderedShapeDoesNotDuplicateActiveResource()
    local ns = fresh()
    mock.playerClass = "MAGE"
    mock.powerType, mock.powerTypeToken = 0, "MANA"
    mock.power[0], mock.powerMax[0] = 3000, 4500

    local pinned = { { key = "mana" } }
    local entries = ns:CollectResources({ pinned = pinned })
    local count = 0
    for _, e in ipairs(entries) do
        if e.key == "mana" then count = count + 1 end
    end
    assertx.assertEqual(count, 1, "pinning the active power type must not duplicate it, ordered shape included")
end

function M.test_normalizePinnedResources_legacySetShapeStillWorks()
    local ns = fresh()
    mock.playerClass = "MAGE"
    mock.powerType, mock.powerTypeToken = 0, "MANA"
    mock.power[0], mock.powerMax[0] = 3000, 4500
    mock.power[1], mock.powerMax[1] = 10, 100
    mock.power[3], mock.powerMax[3] = 20, 100

    -- The pre-order saved shape: a plain set, { key = true }.
    local legacy = { rage = true, energy = true }
    local entries = ns:CollectResources({ pinned = legacy })

    assertx.assertNotNil(findEntry(entries, "rage"), "legacy pinned set must keep working")
    assertx.assertNotNil(findEntry(entries, "energy"), "legacy pinned set must keep working")
end

function M.test_normalizePinnedResources_legacyShapeOrderIsDeterministic()
    local ns = fresh()
    local list = ns:NormalizePinnedResources({ rage = true, energy = true, mana = true })
    -- Alphabetical: energy, mana, rage. Matches the table.sort order
    -- CollectResources used before pin order existed, so a profile saved
    -- before this feature does not visibly reshuffle just from upgrading.
    assertx.assertEqual(list[1].key, "energy")
    assertx.assertEqual(list[2].key, "mana")
    assertx.assertEqual(list[3].key, "rage")
end

function M.test_normalizePinnedResources_nilIsEmptyList()
    local ns = fresh()
    local list = ns:NormalizePinnedResources(nil)
    assertx.assertEqual(#list, 0)
end

function M.test_normalizePinnedResources_toleratesColorOnEntries()
    local ns = fresh()
    local list = ns:NormalizePinnedResources({ { key = "mana", color = { r = 1, g = 0, b = 0 } } })
    assertx.assertEqual(list[1].key, "mana")
    assertx.assertEqual(list[1].color.r, 1)
end

function M.test_togglePinnedResource_tickAppendsToEnd()
    local ns = fresh()
    local pinned = ns:TogglePinnedResource(nil, "mana", true)
    pinned = ns:TogglePinnedResource(pinned, "rage", true)
    assertx.assertEqual(#pinned, 2)
    assertx.assertEqual(pinned[1].key, "mana")
    assertx.assertEqual(pinned[2].key, "rage")
end

function M.test_togglePinnedResource_untickRemovesEntry()
    local ns = fresh()
    local pinned = ns:TogglePinnedResource(nil, "mana", true)
    pinned = ns:TogglePinnedResource(pinned, "mana", false)
    assertx.assertEqual(#pinned, 0)
end

function M.test_togglePinnedResource_reTickMovesToEnd()
    local ns = fresh()
    local pinned = ns:TogglePinnedResource(nil, "mana", true)
    pinned = ns:TogglePinnedResource(pinned, "rage", true)

    -- Untick mana, then re-tick it: it must land after rage, not back in
    -- its old slot 1 - "the order you ticked them", not "the order first seen".
    pinned = ns:TogglePinnedResource(pinned, "mana", false)
    pinned = ns:TogglePinnedResource(pinned, "mana", true)

    assertx.assertEqual(#pinned, 2)
    assertx.assertEqual(pinned[1].key, "rage")
    assertx.assertEqual(pinned[2].key, "mana")
end

function M.test_setPinnedResourceColor_addsColorToExistingEntry()
    local ns = fresh()
    local pinned = ns:TogglePinnedResource(nil, "mana", true)
    pinned = ns:SetPinnedResourceColor(pinned, "mana", { r = 1, g = 0, b = 0 })
    assertx.assertEqual(pinned[1].color.r, 1)
    assertx.assertEqual(pinned[1].color.g, 0)
    assertx.assertEqual(pinned[1].color.b, 0)
end

function M.test_setPinnedResourceColor_onUnpinnedKeyAppendsRatherThanDrops()
    local ns = fresh()
    local pinned = ns:SetPinnedResourceColor(nil, "mana", { r = 0, g = 1, b = 0 })
    assertx.assertEqual(#pinned, 1)
    assertx.assertEqual(pinned[1].key, "mana")
    assertx.assertEqual(pinned[1].color.g, 1)
end

-- --------------------------------------------------------------------------
-- Zero-max resources are skipped, not divided by zero
-- --------------------------------------------------------------------------

function M.test_zeroMaxResourceIsSkipped()
    local ns = fresh()
    mock.playerClass = "MAGE"
    mock.powerType, mock.powerTypeToken = 0, "MANA"
    mock.power[0], mock.powerMax[0] = 3000, 4500
    -- Pin Rage: a Mage has no rage pool, so both current and max stay 0.
    mock.power[1], mock.powerMax[1] = 0, 0

    local entries = ns:CollectResources({ pinned = { rage = true } })
    assertx.assertNil(findEntry(entries, "rage"), "a zero-max resource must be skipped, not shown at 0/0")
end

-- --------------------------------------------------------------------------
-- Always returns a table, never nil or an error
-- --------------------------------------------------------------------------

function M.test_neverReturnsNilOrErrors()
    local ns = fresh()
    mock.playerClass = "MAGE"
    mock.playerHealth, mock.playerHealthMax = 0, 0
    mock.powerType, mock.powerTypeToken = 0, "MANA"
    mock.power[0], mock.powerMax[0] = 0, 0

    local ok, entries = pcall(function() return ns:CollectResources() end)
    assertx.assertTrue(ok, "CollectResources must not error")
    assertx.assertEqual(type(entries), "table")

    local ok2, entries2 = pcall(function() return ns:CollectResources(nil) end)
    assertx.assertTrue(ok2, "CollectResources(nil) must not error")
    assertx.assertEqual(type(entries2), "table")
end

return M
