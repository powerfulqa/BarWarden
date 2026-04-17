-- tests/test_class_presets.lua
-- Structural smoke test for ns.ClassPresets. The goal isn't to validate
-- the curated spell list (that needs a real client), just to catch the
-- typos that break the loader: missing classes, a `groups` table without
-- `bars`, a bar without a `trackMode`, a spec entry with the wrong shape.

local assertx    = require("assert")
local load_addon = require("load_addon")

local M = {}

local WOTLK_CLASSES = {
    "DEATHKNIGHT", "DRUID", "HUNTER", "MAGE", "PALADIN",
    "PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR",
}

local VALID_TRACK_MODES = {
    ["Cooldown"]     = true,
    ["Buff"]         = true,
    ["Debuff"]       = true,
    ["Proc"]         = true,
    ["Item"]         = true,
    ["Enchant"]      = true,
    ["Enchant MH"]   = true,
    ["Enchant OH"]   = true,
    ["Totem"]        = true,
    ["Combo Points"] = true,
    ["Runic Power"]  = true,
    ["Soul Shards"]  = true,
    ["Runes"]        = true,
}

local function fresh()
    local ns = {}
    load_addon.load("Utils.lua",        "BarWarden", ns)
    load_addon.load("ClassPresets.lua", "BarWarden", ns)
    return ns
end

local function validateGroups(groups, context)
    assertx.assertEqual(type(groups), "table", context .. ": groups is not a table")
    assertx.assertTrue(#groups > 0,           context .. ": groups is empty")
    for i, group in ipairs(groups) do
        local gctx = context .. " group[" .. i .. "]"
        assertx.assertEqual(type(group.bars), "table", gctx .. ": bars is not a table")
        assertx.assertTrue(#group.bars > 0,            gctx .. ": bars is empty")
        for j, bar in ipairs(group.bars) do
            local bctx = gctx .. " bar[" .. j .. "]"
            assertx.assertEqual(type(bar.trackMode), "string", bctx .. ": trackMode missing")
            assertx.assertTrue(VALID_TRACK_MODES[bar.trackMode],
                bctx .. ": unknown trackMode " .. tostring(bar.trackMode))
        end
    end
end

function M.test_allWotlkClassesRegistered()
    local ns = fresh()
    for _, class in ipairs(WOTLK_CLASSES) do
        assertx.assertNotNil(ns.ClassPresets[class],
            "ClassPresets missing entry for " .. class)
    end
end

function M.test_classGroupsAreWellFormed()
    local ns = fresh()
    for _, class in ipairs(WOTLK_CLASSES) do
        local preset = ns.ClassPresets[class]
        validateGroups(preset.groups, class)
    end
end

function M.test_classSpecsAreWellFormed()
    local ns = fresh()
    for _, class in ipairs(WOTLK_CLASSES) do
        local preset = ns.ClassPresets[class]
        if preset.specs then
            for idx, spec in pairs(preset.specs) do
                assertx.assertEqual(type(spec.name), "string",
                    class .. " spec[" .. tostring(idx) .. "]: name missing")
                validateGroups(spec.groups, class .. " spec " .. spec.name)
            end
        end
    end
end

function M.test_descriptionsAreStrings()
    local ns = fresh()
    for _, class in ipairs(WOTLK_CLASSES) do
        local preset = ns.ClassPresets[class]
        assertx.assertEqual(type(preset.description), "string",
            class .. ": description missing or not a string")
        assertx.assertTrue(#preset.description > 0,
            class .. ": description is empty")
    end
end

return M
