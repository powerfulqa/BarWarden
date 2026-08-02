-- tests/test_migration.lua
-- v2 upgrade-safety invariants. Locks the fixes for the "bars lost after
-- upgrading" bug so they can't regress. Grows to cover MigrateFrames and the
-- per-bar backfill as those land.

local assertx = require("assert")
local load_addon = require("load_addon")

local M = {}

local function freshUtils()
    local ns = {}
    load_addon.load("Utils.lua", "BarWarden", ns)
    return ns
end

local function freshDB()
    local ns = {}
    load_addon.load("Utils.lua", "BarWarden", ns)
    load_addon.load("DB.lua", "BarWarden", ns)
    return ns
end

-- ns:HasExistingLayout gates the first-login starter prompt. It must report
-- "true" (leave the layout alone) whenever there is anything worth protecting.

function M.test_layout_freshIsNotProtected()
    local ns = freshUtils()
    assertx.assertEqual(ns:HasExistingLayout(nil), false)
    assertx.assertEqual(ns:HasExistingLayout({}), false)
    -- A single empty group is still "fresh" - nothing to lose.
    assertx.assertEqual(ns:HasExistingLayout({ { name = "G", bars = {} } }), false)
end

function M.test_layout_oneBarIsProtected()
    -- The exact upgrade-data-loss case: one group with one configured bar.
    local ns = freshUtils()
    assertx.assertTrue(
        ns:HasExistingLayout({ { name = "G", bars = { { trackMode = "Cooldown", spellName = "Evasion" } } } }),
        "a group with a bar must be protected from the starter prompt")
end

function M.test_layout_multipleGroupsProtected()
    local ns = freshUtils()
    assertx.assertTrue(ns:HasExistingLayout({ { bars = {} }, { bars = {} } }),
        "more than one group is a built layout, protect it")
end

-- ns:MigrateFrames is the single entry point every frame source routes
-- through (live DB, profile load, import, starter). It must canonicalise
-- legacy fields and backfill sub-tables without ever clobbering identity.

function M.test_migrateFrames_canonicalisesLegacyFields()
    local ns = freshDB()
    local frames = { { bars = { { trackMode = "Buff", spell = "Rejuvenation", target = "player" } } } }
    ns:MigrateFrames(frames)
    local bar = frames[1].bars[1]
    assertx.assertEqual(bar.spellName, "Rejuvenation")
    assertx.assertEqual(bar.unit, "player")
    assertx.assertNil(bar.spell)
    assertx.assertNil(bar.target)
end

function M.test_migrateFrames_numericSpellRouting()
    local ns = freshDB()
    local frames = { { bars = {
        { trackMode = "Cooldown", spell = 1766 },
        { trackMode = "Item", spell = 6948 },
    } } }
    ns:MigrateFrames(frames)
    assertx.assertEqual(frames[1].bars[1].spellId, 1766)
    assertx.assertEqual(frames[1].bars[2].itemId, 6948)
end

function M.test_migrateFrames_backfillsSubTables()
    local ns = freshDB()
    local frames = { { bars = { { trackMode = "Cooldown", spellId = 1766 } } } }
    ns:MigrateFrames(frames)
    assertx.assertEqual(type(frames[1].bars[1].conditions), "table")
    assertx.assertEqual(type(frames[1].bars[1].display), "table")
    assertx.assertEqual(frames[1].sortMode, "manual")
end

function M.test_migrateFrames_neverClobbersIdentity()
    local ns = freshDB()
    local frames = { { bars = {
        { trackMode = "Buff", spellName = "Evasion", spell = "Legacy",
          conditions = { combatOnly = true } },
    } } }
    ns:MigrateFrames(frames)
    local bar = frames[1].bars[1]
    assertx.assertEqual(bar.spellName, "Evasion")  -- legacy spell must NOT overwrite
    assertx.assertNil(bar.spell)
    assertx.assertTrue(bar.conditions.combatOnly)  -- existing sub-table preserved
end

function M.test_migrateFrames_idempotent()
    local ns = freshDB()
    local frames = { { bars = { { trackMode = "Cooldown", spell = 1766 } } } }
    ns:MigrateFrames(frames)
    ns:MigrateFrames(frames)
    assertx.assertEqual(frames[1].bars[1].spellId, 1766)
    assertx.assertNil(frames[1].bars[1].spell)
end

-- Safety: in the normal single-addon release, v1's DB IS our DB, so
-- GetV1Layout must find "nothing separate" and return nil - the release build
-- must never self-import. (The positive path only fires in the parallel V2
-- build, where the deploy rename makes our DB a different global; that rides
-- the in-game test.)
function M.test_getV1Layout_nilWhenSameAddon()
    local ns = freshDB()
    _G.BarWardenDB = { frames = { { bars = { { trackMode = "Cooldown" } } } } }
    assertx.assertNil(ns:GetV1Layout())
    _G.BarWardenDB = nil
end

