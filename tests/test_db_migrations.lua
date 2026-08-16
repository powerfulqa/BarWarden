-- tests/test_db_migrations.lua
-- Exercises DB.lua's schema-versioned migration chain (v0 -> v1 -> v2 ->
-- v3 -> v4 -> v5). Each test seeds a snapshot of BarWardenDB at some
-- schema version, calls InitDB, and asserts the canonical post-migration
-- shape.
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
    assertx.assertEqual(_G.BarWardenDB.schemaVersion,  5)
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
    assertx.assertEqual(_G.BarWardenDB.schemaVersion, 5)
end

function M.test_migrationDoesNotRunOnCurrentSchema()
    -- Seed a "corrupt" state that v2 would clean up, but mark the DB as
    -- already v5. The migration guard must skip the v2 block entirely.
    freshDB({
        schemaVersion = 5,
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
-- v4 -> v5: scrub legacy token-parser cache keys from persisted bar configs
-- --------------------------------------------------------------------------

function M.test_v4_stripsTokenCacheFromBars()
    -- Pre-v1.10.2 Trackers.lua stashed `_tokenCache` + `_tokenCacheKey` on
    -- the barConfig, which sits inside SavedVariables. v5 wipes them so
    -- old saves don't carry the cache to disk (and profile exports).
    freshDB({
        schemaVersion = 4,
        global = {}, visual = {}, activity = {},
        frames = { { bars = {
            {
                trackMode = "Buff", spellName = "Slice and Dice",
                _tokenCache    = { "Slice and Dice" },
                _tokenCacheKey = "Slice and Dice",
            },
        } } },
    })
    local bar = _G.BarWardenDB.frames[1].bars[1]
    assertx.assertNil(bar._tokenCache,    "v5 migration must clear _tokenCache")
    assertx.assertNil(bar._tokenCacheKey, "v5 migration must clear _tokenCacheKey")
    assertx.assertEqual(bar.spellName, "Slice and Dice",
        "canonical fields must survive the scrub")
end

function M.test_v4_migratesMinimapFieldsIntoSubtable()
    -- v5 swaps the hand-rolled minimap button for LibDBIcon, which owns a
    -- db sub-table with `hide` + `minimapPos`. Old saves stored the icon
    -- state under `global.minimapIcon` (show-on) + `global.minimapIconPos`;
    -- the migration converts them into the new shape so existing users
    -- keep their angle and visibility.
    freshDB({
        schemaVersion = 4,
        global = {
            enabled = true, locked = true,
            minimapIcon    = false,   -- user had hidden the icon
            minimapIconPos = 142.5,
        },
        visual = {}, activity = {}, frames = {},
    })
    assertx.assertNotNil(_G.BarWardenDB.minimap,
        "v5 migration must create the minimap sub-table")
    assertx.assertEqual(_G.BarWardenDB.minimap.hide, true,
        "minimapIcon=false must invert to hide=true")
    assertx.assertEqual(_G.BarWardenDB.minimap.minimapPos, 142.5,
        "saved angle must survive the migration")
    assertx.assertNil(_G.BarWardenDB.global.minimapIcon,
        "legacy key should be cleared after migration")
    assertx.assertNil(_G.BarWardenDB.global.minimapIconPos,
        "legacy key should be cleared after migration")
end

function M.test_v4_minimapMigrationPreservesExistingSubtable()
    -- If a user (or a prior partial migration) has already populated
    -- BarWardenDB.minimap, don't stomp it; just clear the legacy keys.
    freshDB({
        schemaVersion = 4,
        global = { minimapIcon = true, minimapIconPos = 90 },
        visual = {}, activity = {}, frames = {},
        minimap = { hide = true, minimapPos = 270 },
    })
    assertx.assertEqual(_G.BarWardenDB.minimap.hide, true)
    assertx.assertEqual(_G.BarWardenDB.minimap.minimapPos, 270)
end

-- --------------------------------------------------------------------------
-- MergeDefaults must not corrupt user frames
-- --------------------------------------------------------------------------

function M.test_mergeDefaultsDoesNotInjectIntoFrames()
    -- Regression: the old InitDB ran MergeDefaults on the whole DB, which
    -- spliced sample-frame defaults into user frames. The current InitDB
    -- merges only `global` and `visual` and leaves `frames` untouched.
    freshDB({
        schemaVersion = 5,
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
-- autoIconOnly -> iconOnly rename (via MigrateFrames, unconditional on every
-- InitDB regardless of schemaVersion - Icon Only was promoted from an Auto
-- Track-only tickbox to a general Bar Overrides setting, and this proves the
-- rename fires even on an already-current-schema DB, not just on upgrade).
-- --------------------------------------------------------------------------

function M.test_autoIconOnlyRenamesToIconOnlyOnCurrentSchema()
    freshDB({
        schemaVersion = 5,
        global = {}, visual = {}, activity = {},
        frames = { { bars = {}, autoTrack = "playerBuffs", autoIconOnly = true } },
    })
    assertx.assertTrue(_G.BarWardenDB.frames[1].iconOnly)
    assertx.assertNil(_G.BarWardenDB.frames[1].autoIconOnly)
end

function M.test_groupWithoutAutoIconOnlyUntouchedOnCurrentSchema()
    freshDB({
        schemaVersion = 5,
        global = {}, visual = {}, activity = {},
        frames = { { bars = {}, autoTrack = "playerBuffs" } },
    })
    assertx.assertNil(_G.BarWardenDB.frames[1].iconOnly)
    assertx.assertNil(_G.BarWardenDB.frames[1].autoIconOnly)
end

-- --------------------------------------------------------------------------
-- Account-DB migration: legacy per-character profiles moved to account store
-- --------------------------------------------------------------------------

function M.test_legacyProfilesMigratedToAccountDb()
    _G.BarWardenDB = {
        schemaVersion = 5,
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
        schemaVersion = 5,
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

-- --------------------------------------------------------------------------
-- Profile contents (ns:CaptureProfileData / ns:ApplyProfileData)
--
-- These exist because the answer to "what is in a profile" used to be
-- written out at four separate call sites, and unit frames were added
-- without any of them learning about it - so every Frames-tab setting
-- silently failed to travel with an exported profile. The point of these
-- tests is that a section added to PROFILE_SECTIONS is carried by save,
-- load and import together, or not at all.
-- --------------------------------------------------------------------------

function M.test_captureProfile_carriesUnitFramesNotJustFramesAndVisual()
    local ns = freshDB(nil)
    ns.db.unitFrames.player.enabled = true
    ns.db.unitFrames.player.portraitStyle = "3D"

    local data = ns:CaptureProfileData()
    assertx.assertTrue(type(data.frames) == "table", "frames must be captured")
    assertx.assertTrue(type(data.visual) == "table", "visual must be captured")
    assertx.assertTrue(type(data.unitFrames) == "table", "unit frames must be captured")
    assertx.assertEqual(data.unitFrames.player.portraitStyle, "3D")
end

-- A copy, not a reference: a captured profile must not keep changing as the
-- live config does, or "Save" would be meaningless.
function M.test_captureProfile_isADeepCopy()
    local ns = freshDB(nil)
    local data = ns:CaptureProfileData()
    ns.db.unitFrames.player.barHeight = 39
    assertx.assertTrue(data.unitFrames.player.barHeight ~= 39,
        "the snapshot must not track later edits")
end

function M.test_applyProfile_restoresUnitFrames()
    local ns = freshDB(nil)
    ns:ApplyProfileData({ unitFrames = { player = { enabled = true, barHeight = 22 } } })
    assertx.assertTrue(ns.db.unitFrames.player.enabled)
    assertx.assertEqual(ns.db.unitFrames.player.barHeight, 22)
end

-- Backfill: a profile saved before a setting existed must come back with the
-- current default filled in, not nil, or the next Save would persist a table
-- with holes in it.
function M.test_applyProfile_backfillsKeysAddedSinceItWasSaved()
    local ns = freshDB(nil)
    ns:ApplyProfileData({ unitFrames = { player = { enabled = true } } })
    assertx.assertEqual(ns.db.unitFrames.player.barTexture,
                        ns.DEFAULTS.unitFrames.player.barTexture,
                        "a key the profile predates must be backfilled")
end

-- A profile saved before unit frames existed must leave the current ones
-- alone rather than wiping them.
function M.test_applyProfile_absentSectionIsLeftUntouched()
    local ns = freshDB(nil)
    ns.db.unitFrames.player.enabled = true
    ns:ApplyProfileData({ frames = {}, visual = {} })
    assertx.assertTrue(ns.db.unitFrames.player.enabled,
        "an older profile must not wipe a section it never knew about")
end

function M.test_profileHasContent_acceptsAnyKnownSection()
    local ns = freshDB(nil)
    assertx.assertTrue(ns:ProfileDataHasContent({ frames = {} }))
    assertx.assertTrue(ns:ProfileDataHasContent({ visual = {} }))
    -- The case the old frames-or-visual check would have wrongly rejected.
    assertx.assertTrue(ns:ProfileDataHasContent({ unitFrames = {} }))
end

function M.test_profileHasContent_rejectsJunk()
    local ns = freshDB(nil)
    assertx.assertFalse(ns:ProfileDataHasContent({}))
    assertx.assertFalse(ns:ProfileDataHasContent({ nonsense = {} }))
    assertx.assertFalse(ns:ProfileDataHasContent("not a table"))
    assertx.assertFalse(ns:ProfileDataHasContent(nil))
end

-- The round trip is the thing that actually broke, so assert it end to end.
function M.test_profileRoundTrip_preservesFramesSettings()
    local ns = freshDB(nil)
    ns.db.unitFrames.player.enabled       = true
    ns.db.unitFrames.player.portraitStyle = "3D"
    ns.db.unitFrames.player.barHeight     = 21
    ns.db.unitFrames.player.frameOpacity  = 0.35
    ns.db.unitFrames.player.hiddenResources = { runes = true }

    local exported = ns:CaptureProfileData()

    -- Wipe the live side the way loading a different profile would.
    ns.db.unitFrames.player.enabled       = false
    ns.db.unitFrames.player.portraitStyle = "2D"
    ns.db.unitFrames.player.barHeight     = 16
    ns.db.unitFrames.player.frameOpacity  = 1.0
    ns.db.unitFrames.player.hiddenResources = {}

    ns:ApplyProfileData(exported)

    local p = ns.db.unitFrames.player
    assertx.assertTrue(p.enabled)
    assertx.assertEqual(p.portraitStyle, "3D")
    assertx.assertEqual(p.barHeight, 21)
    assertx.assertEqual(p.frameOpacity, 0.35)
    assertx.assertTrue(p.hiddenResources.runes, "resource choices must survive the round trip")
end

-- Every unit frame, not just the player's. Adding target/target's target
-- must not need a second edit here, and if it ever does, that is the signal
-- that profile capture has gone back to naming things one at a time.
function M.test_profileRoundTrip_carriesEveryUnitFrame()
    local ns = freshDB(nil)
    ns.db.unitFrames.target.enabled = true
    ns.db.unitFrames.target.barHeight = 24
    ns.db.unitFrames.targettarget.enabled = true

    local exported = ns:CaptureProfileData()
    ns.db.unitFrames.target.enabled = false
    ns.db.unitFrames.target.barHeight = 16
    ns.db.unitFrames.targettarget.enabled = false

    ns:ApplyProfileData(exported)
    assertx.assertTrue(ns.db.unitFrames.target.enabled, "target frame must round-trip")
    assertx.assertEqual(ns.db.unitFrames.target.barHeight, 24)
    assertx.assertTrue(ns.db.unitFrames.targettarget.enabled,
        "target's target frame must round-trip")
end

-- MergeDefaults must add the new frames to a save written before they
-- existed, rather than leaving nil tables that every accessor then has to
-- guard against.
function M.test_existingSaveGainsTheNewUnitFrames()
    local ns = freshDB({
        schemaVersion = 5,
        frames = {},
        unitFrames = { player = { enabled = true } },
    })
    assertx.assertTrue(type(ns.db.unitFrames.target) == "table",
        "an older save must gain the target frame")
    assertx.assertTrue(type(ns.db.unitFrames.targettarget) == "table",
        "an older save must gain the target's target frame")
    assertx.assertFalse(ns.db.unitFrames.target.enabled,
        "a frame the user never asked for must arrive switched off")
    assertx.assertTrue(ns.db.unitFrames.player.enabled,
        "the existing player frame must be left alone")
end

return M
