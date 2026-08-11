-- tests/test_utils.lua
-- Covers Utils.lua: CopyTable, MergeDefaults, FormatUptime, Base64,
-- Serialize/Deserialize, ExportProfile/ImportProfile, callback bus,
-- GetVisual caching + InvalidateVisualCache.

local assertx    = require("assert")
local load_addon = require("load_addon")

local M = {}

local function fresh()
    local ns = {}
    load_addon.load("Utils.lua", "BarWarden", ns)
    return ns
end

-- --------------------------------------------------------------------------
-- CopyTable
-- --------------------------------------------------------------------------

function M.test_copyTable_deepIndependence()
    local ns = fresh()
    local src = { a = 1, b = { c = 2, d = { e = 3 } } }
    local cp = ns:CopyTable(src)
    assertx.assertDeepEqual(cp, src)
    cp.b.d.e = 99
    assertx.assertEqual(src.b.d.e, 3, "mutation of copy leaked into source")
end

function M.test_copyTable_passThroughNonTables()
    local ns = fresh()
    assertx.assertEqual(ns:CopyTable(5),    5)
    assertx.assertEqual(ns:CopyTable("x"),  "x")
    assertx.assertEqual(ns:CopyTable(true), true)
    assertx.assertNil(ns:CopyTable(nil))
end

-- --------------------------------------------------------------------------
-- MergeDefaults
-- --------------------------------------------------------------------------

function M.test_mergeDefaults_keepsExistingValues()
    local ns = fresh()
    local target   = { a = 1, nested = { x = "user" } }
    local defaults = { a = 99, b = 2, nested = { x = "default", y = "new" } }
    ns:MergeDefaults(target, defaults)
    assertx.assertEqual(target.a, 1,        "existing scalar preserved")
    assertx.assertEqual(target.b, 2,        "missing scalar filled")
    assertx.assertEqual(target.nested.x, "user", "nested existing preserved")
    assertx.assertEqual(target.nested.y, "new",  "nested missing filled")
end

function M.test_mergeDefaults_createsMissingSubtable()
    local ns = fresh()
    local target   = { a = 1 }
    local defaults = { a = 99, nested = { x = 1, y = 2 } }
    ns:MergeDefaults(target, defaults)
    assertx.assertDeepEqual(target.nested, { x = 1, y = 2 })
    -- The created subtable must be an independent copy, not a shared reference
    target.nested.x = 5
    assertx.assertEqual(defaults.nested.x, 1, "defaults mutated via shared reference")
end

function M.test_mergeDefaults_rejectsNonTableInputs()
    local ns = fresh()
    -- Should not raise and should not mutate anything
    ns:MergeDefaults(nil, { a = 1 })
    ns:MergeDefaults({}, nil)
end

-- --------------------------------------------------------------------------
-- FormatUptime
-- --------------------------------------------------------------------------

function M.test_formatUptime_boundaries()
    local ns = fresh()
    assertx.assertEqual(ns.FormatUptime(0),     "0s")
    assertx.assertEqual(ns.FormatUptime(-5),    "0s")
    assertx.assertEqual(ns.FormatUptime(nil),   "0s")
    assertx.assertEqual(ns.FormatUptime(12.5),  "12.5s")
    assertx.assertEqual(ns.FormatUptime(65),    "1m 5s")
    assertx.assertEqual(ns.FormatUptime(3700),  "1h 1m")
    assertx.assertEqual(ns.FormatUptime(86400), "1d 0h")   -- exactly 24h
    assertx.assertEqual(ns.FormatUptime(90000), "1d 1h")
    assertx.assertEqual(ns.FormatUptime(820380), "9d 11h") -- ~227h all-time
end

-- --------------------------------------------------------------------------
-- FormatSettingDuration
-- --------------------------------------------------------------------------

