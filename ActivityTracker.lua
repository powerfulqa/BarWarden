-- ActivityTracker.lua - Passive usage tracking and per-spell stats store.
-- Author:  Serv
-- Source:  https://github.com/powerfulqa/BarWarden
-- License: GNU GPL v3 (see LICENSE); attribution preservation is required.

local addonName, ns = ...

-- ============================================================================
-- ActivityTracker.lua - Passive spell/aura/cooldown monitoring
--
-- Watches everything happening on the player's character and records it
-- automatically: cooldowns used, buffs gained, debuffs applied, weapon
-- enchants, and totems. Data feeds the Activity Tracker stats tab so
-- users can discover what to track before creating bars.
-- ============================================================================

local GCD_THRESHOLD = ns.GCD_THRESHOLD
local MAX_AURA_INDEX = ns.MAX_AURA_INDEX
local MAX_ACTIVITY_ENTRIES = 200

-- ----------------------------------------------------------------------------
-- State snapshots: previous tick's data, used for diff-based detection
-- ----------------------------------------------------------------------------

-- Buff/debuff snapshots are double-buffered plain sets: prev* holds last
-- scan's spellIds, spare* is wiped and refilled each scan, then the two swap.
-- These scanners ride UNIT_AURA (up to 10 Hz per unit in combat), and the
-- earlier shape - a fresh table plus a {name, icon, expirationTime} sub-table
-- per active aura per scan - was hundreds of throwaway allocations a second
-- on a raid-buffed character. Name/icon are only ever needed at the moment an
-- activation is recorded, while they are still in hand from the aura walk, so
-- the snapshot itself needs nothing but key presence.
local prevBuffs = {}      -- [spellId] = true
local spareBuffs = {}     -- prevBuffs' swap partner
local prevDebuffs = {}    -- [spellId] = true
local spareDebuffs = {}   -- prevDebuffs' swap partner
local prevEnchantMH = false
local prevEnchantOH = false
local prevTotems = {}     -- [slot] = totemName

-- First-scan baseline guards. On every /reload, login, or /bw enable the whole
-- addon re-runs from scratch and StartActivityTracking wipes the snapshots, so
-- the very first scan would otherwise diff everything currently active against
-- an empty snapshot and count each already-running effect as a fresh
-- activation. We seed the snapshot on that first pass and only count genuine
-- transitions afterwards. Per-scanner because the scans can first fire on
-- different ticks (a debuff scan needs a target to exist first).
local primedBuffs = false
local primedDebuffs = false
local primedEnchant = false
local primedTotems = false

-- Active cooldowns being tracked for uptime
local activeCooldowns = {} -- [spellId] = expirationTime

-- Timestamp tracking for uptime on auras/enchants/totems
local activeTimers = {}   -- [key] = GetTime() when activated

-- ----------------------------------------------------------------------------
-- Key builders
-- ----------------------------------------------------------------------------

local function MakeKey(category, id)
    return category .. ":" .. tostring(id)
end

-- ----------------------------------------------------------------------------
-- Recording helpers
-- ----------------------------------------------------------------------------

local function EnsureSessionEntry(key, name, spellId, icon, category)
    if not ns.activitySession then return end
    if not ns.activitySession[key] then
        ns.activitySession[key] = {
            name = name,
            spellId = spellId,
            icon = icon,
            category = category,
            activations = 0,
            uptime = 0,
        }
    end
end

local function EnsurePersistentEntry(key, name, spellId, icon, category)
    if not ns.db or not ns.db.activity then return end
    if not ns.db.activity[key] then
        ns.db.activity[key] = {
            name = name,
            spellId = spellId,
            icon = icon,
            category = category,
            activations = 0,
            uptime = 0,
            lastSeen = time(),
        }
    end
end

-- Evict oldest entries by lastSeen when persistent table exceeds the cap
local function EvictOldest()
    if not ns.db or not ns.db.activity then return end

    local count = 0
    for _ in pairs(ns.db.activity) do count = count + 1 end
    if count <= MAX_ACTIVITY_ENTRIES then return end

    -- Find the oldest entry
    local oldestKey, oldestTime = nil, math.huge
    for key, entry in pairs(ns.db.activity) do
        local t = entry.lastSeen or 0
        if t < oldestTime then
            oldestKey = key
            oldestTime = t
        end
    end
    if oldestKey then
        ns.db.activity[oldestKey] = nil
    end
end

local function RecordActivation(key, name, spellId, icon, category)
    EnsureSessionEntry(key, name, spellId, icon, category)
    EnsurePersistentEntry(key, name, spellId, icon, category)

    ns.activitySession[key].activations = ns.activitySession[key].activations + 1

    if ns.db and ns.db.activity and ns.db.activity[key] then
        local p = ns.db.activity[key]
        p.activations = p.activations + 1
        p.lastSeen = time()
        -- Update metadata in case spell name/icon resolved later
        if name then p.name = name end
        if icon then p.icon = icon end
    end

    activeTimers[key] = GetTime()
    EvictOldest()
