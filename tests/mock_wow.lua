-- tests/mock_wow.lua
--
-- Controllable WoW-host globals installed into _G so BarWarden modules can
-- load under standalone Lua. Tests poke the `M.*` state fields before
-- invoking the code under test; M.reset() clears transient state between
-- tests so one test's side effects can't leak into another.
--
-- Scope: stubs for the APIs actually hit by the pure-logic modules we test
-- (Utils, DB, Conditions, Trackers, AuraGroups, ClassPresets). Frame APIs
-- (CreateFrame, SetPoint, etc.) are NOT stubbed because the files we load
-- don't touch them at file scope or inside the functions we exercise.

local M = {}

-- --------------------------------------------------------------------------
-- Controllable state
-- --------------------------------------------------------------------------

M.now = 0
M.playerClassLoc = "Rogue"
M.playerClass    = "ROGUE"
M.playerHealth   = 100
M.playerHealthMax = 100
M.playerCombat   = false
M.playerMounted  = false
M.playerResting  = false
M.playerInInstance = false
M.playerInVehicle  = false
M.partyMembers   = 0
M.raidMembers    = 0
M.playerGUID     = "Player-Test"

-- Aura lists per unit. Each entry is a table of the 11 values UnitBuff /
-- UnitDebuff returns on 3.3.5a (name, rank, icon, count, dispelType,
-- duration, expirationTime, caster, isStealable, shouldConsolidate, spellId).
M.buffs   = { player = {}, target = {}, focus = {} }
M.debuffs = { player = {}, target = {}, focus = {} }

-- Spell/item registries. Keys are accepted as either numeric IDs or strings
-- (names) so the stub matches GetSpellInfo's lookup flexibility.
M.spellInfo     = {}   -- [key] = {name, rank, icon, cost, isFunnel, powerType, castingTime, minRange, maxRange, spellId}
M.spellCooldown = {}   -- [key] = {start, duration, enabled}
M.itemCooldown  = {}   -- [key] = {start, duration, enabled}
M.itemInfo      = {}   -- [id] = {name, link, quality, level, reqLevel, class, subclass, stack, equipSlot, icon}
M.itemIcon      = {}   -- [id] = icon path
M.itemCount     = {}   -- [id] = integer

-- Resource state
M.power         = {}   -- [powerType] = value (runic power = 6)
M.powerMax      = {}   -- [powerType] = max
M.comboPoints   = 0

-- Rune / totem / enchant fallbacks (mostly irrelevant for the logic we test,
-- but stubs must exist so Trackers.lua loads without erroring).
M.runeCooldown  = function(slot) return 0, 0, true end
M.runeType      = function(slot) return 1 end
M.weaponEnchant = { false, 0, 0, false, 0, 0 }  -- mh, mhExpire, mhCharges, oh, ohExpire, ohCharges
M.totem         = function(slot) return false, "", 0, 0, nil end
M.invTexture    = function(unit, slot) return nil end

-- --------------------------------------------------------------------------
-- Reset helper
-- --------------------------------------------------------------------------

function M.reset()
    M.now             = 0
    M.playerClassLoc  = "Rogue"
    M.playerClass     = "ROGUE"
    M.playerHealth    = 100
    M.playerHealthMax = 100
    M.playerCombat    = false
    M.playerMounted   = false
    M.playerResting   = false
    M.playerInInstance = false
    M.playerInVehicle  = false
    M.partyMembers    = 0
    M.raidMembers     = 0
    for _, t in pairs(M.buffs)   do for k in pairs(t) do t[k] = nil end end
    for _, t in pairs(M.debuffs) do for k in pairs(t) do t[k] = nil end end
    for k in pairs(M.spellInfo)     do M.spellInfo[k]     = nil end
    for k in pairs(M.spellCooldown) do M.spellCooldown[k] = nil end
    for k in pairs(M.itemCooldown)  do M.itemCooldown[k]  = nil end
    for k in pairs(M.itemInfo)      do M.itemInfo[k]      = nil end
    for k in pairs(M.itemIcon)      do M.itemIcon[k]      = nil end
    for k in pairs(M.itemCount)     do M.itemCount[k]     = nil end
    for k in pairs(M.power)         do M.power[k]         = nil end
    for k in pairs(M.powerMax)      do M.powerMax[k]      = nil end
    M.comboPoints = 0
end

-- --------------------------------------------------------------------------
-- Install stubs into _G. Idempotent: safe to call multiple times.
-- --------------------------------------------------------------------------

local function unpackAura(a)
    if not a then return nil end
    return a.name, a.rank, a.icon, a.count, a.dispelType,
           a.duration, a.expirationTime, a.caster,
           a.isStealable, a.shouldConsolidate, a.spellId
