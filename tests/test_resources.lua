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

-- Rune TYPE must thread through to the entry (v2.5.0), so a rune bar can be
-- coloured by type (Conditions.lua's ns:GetResourcePowerColor) instead of
-- always falling through to the addon-wide default. GetRuneType returns
-- 1=Blood, 2=Unholy, 3=Frost, 4=Death (Trackers.lua's RUNE_ICONS/RUNE_NAMES
-- comment); mock a distinct type per slot so this cannot pass by accident
-- (e.g. every slot happening to read the same fallback value).
function M.test_runeEntries_carryTheirRuneType()
    local ns = fresh()
    mock.playerClass = "DEATHKNIGHT"
    mock.powerType, mock.powerTypeToken = 6, "RUNIC_POWER"
    mock.power[6], mock.powerMax[6] = 55, 100
    mock.runeCooldown = function(slot) return 0, 10, true end
    local slotTypes = { 1, 1, 2, 2, 3, 4 }
    mock.runeType = function(slot) return slotTypes[slot] end

    local entries = ns:CollectResources()
    for slot = 1, 6 do
        local rune = findEntry(entries, "rune" .. slot)
        assertx.assertNotNil(rune, "expected rune slot " .. slot)
        assertx.assertEqual(rune.runeType, slotTypes[slot])
    end
end

-- --------------------------------------------------------------------------
-- Capability probing, not class gating (v2.5.0 classless-server fix).
--
-- BarWarden's owner plays on Grimfall, a classless private server where
-- UnitClass("player") reports the SAME class token (DRUID) for every
-- character while a character can genuinely have mana, energy, rage AND six
-- live runes at once. Gating Runes/Runic Power on classToken ==
-- "DEATHKNIGHT" made them permanently uncollectable there, since that token
-- never appears. HasRunes()/HasRunicPower() (Trackers.lua) probe the actual
-- API instead - these tests are the regression coverage for that bug.
-- --------------------------------------------------------------------------

-- The owner's exact case: a character UnitClass reports as DRUID, but who
-- genuinely has runes because the server does not gate resources by class.
function M.test_druidClassToken_withRunesGetsRuneEntries()
    local ns = fresh()
    mock.playerClass = "DRUID"
    mock.powerType, mock.powerTypeToken = 3, "ENERGY"
    mock.power[3], mock.powerMax[3] = 100, 100
    mock.runeCooldown = function(slot) return 0, 10, true end -- all six ready

    local entries = ns:CollectResources()
    for slot = 1, 6 do
        assertx.assertNotNil(findEntry(entries, "rune" .. slot),
            "a DRUID-flagged character with real rune data must still get rune slot " .. slot)
    end
end

-- The flip side of the regression test above: removing the class gate must
-- not spray six empty rune bars at every character. A DRUID-flagged
-- character with no real rune data (the mock's default GetRuneCooldown,
-- duration 0 on every slot) must see none at all.
function M.test_druidClassToken_withNoRunesGetsNoRuneEntries()
    local ns = fresh()
    mock.playerClass = "DRUID"
    mock.powerType, mock.powerTypeToken = 3, "ENERGY"
    mock.power[3], mock.powerMax[3] = 100, 100

    local entries = ns:CollectResources()
    for slot = 1, 6 do
        assertx.assertNil(findEntry(entries, "rune" .. slot),
            "a character with no real rune data must not get an empty rune " .. slot .. " bar")
    end
end

-- Runic Power follows UnitPowerMax("player", 6), not classToken ==
-- "DEATHKNIGHT": a non-DK-flagged character with a real Runic Power pool
-- (as any character can have on a classless server) must still see it.
function M.test_nonDeathKnightClassToken_withRunicPowerCapabilityGetsIt()
    local ns = fresh()
    mock.playerClass = "WARRIOR"
    mock.powerType, mock.powerTypeToken = 1, "RAGE"
    mock.power[1], mock.powerMax[1] = 20, 100
    mock.power[6], mock.powerMax[6] = 40, 100

    local entries = ns:CollectResources()
    local rp = findEntry(entries, "runicpower")
    assertx.assertNotNil(rp, "a real Runic Power pool must show regardless of the class token")
    assertx.assertEqual(rp.current, 40)
end

-- The converse: a DEATHKNIGHT-flagged character with no real Runic Power
-- pool (UnitPowerMax returning 0) must not get a fabricated bar just because
-- the class token used to be the trigger.
function M.test_deathKnightClassToken_withoutRunicPowerCapabilityGetsNone()
    local ns = fresh()
    mock.playerClass = "DEATHKNIGHT"
    mock.powerType, mock.powerTypeToken = 0, "MANA"
    mock.power[0], mock.powerMax[0] = 100, 100
    mock.powerMax[6] = 0

    local entries = ns:CollectResources()
    assertx.assertNil(findEntry(entries, "runicpower"),
        "the class token alone must not conjure a Runic Power bar with no real pool behind it")
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

-- Soul Shards decision: GetItemCount has no capability signal at all (it is
-- a plain bag count, honest for "never picked one up" and "structurally
-- cannot hold one" alike), so the entry is gated on count > 0, not on
-- classToken == "WARLOCK" - a DRUID-flagged character actually carrying
-- shards (as is possible on a classless server) must see them.
function M.test_nonWarlockClassToken_withShardsGetsSoulShards()
    local ns = fresh()
    mock.playerClass = "DRUID"
    mock.powerType, mock.powerTypeToken = 0, "MANA"
    mock.power[0], mock.powerMax[0] = 1000, 2000
    mock.itemCount[6265] = 2

    local entries = ns:CollectResources()
    local shards = findEntry(entries, "soulshards")
    assertx.assertNotNil(shards, "a real Soul Shard count must show regardless of the class token")
    assertx.assertEqual(shards.current, 2)
end

-- The converse: showing "0 Soul Shards" to a WARLOCK-flagged character with
-- none in their bags would be noise (and, on a classless server, noise for
-- everyone) - GetItemCount reporting 0 must hide the bar even for the class
-- that used to trigger it unconditionally.
function M.test_warlockClassToken_withNoShardsGetsNoSoulShards()
    local ns = fresh()
    mock.playerClass = "WARLOCK"
    mock.powerType, mock.powerTypeToken = 0, "MANA"
    mock.power[0], mock.powerMax[0] = 1000, 2000

    local entries = ns:CollectResources()
    assertx.assertNil(findEntry(entries, "soulshards"),
        "zero Soul Shards must not show, even for a Warlock-flagged character")
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
    -- Pin Energy before Rage: opposes the panel's own tickbox order (Mana,
    -- Rage, Energy), while happening to agree with alphabetical order, so
    -- this alone cannot prove the list's sequence rules; paired with the
    -- reversed test below (which opposes alphabetical instead), only the
    -- list's own order explains both results together.
    mock.power[3], mock.powerMax[3] = 50, 100
    mock.power[1], mock.powerMax[1] = 20, 100

    local pinned = { { key = "energy" }, { key = "rage" } }
    local entries = ns:CollectResources({ pinned = pinned })

    local energyIdx, rageIdx
    for i, e in ipairs(entries) do
        if e.key == "energy" then energyIdx = i end
        if e.key == "rage" then rageIdx = i end
    end
    assertx.assertNotNil(energyIdx, "expected energy to be collected")
    assertx.assertNotNil(rageIdx, "expected rage to be collected")
    assertx.assertTrue(energyIdx < rageIdx, "energy was pinned first, so it must appear first")
end

function M.test_pinnedOrder_reversedListReversesOutput()
    local ns = fresh()
    mock.playerClass = "MAGE"
    mock.powerType, mock.powerTypeToken = 0, "MANA"
    mock.power[0], mock.powerMax[0] = 3000, 4500
    mock.power[3], mock.powerMax[3] = 50, 100
    mock.power[1], mock.powerMax[1] = 20, 100

    -- Same two resources as above, ticked in the opposite order (this time
    -- agreeing with the panel order and opposing alphabetical order).
    local pinned = { { key = "rage" }, { key = "energy" } }
    local entries = ns:CollectResources({ pinned = pinned })

    local energyIdx, rageIdx
    for i, e in ipairs(entries) do
        if e.key == "energy" then energyIdx = i end
        if e.key == "rage" then rageIdx = i end
    end
    assertx.assertTrue(rageIdx < energyIdx, "rage was pinned first this time, so it must appear first")
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

-- --------------------------------------------------------------------------
-- The target feed (opts.unit = "target"): health and current power read off
-- the target, not the player; a missing target collects nothing; and the
-- player's own class resources (runes/runic power/soul shards) never leak
-- onto an arbitrary target's reading. Combo Points are the deliberate
-- exception - see the decision recorded in its own test below.
-- --------------------------------------------------------------------------

function M.test_targetFeed_collectsTargetHealthAndPower()
    local ns = fresh()
    mock.playerClass = "MAGE"
    -- Player state deliberately different from target state, so a pass here
    -- can only mean the target feed actually read the TARGET, not the player.
    mock.playerHealth, mock.playerHealthMax = 100, 100
    mock.powerType, mock.powerTypeToken = 0, "MANA"
    mock.power[0], mock.powerMax[0] = 10, 20

    mock.targetExists = true
    mock.targetHealth, mock.targetHealthMax = 4200, 5100
    mock.targetPowerType, mock.targetPowerTypeToken = 1, "RAGE"
    mock.targetPower[1], mock.targetPowerMax[1] = 60, 100

    local entries = ns:CollectResources({ unit = "target" })

    assertx.assertEqual(entries[1].key, "health")
    assertx.assertEqual(entries[1].current, 4200)
    assertx.assertEqual(entries[1].max, 5100)

    local rage = findEntry(entries, "rage")
    assertx.assertNotNil(rage, "target's current power type (rage) should be collected")
    assertx.assertEqual(rage.current, 60)
    assertx.assertEqual(rage.max, 100)
end

function M.test_targetFeed_absentTargetCollectsNothing()
    local ns = fresh()
    mock.playerClass = "WARRIOR"
    mock.targetExists = false
    -- Left non-zero on purpose: if the unit-existence guard were missing or
    -- wrong, these would leak through and this test would still pass by
    -- accident. Non-zero values make a leak visible instead.
    mock.targetHealth, mock.targetHealthMax = 4200, 5100
    mock.targetPowerType, mock.targetPowerTypeToken = 1, "RAGE"
    mock.targetPower[1], mock.targetPowerMax[1] = 60, 100

    local ok, entries = pcall(function() return ns:CollectResources({ unit = "target" }) end)
    assertx.assertTrue(ok, "collecting for an absent target must not error")
    assertx.assertEqual(#entries, 0, "an absent target must collect nothing")
end

function M.test_targetFeed_playerOnlyClassResourcesDoNotAppear()
    local ns = fresh()
    -- A Death Knight and a Warlock: if the class gate were mistakenly read
    -- from UnitClass(unit) instead of UnitClass("player") always, a target
    -- feed would still show nothing here (UnitClass(unit) returns nil for a
    -- non-player unit in this harness), but that would be the WRONG reason -
    -- it would also, wrongly, show these for a player who has since
    -- targeted a same-class ally. The real guard is `if unit == "player"`
    -- around the Runes/Runic Power/Soul Shards block in CollectResources
    -- (Trackers.lua), which this proves by using the PLAYER's own
    -- DEATHKNIGHT class while asking for the TARGET feed.
    mock.playerClass = "DEATHKNIGHT"
    mock.powerType, mock.powerTypeToken = 6, "RUNIC_POWER"
    mock.power[6], mock.powerMax[6] = 55, 100
    mock.runeCooldown = function(slot) return 0, 10, true end

    mock.targetExists = true
    mock.targetPowerType, mock.targetPowerTypeToken = 0, "MANA"
    mock.targetPower[0], mock.targetPowerMax[0] = 100, 100

    local entries = ns:CollectResources({ unit = "target" })
    assertx.assertNil(findEntry(entries, "runicpower"), "the player's own Runic Power must not appear on a target feed")
    assertx.assertNil(findEntry(entries, "rune1"), "the player's own Runes must not appear on a target feed")
end

-- --------------------------------------------------------------------------
-- Combo Points decision: they are the player's own resource, but they are
-- ALWAYS a reading of "my points on my current target" (GetComboPoints
-- hard-codes "player", "target" regardless of which feed asks), so unlike
-- Runes/Runic Power/Soul Shards, offering them on the target feed is never a
-- mislabelled read of someone else's data - it is the exact same reading
-- either feed would give. Decision: show Combo Points on BOTH feeds, gated
-- on GetComboPoints' own value (cur > 0), not on UnitClass("player") - see
-- the CollectResources file comment (Trackers.lua) for why a class token was
-- dropped as a signal here too.
-- --------------------------------------------------------------------------

function M.test_comboPoints_appearOnTargetFeedToo()
    local ns = fresh()
    mock.playerClass = "ROGUE"
    mock.comboPoints = 3
    mock.targetExists = true
    mock.targetPowerType, mock.targetPowerTypeToken = 0, "MANA"
    mock.targetPower[0], mock.targetPowerMax[0] = 1000, 1000

    local entries = ns:CollectResources({ unit = "target" })
    local cp = findEntry(entries, "combopoints")
    assertx.assertNotNil(cp, "Combo Points must appear on the target feed")
    assertx.assertEqual(cp.current, 3)
end

-- Was "test_comboPoints_stillGatedOnPlayerClassForTargetFeed" (asserted the
-- opposite): on a classless server UnitClass("player") reporting "MAGE" is
-- not proof the character cannot generate combo points - GetComboPoints'
-- own non-zero value is what proves it, whatever the class token says.
function M.test_comboPoints_appearRegardlessOfClassTokenOnTargetFeed()
    local ns = fresh()
    mock.playerClass = "MAGE"
    mock.comboPoints = 3
    mock.targetExists = true
    mock.targetPowerType, mock.targetPowerTypeToken = 0, "MANA"
    mock.targetPower[0], mock.targetPowerMax[0] = 1000, 1000

    local entries = ns:CollectResources({ unit = "target" })
    local cp = findEntry(entries, "combopoints")
    assertx.assertNotNil(cp, "GetComboPoints reporting a real value must surface it regardless of the class token")
    assertx.assertEqual(cp.current, 3)
end

-- --------------------------------------------------------------------------
-- Always Show Focus was removed (v2.5.0): a legacy pinned "focus" must be
-- dropped silently, not error or produce a stale entry.
-- --------------------------------------------------------------------------

function M.test_legacyFocusPin_droppedWithoutError()
    local ns = fresh()
    mock.playerClass = "MAGE"
    mock.powerType, mock.powerTypeToken = 0, "MANA"
    mock.power[0], mock.powerMax[0] = 3000, 4500
    mock.power[1], mock.powerMax[1] = 10, 100

    -- Legacy plain-set shape.
    local legacySet = { focus = true, rage = true }
    local ok, entries = pcall(function() return ns:CollectResources({ pinned = legacySet }) end)
    assertx.assertTrue(ok, "a legacy focus pin must not error")
    assertx.assertNil(findEntry(entries, "focus"), "focus must be dropped, not shown, from the legacy set shape")
    assertx.assertNotNil(findEntry(entries, "rage"), "other legacy pins must keep working")

    -- Current ordered-list shape.
    local orderedList = { { key = "focus" }, { key = "rage" } }
    local ok2, entries2 = pcall(function() return ns:CollectResources({ pinned = orderedList }) end)
    assertx.assertTrue(ok2, "a legacy focus pin must not error in the ordered shape either")
    assertx.assertNil(findEntry(entries2, "focus"), "focus must be dropped, not shown, from the ordered shape")
    assertx.assertNotNil(findEntry(entries2, "rage"), "other pins must keep working alongside a stale focus entry")
end

-- --------------------------------------------------------------------------
-- The target's-target feed (opts.unit = "targettarget"): health and current
-- power read off that third unit, independently of both player and target
-- state; a target with no target of its own collects nothing; and Combo
-- Points, unlike the target feed, do NOT appear here - see the decision
-- recorded in its own test below.
-- --------------------------------------------------------------------------

function M.test_targetTargetFeed_collectsThatUnitsHealthAndPower()
    local ns = fresh()
    mock.playerClass = "MAGE"
    -- Player, target, AND target's-target all deliberately different, so a
    -- pass here can only mean this feed read the THIRD unit, not either of
    -- the other two.
    mock.playerHealth, mock.playerHealthMax = 100, 100
    mock.powerType, mock.powerTypeToken = 0, "MANA"
    mock.power[0], mock.powerMax[0] = 10, 20

    mock.targetExists = true
    mock.targetHealth, mock.targetHealthMax = 4200, 5100
    mock.targetPowerType, mock.targetPowerTypeToken = 1, "RAGE"
    mock.targetPower[1], mock.targetPowerMax[1] = 60, 100

    mock.totExists = true
    mock.totHealth, mock.totHealthMax = 777, 888
    mock.totPowerType, mock.totPowerTypeToken = 3, "ENERGY"
    mock.totPower[3], mock.totPowerMax[3] = 33, 100

    local entries = ns:CollectResources({ unit = "targettarget" })

    assertx.assertEqual(entries[1].key, "health")
    assertx.assertEqual(entries[1].current, 777)
    assertx.assertEqual(entries[1].max, 888)

    local energy = findEntry(entries, "energy")
    assertx.assertNotNil(energy, "the target's target's current power type (energy) should be collected")
    assertx.assertEqual(energy.current, 33)
    assertx.assertEqual(energy.max, 100)
end

function M.test_targetTargetFeed_absentCollectsNothing()
    local ns = fresh()
    mock.playerClass = "WARRIOR"
    -- The common case this guards: you have a target, but IT has nothing
    -- targeted (most mobs/players much of the time).
    mock.targetExists = true
    mock.targetHealth, mock.targetHealthMax = 4200, 5100
    mock.totExists = false
    -- Left non-zero on purpose, same reasoning as the target-absent test
    -- above: a missing/backwards guard would leak these through silently.
    mock.totHealth, mock.totHealthMax = 999, 999
    mock.totPowerType, mock.totPowerTypeToken = 0, "MANA"
    mock.totPower[0], mock.totPowerMax[0] = 500, 500

    local ok, entries = pcall(function() return ns:CollectResources({ unit = "targettarget" }) end)
    assertx.assertTrue(ok, "collecting for a target with no target of its own must not error")
    assertx.assertEqual(#entries, 0, "a target with no target of its own must collect nothing")
end

-- --------------------------------------------------------------------------
-- Combo Points decision for the target's-target feed: GetComboPoints has no
-- "on my target's target" reading to give - it is hardcoded to "target" -
-- so showing them here would just repeat the target feed's own number under
-- a label that implies it belongs to a different unit. Decision: Combo
-- Points do NOT appear on this feed, even for a class that has them.
-- --------------------------------------------------------------------------

function M.test_comboPoints_doNotAppearOnTargetTargetFeed()
    local ns = fresh()
    mock.playerClass = "ROGUE"
    mock.comboPoints = 5
    mock.totExists = true
    mock.totPowerType, mock.totPowerTypeToken = 0, "MANA"
    mock.totPower[0], mock.totPowerMax[0] = 1000, 1000

    local entries = ns:CollectResources({ unit = "targettarget" })
    assertx.assertNil(findEntry(entries, "combopoints"),
        "Combo Points must not appear on the target's-target feed even for a Rogue")
end

-- --------------------------------------------------------------------------
-- Combo Points pin (v2.5.0): at zero, Combo Points behave like the other
-- pinnable resources - shown while "in use" (here, while you have at least
-- one), hidden at zero unless the owner has ticked "Keep Combo Points
-- Visible". There is no class gate any more (see the CollectResources file
-- comment, Trackers.lua): pinning at zero shows the bar for ANY class token,
-- including one that (on a normal Blizzard server) could never generate a
-- combo point at all - that residual static-0/5-bar case is the accepted
-- cost of not inferring capability from UnitClass, since the class token is
-- not trustworthy on a classless server.
-- --------------------------------------------------------------------------

function M.test_comboPoints_hiddenAtZeroWhenUnpinned()
    local ns = fresh()
    mock.playerClass = "ROGUE"
    mock.comboPoints = 0

    local entries = ns:CollectResources()
    assertx.assertNil(findEntry(entries, "combopoints"),
        "an idle Rogue with no combo points yet should not see an empty bar")
end

function M.test_comboPoints_pinnedShowsAtZero()
    local ns = fresh()
    mock.playerClass = "ROGUE"
    mock.comboPoints = 0

    local entries = ns:CollectResources({ pinned = { { key = "combopoints" } } })
    local cp = findEntry(entries, "combopoints")
    assertx.assertNotNil(cp, "pinning Combo Points must keep the bar up at zero")
    assertx.assertEqual(cp.current, 0)
end

function M.test_comboPoints_nonZeroShowsEvenUnpinned()
    local ns = fresh()
    mock.playerClass = "DRUID"
    mock.comboPoints = 2

    local entries = ns:CollectResources()
    assertx.assertNotNil(findEntry(entries, "combopoints"),
        "an already-active combo point count keeps showing without needing the pin")
end

-- Was "test_comboPoints_pinDoesNotShowForClassThatCannotGenerateThem"
-- (asserted the opposite): that behaviour depended on UnitClass("player"),
-- which is exactly the signal this fix removes. Pinning now shows the bar
-- regardless of the class token - see the pin's own comment above for why
-- that is the accepted trade-off, not a regression.
function M.test_comboPoints_pinShowsRegardlessOfClassToken()
    local ns = fresh()
    mock.playerClass = "MAGE"
    mock.comboPoints = 0

    local entries = ns:CollectResources({ pinned = { { key = "combopoints" } } })
    local cp = findEntry(entries, "combopoints")
    assertx.assertNotNil(cp,
        "pinning must not depend on the class token, which is not trustworthy on a classless server")
    assertx.assertEqual(cp.current, 0)
end

function M.test_comboPoints_pinnedShowsAtZeroOnTargetFeedToo()
    local ns = fresh()
    mock.playerClass = "ROGUE"
    mock.comboPoints = 0
    mock.targetExists = true
    mock.targetPowerType, mock.targetPowerTypeToken = 0, "MANA"
    mock.targetPower[0], mock.targetPowerMax[0] = 1000, 1000

    local entries = ns:CollectResources({ unit = "target", pinned = { { key = "combopoints" } } })
    assertx.assertNotNil(findEntry(entries, "combopoints"),
        "the pin applies to the target feed the same way as the player feed")
end

function M.test_comboPoints_pinnedStillDoesNotAppearOnTargetTargetFeed()
    local ns = fresh()
    mock.playerClass = "ROGUE"
    mock.comboPoints = 0
    mock.totExists = true
    mock.totPowerType, mock.totPowerTypeToken = 0, "MANA"
    mock.totPower[0], mock.totPowerMax[0] = 1000, 1000

    local entries = ns:CollectResources({ unit = "targettarget", pinned = { { key = "combopoints" } } })
    assertx.assertNil(findEntry(entries, "combopoints"),
        "GetComboPoints has no target's-target reading, so the pin must not surface one")
end

-- --------------------------------------------------------------------------
-- Pinned Combo Points must follow tick order (v2.5.0 fix): Combo Points used
-- to be added in the class-resource block, ahead of the pinned-extras loop
-- that honours ns:NormalizePinnedResources' order, so a pinned Combo Points
-- entry always landed right after Health/current-power regardless of when it
-- was ticked relative to another pinned resource. addEntry's `seen` guard
-- means whichever add runs FIRST silently wins the slot, so the fix is not
-- just "let the pinned loop add Combo Points too" but also "stop the early
-- add from claiming the slot while pinned".
-- --------------------------------------------------------------------------

function M.test_comboPoints_pinned_landsAfterAResourcePinnedBeforeIt()
    local ns = fresh()
    mock.playerClass = "ROGUE"
    mock.comboPoints = 0
    mock.power[1], mock.powerMax[1] = 20, 100 -- give Rage a real pool to pin

    local pinned = { { key = "rage" }, { key = "combopoints" } }
    local entries = ns:CollectResources({ pinned = pinned })

    local rageIdx, comboIdx
    for i, e in ipairs(entries) do
        if e.key == "rage" then rageIdx = i end
        if e.key == "combopoints" then comboIdx = i end
    end
    assertx.assertNotNil(rageIdx, "expected rage to be collected")
    assertx.assertNotNil(comboIdx, "expected combopoints to be collected")
    assertx.assertTrue(rageIdx < comboIdx, "rage was pinned first, so it must appear first")
end

function M.test_comboPoints_pinned_landsBeforeAResourcePinnedAfterIt()
    local ns = fresh()
    mock.playerClass = "ROGUE"
    mock.comboPoints = 0
    mock.power[1], mock.powerMax[1] = 20, 100

    -- Same two resources, ticked in the opposite order.
    local pinned = { { key = "combopoints" }, { key = "rage" } }
    local entries = ns:CollectResources({ pinned = pinned })

    local rageIdx, comboIdx
    for i, e in ipairs(entries) do
        if e.key == "rage" then rageIdx = i end
        if e.key == "combopoints" then comboIdx = i end
    end
    assertx.assertTrue(comboIdx < rageIdx, "combo points was pinned first this time, so it must appear first")
end

-- Also active (cur > 0) as well as pinned: the pin still governs position,
-- not the "already in use" early path.
function M.test_comboPoints_pinnedAndActive_stillFollowsTickOrder()
    local ns = fresh()
    mock.playerClass = "ROGUE"
    mock.comboPoints = 3
    mock.power[1], mock.powerMax[1] = 20, 100

    local pinned = { { key = "rage" }, { key = "combopoints" } }
    local entries = ns:CollectResources({ pinned = pinned })

    local rageIdx, comboIdx
    for i, e in ipairs(entries) do
        if e.key == "rage" then rageIdx = i end
        if e.key == "combopoints" then comboIdx = i end
    end
    assertx.assertTrue(rageIdx < comboIdx, "rage was pinned first, so an active combo count must still fall in behind it")
end

-- --------------------------------------------------------------------------
-- Runic Power / Runes pins (v2.5.0, commit 2): unlike Mana/Rage/Energy,
-- Runic Power and Runes already show unconditionally whenever HasRunicPower/
-- HasRunes says the pool is real (see the file comment above), so pinning
-- them changes nothing about VISIBILITY - it only changes ORDER. Before this
-- fix, both were added in a fixed spot ahead of the pinned-extras loop
-- (same bug just fixed for Combo Points), so a pinned Runic Power/Runes
-- entry always landed right after Health/current-power regardless of tick
-- order. These tests are the regression coverage for that fix, plus basic
-- pin-does-not-duplicate coverage.
-- --------------------------------------------------------------------------

-- Current power type deliberately left as Mana (0), disjoint from both
-- resources being compared (Rage and Runic Power): the current power type is
-- always added, unconditionally, before the pinned-extras loop even runs
-- (see the file comment above CollectResources), so a test that used Rage as
-- BOTH the current power type AND one of the two pins compared would prove
-- nothing about tick order - Rage would always land first no matter which
-- pin was ticked first. The same reasoning already shapes the existing
-- Energy/Rage ordering tests further above.
function M.test_runicPower_pinned_landsAfterAResourcePinnedBeforeIt()
    local ns = fresh()
    mock.playerClass = "WARRIOR"
    mock.powerType, mock.powerTypeToken = 0, "MANA"
    mock.power[0], mock.powerMax[0] = 10, 100
    mock.power[1], mock.powerMax[1] = 20, 100
    mock.power[6], mock.powerMax[6] = 40, 100

    local pinned = { { key = "rage" }, { key = "runicpower" } }
    local entries = ns:CollectResources({ pinned = pinned })

    local rageIdx, rpIdx
    for i, e in ipairs(entries) do
        if e.key == "rage" then rageIdx = i end
        if e.key == "runicpower" then rpIdx = i end
    end
    assertx.assertNotNil(rageIdx, "expected rage to be collected")
    assertx.assertNotNil(rpIdx, "expected runicpower to be collected")
    assertx.assertTrue(rageIdx < rpIdx, "rage was pinned first, so it must appear first")
end

function M.test_runicPower_pinned_landsBeforeAResourcePinnedAfterIt()
    local ns = fresh()
    mock.playerClass = "WARRIOR"
    mock.powerType, mock.powerTypeToken = 0, "MANA"
    mock.power[0], mock.powerMax[0] = 10, 100
    mock.power[1], mock.powerMax[1] = 20, 100
    mock.power[6], mock.powerMax[6] = 40, 100

    -- Same two resources, ticked in the opposite order.
    local pinned = { { key = "runicpower" }, { key = "rage" } }
    local entries = ns:CollectResources({ pinned = pinned })

    local rageIdx, rpIdx
    for i, e in ipairs(entries) do
        if e.key == "rage" then rageIdx = i end
        if e.key == "runicpower" then rpIdx = i end
    end
    assertx.assertTrue(rpIdx < rageIdx, "runic power was pinned first this time, so it must appear first")
end

function M.test_runicPower_pinnedDoesNotDuplicate()
    local ns = fresh()
    mock.playerClass = "WARRIOR"
    mock.powerType, mock.powerTypeToken = 1, "RAGE"
    mock.power[1], mock.powerMax[1] = 20, 100
    mock.power[6], mock.powerMax[6] = 40, 100

    local entries = ns:CollectResources({ pinned = { { key = "runicpower" } } })
    local count = 0
    for _, e in ipairs(entries) do
        if e.key == "runicpower" then count = count + 1 end
    end
    assertx.assertEqual(count, 1, "pinning runic power must not duplicate the entry")
end

function M.test_runicPower_unpinnedStillShowsWhenCapable()
    local ns = fresh()
    mock.playerClass = "WARRIOR"
    mock.powerType, mock.powerTypeToken = 1, "RAGE"
    mock.power[1], mock.powerMax[1] = 20, 100
    mock.power[6], mock.powerMax[6] = 40, 100

    local entries = ns:CollectResources()
    assertx.assertNotNil(findEntry(entries, "runicpower"),
        "runic power must still show unconditionally when nothing is pinned")
end

function M.test_runicPower_pinnedWithNoRealPoolAddsNothing()
    local ns = fresh()
    mock.playerClass = "WARRIOR"
    mock.powerType, mock.powerTypeToken = 1, "RAGE"
    mock.power[1], mock.powerMax[1] = 20, 100
    mock.powerMax[6] = 0

    local ok, entries = pcall(function()
        return ns:CollectResources({ pinned = { { key = "runicpower" } } })
    end)
    assertx.assertTrue(ok, "pinning runic power without a real pool must not error")
    assertx.assertNil(findEntry(entries, "runicpower"),
        "pinning must not conjure a runic power bar with no real pool behind it")
end

-- Same current-power-type caveat as the Runic Power ordering tests above:
-- Mana is current, disjoint from Rage and Runes, so tick order is the only
-- thing that can explain the result.
function M.test_runes_pinned_landsAfterAResourcePinnedBeforeIt()
    local ns = fresh()
    mock.playerClass = "WARRIOR"
    mock.powerType, mock.powerTypeToken = 0, "MANA"
    mock.power[0], mock.powerMax[0] = 10, 100
    mock.power[1], mock.powerMax[1] = 20, 100
    mock.runeCooldown = function(slot) return 0, 10, true end -- all runes ready

    local pinned = { { key = "rage" }, { key = "runes" } }
    local entries = ns:CollectResources({ pinned = pinned })

    local rageIdx, rune1Idx
    for i, e in ipairs(entries) do
        if e.key == "rage" then rageIdx = i end
        if e.key == "rune1" then rune1Idx = i end
    end
    assertx.assertNotNil(rageIdx, "expected rage to be collected")
    assertx.assertNotNil(rune1Idx, "expected the first rune slot to be collected")
    assertx.assertTrue(rageIdx < rune1Idx, "rage was pinned first, so it must appear before the runes")
end

function M.test_runes_pinned_landsBeforeAResourcePinnedAfterIt()
    local ns = fresh()
    mock.playerClass = "WARRIOR"
    mock.powerType, mock.powerTypeToken = 0, "MANA"
    mock.power[0], mock.powerMax[0] = 10, 100
    mock.power[1], mock.powerMax[1] = 20, 100
    mock.runeCooldown = function(slot) return 0, 10, true end

    local pinned = { { key = "runes" }, { key = "rage" } }
    local entries = ns:CollectResources({ pinned = pinned })

    local rageIdx, rune1Idx
    for i, e in ipairs(entries) do
        if e.key == "rage" then rageIdx = i end
        if e.key == "rune1" then rune1Idx = i end
    end
    assertx.assertTrue(rune1Idx < rageIdx, "runes were pinned first this time, so they must appear first")
end

function M.test_runes_pinnedDoesNotDuplicate()
    local ns = fresh()
    mock.playerClass = "WARRIOR"
    mock.powerType, mock.powerTypeToken = 1, "RAGE"
    mock.power[1], mock.powerMax[1] = 20, 100
    mock.runeCooldown = function(slot) return 0, 10, true end

    local entries = ns:CollectResources({ pinned = { { key = "runes" } } })
    for slot = 1, 6 do
        local count = 0
        for _, e in ipairs(entries) do
            if e.key == "rune" .. slot then count = count + 1 end
        end
        assertx.assertEqual(count, 1, "pinning runes must not duplicate rune slot " .. slot)
    end
end

function M.test_runes_unpinnedStillShowsSixEntries()
    local ns = fresh()
    mock.playerClass = "WARRIOR"
    mock.powerType, mock.powerTypeToken = 1, "RAGE"
    mock.power[1], mock.powerMax[1] = 20, 100
    mock.runeCooldown = function(slot) return 0, 10, true end

    local entries = ns:CollectResources()
    for slot = 1, 6 do
        assertx.assertNotNil(findEntry(entries, "rune" .. slot),
            "runes must still show unconditionally when nothing is pinned, slot " .. slot)
    end
end

function M.test_runes_pinnedWithNoRealRunesAddsNothing()
    local ns = fresh()
    mock.playerClass = "WARRIOR"
    mock.powerType, mock.powerTypeToken = 1, "RAGE"
    mock.power[1], mock.powerMax[1] = 20, 100
    -- Default mock.runeCooldown (duration 0 on every slot) = no real runes.

    local ok, entries = pcall(function()
        return ns:CollectResources({ pinned = { { key = "runes" } } })
    end)
    assertx.assertTrue(ok, "pinning runes without any real rune data must not error")
    assertx.assertNil(findEntry(entries, "rune1"),
        "pinning must not conjure rune bars with no real rune data behind them")
end

return M
