-- tests/test_db_migrations.lua
-- Exercises DB.lua's schema-versioned migration chain (v0 -> v1 -> v2 ->
-- v3 -> v4). Each test seeds a snapshot of BarWardenDB at some schema
-- version, calls InitDB, and asserts the canonical post-migration shape.
--
-- Migrations are the single scariest code path in a user-data-holding
-- addon: a silent corruption here means a user's bars/settings vanish
-- on the next login. These tests are the gate that catches regressions
-- before a release ships.

local assertx    = require("assert")
local load_addon = require("load_addon")

local M = {}

local function freshDB(preset)
    local ns = {}
    load_addon.load("Utils.lua", "BarWarden", ns)
    _G.BarWardenDB        = preset
    _G.BarWardenAccountDB = nil
    load_addon.load("DB.lua", "BarWarden", ns)
    ns:InitDB()
    return ns
end

-- --------------------------------------------------------------------------
-- Fresh install
-- --------------------------------------------------------------------------

function M.test_freshInstall_populatesDefaults()
    local ns = freshDB(nil)
    assertx.assertNotNil(_G.BarWardenDB)
    assertx.assertEqual(_G.BarWardenDB.global.enabled, true)
    assertx.assertEqual(_G.BarWardenDB.schemaVersion,  4)
    assertx.assertDeepEqual(_G.BarWardenDB.frames, {})
end

function M.test_freshInstall_seedsDefaultAccountProfile()
    freshDB(nil)
    assertx.assertNotNil(_G.BarWardenAccountDB)
    assertx.assertNotNil(_G.BarWardenAccountDB.profiles["Default"])
end

-- --------------------------------------------------------------------------
-- v0 -> v1: legacy field rename
-- --------------------------------------------------------------------------

function M.test_v0_stringSpellBecomesSpellName()
    local ns = freshDB({
        frames = { { bars = { { trackMode = "Buff", spell = "Evasion" } } } },
    })
    local bar = _G.BarWardenDB.frames[1].bars[1]
    assertx.assertEqual(bar.spellName, "Evasion")
    assertx.assertNil(bar.spell)
end

function M.test_v0_numericSpellBecomesSpellId_forCooldown()
    freshDB({
        frames = { { bars = { { trackMode = "Cooldown", spell = 1856 } } } },
    })
    local bar = _G.BarWardenDB.frames[1].bars[1]
    assertx.assertEqual(bar.spellId, 1856)
    assertx.assertNil(bar.spell)
end

function M.test_v0_numericSpellBecomesItemId_forItem()
    freshDB({
        frames = { { bars = { { trackMode = "Item", spell = 6948 } } } },
    })
    local bar = _G.BarWardenDB.frames[1].bars[1]
    assertx.assertEqual(bar.itemId, 6948)
    assertx.assertNil(bar.spell)
end

function M.test_v0_spellInputRenamedToSpellName()
    freshDB({
        frames = { { bars = { { trackMode = "Buff", spellInput = "Slice and Dice" } } } },
    })
    local bar = _G.BarWardenDB.frames[1].bars[1]
    assertx.assertEqual(bar.spellName, "Slice and Dice")
    assertx.assertNil(bar.spellInput)
end

function M.test_v0_targetRenamedToUnit()
    freshDB({
        frames = { { bars = { { trackMode = "Buff", spellName = "X", target = "focus" } } } },
    })
    local bar = _G.BarWardenDB.frames[1].bars[1]
    assertx.assertEqual(bar.unit, "focus")
    assertx.assertNil(bar.target)
end

function M.test_v0_doesNotOverwriteExistingCanonicalFields()
    -- If both legacy and canonical fields are present, canonical wins.
    freshDB({
        frames = { { bars = {
            { trackMode = "Buff", spell = "Legacy", spellName = "Canonical" },
        } } },
    })
    local bar = _G.BarWardenDB.frames[1].bars[1]
    assertx.assertEqual(bar.spellName, "Canonical")
    assertx.assertNil(bar.spell)
end

-- --------------------------------------------------------------------------
-- v1 -> v2: clear spellId corrupted by the old MergeDefaults bug
-- --------------------------------------------------------------------------

function M.test_v1_clearsCorruptedSpellIdOnCooldownBar()
    -- Pre-v2: MergeDefaults injected the sample Hearthstone spellId=6948 onto
    -- a user's Evasion Cooldown bar. The v2 migration drops spellId when both
    -- fields are set on a non-Item bar, because the UI only ever sets one.
    freshDB({
        schemaVersion = 1,
        frames = { { bars = {
            { trackMode = "Cooldown", spellName = "Evasion", spellId = 6948 },
        } } },
    })
    local bar = _G.BarWardenDB.frames[1].bars[1]
    assertx.assertEqual(bar.spellName, "Evasion")
    assertx.assertNil(bar.spellId, "corrupted spellId should have been cleared")
end

