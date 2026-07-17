-- tests/test_activity_tracker.lua
-- Covers the pure snapshot-diff logic of ActivityTracker.lua:
--   * a genuine new aura counts once
--   * an aura present continuously across a StartActivityTracking() (login /
--     reload / re-enable) is NOT re-counted as a fresh activation (the
--     first-scan baseline guard)
--   * an aura that drops after the baseline stops being counted correctly
--
-- Frame-bound machinery is out of scope; this is the diff engine only.

local assertx    = require("assert")
local load_addon = require("load_addon")
local mock       = require("mock_wow")

local M = {}

local function fresh()
    mock.reset()
    local ns = {}
    load_addon.load("Utils.lua", "BarWarden", ns)
    load_addon.load("ActivityTracker.lua", "BarWarden", ns)
    -- Minimal DB surfaces the recorder writes to.
    ns.db = { activity = {} }
    ns.activitySession = {}
    return ns
end

local function buff(name, spellId)
    return {
        name           = name,
        spellId        = spellId,
        icon           = "icon",
        count          = 0,
        duration       = 30,
        expirationTime = 30,
        caster         = "player",
    }
end

local function procs(ns, key)
    local p = ns.db.activity[key]
    return p and p.activations or 0
end

-- A buff that appears mid-session counts exactly once.
function M.test_buff_newActivationCountsOnce()
    local ns = fresh()
    ns:StartActivityTracking()

    -- First scan: nothing up yet, establishes the baseline.
    ns:ScanBuffActivity()

    -- Buff comes up, then two more scans while it stays up.
    mock.buffs.player[1] = buff("Slice and Dice", 6774)
    ns:ScanBuffActivity()
    ns:ScanBuffActivity()

    assertx.assertEqual(procs(ns, "Buff:6774"), 1)
end

-- The regression this fix targets: a buff already active when tracking
-- (re)starts - the case on every /reload or login with a self-buff up - must
-- NOT be counted as a fresh activation by the first scan.
function M.test_buff_activeAcrossReloadNotRecounted()
    local ns = fresh()

    -- Simulate a self-buff already running.
    mock.buffs.player[1] = buff("Blessing of Kings", 20217)

    -- Reload / re-enable: snapshots reset, then the periodic scan fires.
    ns:StartActivityTracking()
    ns:ScanBuffActivity()
    ns:ScanBuffActivity()

    -- It was already up, so it is not a new activation.
    assertx.assertEqual(procs(ns, "Buff:20217"), 0)
end

-- After the baseline, a real re-application still counts: buff drops, then
-- comes back.
function M.test_buff_reappliesAfterBaselineCounts()
    local ns = fresh()

    mock.buffs.player[1] = buff("Blessing of Kings", 20217)
    ns:StartActivityTracking()
    ns:ScanBuffActivity()          -- baseline: 0

    mock.buffs.player[1] = nil     -- drops
    ns:ScanBuffActivity()

    mock.buffs.player[1] = buff("Blessing of Kings", 20217)  -- recast
    ns:ScanBuffActivity()

    assertx.assertEqual(procs(ns, "Buff:20217"), 1)
end

return M
