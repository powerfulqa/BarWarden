-- tests/test_bug_report.lua
-- Covers ns:GenerateBugReport (BugReport.lua), specifically the per-group
-- line: an auto-tracking group must surface its feed and governing
-- settings, an ordinary hand-built group must not gain any of that text.
--
-- ns:ShowBugReport (the frame half) needs CreateFrame and is out of scope
-- here, per existing policy for frame-driving code; GenerateBugReport was
-- exposed on ns specifically so this pure-string half is reachable without
-- it. See load_addon.lua's file-scope-only loading model.

local assertx    = require("assert")
local load_addon = require("load_addon")
local mock       = require("mock_wow")

local M = {}

local function fresh()
    mock.reset()
    local ns = {}
    load_addon.load("Utils.lua",     "BarWarden", ns)
    load_addon.load("BugReport.lua", "BarWarden", ns)
    return ns
end

-- Minimal ns.db shell: only what GenerateBugReport actually reads. `frames`
-- is the list under test; the rest is left absent so the guarded sections
-- (Settings / Visual Config / Activity Statistics) fall back to their
-- "nothing loaded" branches without erroring.
local function withFrames(frames)
    return { frames = frames }
end

function M.test_ordinaryGroupHasNoAutoTrackOrBannedLines()
    local ns = fresh()
    ns.db = withFrames({
        { name = "Cooldowns", width = 200, columns = 1, scale = 1.0, enabled = true },
    })

    local report = ns:GenerateBugReport()

    assertx.assertTrue(report:find("Group 1: \"Cooldowns\"") ~= nil, "group line missing")
    assertx.assertTrue(report:find("autoTrack:") == nil, "ordinary group must not print an autoTrack line")
    assertx.assertTrue(report:find("autoBanned:") == nil, "ordinary group with no bans must not print an autoBanned line")
end

function M.test_autoTrackGroupPrintsFeedAndGoverningSettings()
    local ns = fresh()
    ns.db = withFrames({
        {
            name = "Buffs",
            width = 200,
            columns = 1,
            scale = 1.0,
            enabled = true,
            autoTrack = "playerBuffs",
            autoMaxBars = 15,
            autoMaxDuration = 600,
            autoOnlyMine = true,
            autoSkipTracked = false,
            autoStableOrder = true,
            autoIncludePermanent = false,
        },
    })

    local report = ns:GenerateBugReport()
    local autoLine = report:match("autoTrack:[^\n]*")

    assertx.assertNotNil(autoLine, "auto-tracking group must print an autoTrack line")
    assertx.assertTrue(autoLine:find("feed=playerBuffs", 1, true) ~= nil, "feed value missing")
    assertx.assertTrue(autoLine:find("maxBars=15", 1, true) ~= nil, "maxBars value missing")
    assertx.assertTrue(autoLine:find("maxDuration=600", 1, true) ~= nil, "maxDuration value missing")
    assertx.assertTrue(autoLine:find("onlyMine=true", 1, true) ~= nil, "onlyMine value missing")
    assertx.assertTrue(autoLine:find("skipTracked=false", 1, true) ~= nil, "skipTracked value missing")
    assertx.assertTrue(autoLine:find("stableOrder=true", 1, true) ~= nil, "stableOrder value missing")
    assertx.assertTrue(autoLine:find("includePermanent=false", 1, true) ~= nil, "includePermanent value missing")
end

function M.test_autoBannedCountPrintedOnlyWhenNonEmpty()
    local ns = fresh()
    ns.db = withFrames({
        {
            name = "Buffs",
            autoTrack = "playerBuffs",
            autoBanned = {
                ["blade flurry"] = { name = "Blade Flurry", id = 13877 },
                ["slice and dice"] = { name = "Slice and Dice", id = 5171 },
            },
        },
    })

    local report = ns:GenerateBugReport()
    assertx.assertTrue(report:find("autoBanned: 2 hidden", 1, true) ~= nil, "expected a count of 2 banned spells")
end

function M.test_emptyAutoBannedTableIsTreatedAsNone()
    local ns = fresh()
    -- Options_Bars.lua's own invariant is that an emptied autoBanned is set
    -- back to nil (see its "if not next(g.autoBanned) then g.autoBanned =
    -- nil end"), but the report must not error even if a stray empty table
    -- shows up some other way.
    ns.db = withFrames({
        { name = "Buffs", autoTrack = "playerBuffs", autoBanned = {} },
    })

    local report = ns:GenerateBugReport()
    assertx.assertTrue(report:find("autoBanned:") == nil, "an empty autoBanned table must not print a count")
end

function M.test_opacityAlwaysPrintedWithExplicitZeroUnmistakable()
    local ns = fresh()
    ns.db = withFrames({
        { name = "Default", width = 200 },                        -- bgAlpha/borderAlpha unset
        { name = "Hidden",  width = 200, bgAlpha = 0, borderAlpha = 0 }, -- deliberately invisible
    })

    local report = ns:GenerateBugReport()
    assertx.assertTrue(report:find("bgAlpha=0.60, borderAlpha=0.80", 1, true) ~= nil,
        "unset opacity must report the live default (0.6 / 0.8)")
    assertx.assertTrue(report:find("bgAlpha=0.00, borderAlpha=0.00", 1, true) ~= nil,
        "an explicit 0 must read as 0.00, not fall back to the default")
end

function M.test_overridesLineFoldsInIconOnlyAndBarStyle()
    local ns = fresh()
    ns.db = withFrames({
        { name = "Icons", width = 200, iconOnly = true, barStyle = "SWITCH" },
    })

    local report = ns:GenerateBugReport()
    local overridesLine = report:match("overrides:[^\n]*")

    assertx.assertNotNil(overridesLine, "iconOnly/barStyle group must print an overrides line")
    assertx.assertTrue(overridesLine:find("iconOnly", 1, true) ~= nil, "iconOnly missing from overrides")
    assertx.assertTrue(overridesLine:find("barStyle=SWITCH", 1, true) ~= nil, "barStyle missing from overrides")
end

return M