function M.test_formatSettingDuration_boundaries()
    local ns = fresh()
    assertx.assertEqual(ns.FormatSettingDuration(0),    "No limit")
    assertx.assertEqual(ns.FormatSettingDuration(nil),  "No limit")
    assertx.assertEqual(ns.FormatSettingDuration(-5),   "No limit")
    assertx.assertEqual(ns.FormatSettingDuration(1),    "1s")
    assertx.assertEqual(ns.FormatSettingDuration(45),   "45s")
    assertx.assertEqual(ns.FormatSettingDuration(59),   "59s")
    assertx.assertEqual(ns.FormatSettingDuration(60),   "1 min")
    assertx.assertEqual(ns.FormatSettingDuration(300),  "5 min")
    assertx.assertEqual(ns.FormatSettingDuration(330),  "5 min 30s")
    assertx.assertEqual(ns.FormatSettingDuration(1800), "30 min") -- Skip Longer Than's slider max
end

-- --------------------------------------------------------------------------
-- Base64
-- --------------------------------------------------------------------------

function M.test_base64_roundtripMod3()
    local ns = fresh()
    -- Round-trip strings at every length class mod 3 so each padding case
    -- (no pad, single pad, double pad) is exercised.
    for _, s in ipairs({ "", "a", "ab", "abc", "abcd", "abcde" }) do
        local encoded = ns.Base64Encode(s)
        local decoded = ns.Base64Decode(encoded)
        assertx.assertEqual(decoded, s, "roundtrip failed for length " .. #s)
    end
end

function M.test_base64_roundtripSpecialBytes()
    local ns = fresh()
    local original = "line1\nline2\rtab\there\"quote\"and\\slash"
    local decoded = ns.Base64Decode(ns.Base64Encode(original))
    assertx.assertEqual(decoded, original)
end

-- --------------------------------------------------------------------------
-- Serialize / Deserialize
-- --------------------------------------------------------------------------

function M.test_serialize_roundtripMixed()
    local ns = fresh()
    local original = {
        name   = "Test",
        count  = 42,
        flag   = true,
        nested = { a = 1, b = "quoted \"text\" \nnewline" },
        array  = { "x", "y", "z" },
    }
    local roundtrip = ns:Deserialize(ns:Serialize(original))
    assertx.assertDeepEqual(roundtrip, original)
end

function M.test_serialize_preservesBooleanFalse()
    -- Regression: naive serializers treat `false` as nil and drop the key.
    local ns = fresh()
    local original = { flag = false, other = true }
    local roundtrip = ns:Deserialize(ns:Serialize(original))
    assertx.assertEqual(roundtrip.flag,  false)
    assertx.assertEqual(roundtrip.other, true)
end

function M.test_deserialize_rejectsGarbage()
    local ns = fresh()
    assertx.assertNil(ns:Deserialize(nil))
    assertx.assertNil(ns:Deserialize(""))
end

-- --------------------------------------------------------------------------
-- ExportProfile / ImportProfile
-- --------------------------------------------------------------------------

function M.test_exportImport_roundtrip()
    local ns = fresh()
    local profile = {
        visual = { texture = "Flat", barHeight = 20, defaultColor = { r = 0.2, g = 0.6, b = 1.0 } },
        frames = { { name = "Group 1", bars = { { trackMode = "Cooldown", spellName = "Evasion" } } } },
    }
    local exported = ns:ExportProfile(profile)
    assertx.assertNotNil(exported)
    assertx.assertTrue(exported:sub(1, 13) == "BarWarden:v1:", "export string missing prefix")
    local imported = ns:ImportProfile(exported)
    assertx.assertDeepEqual(imported, profile)
end

function M.test_exportProfile_appendsFingerprintSuffix()
    local ns = fresh()
    local exported = ns:ExportProfile({ visual = {}, frames = {} })
    assertx.assertNotNil(exported)
    assertx.assertTrue(exported:match(";fp=[0-9a-f]+$") ~= nil,
        "export must end with ;fp=<6-hex-chars> fingerprint suffix")
end

function M.test_importProfile_acceptsLegacyStringWithoutFingerprint()
    -- Backward compat: profile strings exported by versions before fingerprinting
    -- (or hand-typed by users) must still import without complaint.
    local ns = fresh()
    local profile = { visual = { texture = "Flat" }, frames = {} }
    local exported = ns:ExportProfile(profile)
    -- Strip the fingerprint suffix to simulate a legacy string
    local legacy = exported:gsub(";fp=[0-9a-f]+$", "")
    assertx.assertTrue(legacy ~= exported, "fingerprint suffix should have been stripped")
    local imported = ns:ImportProfile(legacy)
    assertx.assertDeepEqual(imported, profile)
end

function M.test_importProfile_rejectsBadInput()
    local ns = fresh()
    assertx.assertNil(ns:ImportProfile(nil))
    assertx.assertNil(ns:ImportProfile(""))
    assertx.assertNil(ns:ImportProfile("not-barwarden"))
    assertx.assertNil(ns:ImportProfile("BarWarden:v99:anything"),
        "future-version strings must be rejected, not silently decoded")
end

-- --------------------------------------------------------------------------
-- Fingerprint
-- --------------------------------------------------------------------------

function M.test_fingerprint_isDeterministic()
    local ns = fresh()
    local a = ns:Fingerprint("hello world")
    local b = ns:Fingerprint("hello world")
    assertx.assertEqual(a, b, "same input must produce same fingerprint")
end

function M.test_fingerprint_returns6HexChars()
    local ns = fresh()
    local fp = ns:Fingerprint("anything")
    assertx.assertTrue(fp:match("^[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]$") ~= nil,
        "fingerprint must be exactly 6 lowercase hex chars; got: " .. tostring(fp))
end

function M.test_fingerprint_differentInputsDiffer()
    local ns = fresh()
    -- Sanity: small input perturbations should change the hash. Not a
    -- crypto-strength check, just confirms the salt-mix is wired up.
    local a = ns:Fingerprint("BarWarden@1.0.0")
    local b = ns:Fingerprint("BarWarden@1.0.1")
    assertx.assertTrue(a ~= b, "neighbouring versions must hash differently")
end

-- --------------------------------------------------------------------------
-- Callback bus
-- --------------------------------------------------------------------------

function M.test_callbacks_dispatchInRegistrationOrder()
    local ns = fresh()
    local calls = {}
    ns:RegisterCallback("evt", function(arg) calls[#calls + 1] = "A:" .. arg end)
    ns:RegisterCallback("evt", function(arg) calls[#calls + 1] = "B:" .. arg end)
    ns:FireCallback("evt", "hi")
    assertx.assertDeepEqual(calls, { "A:hi", "B:hi" })
end

function M.test_callbacks_fireWithNoSubscribersIsNoop()
    local ns = fresh()
    -- Must not raise
    ns:FireCallback("never-registered", 1, 2, 3)
end

-- --------------------------------------------------------------------------
-- GetVisual cache
-- --------------------------------------------------------------------------

function M.test_getVisual_fallsBackToDefaultsBeforeDbLoads()
    local ns = fresh()
    ns.DEFAULTS = { visual = { marker = "defaults" } }
    _G.BarWardenDB = nil
    assertx.assertEqual(ns:GetVisual().marker, "defaults")
end

function M.test_getVisual_cachesLiveTable()
    local ns = fresh()
    ns.DEFAULTS = { visual = { marker = "defaults" } }
    _G.BarWardenDB = { visual = { marker = "live", value = 1 } }
    local v = ns:GetVisual()
    assertx.assertEqual(v.marker, "live")
    -- In-place mutation of the live table is reflected without invalidation
    _G.BarWardenDB.visual.value = 2
    assertx.assertEqual(ns:GetVisual().value, 2)
    _G.BarWardenDB = nil
end

function M.test_getVisual_invalidateReleasesStalePointer()
    local ns = fresh()
    ns.DEFAULTS = { visual = { marker = "defaults" } }
    _G.BarWardenDB = { visual = { marker = "first" } }
    assertx.assertEqual(ns:GetVisual().marker, "first")

    -- Simulate profile load replacing the visual table wholesale
    _G.BarWardenDB.visual = { marker = "second" }
    -- Without invalidation the cache still points at the first table
    assertx.assertEqual(ns:GetVisual().marker, "first", "cache held stale before invalidation")
    ns:InvalidateVisualCache()
    assertx.assertEqual(ns:GetVisual().marker, "second")
    _G.BarWardenDB = nil
end

return M