end

local function RecordDeactivation(key)
    local startTime = activeTimers[key]
    if not startTime then return end

    local elapsed = GetTime() - startTime
    if elapsed <= 0 then
        activeTimers[key] = nil
        return
    end

    if ns.activitySession and ns.activitySession[key] then
        ns.activitySession[key].uptime = ns.activitySession[key].uptime + elapsed
    end

    if ns.db and ns.db.activity and ns.db.activity[key] then
        ns.db.activity[key].uptime = ns.db.activity[key].uptime + elapsed
        ns.db.activity[key].lastSeen = time()
    end

    activeTimers[key] = nil
end

-- Flush all pending timers (called on disable/logout)
local function FlushActiveTimers()
    for key in pairs(activeTimers) do
        RecordDeactivation(key)
    end
end

-- ----------------------------------------------------------------------------
-- Buff scanner: snapshot-diff on UnitBuff("player", 1..40)
-- ----------------------------------------------------------------------------

function ns:ScanBuffActivity()
    local current = spareBuffs
    wipe(current)

    for i = 1, MAX_AURA_INDEX do
        local name, _, icon, count, _, duration, expirationTime, _, _, _, spellId = UnitBuff("player", i)
        if not name then break end
        if spellId and not current[spellId] then
            -- Record while name/icon are in hand from this walk, so the
            -- snapshot needs no per-aura sub-tables. The `not current` guard
            -- above also stops a buff listed twice in one scan (two casters,
            -- one spellId) from recording two activations.
            -- First scan after a (re)start only seeds the snapshot; effects
            -- already active are a baseline, not new activations.
            if primedBuffs and not prevBuffs[spellId] then
                RecordActivation(MakeKey("Buff", spellId), name, spellId, icon, "Buff")
            end
            current[spellId] = true
        end
    end

    if primedBuffs then
        -- Detect lost buffs (in previous but not in current)
        for spellId in pairs(prevBuffs) do
            if not current[spellId] then
                RecordDeactivation(MakeKey("Buff", spellId))
            end
        end
    else
        primedBuffs = true
    end

    spareBuffs = prevBuffs
    prevBuffs = current
end

-- ----------------------------------------------------------------------------
-- Debuff scanner: snapshot-diff on UnitDebuff("target", 1..40)
-- Only tracks debuffs cast by the player.
-- ----------------------------------------------------------------------------

function ns:ScanDebuffActivity()
    local current = spareDebuffs
    wipe(current)

    if UnitExists("target") then
        for i = 1, MAX_AURA_INDEX do
            local name, _, icon, count, _, duration, expirationTime, caster, _, _, spellId = UnitDebuff("target", i)
            if not name then break end
            if spellId and caster == "player" and not current[spellId] then
                -- Same inline shape as ScanBuffActivity above: record with
                -- name/icon in hand, snapshot holds key presence only.
                if primedDebuffs and not prevDebuffs[spellId] then
                    RecordActivation(MakeKey("Debuff", spellId), name, spellId, icon, "Debuff")
                end
                current[spellId] = true
            end
        end
    end

    if primedDebuffs then
        for spellId in pairs(prevDebuffs) do
            if not current[spellId] then
                RecordDeactivation(MakeKey("Debuff", spellId))
            end
        end
    else
        primedDebuffs = true
    end

    spareDebuffs = prevDebuffs
    prevDebuffs = current
end

-- ----------------------------------------------------------------------------
-- Enchant scanner: GetWeaponEnchantInfo state transitions
-- ----------------------------------------------------------------------------

function ns:ScanEnchantActivity()
    local hasMain, mainExpires, _, hasOff, offExpires = GetWeaponEnchantInfo()

    -- First scan seeds the baseline: an enchant already on the weapon at
    -- login/reload is not a fresh application.
    if primedEnchant then
        -- Mainhand
        if hasMain and not prevEnchantMH then
            local icon = GetInventoryItemTexture("player", 16)
            RecordActivation("Enchant:MH", "Mainhand Enchant", nil, icon, "Enchant")
        elseif not hasMain and prevEnchantMH then
            RecordDeactivation("Enchant:MH")
        end

        -- Offhand
        if hasOff and not prevEnchantOH then
            local icon = GetInventoryItemTexture("player", 17)
            RecordActivation("Enchant:OH", "Offhand Enchant", nil, icon, "Enchant")
        elseif not hasOff and prevEnchantOH then
            RecordDeactivation("Enchant:OH")
        end
    else
        primedEnchant = true
    end

    prevEnchantMH = hasMain and true or false
    prevEnchantOH = hasOff and true or false
end

-- ----------------------------------------------------------------------------
-- Totem scanner: GetTotemInfo(1..4) snapshot-diff by slot
-- ----------------------------------------------------------------------------

