-- Events.lua - Central event dispatcher and factory wrappers.
-- Author:  Serv
-- Source:  https://github.com/powerfulqa/BarWarden
-- License: see LICENSE; attribution preservation is required.

local addonName, ns = ...

-- ============================================================================
-- Events.lua - Central event dispatcher: register/unregister, routing, throttle
-- ============================================================================

local eventFrame = CreateFrame("Frame", "BarWardenEventFrame", UIParent)
local registeredEvents = {}
local eventHandlers = {}
local throttleTimers = {}

local UNIT_HEALTH_THROTTLE = 0.25 -- 4 Hz max
local UNIT_AURA_THROTTLE   = 0.1  -- 10 Hz max; prevents bursts from rapid aura churn

local function OnEvent(self, event, ...)
    local handler = eventHandlers[event]
    if handler then
        handler(event, ...)
    end
end

eventFrame:SetScript("OnEvent", OnEvent)

function ns:RegisterAddonEvent(event, handler)
    if not registeredEvents[event] then
        eventFrame:RegisterEvent(event)
        registeredEvents[event] = true
    end
    if handler then
        eventHandlers[event] = handler
    end
end

function ns:UnregisterAddonEvent(event)
    if registeredEvents[event] then
        eventFrame:UnregisterEvent(event)
        registeredEvents[event] = nil
    end
    eventHandlers[event] = nil
    throttleTimers[event] = nil
    -- The per-unit throttler keys as "event:unit", so clearing the bare event
    -- key alone left stale timestamps behind that could swallow the first scan
    -- after a re-enable.
    local prefix = event .. ":"
    local plen = #prefix
    for key in pairs(throttleTimers) do
        if string.sub(key, 1, plen) == prefix then
            throttleTimers[key] = nil
        end
    end
end

-- (A plain per-event ThrottledHandler lived here until v2.1.1; every throttled
-- event needs the per-unit variant below, so it had no call sites.)

-- Per-unit rate-limit: throttles each unit independently (key = event:unit), so
-- a UNIT_AURA burst on player then target in the same window doesn't drop the
-- second unit's scan (a plain per-event throttle would - it caught only the
-- first, leaving the other to the slower poll loop).
local function ThrottledUnitHandler(event, interval, handler)
    return function(evt, unit)
        if not unit then return end
        local key = event .. ":" .. unit
        local now = GetTime()
        local last = throttleTimers[key] or 0
        if now - last < interval then return end
        throttleTimers[key] = now
        handler(evt, unit)
    end
end

-- ----------------------------------------------------------------------------
-- Handler factories
--
-- Each factory returns an OnEvent-shaped function that forwards to the
-- corresponding ns:<method> if defined. Keeping these tiny avoids the
-- copy-paste wrappers that used to live here.
-- ----------------------------------------------------------------------------

local function Dispatch(method)
    return function()
        if ns[method] then ns[method](ns) end
    end
end

local function DispatchUnit(method)
    return function(_, unit)
        if ns[method] then ns[method](ns, unit) end
    end
end

local function DispatchFixed(method, arg)
    return function()
        if ns[method] then ns[method](ns, arg) end
    end
end

-- DispatchCombatLogCast: specialised dispatcher for COMBAT_LOG_EVENT_UNFILTERED.
-- CLEU is the single highest-volume event on 3.3.5a (tens of thousands per
-- minute in a raid), but BarWarden only cares about the player's own
-- SPELL_CAST_SUCCESS for activity tracking. Filtering at dispatch time lets
-- the other 95%+ of events bail before any method lookup or vararg forwarding.
local playerGUID  -- resolved lazily; UnitGUID returns nil before PLAYER_LOGIN
local function DispatchCombatLogCast(method)
    return function(_, timestamp, subEvent, sourceGUID, ...)
        if subEvent ~= "SPELL_CAST_SUCCESS" then return end
        if not playerGUID then playerGUID = UnitGUID("player") end
        if sourceGUID ~= playerGUID then return end
        if ns[method] then
            ns[method](ns, timestamp, subEvent, sourceGUID, ...)
        end
    end
end

-- PLAYER_REGEN_ENABLED/DISABLED share a handler, with an extra side effect:
-- entering combat auto-exits test mode so it never leaks into real play.
local function OnCombatStateChanged(event)
    if event == "PLAYER_REGEN_DISABLED" and ns.testMode then
        ns:DeactivateTestMode()
    end
    if ns.OnCombatStateChanged then
        ns:OnCombatStateChanged(event == "PLAYER_REGEN_DISABLED")
    end
end

local GAMEPLAY_EVENTS = {
    { "SPELL_UPDATE_COOLDOWN",     Dispatch("OnSpellCooldownUpdate") },
    { "ACTIONBAR_UPDATE_COOLDOWN", Dispatch("OnSpellCooldownUpdate") },
    { "UNIT_AURA",                 ThrottledUnitHandler("UNIT_AURA", UNIT_AURA_THROTTLE, DispatchUnit("OnUnitAura")) },
    { "PLAYER_TARGET_CHANGED",     DispatchFixed("OnTargetChanged", "target") },
    { "PLAYER_FOCUS_CHANGED",      DispatchFixed("OnFocusChanged",  "focus") },
    { "PLAYER_REGEN_ENABLED",      OnCombatStateChanged },
    { "PLAYER_REGEN_DISABLED",     OnCombatStateChanged },
    { "UNIT_HEALTH",               ThrottledUnitHandler("UNIT_HEALTH", UNIT_HEALTH_THROTTLE, DispatchUnit("OnUnitHealth")) },
    { "PARTY_MEMBERS_CHANGED",     Dispatch("OnGroupChanged") },
    { "RAID_ROSTER_UPDATE",        Dispatch("OnGroupChanged") },
    { "BAG_UPDATE_COOLDOWN",       Dispatch("OnBagCooldownUpdate") },
    { "PLAYER_ENTERING_WORLD",     Dispatch("OnPlayerEnteringWorld") },
    { "UNIT_INVENTORY_CHANGED",    Dispatch("OnEnchantUpdate") },
    { "PLAYER_TOTEM_UPDATE",       Dispatch("OnTotemUpdate") },
    { "COMBAT_LOG_EVENT_UNFILTERED", DispatchCombatLogCast("OnCombatLogEvent") },
    -- Resource events (Combo Points + DK runes). Runic Power and Soul Shards
    -- are intentionally event-less; the 0.25 s scan loop in Core.lua catches
    -- them, which avoids the firehose of UNIT_POWER / BAG_UPDATE in combat.
    { "UNIT_COMBO_POINTS",         DispatchUnit("OnComboPointsChanged") },
    { "RUNE_POWER_UPDATE",         Dispatch("OnRuneUpdate") },
    { "RUNE_TYPE_UPDATE",          Dispatch("OnRuneUpdate") },
}

function ns:EnableEvents()
    for _, entry in ipairs(GAMEPLAY_EVENTS) do
        ns:RegisterAddonEvent(entry[1], entry[2])
    end
end

function ns:DisableEvents()
    for _, entry in ipairs(GAMEPLAY_EVENTS) do
        ns:UnregisterAddonEvent(entry[1])
    end
end

function ns:SetAddonEnabled(enabled)
    if enabled then
        ns:EnableEvents()
    else
        ns:DisableEvents()
    end
end

ns.eventFrame = eventFrame
