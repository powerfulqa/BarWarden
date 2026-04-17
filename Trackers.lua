local addonName, ns = ...

local GetTime = GetTime
local type, tonumber, tostring = type, tonumber, tostring
local ceil = math.ceil

-- ============================================================================
-- Trackers.lua - Canonical tracking mode implementations.
-- Each checker returns (isActive, remaining, duration, icon, name, stacks).
-- Called exclusively via ns:CheckTracker(barConfig) from BarEngine.lua.
-- ============================================================================

local GCD_THRESHOLD = ns.GCD_THRESHOLD
local MAX_AURA_INDEX = ns.MAX_AURA_INDEX

-- ns.SpellDurations: optional per-spell cooldown-duration override.
-- Keys are numeric spell IDs; values are seconds. When present, CheckCooldown
-- prefers the override over GetSpellCooldown's reported duration. Empty by
-- default. Users can populate this to work around private-server CD patches
-- where GetSpellCooldown returns the wrong value.
--
-- Example (paste into a user-addon or directly append in Trackers.lua):
--   ns.SpellDurations[47568] = 60    -- Empower Rune Weapon forced to 60 s
ns.SpellDurations = ns.SpellDurations or {}

-- stableExpiry prevents bar jitter from fluctuating server expiration times.
-- Key: "unit:spellId_or_name". If the server returns a shorter expiration
-- than what we last saw, we keep the longer cached value.
local stableExpiry = {}

