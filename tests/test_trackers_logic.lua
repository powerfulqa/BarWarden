-- tests/test_trackers_logic.lua
-- Covers the pure-logic surface of Trackers.lua:
--   * getSpellTokens parsing (via CheckBuff observable behaviour)
--   * @group expansion (needs AuraGroups loaded first)
--   * smoothExpiry monotonicity
--   * clearExpiry / ClearStableExpiry
--   * CheckCooldown override table
--
-- Frame-bound machinery (ActivateBar, OnUpdate, resource-bar dispatch) stays
-- out of scope; those are exercised in-game.

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

-- Helpers to build aura table entries in the shape UnitBuff / UnitDebuff
-- return on 3.3.5a (11 values).
local function buff(name, spellId, expirationTime, duration, icon, count, caster)
    return {
        name           = name,
        spellId        = spellId,
        icon           = icon or "icon",
        count          = count or 0,
        duration       = duration or 0,
        expirationTime = expirationTime or 0,
        caster         = caster or "player",
    }
end

-- --------------------------------------------------------------------------
-- CheckBuff: match by name vs. spellId
-- --------------------------------------------------------------------------

function M.test_checkBuff_matchesByName()
    local ns = fresh()
    mock.now = 0
    mock.buffs.player[1] = buff("Slice and Dice", 5171, 20, 20)
    local active, remaining = ns.TRACKERS["Buff"]({ spellName = "Slice and Dice" })
    assertx.assertTrue(active)
    assertx.assertEqual(remaining, 20)
end

function M.test_checkBuff_matchesBySpellId()
    local ns = fresh()
    mock.buffs.player[1] = buff("Slice and Dice", 5171, 20, 20)
    local active = ns.TRACKERS["Buff"]({ spellId = 5171 })
    assertx.assertTrue(active)
end

function M.test_checkBuff_missingReturnsInactive()
    local ns = fresh()
    -- No buffs set
    local active, remaining = ns.TRACKERS["Buff"]({ spellName = "Nothing" })
    assertx.assertFalse(active)
    assertx.assertEqual(remaining, 0)
end

-- --------------------------------------------------------------------------
-- getSpellTokens: comma-split, @group expansion, caching
-- --------------------------------------------------------------------------

function M.test_commaSeparatedNames_matchEither()
    local ns = fresh()
    mock.buffs.player[1] = buff("Slice and Dice", 5171, 20, 20)
    local bd = { spellName = "Slice and Dice, Adrenaline Rush" }
    local active = ns.TRACKERS["Buff"](bd)
    assertx.assertTrue(active, "first token should match")

    -- Swap the aura so only the second token matches
    mock.buffs.player[1] = buff("Adrenaline Rush", 13750, 30, 30)
    -- Reuse the same barConfig so we also exercise the token cache
    local active2 = ns.TRACKERS["Buff"](bd)
    assertx.assertTrue(active2, "second token should match")
end

function M.test_auraGroupExpansion_matchesAnyGroupId()
    local ns = fresh()
    -- Stunned group contains 1833 (Cheap Shot). Set a buff with that id.
    mock.buffs.target[1] = buff("Cheap Shot", 1833, 5, 5)
    local bd = { spellName = "@Stunned", unit = "target", onlyMine = false }
    local active = ns.TRACKERS["Debuff"]({ spellName = "@Stunned", unit = "target", onlyMine = false })
    -- Debuff channel is what @Stunned would use; ensure *either* channel
    -- picks it up so the test isn't tied to which UnitBuff/Debuff the spell
    -- landed in. Using debuff channel with `onlyMine = false`.
    mock.debuffs.target[1] = buff("Cheap Shot", 1833, 5, 5)
    local active2 = ns.TRACKERS["Debuff"](bd)
    assertx.assertTrue(active2, "@Stunned group should expand to include Cheap Shot (1833)")
end

function M.test_unknownAuraGroup_returnsNoTokens()
    local ns = fresh()
    mock.buffs.player[1] = buff("Anything", 999, 10, 10)
    local active = ns.TRACKERS["Buff"]({ spellName = "@ThisGroupDoesNotExist" })
    assertx.assertFalse(active, "unknown group should match nothing")
