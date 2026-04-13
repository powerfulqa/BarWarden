local addonName, ns = ...

-- ============================================================================
-- Conditions.lua - Condition evaluator for bar visibility
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Individual checks. Each returns true if the bar should stay visible; a
-- false return from any one fails the whole evaluation.
-- ----------------------------------------------------------------------------

local function CheckCombatOnly(conditions)
    if conditions.combatOnly then
        return UnitAffectingCombat("player")
    end
    return true
end

local function CheckOutOfCombatOnly(conditions)
    if conditions.outOfCombatOnly then
        return not UnitAffectingCombat("player")
    end
    return true
end

local function CheckRequireBuff(conditions)
    local buffName = conditions.requireBuff
    if not buffName then
        return true
    end
    -- Scan player buffs for matching name or spellID
    for i = 1, 40 do
        local name, _, _, _, _, _, _, _, _, _, spellId = UnitBuff("player", i)
        if not name then
            break
        end
        if name == buffName or (tonumber(buffName) and spellId == tonumber(buffName)) then
            return true
        end
    end
    return false
end

local function CheckHealthBelow(conditions)
    local threshold = conditions.healthBelow
    if not threshold then
        return true
    end
    local health = UnitHealth("player")
    local maxHealth = UnitHealthMax("player")
    if maxHealth == 0 then
        return true
    end
    local pct = (health / maxHealth) * 100
    return pct < threshold
end

local function CheckInGroup(conditions)
    if conditions.inGroup then
        return GetNumPartyMembers() > 0
    end
    return true
end

local function CheckInRaid(conditions)
    if conditions.inRaid then
        return GetNumRaidMembers() > 0
    end
    return true
end

-- Checks run in order; first failure wins. Order matches the original
-- hand-written sequence so short-circuit behaviour is preserved.
local CHECKS = {
    CheckCombatOnly,
    CheckOutOfCombatOnly,
    CheckRequireBuff,
    CheckHealthBelow,
    CheckInGroup,
    CheckInRaid,
}

function ns:EvaluateConditions(bar, conditions)
    if not conditions then return true end
    for _, check in ipairs(CHECKS) do
        if not check(conditions) then return false end
    end
    return true
end

-- hideWhenInactive and showEmpty are queried by the bar engine during
-- active/inactive transitions rather than inside EvaluateConditions.

function ns:ShouldHideWhenInactive(conditions)
    if not conditions then return false end
    return not not conditions.hideWhenInactive
end

function ns:ShouldShowEmpty(conditions)
    if not conditions then return true end
    return conditions.showEmpty ~= false
end
