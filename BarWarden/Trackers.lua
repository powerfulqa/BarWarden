local addonName, ns = ...

-- ============================================================================
-- Trackers.lua - Tracking mode implementations (Cooldown, Buff, Debuff, Proc,
-- Item, Custom). Each returns (isActive, value, maxValue, icon, name, stacks).
-- ============================================================================

local GCD_THRESHOLD = 1.5

-- ----------------------------------------------------------------------------
-- Field normalization helpers
-- Options_Bars.lua stores user-created bars with fields: spellName, spellId,
-- target. The original schema used: spell, unit. Support both so bars created
-- via the UI and bars defined directly in DB both work.
-- ----------------------------------------------------------------------------
local function getSpell(barConfig)
    if barConfig.spell and barConfig.spell ~= "" then
        return barConfig.spell
    end
    if barConfig.spellId then
        return tostring(barConfig.spellId)
    end
    if barConfig.spellName and barConfig.spellName ~= "" then
        return barConfig.spellName
    end
    return nil
end

local function getUnit(barConfig, default)
    return barConfig.unit or barConfig.target or default
end

-- ----------------------------------------------------------------------------
-- Cooldown Tracker
-- ----------------------------------------------------------------------------

local function CheckCooldown(barConfig)
    local spell = getSpell(barConfig)
    if not spell then
        return false, 0, 0, nil, nil, 0
    end

    -- Resolve spell: prefer spellID if numeric
    local spellID = tonumber(spell)
    local spellName, _, spellIcon

    if spellID then
        spellName, _, spellIcon = GetSpellInfo(spellID)
    else
        spellName, _, spellIcon = GetSpellInfo(spell)
    end

    if not spellName then
        return false, 0, 0, nil, spell, 0
    end

    local start, duration, enabled = GetSpellCooldown(spellID or spellName)

    if not start or enabled ~= 1 then
        return false, 0, 0, spellIcon, spellName, 0
    end

    -- Filter GCD: ignore cooldowns with duration <= 1.5s
    if duration <= GCD_THRESHOLD then
        return false, 0, 0, spellIcon, spellName, 0
    end

    local now = GetTime()
    local remaining = (start + duration) - now

    if remaining <= 0 then
        return false, 0, 0, spellIcon, spellName, 0
    end

    return true, remaining, duration, spellIcon, spellName, 0
end

-- ----------------------------------------------------------------------------
-- Buff Tracker
-- ----------------------------------------------------------------------------

local function CheckBuff(barConfig)
    local spell = getSpell(barConfig)
    local unit = getUnit(barConfig, "player")
    if not spell then
        return false, 0, 0, nil, nil, 0
    end

    local target = tonumber(spell)

    for i = 1, 40 do
        local name, _, icon, count, _, duration, expirationTime, _, _, _, spellId = UnitBuff(unit, i)
        if not name then
            break
        end

        local match = false
        if target then
            match = (spellId == target)
        else
            match = (name == spell)
        end

        if match then
            local remaining = 0
            local maxVal = 0
            if duration and duration > 0 and expirationTime then
                remaining = expirationTime - GetTime()
                maxVal = duration
            end
            return true, remaining, maxVal, icon, name, count or 0
        end
    end

    return false, 0, 0, nil, spell, 0
end

-- ----------------------------------------------------------------------------
-- Debuff Tracker
-- ----------------------------------------------------------------------------

local function CheckDebuff(barConfig)
    local spell = getSpell(barConfig)
    local unit = getUnit(barConfig, "target")
    if not spell then
        return false, 0, 0, nil, nil, 0
    end

    local target = tonumber(spell)

    for i = 1, 40 do
        local name, _, icon, count, _, duration, expirationTime, caster, _, _, spellId = UnitDebuff(unit, i)
        if not name then
            break
        end

        local match = false
        if target then
            match = (spellId == target)
        else
            match = (name == spell)
        end

        -- Only track debuffs cast by the player (onlyMine default true)
        if match then
            local onlyMine = barConfig.onlyMine
            if onlyMine == nil then
                onlyMine = true
            end
            if onlyMine and caster ~= "player" then
                -- Skip this match, keep scanning
            else
                local remaining = 0
                local maxVal = 0
                if duration and duration > 0 and expirationTime then
                    remaining = expirationTime - GetTime()
                    maxVal = duration
                end
                return true, remaining, maxVal, icon, name, count or 0
            end
        end
    end

    return false, 0, 0, nil, spell, 0
end

-- ----------------------------------------------------------------------------
-- Proc Tracker (short-duration player buffs, e.g. Art of War, Missile Barrage)
-- ----------------------------------------------------------------------------