function M.test_v1_leavesItemBarsAlone()
    -- Item bars legitimately carry both fields and must survive the migration.
    freshDB({
        schemaVersion = 1,
        frames = { { bars = {
            { trackMode = "Item", spellName = "Hearthstone", spellId = 6948 },
        } } },
    })
    local bar = _G.BarWardenDB.frames[1].bars[1]
    assertx.assertEqual(bar.spellName, "Hearthstone")
    assertx.assertEqual(bar.spellId,   6948)
end

function M.test_v1_leavesBarWithOnlySpellIdAlone()
    -- If only spellId is set (no spellName), it wasn't injected; keep it.
    freshDB({
        schemaVersion = 1,
        frames = { { bars = {
            { trackMode = "Cooldown", spellId = 1856 },
        } } },
    })
    local bar = _G.BarWardenDB.frames[1].bars[1]
    assertx.assertEqual(bar.spellId, 1856)
end

-- --------------------------------------------------------------------------
-- v2 -> v3: ensure sortMode exists on every frame
-- --------------------------------------------------------------------------

function M.test_v2_fillsSortModeOnAllFrames()
    freshDB({
        schemaVersion = 2,
        frames = {
            { name = "A", bars = {} },
            { name = "B", bars = {}, sortMode = "alpha" },  -- existing value preserved
        },
    })
    assertx.assertEqual(_G.BarWardenDB.frames[1].sortMode, "manual")
    assertx.assertEqual(_G.BarWardenDB.frames[2].sortMode, "alpha")
end

-- --------------------------------------------------------------------------
-- v3 -> v4: initialise the activity tracker table
-- --------------------------------------------------------------------------

function M.test_v3_initialisesActivityTable()
    freshDB({ schemaVersion = 3 })
    assertx.assertDeepEqual(_G.BarWardenDB.activity, {})
end

-- --------------------------------------------------------------------------
-- Schema version stamping
-- --------------------------------------------------------------------------

function M.test_schemaVersionStampedAtEnd()
    freshDB({ schemaVersion = 0 })
    assertx.assertEqual(_G.BarWardenDB.schemaVersion, 4)
end

function M.test_migrationDoesNotRunOnCurrentSchema()
    -- Seed a "corrupt" state that v2 would clean up, but mark the DB as
    -- already v4. The migration guard must skip the v2 block entirely.
    freshDB({
        schemaVersion = 4,
        global = {},
        visual = {},
        frames = { { bars = {
            { trackMode = "Cooldown", spellName = "Evasion", spellId = 6948 },
        } } },
        activity = {},
    })
    local bar = _G.BarWardenDB.frames[1].bars[1]
    assertx.assertEqual(bar.spellId, 6948,
        "v2 migration fired under schemaVersion >= CURRENT_SCHEMA")
end

-- --------------------------------------------------------------------------
-- MergeDefaults must not corrupt user frames
-- --------------------------------------------------------------------------

function M.test_mergeDefaultsDoesNotInjectIntoFrames()
    -- Regression: the old InitDB ran MergeDefaults on the whole DB, which
    -- spliced sample-frame defaults into user frames. The current InitDB
    -- merges only `global` and `visual` and leaves `frames` untouched.
    freshDB({
        schemaVersion = 4,
        global = {},
        visual = {},
        frames = {
            { name = "Mine", bars = { { trackMode = "Cooldown", spellName = "Evasion" } } },
        },
        activity = {},
    })
    assertx.assertEqual(#_G.BarWardenDB.frames, 1)
    assertx.assertEqual(#_G.BarWardenDB.frames[1].bars, 1)
    assertx.assertEqual(_G.BarWardenDB.frames[1].name, "Mine")
end

-- --------------------------------------------------------------------------
-- Account-DB migration: legacy per-character profiles moved to account store
-- --------------------------------------------------------------------------

function M.test_legacyProfilesMigratedToAccountDb()
    _G.BarWardenDB = {
        schemaVersion = 4,
        global = {}, visual = {}, frames = {}, activity = {},
        profiles = {
            Old = { description = "x", lastModified = 0,
                    data = { frames = {}, visual = {} } },
        },
    }
    _G.BarWardenAccountDB = nil
    local ns = {}
    load_addon.load("Utils.lua", "BarWarden", ns)
    load_addon.load("DB.lua",    "BarWarden", ns)
    ns:InitDB()
    assertx.assertNil(_G.BarWardenDB.profiles, "legacy profiles table should be cleared")
    assertx.assertNotNil(_G.BarWardenAccountDB.profiles["Old"])
end

function M.test_legacyProfileMigrationDoesNotClobberAccountEntry()
    -- If BarWardenAccountDB already has "Old", the legacy copy must not overwrite.
    _G.BarWardenDB = {
        schemaVersion = 4,
        global = {}, visual = {}, frames = {}, activity = {},
        profiles = { Old = { marker = "legacy" } },
    }
    _G.BarWardenAccountDB = { profiles = { Old = { marker = "account" } } }
    local ns = {}
    load_addon.load("Utils.lua", "BarWarden", ns)
    load_addon.load("DB.lua",    "BarWarden", ns)
    ns:InitDB()
    assertx.assertEqual(_G.BarWardenAccountDB.profiles.Old.marker, "account")
end

return M