-- Wipe stale entries for a specific unit (e.g. on target/focus change) or
-- the whole table. Called from BarEngine event handlers to prevent unbounded
-- growth when units despawn without a final aura scan.
function ns:ClearStableExpiry(unit)
    if unit then
        local prefix = unit .. ":"
        for key in pairs(stableExpiry) do
            if key:sub(1, #prefix) == prefix then
                stableExpiry[key] = nil
            end
        end
    else
        wipe(stableExpiry)
    end
end

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
-- list of tokens. Each token is either a number (spell ID) or a string
-- (spell name), depending on how the user wrote it. Tokens starting with
-- `@` are expanded to their entries in ns.AuraGroups (AuraGroups.lua),
-- enabling shortcuts like `@Stunned` or `Rupture, @Bleeding`.
--
-- Caches parsed tokens in a module-local table keyed by the raw spell
-- string. Parsing is deterministic from the string, so string → tokens
-- is a stable mapping and the cache never needs explicit invalidation.
-- The table stays out of SavedVariables (prior versions stashed it on
-- barConfig, which is persisted; DB migration v5 wipes the stale keys).
local tokenCache = {}

local function getSpellTokens(spell)
    if not spell then return nil end
    local cached = tokenCache[spell]
    if cached ~= nil then
        -- `false` sentinel means "parsed, yielded zero tokens" (e.g. unknown
        -- @group). Avoids re-parsing the same dud string every scan.
        if cached == false then return nil end
        return cached
    end
    local tokens = {}
    for rawToken in spell:gmatch("([^,]+)") do
        local t = rawToken:match("^%s*(.-)%s*$")
        if t and t ~= "" then
            if t:sub(1, 1) == "@" then
                local groupName = t:sub(2)
                local group = ns.AuraGroups and ns.AuraGroups[groupName]
                if group then
                    for _, id in ipairs(group) do
                        tokens[#tokens + 1] = id
                    end
                end
            else
                local asNumber = tonumber(t)
                tokens[#tokens + 1] = asNumber or t
            end
        end
    end
    local result = #tokens > 0 and tokens or nil
    tokenCache[spell] = result == nil and false or result
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
    local tokens = (not numericId) and getSpellTokens(spell) or nil

    for i = 1, MAX_AURA_INDEX do
        local name, _, icon, count, _, duration, expirationTime, caster, _, _, spellId = auraFunc(unit, i)
        if not name then break end

        local match = false
        if numericId then
            match = (spellId == numericId)
        elseif tokens then
            for _, token in ipairs(tokens) do
                if type(token) == "number" then
                    if spellId == token then match = true; break end
                else
                    if name == token then match = true; break end
                end
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
    local spellName, spellIcon, resolvedID

    if spellID then
        spellName, _, spellIcon = GetSpellInfo(spellID)
        resolvedID = spellID
    else
        -- Single GetSpellInfo call captures both name/icon and the numeric ID
        -- used later for the SpellDurations override lookup; the earlier
        -- `select(10, GetSpellInfo(spellName))` repeat call is now redundant.
        spellName, _, spellIcon, _, _, _, _, _, _, resolvedID = GetSpellInfo(spell)
    end

    if not spellName then
        return false, 0, 0, nil, spell, 0
    end

    local start, duration, enabled = GetSpellCooldown(spellID or spellName)

    if not start or enabled ~= 1 then
        return false, 0, 0, spellIcon, spellName, 0
    end

    -- Apply ns.SpellDurations override, if the user has one for this spell.
    if resolvedID and ns.SpellDurations[resolvedID] then
        duration = ns.SpellDurations[resolvedID]
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

-- ----------------------------------------------------------------------------
-- Resource Trackers (class resources: combo points, runic power, soul shards,
-- death knight runes).
--
-- Combo Points / Runic Power / Soul Shards are value-based: the bar fills to
-- show current / max and does not count down with time. The engine dispatches
-- these via UpdateResourceBar (BarEngine.lua) instead of the time-based
-- Bar_OnUpdate; see ns.RESOURCE_TRACK_MODES below.
--
-- Runes ARE time-based (rune cooldown), so they use the standard depleting
-- path unchanged. barConfig.spellId selects the rune slot (1..6).
-- ----------------------------------------------------------------------------

local COMBO_ICON       = "Interface\\Icons\\Ability_Rogue_Eviscerate"
local RUNIC_POWER_ICON = "Interface\\Icons\\Spell_Deathknight_EmpowerRuneblade"
local SHARD_ICON       = "Interface\\Icons\\INV_Misc_Gem_Amethyst_02"
local SOUL_SHARD_ITEM_ID = 6265
local DEFAULT_MAX_SOUL_SHARDS = 10
-- Fallback rune CD for when GetRuneCooldown returns zero or has never been
-- called for a slot. Unholy Presence reduces this in-game but 10s is the
-- baseline and a safe default for the "freshly logged in, never used" case.
local DEFAULT_RUNE_CD = 10

-- GetRuneType returns 1=Blood, 2=Unholy, 3=Frost, 4=Death.
local RUNE_ICONS = {
    [1] = "Interface\\Icons\\Spell_Deathknight_BloodPresence",
    [2] = "Interface\\Icons\\Spell_Deathknight_UnholyPresence",
    [3] = "Interface\\Icons\\Spell_Deathknight_FrostPresence",
    [4] = "Interface\\Icons\\Spell_Deathknight_ClassIcon",
}
local RUNE_NAMES = {
    [1] = "Blood Rune",
    [2] = "Unholy Rune",
    [3] = "Frost Rune",
    [4] = "Death Rune",
}

local function CheckComboPoints(barConfig)
    local cp = GetComboPoints("player", "target") or 0
    -- Always show the bar (even at 0 CP) so the user sees the resource slot.
    return true, cp, 5, COMBO_ICON, "Combo Points", cp
end

local function CheckRunicPower(barConfig)
    -- Power type 6 is SPELL_POWER_RUNIC_POWER on 3.3.5a.
    local power = UnitPower("player", 6) or 0
    local maxPower = UnitPowerMax("player", 6) or 100
    if maxPower <= 0 then maxPower = 100 end
    return true, power, maxPower, RUNIC_POWER_ICON, "Runic Power", power
end

local function CheckSoulShards(barConfig)
    local count = GetItemCount(SOUL_SHARD_ITEM_ID) or 0
    local max = tonumber(barConfig.maxValue) or DEFAULT_MAX_SOUL_SHARDS
    if max <= 0 then max = DEFAULT_MAX_SOUL_SHARDS end
    local icon = GetItemIcon(SOUL_SHARD_ITEM_ID) or SHARD_ICON
    return true, count, max, icon, "Soul Shards", count
end

-- Runes are a resource-style bar (see RESOURCE_TRACK_MODES below) even though
-- the underlying data is a countdown. The bar FILLS as the rune regenerates
-- and stays full when ready, matching the intuition from Blizzard's default
-- DK rune display. Text shows "Ns" countdown while on CD, blank when ready.
--
-- Returns (isActive, current, max, icon, name, stacks) where:
--   current = max when ready, 0..max as the rune regenerates
--   max     = the rune's cooldown duration (10 s baseline; server may vary)
--   stacks  = ceil(cdRemaining) in seconds, 0 means ready (used by the text
--             display in UpdateResourceBar)
local function CheckRunes(barConfig)
    -- Slot lives in spellId (numeric 1..6). spellName falls back for users who
    -- typed it in the text box as a string.
    local slot = tonumber(barConfig.spellId) or tonumber(barConfig.spellName) or 1
    if slot < 1 or slot > 6 then slot = 1 end

    local runeType = GetRuneType and GetRuneType(slot) or 1
    local icon = RUNE_ICONS[runeType] or RUNE_ICONS[1]
    local name = RUNE_NAMES[runeType] or "Rune"

    local start, duration, ready = GetRuneCooldown(slot)

    -- Never-used slot or private-server API glitch: treat as ready at baseline.
    if not duration or duration <= 0 then
        return true, DEFAULT_RUNE_CD, DEFAULT_RUNE_CD, icon, name, 0
    end

    -- Ready: full bar, no countdown text.
    if ready then
        return true, duration, duration, icon, name, 0
    end

    -- On cooldown: bar fills from 0 toward max as the rune regenerates.
    local cdRemaining = (start + duration) - GetTime()
    if cdRemaining <= 0 then
        return true, duration, duration, icon, name, 0
    end

    local current = duration - cdRemaining
    if current < 0 then current = 0 end

    return true, current, duration, icon, name, ceil(cdRemaining)
end

-- Event-driven resource modes. BarEngine's ScanBar checks this set to pick
-- the static (UpdateResourceBar) path instead of time-based ActivateBar.
-- Runes are here even though their data is a cooldown countdown, because we
-- want the bar to FILL (not deplete) as the rune regenerates; the
-- 0.25 s scan loop + RUNE_POWER_UPDATE / RUNE_TYPE_UPDATE events refresh
-- the fill level at a rate that is visibly smooth enough in practice.
ns.RESOURCE_TRACK_MODES = {
    ["Combo Points"] = true,
    ["Runic Power"]  = true,
    ["Soul Shards"]  = true,
    ["Runes"]        = true,
}

function ns:IsResourceTrackMode(mode)
    return ns.RESOURCE_TRACK_MODES[mode] == true
end

-- Dispatch table keyed by barConfig.trackMode.
-- Proc is just Buff restricted to "player"; CheckBuff already defaults unit
-- to "player" via getUnit(barConfig, "player"), so no separate function exists.
ns.TRACKERS = {
    ["Cooldown"]     = CheckCooldown,
    ["Buff"]         = CheckBuff,
    ["Debuff"]       = CheckDebuff,
    ["Proc"]         = CheckBuff,
    ["Item"]         = CheckItem,
    ["Enchant"]      = CheckEnchant,
    ["Enchant MH"]   = CheckEnchant,
    ["Enchant OH"]   = CheckEnchant,
    ["Totem"]        = CheckTotem,
    ["Combo Points"] = CheckComboPoints,
    ["Runic Power"]  = CheckRunicPower,
    ["Soul Shards"]  = CheckSoulShards,
    ["Runes"]        = CheckRunes,
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
