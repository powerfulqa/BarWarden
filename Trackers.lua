local addonName, ns = ...

-- ============================================================================
-- Trackers.lua - Canonical tracking mode implementations.
-- Each checker returns (isActive, remaining, duration, icon, name, stacks).
-- Called exclusively via ns:CheckTracker(barConfig) from BarEngine.lua.
-- ============================================================================

local GCD_THRESHOLD = ns.GCD_THRESHOLD
local MAX_AURA_INDEX = ns.MAX_AURA_INDEX

-- stableExpiry prevents bar jitter from fluctuating server expiration times.
-- Key: "unit:spellId_or_name". If the server returns a shorter expiration
-- than what we last saw, we keep the longer cached value.
local stableExpiry = {}

-- Bar configs use canonical fields after DB.lua's v1 migration: spellName
-- (string), spellId (number), itemId (number). Legacy `spell`/`spellInput`
-- are migrated away and no longer referenced here.

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

-- getSpellTokens: split a (possibly comma-separated) spell string into a
-- list. Caches the result on the barConfig to avoid re-parsing every scan.
-- The cache is keyed by the raw spell string so an edit in the options panel
-- (which writes a new spellName) automatically invalidates it.
local function getSpellTokens(barConfig, spell)
    if not spell then return nil end
    if barConfig._tokenCache and barConfig._tokenCacheKey == spell then
        return barConfig._tokenCache
    end
    local tokens = {}
    for token in spell:gmatch("([^,]+)") do
        local t = token:match("^%s*(.-)%s*$")  -- trim whitespace
        if t and t ~= "" then
            tokens[#tokens + 1] = t
        end
    end
    local result = #tokens > 0 and tokens or nil
    barConfig._tokenCache = result
    barConfig._tokenCacheKey = spell
    return result
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

-- clearExpiry: remove cached expiry entries for a spell that is no longer
-- active (prevents stale entries from accumulating).
local function clearExpiry(unit, numericId, tokens)
    if numericId then
        stableExpiry[unit .. ":" .. tostring(numericId)] = nil
    elseif tokens then
        for _, token in ipairs(tokens) do
            stableExpiry[unit .. ":" .. token] = nil
        end
    end
end

-- ----------------------------------------------------------------------------
-- ScanAuras: shared aura-scan loop for Buff, Debuff, and Proc trackers.
--
-- auraFunc:    UnitBuff or UnitDebuff
-- unit:        unit token to scan
-- barConfig:   the bar's config table (for token cache + onlyMine)
-- spell:       the raw spell string from getSpell()
-- filterMine:  if true, skip auras not cast by "player"
-- ----------------------------------------------------------------------------

local function ScanAuras(auraFunc, unit, barConfig, spell, filterMine)
    local numericId = tonumber(spell)
    local tokens = (not numericId) and getSpellTokens(barConfig, spell) or nil

    for i = 1, MAX_AURA_INDEX do
        local name, _, icon, count, _, duration, expirationTime, caster, _, _, spellId = auraFunc(unit, i)
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
            if filterMine and caster ~= "player" then
                -- Aura matches but wasn't cast by the player; keep scanning
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

    -- No match; clear cached expiry entries
    clearExpiry(unit, numericId, tokens)
    return false, 0, 0, nil, spell, 0
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
-- Delegates to ScanAuras with UnitBuff; defaults to "player".
-- ----------------------------------------------------------------------------

local function CheckBuff(barConfig)
    local spell = getSpell(barConfig)
    local unit = getUnit(barConfig, "player")
    if not spell then
        return false, 0, 0, nil, nil, 0
    end
    return ScanAuras(UnitBuff, unit, barConfig, spell, false)
end

-- ----------------------------------------------------------------------------
-- Debuff Tracker
-- Delegates to ScanAuras with UnitDebuff; defaults to "target".
-- onlyMine defaults to true so only the player's debuffs are matched.
-- ----------------------------------------------------------------------------

local function CheckDebuff(barConfig)
    local spell = getSpell(barConfig)
    local unit = getUnit(barConfig, "target")
    if not spell then
        return false, 0, 0, nil, nil, 0
    end
    local onlyMine = barConfig.onlyMine
    if onlyMine == nil then onlyMine = true end
    return ScanAuras(UnitDebuff, unit, barConfig, spell, onlyMine)
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
-- Enchant Tracker (temporary weapon enchants: poisons, shaman buffs, stones)
-- Uses GetWeaponEnchantInfo() which returns enchant data for MH and OH.
-- The "spell" field selects the slot: "mainhand" or "offhand" (default MH).
-- ----------------------------------------------------------------------------

local function CheckEnchant(barConfig)
    -- Determine slot from trackMode: "Enchant OH" = offhand, anything else = mainhand
    local mode = barConfig.trackMode or ""
    local isOH = (mode == "Enchant OH")

    local hasMainEnchant, mainExpires, mainCharges, hasOffEnchant, offExpires, offCharges = GetWeaponEnchantInfo()

    local hasEnchant, expires, charges
    if isOH then
        hasEnchant, expires, charges = hasOffEnchant, offExpires, offCharges
    else
        hasEnchant, expires, charges = hasMainEnchant, mainExpires, mainCharges
    end

    -- Get the weapon icon from the inventory slot
    local invSlot = isOH and 17 or 16  -- 16=MainHand, 17=OffHand
    local icon = GetInventoryItemTexture("player", invSlot)
    -- Use the bar name for display; fall back to slot label
    local displayName = (barConfig.name and barConfig.name ~= "") and barConfig.name
                        or (isOH and "Offhand Enchant" or "Mainhand Enchant")

    if hasEnchant and expires then
        -- GetWeaponEnchantInfo returns milliseconds remaining
        local remaining = expires / 1000
        if remaining > 0 then
            -- Duration is unknown for enchants; use remaining as duration
            return true, remaining, remaining, icon, displayName, charges or 0
        end
    end

    return false, 0, 0, icon, displayName, 0
end

-- ----------------------------------------------------------------------------
-- Totem Tracker (shaman totems, DK ghouls)
-- Uses GetTotemInfo(slot) where slot is 1-4.
-- The "spell" field can be the totem name or slot number (1-4).
-- If a name is given, all 4 slots are searched for a matching totem.
-- ----------------------------------------------------------------------------

local function CheckTotem(barConfig)
    local spell = getSpell(barConfig)
    if not spell then
        return false, 0, 0, nil, nil, 0
    end

    local slotNum = tonumber(spell)

    if slotNum and slotNum >= 1 and slotNum <= 4 then
        -- Direct slot lookup
        local haveTotem, name, startTime, duration, icon = GetTotemInfo(slotNum)
        if haveTotem and name and name ~= "" and duration > 0 then
            local remaining = (startTime + duration) - GetTime()
            if remaining > 0 then
                return true, remaining, duration, icon, name, 0
            end
        end
        return false, 0, 0, nil, "Totem Slot " .. slotNum, 0
    else
        -- Search all 4 slots for a matching totem name
        for slot = 1, 4 do
            local haveTotem, name, startTime, duration, icon = GetTotemInfo(slot)
            if haveTotem and name and name ~= "" then
                if name:lower():find(spell:lower(), 1, true) then
                    if duration > 0 then
                        local remaining = (startTime + duration) - GetTime()
                        if remaining > 0 then
                            return true, remaining, duration, icon, name, 0
                        end
                    end
                end
            end
        end
        return false, 0, 0, nil, spell, 0
    end
end

-- Dispatch table keyed by barConfig.trackMode.
-- Proc is just Buff restricted to "player"; CheckBuff already defaults unit
-- to "player" via getUnit(barConfig, "player"), so no separate function exists.
ns.TRACKERS = {
    ["Cooldown"]   = CheckCooldown,
    ["Buff"]       = CheckBuff,
    ["Debuff"]     = CheckDebuff,
    ["Proc"]       = CheckBuff,
    ["Item"]       = CheckItem,
    ["Enchant"]    = CheckEnchant,
    ["Enchant MH"] = CheckEnchant,
    ["Enchant OH"] = CheckEnchant,
    ["Totem"]      = CheckTotem,
}

-- Check tracking state for `barConfig` by dispatching on its trackMode.
-- See the file header for the returned tuple shape.
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