end

function M.test_tokenCacheStashedOnBarConfig()
    local ns = fresh()
    mock.buffs.player[1] = buff("Slice and Dice", 5171, 20, 20)
    local bd = { spellName = "Slice and Dice" }
    ns.TRACKERS["Buff"](bd)
    assertx.assertNotNil(bd._tokenCache,    "token cache not stashed on barConfig")
    assertx.assertEqual(bd._tokenCacheKey, "Slice and Dice")
end

-- --------------------------------------------------------------------------
-- smoothExpiry: expiration drift never moves remaining backward
-- --------------------------------------------------------------------------

function M.test_smoothExpiry_holdsLongerValueAgainstServerDrift()
    local ns = fresh()
    local bd = { spellName = "Slice and Dice", unit = "player" }

    mock.now = 0
    mock.buffs.player[1] = buff("Slice and Dice", 5171, 100, 100)
    local _, remaining1 = ns.TRACKERS["Buff"](bd)
    assertx.assertEqual(remaining1, 100)

    -- Server drift: expiration clocks back 10s even though no time passed
    mock.now = 5
    mock.buffs.player[1] = buff("Slice and Dice", 5171, 90, 100)
    local _, remaining2 = ns.TRACKERS["Buff"](bd)
    -- Without smoothing: remaining2 = 90 - 5 = 85
    -- With smoothing: cached expiration = 100, remaining2 = 100 - 5 = 95
    assertx.assertEqual(remaining2, 95,
        "smoothExpiry should keep the earlier (longer) cached expiration")
end

function M.test_smoothExpiry_acceptsLongerValue()
    local ns = fresh()
    local bd = { spellName = "Slice and Dice", unit = "player" }

    mock.now = 0
    mock.buffs.player[1] = buff("Slice and Dice", 5171, 50, 50)
    ns.TRACKERS["Buff"](bd)

    -- Refresh: server pushes expiration out
    mock.now = 10
    mock.buffs.player[1] = buff("Slice and Dice", 5171, 80, 50)
    local _, remaining = ns.TRACKERS["Buff"](bd)
    assertx.assertEqual(remaining, 70, "longer expiration should replace cache")
end

function M.test_clearStableExpiry_clearsPerUnitCache()
    local ns = fresh()
    local targetBD = { spellName = "Cheap Shot", unit = "target" }
    mock.debuffs.target[1] = buff("Cheap Shot", 1833, 10, 10, nil, 0, "player")
    mock.now = 0
    ns.TRACKERS["Debuff"](targetBD)    -- caches target:1833 at expiration 10

    -- Shorten expiration; smoothing keeps the old value
    mock.now = 2
    mock.debuffs.target[1] = buff("Cheap Shot", 1833, 8, 10, nil, 0, "player")
    local _, r1 = ns.TRACKERS["Debuff"](targetBD)
    assertx.assertEqual(r1, 8, "smoothed cache should keep remaining at (10 - 2) = 8")

    -- Wipe the target cache; the reduced expiration is now authoritative
    ns:ClearStableExpiry("target")
    mock.debuffs.target[1] = buff("Cheap Shot", 1833, 6, 10, nil, 0, "player")
    local _, r2 = ns.TRACKERS["Debuff"](targetBD)
    assertx.assertEqual(r2, 4, "after ClearStableExpiry, new expiration takes effect")
end

-- --------------------------------------------------------------------------
-- onlyMine filter
-- --------------------------------------------------------------------------

function M.test_debuff_onlyMine_skipsOtherCasters()
    local ns = fresh()
    mock.debuffs.target[1] = buff("Rupture", 1943, 12, 12, nil, 0, "someoneelse")
    local bd = { spellName = "Rupture", unit = "target", onlyMine = true }
    local active = ns.TRACKERS["Debuff"](bd)
    assertx.assertFalse(active, "onlyMine=true should reject auras cast by others")
end

