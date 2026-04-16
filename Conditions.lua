local addonName, ns = ...

-- ============================================================================
-- Conditions.lua: extensible visibility-condition registry + evaluator.
--
-- Use ns:RegisterCondition(name, fn) to add new condition checks. The
-- evaluator iterates them in registration order; the first one to return
-- false hides the bar. Each check function receives the bar's `conditions`
-- table and returns true (keep visible) or false (hide).
--
-- Built-in conditions register themselves at module load order. Future
-- conditions (smart-visibility, spec check, etc.) plug in by calling
-- RegisterCondition without editing core logic.
-- ============================================================================

-- Ordered list of { name, fn } entries. Registration order matters because
-- it defines the short-circuit order of the evaluator.
local registered = {}

function ns:RegisterCondition(name, fn)
    registered[#registered + 1] = { name = name, fn = fn }
end

-- Exposed for introspection (e.g. the bug-report dumper) and tests.
ns.conditionChecks = registered

function ns:EvaluateConditions(bar, conditions)
    if not conditions then return true end
    for _, entry in ipairs(registered) do
        if not entry.fn(conditions) then return false end
    end
    return true
end

-- hideWhenInactive and showEmpty are queried by the bar engine during
-- active/inactive transitions rather than inside EvaluateConditions, so they
-- stay as standalone queries rather than going through the registry.

function ns:ShouldHideWhenInactive(conditions)
    if not conditions then return false end
    return not not conditions.hideWhenInactive
end

function ns:ShouldShowEmpty(conditions)
    if not conditions then return true end
    return conditions.showEmpty ~= false
end

-- ----------------------------------------------------------------------------
-- Built-in conditions.
--
-- requireClass goes first. Class never changes during a session so the check
-- is effectively constant; putting it first means bars that don't belong to
-- the player's class bail out before any of the more expensive checks run.
-- ----------------------------------------------------------------------------

ns:RegisterCondition("requireClass", function(conditions)
    local required = conditions.requireClass
    if not required or required == "" then return true end
    local _, playerClass = UnitClass("player")
    return playerClass == required
end)

ns:RegisterCondition("combatOnly", function(conditions)
    if conditions.combatOnly then
        return UnitAffectingCombat("player")
    end
    return true
end)

ns:RegisterCondition("outOfCombatOnly", function(conditions)
    if conditions.outOfCombatOnly then
        return not UnitAffectingCombat("player")
    end
    return true
end)

ns:RegisterCondition("requireBuff", function(conditions)
    local buffName = conditions.requireBuff
    if not buffName then return true end
    for i = 1, 40 do
        local name, _, _, _, _, _, _, _, _, _, spellId = UnitBuff("player", i)
        if not name then break end
        if name == buffName or (tonumber(buffName) and spellId == tonumber(buffName)) then
            return true
        end
    end
    return false
end)

ns:RegisterCondition("healthBelow", function(conditions)
    local threshold = conditions.healthBelow
    if not threshold then return true end
    local health = UnitHealth("player")
    local maxHealth = UnitHealthMax("player")
    if maxHealth == 0 then return true end
    local pct = (health / maxHealth) * 100
    return pct < threshold
end)

ns:RegisterCondition("inGroup", function(conditions)
    if conditions.inGroup then
        return GetNumPartyMembers() > 0
    end
    return true
end)

ns:RegisterCondition("inRaid", function(conditions)
    if conditions.inRaid then
        return GetNumRaidMembers() > 0
    end
    return true
end)

-- Smart-visibility conditions (player state). All four APIs are confirmed
-- present on 3.3.5a (used by WeakAuras, DiminishingReturns, Forte, etc.).
-- The 0.25 s scan loop evaluates these cheaply; no dedicated events needed.

ns:RegisterCondition("hideWhileMounted", function(conditions)
    if conditions.hideWhileMounted then
        return not IsMounted()
    end
    return true
end)

ns:RegisterCondition("hideWhileResting", function(conditions)
    if conditions.hideWhileResting then
        return not IsResting()
    end
    return true
end)

ns:RegisterCondition("hideInVehicle", function(conditions)
    if conditions.hideInVehicle then
        return not UnitInVehicle("player")
    end
    return true
end)

ns:RegisterCondition("onlyInInstance", function(conditions)
    if conditions.onlyInInstance then
        local inInstance = IsInInstance()
        return inInstance
    end
    return true
end)
