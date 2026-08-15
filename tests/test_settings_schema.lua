-- tests/test_settings_schema.lua
--
-- Lock the DEFAULTS shape + core registries + condition-check order.
--
-- When any of these tests fails, the change was either:
--   (a) INTENTIONAL - update the expected value below to match. The test
--       failing forces you to write the update down, so future sessions
--       (and your future self) can see the new canonical shape.
--   (b) ACCIDENTAL - revert. A removed default or a renamed track mode
--       silently breaks user saves and the options UI; this test is the
--       gate that keeps "oops" out of a release.
--
-- Prefer extending the expected tables here over deleting assertions.
-- Strict schema tests are maintenance work on purpose.

local assertx    = require("assert")
local load_addon = require("load_addon")

local M = {}

local function freshDB()
    local ns = {}
    load_addon.load("Utils.lua", "BarWarden", ns)
    load_addon.load("DB.lua",    "BarWarden", ns)
    return ns
end

local function freshTrackers()
    local ns = {}
    load_addon.load("Utils.lua",      "BarWarden", ns)
    load_addon.load("AuraGroups.lua", "BarWarden", ns)
    load_addon.load("Trackers.lua",   "BarWarden", ns)
    return ns
end

local function freshConditions()
    local ns = {}
    load_addon.load("Utils.lua",      "BarWarden", ns)
    load_addon.load("Conditions.lua", "BarWarden", ns)
    return ns
end

-- --------------------------------------------------------------------------
-- Top-level DEFAULTS shape
-- --------------------------------------------------------------------------

function M.test_defaults_topLevelKeys()
    local ns = freshDB()
    local expected = {
        schemaVersion = true,
        global        = true,
        visual        = true,
        minimap       = true,
        frames        = true,
        activity      = true,
        activeProfile = true,
    }
    -- activeProfile is nil by design; include it in the expected set so the
    -- existence check passes. Use a direct key-walk that tolerates nil values.
    local actual = {}
    for k in pairs(ns.DEFAULTS) do actual[k] = true end
    -- activeProfile is deliberately nil at the value level so pairs() won't
    -- surface it. Verify it was set to nil in DEFAULTS but don't require it
    -- in the key set check.
    expected.activeProfile = nil
    assertx.assertSameKeys(actual, expected, "DEFAULTS top-level keys")
    assertx.assertNil(ns.DEFAULTS.activeProfile, "activeProfile must default to nil")
end

function M.test_defaults_schemaVersionMatchesCurrent()
    -- CURRENT_SCHEMA in DB.lua must match DEFAULTS.schemaVersion. Bumping
    -- one without the other means fresh installs land on the wrong version
    -- and either re-run migrations on clean data or skip them on upgrades.
    local ns = freshDB()
    assertx.assertEqual(ns.DEFAULTS.schemaVersion, 5)
end

function M.test_defaults_framesIsEmptyArray()
    local ns = freshDB()
    assertx.assertDeepEqual(ns.DEFAULTS.frames, {})
end

function M.test_defaults_activityIsEmptyTable()
    local ns = freshDB()
    assertx.assertDeepEqual(ns.DEFAULTS.activity, {})
end

-- --------------------------------------------------------------------------
-- DEFAULTS.global
-- --------------------------------------------------------------------------

function M.test_defaults_globalExact()
    local ns = freshDB()
    assertx.assertDeepEqual(ns.DEFAULTS.global, {
        enabled = true,
        locked  = true,
        versionAlerts = true,
        hidePlayerFrame = false,
        -- Help-tab section collapse seed (added with the Help tab). Getting
        -- Started ships open, so it has no key here; the rest start collapsed.
        helpCollapsed = {
            trackingModes   = true,
            autoTracking    = true,
            conditions      = true,
            visuals         = true,
            profiles        = true,
            activity        = true,
            troubleshooting = true,
        },
    }, "DEFAULTS.global drift - see the file header for what to do")
end

-- Minimap state lives outside `global` because LibDBIcon-1.0 expects to
-- own the `hide` + `minimapPos` keys directly on the db sub-table it was
-- registered with.
function M.test_defaults_minimapExact()
    local ns = freshDB()
    assertx.assertDeepEqual(ns.DEFAULTS.minimap, {
        hide       = false,
        minimapPos = 220,
    }, "DEFAULTS.minimap drift")
end

-- --------------------------------------------------------------------------
-- DEFAULTS.visual - key set locked, then critical values locked
-- --------------------------------------------------------------------------