-- --------------------------------------------------------------------------
-- NormalizeGroupAnchor: the group-position drift fix. Screen edges must pass
-- through verbatim - any scale factor here is the drift bug returning.
-- --------------------------------------------------------------------------

function M.test_normalizeAnchor_growDown_pinsTopVerbatim()
    local ns = freshUtils()
    local p = ns:NormalizeGroupAnchor(false, 100, 550, 400)
    assertx.assertEqual(p.point, "TOPLEFT")
    assertx.assertEqual(p.relativePoint, "BOTTOMLEFT")
    assertx.assertEqual(p.x, 100)
    assertx.assertEqual(p.y, 550)
end

function M.test_normalizeAnchor_growUp_pinsBottomVerbatim()
    local ns = freshUtils()
    local p = ns:NormalizeGroupAnchor(true, 100, 550, 400)
    assertx.assertEqual(p.point, "BOTTOMLEFT")
    assertx.assertEqual(p.relativePoint, "BOTTOMLEFT")
    assertx.assertEqual(p.x, 100)
    assertx.assertEqual(p.y, 400)
end

-- Re-normalising an already-normalised anchor must be a no-op. The drift bug
-- was exactly this being non-idempotent (each pass multiplied by the scale).
function M.test_normalizeAnchor_isIdempotent()
    local ns = freshUtils()
    local first  = ns:NormalizeGroupAnchor(true, 100, 550, 400)
    local second = ns:NormalizeGroupAnchor(true, first.x, 550, first.y)
    assertx.assertEqual(second.x, first.x)
    assertx.assertEqual(second.y, first.y)
end

-- --------------------------------------------------------------------------
-- Per-group backfill: fills nils only, never touches a saved position.
-- --------------------------------------------------------------------------

function M.test_migrateFrames_backfillsGroupDefaults()
    local ns = freshDB()
    local frames = { { bars = {} } }
    ns:MigrateFrames(frames)
    assertx.assertEqual(frames[1].growDirection, "DOWN")
    assertx.assertEqual(frames[1].columns, 1)
    assertx.assertEqual(type(frames[1].position), "table")
end

function M.test_migrateFrames_keepsExistingGroupPosition()
    local ns = freshDB()
    local frames = { {
        bars = {},
        growDirection = "UP",
        columns = 2,
        position = { point = "BOTTOMLEFT", relativePoint = "BOTTOMLEFT", x = 42, y = 99 },
    } }
    ns:MigrateFrames(frames)
    assertx.assertEqual(frames[1].growDirection, "UP")
    assertx.assertEqual(frames[1].columns, 2)
    assertx.assertEqual(frames[1].position.x, 42)
    assertx.assertEqual(frames[1].position.y, 99)
end

-- --------------------------------------------------------------------------
-- autoIconOnly -> iconOnly rename: Icon Only was promoted from an Auto
-- Track-only tickbox to a general Bar Overrides setting. Owners who already
-- had it ticked on a live auto-tracking group must not silently lose it.
-- --------------------------------------------------------------------------

function M.test_migrateFrames_autoIconOnlyCarriesOverToIconOnly()
    local ns = freshDB()
    local frames = { { bars = {}, autoTrack = "playerBuffs", autoIconOnly = true } }
    ns:MigrateFrames(frames)
    assertx.assertTrue(frames[1].iconOnly)
    assertx.assertNil(frames[1].autoIconOnly)
end

function M.test_migrateFrames_autoIconOnlyFalseCarriesOver()
    local ns = freshDB()
    local frames = { { bars = {}, autoTrack = "playerBuffs", autoIconOnly = false } }
    ns:MigrateFrames(frames)
    assertx.assertEqual(frames[1].iconOnly, false)
    assertx.assertNil(frames[1].autoIconOnly)
end

function M.test_migrateFrames_groupWithoutAutoIconOnlyIsUntouched()
    local ns = freshDB()
    local frames = { { bars = {}, autoTrack = "playerBuffs" } }
    ns:MigrateFrames(frames)
    assertx.assertNil(frames[1].iconOnly)
    assertx.assertNil(frames[1].autoIconOnly)
end

function M.test_migrateFrames_autoIconOnlyRenameIsIdempotent()
    local ns = freshDB()
    local frames = { { bars = {}, autoIconOnly = true } }
    ns:MigrateFrames(frames)
    ns:MigrateFrames(frames)
    assertx.assertTrue(frames[1].iconOnly)
    assertx.assertNil(frames[1].autoIconOnly)
end

function M.test_migrateFrames_autoIconOnlyNeverClobbersExistingIconOnly()
    local ns = freshDB()
    -- A group that somehow already has both (e.g. a partially-migrated
    -- import): the existing iconOnly value wins, matching the "fill nil
    -- keys only" rule every other rename in this function follows.
    local frames = { { bars = {}, autoIconOnly = true, iconOnly = false } }
    ns:MigrateFrames(frames)
    assertx.assertEqual(frames[1].iconOnly, false)
    assertx.assertNil(frames[1].autoIconOnly)
end

return M