local function CheckProc(barConfig)
    local spell = getSpell(barConfig)
    if not spell then
        return false, 0, 0, nil, nil, 0
    end

    local target = tonumber(spell)

    for i = 1, 40 do
        local name, _, icon, count, _, duration, expirationTime, _, _, _, spellId = UnitBuff("player", i)
        if not name then
            break
        end

        local match = false
        if target then
            match = (spellId == target)
        else
            match = (name == spell)
        end

        if match then
            local remaining = 0
            local maxVal = 0
            if duration and duration > 0 and expirationTime then
                remaining = expirationTime - GetTime()
                maxVal = duration
            end
            return true, remaining, maxVal, icon, name, count or 0
        end
    end

    return false, 0, 0, nil, spell, 0
end

-- ----------------------------------------------------------------------------
-- Item Tracker (item cooldowns: equipped, bag, inventory)
-- ----------------------------------------------------------------------------

local function CheckItem(barConfig)
    local itemRef = getSpell(barConfig)  -- reuse spell field for item ID/name
    if not itemRef then
        return false, 0, 0, nil, nil, 0
    end

    local itemID = tonumber(itemRef)
    local itemName, itemIcon

    if itemID then
        -- GetItemInfo may return nil if item not in cache
        itemName = GetItemInfo(itemID)
        -- GetItemIcon is more reliable for icons
        itemIcon = GetItemIcon(itemID)
    else
        itemName = itemRef
        itemIcon = GetItemIcon(itemRef)
    end

    -- Use itemRef as display name if GetItemInfo returned nil
    local displayName = itemName or itemRef

    -- Try GetItemCooldown (works for equipped/inventory items)
    local start, duration, enabled
    if itemID then
        start, duration, enabled = GetItemCooldown(itemID)
    else
        start, duration, enabled = GetItemCooldown(itemRef)
    end

    if start and duration and duration > 0 and enabled == 1 then
        local now = GetTime()
        local remaining = (start + duration) - now
        if remaining > 0 then
            return true, remaining, duration, itemIcon, displayName, 0
        end
    end

    return false, 0, 0, itemIcon, displayName, 0
end

-- ----------------------------------------------------------------------------
-- Custom Tracker (user-defined condition expression)
-- ----------------------------------------------------------------------------

local function CheckCustom(barConfig)
    local expression = barConfig.customExpression
    if not expression or expression == "" then
        return false, 0, 0, nil, barConfig.spell or "Custom", 0
    end

    -- Evaluate the custom expression in a safe environment
    local func, err = loadstring("return " .. expression)
    if not func then
        return false, 0, 0, nil, barConfig.spell or "Custom", 0
    end

    -- Sandbox: give access to common WoW API functions
    local env = setmetatable({
        UnitBuff = UnitBuff,
        UnitDebuff = UnitDebuff,
        UnitHealth = UnitHealth,
        UnitHealthMax = UnitHealthMax,
        UnitPower = UnitPower,
        UnitPowerMax = UnitPowerMax,
        UnitAffectingCombat = UnitAffectingCombat,
        UnitExists = UnitExists,
        GetSpellCooldown = GetSpellCooldown,
        GetSpellInfo = GetSpellInfo,
        GetTime = GetTime,
        GetItemCooldown = GetItemCooldown,
        GetItemInfo = GetItemInfo,
        GetComboPoints = GetComboPoints,
        UnitMana = UnitMana,
        UnitManaMax = UnitManaMax,
        pairs = pairs,
        ipairs = ipairs,
        tonumber = tonumber,
        tostring = tostring,
        select = select,
        math = math,
        string = string,
    }, { __index = function() return nil end })

    setfenv(func, env)

    local ok, result = pcall(func)
    if not ok or not result then
        return false, 0, 0, nil, barConfig.spell or "Custom", 0
    end

    -- Custom can return: true (simple boolean) or a table {value, maxValue, icon, name, stacks}
    if type(result) == "table" then
        return true,
            result.value or result[1] or 0,
            result.maxValue or result[2] or 0,
            result.icon or result[3],
            result.name or result[4] or barConfig.spell or "Custom",
            result.stacks or result[5] or 0
    end

    -- Simple boolean result
    return true, 0, 0, nil, barConfig.spell or "Custom", 0
end

-- ----------------------------------------------------------------------------
-- Dispatch Table
-- ----------------------------------------------------------------------------

ns.TRACKERS = {
    ["Cooldown"] = CheckCooldown,
    ["Buff"]     = CheckBuff,
    ["Debuff"]   = CheckDebuff,
    ["Proc"]     = CheckProc,
    ["Item"]     = CheckItem,
    ["Custom"]   = CheckCustom,
}

--- Check tracking state for a bar based on its trackMode.
-- @param barConfig table - The bar configuration
-- @return isActive, value, maxValue, icon, name, stacks
function ns:CheckTracker(barConfig)
    local trackMode = barConfig.trackMode
    if not trackMode then
        return false, 0, 0, nil, nil, 0
    end

    local checker = ns.TRACKERS[trackMode]
    if not checker then
        return false, 0, 0, nil, nil, 0
    end

    return checker(barConfig)
end