function M.test_defaults_visualHasExactKeys()
    local ns = freshDB()
    local expectedKeys = {
        -- Texture + custom
        texture = 1, customTexture = 1,
        -- Sizing
        barWidth = 1, barHeight = 1, iconSize = 1, barSpacing = 1,
        -- Icon
        showIcon = 1, iconPosition = 1, iconCrop = 1,
        -- Font + text
        font = 1, fontSize = 1, textEnabled = 1, textPosition = 1,
        textFormat = 1, durationStyle = 1, showStacks = 1,
        stackFontSize = 1, stackColor = 1,
        -- Colour
        colorMode = 1, defaultColor = 1, trackModeColors = 1,
        -- Alpha
        activeAlpha = 1, inactiveAlpha = 1,
        -- Bar features
        showSpark = 1, showCooldownSpiral = 1, showBarTooltip = 1,
    }
    assertx.assertSameKeys(ns.DEFAULTS.visual, expectedKeys, "DEFAULTS.visual")
end

function M.test_defaults_visualCriticalValues()
    -- Values that ship in starter profiles and export strings - changing
    -- any of these silently shifts every new user's starting experience.
    local ns = freshDB()
    local v = ns.DEFAULTS.visual
    assertx.assertEqual(v.texture,       "Flat")
    assertx.assertEqual(v.barWidth,      200)
    assertx.assertEqual(v.barHeight,     20)
    assertx.assertEqual(v.iconSize,      20)
    assertx.assertEqual(v.barSpacing,    2)
    assertx.assertEqual(v.font,          "Fonts\\FRIZQT__.TTF")
    assertx.assertEqual(v.fontSize,      11)
    assertx.assertEqual(v.textFormat,    "NAME_DURATION")
    assertx.assertEqual(v.textPosition,  "INSIDE_LEFT")
    assertx.assertEqual(v.durationStyle, "DECIMAL")
    assertx.assertEqual(v.showStacks,    true)
    assertx.assertEqual(v.stackFontSize, 12)
    assertx.assertEqual(v.colorMode,     "CLASS")
    assertx.assertEqual(v.activeAlpha,   1.0)
    assertx.assertEqual(v.inactiveAlpha, 0.3)
    assertx.assertEqual(v.showIcon,      true)
    assertx.assertEqual(v.showSpark,     true)
    assertx.assertEqual(v.iconCrop,      true)
    assertx.assertEqual(v.showCooldownSpiral, true)
    assertx.assertEqual(v.showBarTooltip, false)
    assertx.assertEqual(v.iconPosition,   "LEFT")
    assertx.assertEqual(v.customTexture,  "")
    assertx.assertEqual(v.textEnabled,    true)
end

function M.test_defaults_defaultColorExact()
    local ns = freshDB()
    assertx.assertDeepEqual(ns.DEFAULTS.visual.defaultColor, { r = 0.2, g = 0.6, b = 1.0 })
end

-- White, matching NumberFontNormalSmall's own <Color r="1" g="1" b="1"/> -
-- the fixed template the stack badge used before Stack Text Colour existed,
-- so a fresh install's badge renders identically to before this setting.
function M.test_defaults_stackColorExact()
    local ns = freshDB()
    assertx.assertDeepEqual(ns.DEFAULTS.visual.stackColor, { r = 1, g = 1, b = 1 })
end

-- --------------------------------------------------------------------------
-- trackModeColors must cover every tracker that the options UI offers
-- --------------------------------------------------------------------------

function M.test_trackModeColors_coverEveryRegisteredTracker()
    -- Every mode in ns.TRACKERS must have a colour entry, otherwise the
    -- TRACK_MODE colouring silently falls back to defaultColor at runtime.
    local nsT = freshTrackers()
    local nsD = freshDB()
    for mode in pairs(nsT.TRACKERS) do
        assertx.assertNotNil(nsD.DEFAULTS.visual.trackModeColors[mode],
            "trackModeColors missing entry for " .. mode)
    end
end

function M.test_trackModeColors_noOrphanEntries()
    -- The inverse: every colour entry must reference a real tracker. An
    -- orphan entry means a tracker was removed but the colour was forgotten.
    local nsT = freshTrackers()
    local nsD = freshDB()
    for mode in pairs(nsD.DEFAULTS.visual.trackModeColors) do
        assertx.assertNotNil(nsT.TRACKERS[mode],
            "trackModeColors has orphan entry for removed tracker: " .. mode)
    end
end