function M.test_debuff_onlyMine_acceptsPlayerCaster()
    local ns = fresh()
    mock.debuffs.target[1] = buff("Rupture", 1943, 12, 12, nil, 0, "player")
    local bd = { spellName = "Rupture", unit = "target", onlyMine = true }
    local active = ns.TRACKERS["Debuff"](bd)
    assertx.assertTrue(active)
end

-- --------------------------------------------------------------------------
-- CheckCooldown + SpellDurations override
-- --------------------------------------------------------------------------

function M.test_checkCooldown_activeSpell()
    local ns = fresh()
    mock.now = 100
    mock.spellInfo[1856] = { name = "Vanish", icon = "vanish-icon", spellId = 1856 }
    mock.spellCooldown[1856] = { start = 95, duration = 180, enabled = 1 }
    local active, remaining, duration = ns.TRACKERS["Cooldown"]({ spellId = 1856 })
    assertx.assertTrue(active)
    assertx.assertEqual(duration,  180)
    assertx.assertEqual(remaining, 175)
end

function M.test_checkCooldown_ignoresGcd()
    local ns = fresh()
    mock.now = 100
    mock.spellInfo[1856] = { name = "Vanish", spellId = 1856 }
    -- GCD_THRESHOLD is 1.5; duration at/under that is ignored
    mock.spellCooldown[1856] = { start = 100, duration = 1.5, enabled = 1 }
    local active = ns.TRACKERS["Cooldown"]({ spellId = 1856 })
    assertx.assertFalse(active)
end

function M.test_checkCooldown_spellDurationsOverride()
    local ns = fresh()
    mock.now = 100
    mock.spellInfo[47568] = { name = "Empower Rune Weapon", spellId = 47568 }
    mock.spellCooldown[47568] = { start = 90, duration = 300, enabled = 1 }
    -- Private-server override forces the CD to 60s
    ns.SpellDurations[47568] = 60
    local _, _, duration = ns.TRACKERS["Cooldown"]({ spellId = 47568 })
    assertx.assertEqual(duration, 60, "SpellDurations override should replace the API-reported duration")
end

function M.test_checkCooldown_overrideAppliesWhenUserTypedName()
    -- The override lookup uses the resolvedID from GetSpellInfo, which works
    -- whether the user typed "Empower Rune Weapon" or 47568.
    local ns = fresh()
    mock.now = 100
    mock.spellInfo["Empower Rune Weapon"] = { name = "Empower Rune Weapon", spellId = 47568 }
    mock.spellCooldown["Empower Rune Weapon"] = { start = 90, duration = 300, enabled = 1 }
    ns.SpellDurations[47568] = 60
    local _, _, duration = ns.TRACKERS["Cooldown"]({ spellName = "Empower Rune Weapon" })
    assertx.assertEqual(duration, 60)
end

-- --------------------------------------------------------------------------
-- Resource mode dispatch table
-- --------------------------------------------------------------------------

function M.test_resourceTrackModesRegistry()
    local ns = fresh()
    assertx.assertTrue(ns:IsResourceTrackMode("Combo Points"))
    assertx.assertTrue(ns:IsResourceTrackMode("Runic Power"))
    assertx.assertTrue(ns:IsResourceTrackMode("Soul Shards"))
    assertx.assertTrue(ns:IsResourceTrackMode("Runes"))
    assertx.assertFalse(ns:IsResourceTrackMode("Cooldown"))
    assertx.assertFalse(ns:IsResourceTrackMode("Buff"))
    assertx.assertFalse(ns:IsResourceTrackMode(nil))
end

-- --------------------------------------------------------------------------
-- CheckTracker dispatch
-- --------------------------------------------------------------------------

function M.test_checkTracker_unknownModeReturnsInactive()
    local ns = fresh()
    local active = ns:CheckTracker({ trackMode = "Nonsense" })
    assertx.assertFalse(active)
end

function M.test_checkTracker_nilModeReturnsInactive()
    local ns = fresh()
    local active = ns:CheckTracker({})
    assertx.assertFalse(active)
end

return M
