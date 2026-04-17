-- tests/test_aura_groups.lua
-- Structural invariants on ns.AuraGroups. Catches typos (string where a
-- number was meant) and accidental duplicates across groups that would
-- confuse `@GroupA, @GroupB`-style compositions at match time.

local assertx    = require("assert")
local load_addon = require("load_addon")

local M = {}

local function fresh()
    local ns = {}
    load_addon.load("AuraGroups.lua", "BarWarden", ns)
    return ns
end

function M.test_groupsTableExists()
    local ns = fresh()
    assertx.assertNotNil(ns.AuraGroups)
    assertx.assertEqual(type(ns.AuraGroups), "table")
end

function M.test_allGroupsAreNonEmptyArraysOfNumbers()
    local ns = fresh()
    for name, ids in pairs(ns.AuraGroups) do
        assertx.assertEqual(type(ids), "table", "group " .. name .. " is not a table")
        assertx.assertTrue(#ids > 0, "group " .. name .. " is empty")
        for i, id in ipairs(ids) do
            assertx.assertEqual(type(id), "number",
                "group " .. name .. " index " .. i .. " is " .. type(id) .. ", expected number")
        end
    end
end

function M.test_noDuplicateIdsWithinAGroup()
    local ns = fresh()
    for name, ids in pairs(ns.AuraGroups) do
        local seen = {}
        for _, id in ipairs(ids) do
            assertx.assertNil(seen[id],
                "duplicate id " .. tostring(id) .. " in group " .. name)
            seen[id] = true
        end
    end
end

function M.test_coreGroupsPresent()
    -- Smoke test: the groups referenced in the starter presets and docs
    -- must exist. If a refactor renames one, the presets break silently.
    local ns = fresh()
    for _, required in ipairs({ "Stunned", "Silenced", "Bleeding" }) do
        assertx.assertNotNil(ns.AuraGroups[required],
            "core aura group missing: " .. required)
    end
end

return M