-- --------------------------------------------------------------------------
-- Tracker registries
-- --------------------------------------------------------------------------

function M.test_trackers_exactSet()
    local ns = freshTrackers()
    local expected = {
        ["Cooldown"]     = 1,
        ["Buff"]         = 1,
        ["Debuff"]       = 1,
        ["Proc"]         = 1,
        ["Item"]         = 1,
        ["Enchant"]      = 1,
        ["Enchant MH"]   = 1,
        ["Enchant OH"]   = 1,
        ["Totem"]        = 1,
        ["Combo Points"] = 1,
        ["Runic Power"]  = 1,
        ["Soul Shards"]  = 1,
        ["Runes"]        = 1,
        ["Health"]       = 1,
        ["Mana"]         = 1,
        ["Energy"]       = 1,
        ["Rage"]         = 1,
    }
    assertx.assertSameKeys(ns.TRACKERS, expected, "TRACKERS registry")
end

function M.test_resourceTrackers_exactSet()
    local ns = freshTrackers()
    local expected = {
        ["Combo Points"] = 1,
        ["Runic Power"]  = 1,
        ["Soul Shards"]  = 1,
        ["Runes"]        = 1,
        ["Health"]       = 1,
        ["Mana"]         = 1,
        ["Energy"]       = 1,
        ["Rage"]         = 1,
    }
    assertx.assertSameKeys(ns.RESOURCE_TRACK_MODES, expected, "RESOURCE_TRACK_MODES")
end

function M.test_resourceTrackers_subsetOfTrackers()
    -- Invariant: anything marked resource-mode must actually have a tracker,
    -- otherwise ScanBar dispatches to UpdateResourceBar for a mode that
    -- doesn't resolve to a checker.
    local ns = freshTrackers()
    for mode in pairs(ns.RESOURCE_TRACK_MODES) do
        assertx.assertNotNil(ns.TRACKERS[mode],
            "RESOURCE_TRACK_MODES references unknown tracker: " .. mode)
    end
end

-- --------------------------------------------------------------------------
-- Condition registry order - locks the short-circuit order
-- --------------------------------------------------------------------------

-- --------------------------------------------------------------------------
-- Options_Builder's OFFSET_* constants - guard the load-order assumption
-- --------------------------------------------------------------------------

function M.test_offsetConstants_areNumbersAfterOptionsLoad()
    -- Options_General.lua's schema reads ns.OFFSET_* at FILE SCOPE (see its
    -- SCHEMA table literal), so it depends on Options_Builder.lua having
    -- already run and set them on the shared ns. BarWarden.toc currently
    -- lists Options_Builder.lua before Options_General.lua; load them here
    -- in that same order so a future TOC reorder that breaks this silently
    -- degrades every offsetX to nil (SetPoint math would then error at
    -- runtime) rather than being caught here.
    local ns = {}
    load_addon.load("Options_Builder.lua", "BarWarden", ns)
    load_addon.load("Options_General.lua",  "BarWarden", ns)

    local names = {
        "OFFSET_HEADER", "OFFSET_DROPDOWN", "OFFSET_TOGGLE",
        "OFFSET_SLIDER", "OFFSET_EDITBOX", "OFFSET_COLOR",
    }
    for _, name in ipairs(names) do
        assertx.assertTrue(type(ns[name]) == "number",
            "ns." .. name .. " must be a number after Options_Builder.lua loads, got "
                .. type(ns[name]))
    end
end

function M.test_conditions_registrationOrder()
    -- Short-circuit order is a perf + correctness contract: requireClass
    -- first (cheapest + most selective; reject non-class bars before
    -- touching any game state), then cheap flag checks, then expensive
    -- UnitBuff scan (requireBuff), then state checks. Reordering changes
    -- how quickly bars bail out during the scan loop. If you reorder on
    -- purpose, update the expected list below and justify in the commit.
    local ns = freshConditions()
    local expected = {
        "requireClass",
        "combatOnly",
        "outOfCombatOnly",
        "requireBuff",
        "healthBelow",
        "inGroup",
        "inRaid",
        "hideWhileMounted",
        "hideWhileResting",
        "hideInVehicle",
        "onlyInInstance",
    }
    assertx.assertEqual(#ns.conditionChecks, #expected, "condition count changed")
    for i, name in ipairs(expected) do
        local got = ns.conditionChecks[i] and ns.conditionChecks[i].name
        assertx.assertEqual(got, name, string.format("conditionChecks[%d]", i))
    end
end

return M
