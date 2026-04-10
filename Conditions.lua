local addonName, ns = ...

-- ============================================================================
-- Conditions.lua - Condition evaluator for bar visibility
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Individual Condition Checks
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

-- ----------------------------------------------------------------------------
-- Main Evaluator
-- ----------------------------------------------------------------------------

--- Evaluate all visibility conditions for a bar.
-- @param bar table - The bar configuration table
-- @param conditions table - The conditions sub-table from bar config
-- @return boolean - true if the bar should be visible
function ns:EvaluateConditions(bar, conditions)
    if not conditions then
        return true
    end

    if not CheckCombatOnly(conditions) then
        return false
    end

    if not CheckOutOfCombatOnly(conditions) then
        return false
    end

    if not CheckRequireBuff(conditions) then
        return false
    end

    if not CheckHealthBelow(conditions) then
        return false
    end

    if not CheckInGroup(conditions) then
        return false
    end

    if not CheckInRaid(conditions) then
        return false
    end

    -- hideWhenInactive and showEmpty are handled by the bar engine
    -- during active/inactive state transitions, not here.
    -- We expose helpers for the engine to query them.

    return true
end

--- Check if a bar should be hidden when it has no active tracker data.
-- @param conditions table - The conditions sub-table
-- @return boolean - true if the bar should hide when inactive
function ns:ShouldHideWhenInactive(conditions)
    if not conditions then return false end
    return not not conditions.hideWhenInactive
end

--- Check if a bar should show an empty bar when inactive.
-- @param conditions table - The conditions sub-table
-- @return boolean - true if an empty bar should be shown
function ns:ShouldShowEmpty(conditions)
    if not conditions then return true end
    return conditions.showEmpty ~= false
end
