local addonName, ns = ...

-- ============================================================================
-- Trackers.lua - Canonical tracking mode implementations.
-- Each checker returns (isActive, remaining, duration, icon, name, stacks).
-- Called exclusively via ns:CheckTracker(barConfig) from BarEngine.lua.
-- ============================================================================

local GCD_THRESHOLD = 1.5

-- ----------------------------------------------------------------------------
-- Module-level state tables
-- ----------------------------------------------------------------------------

-- stableExpiry: prevents bar jitter from server expiration time fluctuations.
-- Key: "unit:spellId_or_name". If the server returns a shorter expiration
-- than what we last saw, we keep the longer cached value.
local stableExpiry = {}

-- ----------------------------------------------------------------------------
-- Field normalization helpers
-- After schema migration (DB.lua v1) new bars use spellName/spellId/itemId.
-- Legacy fields (spell, spellInput) are kept here as fallbacks during
-- the transition window.
-- ----------------------------------------------------------------------------

local function getSpell(barConfig)
    if barConfig.spellName and barConfig.spellName ~= "" then
        return barConfig.spellName
    end
    if barConfig.spellId then
        return tostring(barConfig.spellId)
    end
    return nil
end

local function getUnit(barConfig, default)
    return barConfig.unit or default
end

-- getSpellTokens: split a (possibly comma-separated) spell string into a list.
-- Supports: "Rupture" → {"Rupture"}
--           "Rupture, Garrote" → {"Rupture", "Garrote"}
local function getSpellTokens(spell)
    if not spell then return nil end
    local tokens = {}
    for token in spell:gmatch("([^,]+)") do
        local t = token:match("^%s*(.-)%s*$")  -- trim whitespace
        if t and t ~= "" then
            tokens[#tokens + 1] = t
        end
    end
    return #tokens > 0 and tokens or nil
end

-- smoothExpiry: apply stable-expiry smoothing.
-- Returns the effective expiration time (never moves backward).
local function smoothExpiry(key, expirationTime)
    local cached = stableExpiry[key]
    if cached and expirationTime < cached then
        return cached
    end
    stableExpiry[key] = expirationTime
    return expirationTime
end

-- ----------------------------------------------------------------------------
-- Cooldown Tracker
-- ----------------------------------------------------------------------------

local function CheckCooldown(barConfig)
    local spell = getSpell(barConfig)
    if not spell then
        return false, 0, 0, nil, nil, 0
    end

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
-- Supports comma-separated spell names and numeric spell IDs.
-- Applies expiration time smoothing to prevent bar jitter.
-- ----------------------------------------------------------------------------

local function CheckBuff(barConfig)
    local spell = getSpell(barConfig)
    local unit = getUnit(barConfig, "player")
    if not spell then
        return false, 0, 0, nil, nil, 0
    end

    -- Parse spell string into tokens (handles "Spell A, Spell B")
    local numericId = tonumber(spell)
    local tokens = (not numericId) and getSpellTokens(spell) or nil

    for i = 1, 40 do
        local name, _, icon, count, _, duration, expirationTime, _, _, _, spellId = UnitBuff(unit, i)
        if not name then break end

        local match = false
        if numericId then
            match = (spellId == numericId)
        elseif tokens then
            for _, token in ipairs(tokens) do
                if name == token then match = true; break end
            end
        end

        if match then
            local remaining = 0
            local maxVal = 0
            if duration and duration > 0 and expirationTime then
                local key = unit .. ":" .. tostring(spellId or name)
                local stableExp = smoothExpiry(key, expirationTime)
                remaining = stableExp - GetTime()
                if remaining < 0 then remaining = 0 end
                maxVal = duration
            end
            return true, remaining, maxVal, icon, name, count or 0
        end
    end

    -- No match found; clear any cached expiry for this bar's tracked name
    if numericId then
        stableExpiry[unit .. ":" .. tostring(numericId)] = nil
    elseif tokens then
        for _, token in ipairs(tokens) do
            stableExpiry[unit .. ":" .. token] = nil
        end
    end

    return false, 0, 0, nil, spell, 0
end

-- ----------------------------------------------------------------------------
-- Debuff Tracker
-- Supports comma-separated spell names, numeric spell IDs, and onlyMine filter.
-- Applies expiration time smoothing.
-- ----------------------------------------------------------------------------

local function CheckDebuff(barConfig)
    local spell = getSpell(barConfig)
    local unit = getUnit(barConfig, "target")
    if not spell then
        return false, 0, 0, nil, nil, 0
    end

    local onlyMine = barConfig.onlyMine
    if onlyMine == nil then onlyMine = true end

    local numericId = tonumber(spell)
    local tokens = (not numericId) and getSpellTokens(spell) or nil

    for i = 1, 40 do
        local name, _, icon, count, _, duration, expirationTime, caster, _, _, spellId = UnitDebuff(unit, i)
        if not name then break end

        local match = false
        if numericId then
            match = (spellId == numericId)
        elseif tokens then
            for _, token in ipairs(tokens) do
                if name == token then match = true; break end
            end
        end

        if match then
            if onlyMine and caster ~= "player" then
                -- This aura matches but wasn't cast by the player; keep scanning
            else
                local remaining = 0
                local maxVal = 0
                if duration and duration > 0 and expirationTime then
                    local key = unit .. ":" .. tostring(spellId or name)
                    local stableExp = smoothExpiry(key, expirationTime)
                    remaining = stableExp - GetTime()
                    if remaining < 0 then remaining = 0 end
                    maxVal = duration
                end
                return true, remaining, maxVal, icon, name, count or 0
            end
        end
    end

    -- No match; clear cached expiry
    if numericId then
        stableExpiry[unit .. ":" .. tostring(numericId)] = nil
    elseif tokens then
        for _, token in ipairs(tokens) do
            stableExpiry[unit .. ":" .. token] = nil
        end
    end

    return false, 0, 0, nil, spell, 0
end

-- ----------------------------------------------------------------------------
-- Item Tracker (item cooldowns: equipped, bag, inventory)
-- ----------------------------------------------------------------------------

local function CheckItem(barConfig)
    -- itemId takes priority; fall back to spellName/spellId for legacy configs
    local itemRef = barConfig.itemId or getSpell(barConfig)
    if not itemRef then
        return false, 0, 0, nil, nil, 0
    end

    local itemID = tonumber(itemRef)
    local itemName, itemIcon

    if itemID then
        itemName = GetItemInfo(itemID)
        itemIcon = GetItemIcon(itemID)
    else
        itemName = itemRef
        itemIcon = GetItemIcon(itemRef)
    end

    local displayName = itemName or tostring(itemRef)

    local start, duration, enabled
    if itemID then
        start, duration, enabled = GetItemCooldown(itemID)
    else
        start, duration, enabled = GetItemCooldown(itemRef)
    end

    if start and duration and duration > GCD_THRESHOLD and enabled == 1 then
        local now = GetTime()
        local remaining = (start + duration) - now
        if remaining > 0 then
            return true, remaining, duration, itemIcon, displayName, 0
        end
    end

    return false, 0, 0, itemIcon, displayName, 0
end

-- ----------------------------------------------------------------------------
-- Dispatch Table
-- Proc is Buff restricted to "player" unit; CheckBuff defaults unit to "player"
-- via getUnit(barConfig, "player"), so no separate function is needed.
-- ----------------------------------------------------------------------------

ns.TRACKERS = {
    ["Cooldown"] = CheckCooldown,
    ["Buff"]     = CheckBuff,
    ["Debuff"]   = CheckDebuff,
    ["Proc"]     = CheckBuff,
    ["Item"]     = CheckItem,
}

--- Check tracking state for a bar based on its trackMode.
-- @param barConfig table - The bar configuration
-- @return isActive, remaining, duration, icon, name, stacks
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