function ns:ScanTotemActivity()
    for slot = 1, 4 do
        local haveTotem, name, startTime, duration, icon = GetTotemInfo(slot)
        local wasActive = prevTotems[slot]

        if haveTotem and name and name ~= "" then
            -- First scan seeds the baseline: a totem already standing at
            -- login/reload is not a fresh drop.
            if primedTotems and (not wasActive or wasActive ~= name) then
                -- New totem or different totem in this slot
                if wasActive then
                    RecordDeactivation(MakeKey("Totem", wasActive))
                end
                RecordActivation(MakeKey("Totem", name), name, nil, icon, "Totem")
            end
            prevTotems[slot] = name
        else
            if primedTotems and wasActive then
                RecordDeactivation(MakeKey("Totem", wasActive))
            end
            prevTotems[slot] = nil
        end
    end
    primedTotems = true
end

-- ----------------------------------------------------------------------------
-- Combat log handler: SPELL_CAST_SUCCESS → cooldown detection
-- In 3.3.5a, CombatLogGetCurrentEventInfo does not exist; the payload is
-- passed directly as varargs to the event handler via the event frame.
-- ----------------------------------------------------------------------------

function ns:OnCombatLogEvent(...)
    -- 3.3.5a CLEU args: timestamp, event, sourceGUID, sourceName, sourceFlags,
    --                    destGUID, destName, destFlags, spellId, spellName, spellSchool, ...
    --
    -- Only reached via DispatchCombatLogCast (Events.lua), which has already
    -- filtered to SPELL_CAST_SUCCESS from the player and caches the player GUID.
    -- Re-checking here meant a UnitGUID call on every combat-log event, and two
    -- copies of one rule to keep in step.
    local spellId, spellName = select(9, ...)
    if not spellId or spellId == 0 then return end

    -- Check if this spell went on cooldown
    local start, duration, enabled = GetSpellCooldown(spellId)
    if not start or not duration or duration <= GCD_THRESHOLD or enabled ~= 1 then
        return
    end

    local _, _, spellIcon = GetSpellInfo(spellId)
    local key = MakeKey("Cooldown", spellId)
    local expirationTime = start + duration

    -- Only record if not already tracking this cooldown (avoid duplicate from
    -- rapid CLEU events for the same cast)
    if not activeCooldowns[spellId] then
        RecordActivation(key, spellName, spellId, spellIcon, "Cooldown")
    end
    activeCooldowns[spellId] = expirationTime
end

-- ----------------------------------------------------------------------------
-- Cooldown expiry check: called from the periodic scan timer (0.25s)
-- Lightweight: only iterates cooldowns we've already detected, not the
-- full spellbook.
-- ----------------------------------------------------------------------------

function ns:CheckCooldownExpiry()
    local now = GetTime()
    for spellId, expiry in pairs(activeCooldowns) do
        if now >= expiry then
            local key = MakeKey("Cooldown", spellId)
            RecordDeactivation(key)
            activeCooldowns[spellId] = nil
        end
    end
end

-- ----------------------------------------------------------------------------
-- Lifecycle
-- ----------------------------------------------------------------------------

function ns:StartActivityTracking()
    -- Clear snapshots and re-arm the baseline guards. The next scan of each
    -- kind seeds its snapshot from live state without recording, so effects
    -- already running at login/reload/re-enable are not miscounted as fresh
    -- activations (see the primed* guards above).
    wipe(prevBuffs)
    wipe(spareBuffs)
    wipe(prevDebuffs)
    wipe(spareDebuffs)
    prevEnchantMH = false
    prevEnchantOH = false
    wipe(prevTotems)
    wipe(activeCooldowns)
    wipe(activeTimers)
    primedBuffs = false
    primedDebuffs = false
    primedEnchant = false
    primedTotems = false
end

function ns:StopActivityTracking()
    FlushActiveTimers()
    wipe(activeCooldowns)
end

-- Public: get combined session + persistent data for a key
function ns:GetActivityEntry(key)
    local session = ns.activitySession and ns.activitySession[key]
    local persistent = ns.db and ns.db.activity and ns.db.activity[key]
    return session, persistent
end

-- Public: iterate all known activity keys (union of session + persistent)
function ns:GetAllActivityKeys()
    local keys = {}
    if ns.activitySession then
        for key in pairs(ns.activitySession) do keys[key] = true end
    end
    if ns.db and ns.db.activity then
        for key in pairs(ns.db.activity) do keys[key] = true end
    end
    return keys
end

-- Public: get metadata for a key (name, icon, category) from whichever source has it
function ns:GetActivityMeta(key)
    local session = ns.activitySession and ns.activitySession[key]
    if session then return session.name, session.icon, session.category, session.spellId end
    local persistent = ns.db and ns.db.activity and ns.db.activity[key]
    if persistent then return persistent.name, persistent.icon, persistent.category, persistent.spellId end
    return nil, nil, nil, nil
end
