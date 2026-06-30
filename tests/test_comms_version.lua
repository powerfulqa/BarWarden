-- tests/test_comms_version.lua
-- Locks the version-gossip logic and its 3.3.5a safety.
--   * parseVersion encodes numerically (so 1.10.0 ranks ABOVE 1.9.0, the bug a
--     plain string compare would hit).
--   * Comms.lua stays 3.3.5a-safe: no RegisterAddonMessagePrefix (4.0+), no
--     GROUP_ROSTER_UPDATE (Cataclysm+), and the versionAlerts opt-out gate is
--     present.

local assertx = require("assert")
local load_addon = require("load_addon")

local M = {}

-- Comms.lua creates a frame and registers a StaticPopup at load. mock_wow does
-- not stub CreateFrame (the other test files create no frames), so stub the
-- few globals Comms touches at load time before loading it.
local function loadComms()
    _G.CreateFrame = _G.CreateFrame or function()
        return { RegisterEvent = function() end, SetScript = function() end }
    end
    _G.StaticPopupDialogs = _G.StaticPopupDialogs or {}
    _G.CLOSE = _G.CLOSE or "Close"
    local ns = {}
    load_addon.load("Comms.lua", "BarWarden", ns)
    return ns
end

local function commsSource()
    local f = io.open("Comms.lua", "r")
    assertx.assertNotNil(f, "Comms.lua not found (run tests from the repo root)")
    local s = f:read("*a")
    f:close()
    return s
end

-- Strip line comments so the 3.3.5a-safety scan checks actual code, not the
-- header comment that names the forbidden APIs to explain why they are avoided.
local function codeOnly(src)
    local out = {}
    for line in (src .. "\n"):gmatch("(.-)\n") do
        out[#out + 1] = line:gsub("%-%-.*$", "")
    end
    return table.concat(out, "\n")
end

function M.test_parseVersion_numericEncoding()
    local p = loadComms().Comms.parseVersion
    assertx.assertEqual(p("v1.10.0"), 1 * 1000000 + 10 * 1000 + 0)
    assertx.assertEqual(p("1.9.0"), 1 * 1000000 + 9 * 1000 + 0)
    assertx.assertEqual(p("v1.11.2"), 1011002)
    -- The whole point: 1.10.0 must rank ABOVE 1.9.0 (a string compare gets this
    -- wrong because "1" < "9" lexically at the minor position).
    assertx.assertTrue(p("1.10.0") > p("1.9.0"), "1.10.0 must encode higher than 1.9.0")
end

function M.test_parseVersion_rejectsMalformed()
    local p = loadComms().Comms.parseVersion
    assertx.assertNil(p("garbage"))
    assertx.assertNil(p("1.2"))        -- needs all three components
    assertx.assertNil(p(nil))
    assertx.assertNil(p("1.1000.0"))   -- a component >= 1000 is rejected
end

function M.test_3355aSafe()
    local code = codeOnly(commsSource())
    assertx.assertNil(code:find("RegisterAddonMessagePrefix", 1, true),
        "Comms.lua uses RegisterAddonMessagePrefix (4.0+, absent on 3.3.5a)")
    assertx.assertNil(code:find("GROUP_ROSTER_UPDATE", 1, true),
        "Comms.lua references GROUP_ROSTER_UPDATE (Cataclysm+); use PARTY_MEMBERS_CHANGED / RAID_ROSTER_UPDATE")
end

function M.test_versionAlertsGatePresent()
    assertx.assertNotNil(commsSource():find("versionAlerts", 1, true),
        "Comms.lua must gate the nudge on the versionAlerts setting")
end

return M