end

local function unpackSpellInfo(info)
    if not info then return nil end
    return info.name, info.rank, info.icon, info.cost,
           info.isFunnel, info.powerType, info.castingTime,
           info.minRange, info.maxRange, info.spellId
end

function M.install()
    _G.GetTime = function() return M.now end
    _G.time    = function() return M.now end

    _G.UnitClass = function(unit)
        if unit == "player" then return M.playerClassLoc, M.playerClass end
        return nil, nil
    end

    _G.UnitGUID = function(unit)
        if unit == "player" then return M.playerGUID end
        return nil
    end

    _G.UnitHealth      = function(unit) return unit == "player" and M.playerHealth    or 0 end
    _G.UnitHealthMax   = function(unit) return unit == "player" and M.playerHealthMax or 0 end
    _G.UnitAffectingCombat = function(unit) return unit == "player" and M.playerCombat or false end
    _G.IsMounted       = function() return M.playerMounted end
    _G.IsResting       = function() return M.playerResting end
    _G.IsInInstance    = function() return M.playerInInstance, "party" end
    _G.UnitInVehicle   = function(unit) return unit == "player" and M.playerInVehicle or false end
    _G.GetNumPartyMembers = function() return M.partyMembers end
    _G.GetNumRaidMembers  = function() return M.raidMembers  end

    _G.UnitBuff   = function(unit, i) return unpackAura((M.buffs[unit]   or {})[i]) end
    _G.UnitDebuff = function(unit, i) return unpackAura((M.debuffs[unit] or {})[i]) end

    _G.GetSpellInfo = function(key)
        if key == nil then return nil end
        return unpackSpellInfo(M.spellInfo[key])
    end

    _G.GetSpellCooldown = function(key)
        local cd = M.spellCooldown[key]
        if not cd then return 0, 0, 0 end
        return cd.start, cd.duration, cd.enabled
    end

    _G.GetItemCooldown = function(key)
        local cd = M.itemCooldown[key]
        if not cd then return 0, 0, 0 end
        return cd.start, cd.duration, cd.enabled
    end

    _G.GetItemInfo = function(id)
        local i = M.itemInfo[id]
        if not i then return nil end
        return i.name, i.link, i.quality, i.level, i.reqLevel,
               i.class, i.subclass, i.stack, i.equipSlot, i.icon
    end

    _G.GetItemIcon  = function(id) return M.itemIcon[id] end
    _G.GetItemCount = function(id) return M.itemCount[id] or 0 end

    _G.UnitPower    = function(unit, t) return M.power[t]    or 0 end
    _G.UnitPowerMax = function(unit, t) return M.powerMax[t] or 0 end
    _G.GetComboPoints = function(unit, target) return M.comboPoints end

    _G.GetRuneCooldown     = function(slot) return M.runeCooldown(slot) end
    _G.GetRuneType         = function(slot) return M.runeType(slot) end
    _G.GetWeaponEnchantInfo = function()
        local e = M.weaponEnchant
        return e[1], e[2], e[3], e[4], e[5], e[6]
    end
    _G.GetTotemInfo        = function(slot) return M.totem(slot) end
    _G.GetInventoryItemTexture = function(unit, slot) return M.invTexture(unit, slot) end

    _G.GetAddOnMetadata = function(name, field)
        if field == "Version" then return "test" end
        return nil
    end

    -- Blizzard globals BarWarden reads
    _G.RAID_CLASS_COLORS = _G.RAID_CLASS_COLORS or {
        DEATHKNIGHT = { r = 0.77, g = 0.12, b = 0.23 },
        DRUID       = { r = 1.00, g = 0.49, b = 0.04 },
        HUNTER      = { r = 0.67, g = 0.83, b = 0.45 },
        MAGE        = { r = 0.41, g = 0.80, b = 0.94 },
        PALADIN     = { r = 0.96, g = 0.55, b = 0.73 },
        PRIEST      = { r = 1.00, g = 1.00, b = 1.00 },
        ROGUE       = { r = 1.00, g = 0.96, b = 0.41 },
        SHAMAN      = { r = 0.00, g = 0.44, b = 0.87 },
        WARLOCK     = { r = 0.58, g = 0.51, b = 0.79 },
        WARRIOR     = { r = 0.78, g = 0.61, b = 0.43 },
    }

    -- WoW-flavoured helpers BarWarden calls as globals
    _G.wipe    = _G.wipe    or function(t) for k in pairs(t) do t[k] = nil end; return t end
    _G.strtrim = _G.strtrim or function(s) return (s:gsub("^%s*(.-)%s*$", "%1")) end
end

return M
