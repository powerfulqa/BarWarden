-- tests/test_help.lua
-- Structural invariants on the Help FAQ data (Options_Help.lua HELP_ENTRIES)
-- and its contracts with the rest of the addon:
--   * every content entry is well-formed and has a unique id;
--   * every [?] deep-link target id resolves to a content entry (catches a
--     [?] icon pointing at a renamed or deleted entry);
--   * every collapsible section has a matching collapse-state seed in
--     DB.lua's ns.DEFAULTS.global.helpCollapsed (catches section-key drift).

local assertx    = require("assert")
local load_addon = require("load_addon")

local M = {}

-- The id of the only section that ships expanded; everything else is seeded
-- collapsed in DB.lua.
local OPEN_SECTION = "gettingStarted"

-- Ids referenced by ns:CreateHelpIcon ([?]) calls across the option tabs.
-- Keep in sync with those call sites; the test fails if one stops resolving.
local DEEPLINK_IDS = {
    "create-group",
    "add-bar",
    "conditions-overview",
    "visuals-overview",
    "class-starters",
    "activity-overview",
}

local function fresh()
    local ns = {}
    load_addon.load("Utils.lua", "BarWarden", ns)
    load_addon.load("DB.lua", "BarWarden", ns)
    load_addon.load("Options.lua", "BarWarden", ns)
    load_addon.load("Options_Help.lua", "BarWarden", ns)
    return ns
end

-- Collect the content entries (those with an id) into id -> entry.
local function contentById(entries)
    local byId = {}
    for _, e in ipairs(entries) do
        if e.id then byId[e.id] = e end
    end
    return byId
end

function M.test_helpEntriesExposed()
    local ns = fresh()
    assertx.assertNotNil(ns.HELP_ENTRIES, "ns.HELP_ENTRIES not exposed")
    assertx.assertEqual(type(ns.HELP_ENTRIES), "table")
    assertx.assertTrue(#ns.HELP_ENTRIES > 0, "HELP_ENTRIES is empty")
end

function M.test_contentEntriesWellFormed()
    local ns = fresh()
    for i, e in ipairs(ns.HELP_ENTRIES) do
        if not e.section then
            for _, field in ipairs({ "id", "q", "a" }) do
                assertx.assertEqual(type(e[field]), "string",
                    "entry " .. i .. " field " .. field .. " is not a string")
                assertx.assertTrue(#e[field] > 0,
                    "entry " .. i .. " field " .. field .. " is empty")
            end
        end
    end
end

function M.test_idsUnique()
    local ns = fresh()
    local seen = {}
    for _, e in ipairs(ns.HELP_ENTRIES) do
        if e.id then
            assertx.assertNil(seen[e.id], "duplicate help entry id: " .. tostring(e.id))
            seen[e.id] = true
        end
    end
end

function M.test_sectionsHaveTitle()
    local ns = fresh()
    for i, e in ipairs(ns.HELP_ENTRIES) do
        if e.section then
            assertx.assertEqual(type(e.title), "string",
                "section " .. i .. " (" .. tostring(e.section) .. ") has no title")
            assertx.assertTrue(#e.title > 0, "section " .. tostring(e.section) .. " title is empty")
        end
    end
end

function M.test_everyContentEntryHasASection()
    -- A content entry before any section marker would render orphaned.
    local ns = fresh()
    local sawSection = false
    for _, e in ipairs(ns.HELP_ENTRIES) do
        if e.section then
            sawSection = true
        elseif e.id then
            assertx.assertTrue(sawSection,
                "content entry " .. e.id .. " appears before any section marker")
        end
    end
end

function M.test_deepLinkTargetsResolve()
    local ns = fresh()
    local byId = contentById(ns.HELP_ENTRIES)
    for _, id in ipairs(DEEPLINK_IDS) do
        assertx.assertNotNil(byId[id],
            "deep-link target id has no matching help entry: " .. id)
    end
end

function M.test_sectionKeysMatchCollapseSeed()
    local ns = fresh()
    local seed = ns.DEFAULTS and ns.DEFAULTS.global and ns.DEFAULTS.global.helpCollapsed
    assertx.assertNotNil(seed, "ns.DEFAULTS.global.helpCollapsed missing")

    -- Every section except the open one must have a collapse seed.
    local sectionKeys = {}
    for _, e in ipairs(ns.HELP_ENTRIES) do
        if e.section then
            sectionKeys[e.section] = true
            if e.section ~= OPEN_SECTION then
                assertx.assertTrue(seed[e.section] == true,
                    "section " .. e.section .. " has no collapse seed in DEFAULTS")
            end
        end
    end

    -- Every seed key must be a real section (catches a stale seed key).
    for key in pairs(seed) do
        assertx.assertTrue(sectionKeys[key] == true,
            "helpCollapsed seed key is not a real section: " .. key)
    end
end

return M
