local addonName, ns = ...

-- ============================================================================
-- Events.lua - Central event dispatcher: register/unregister, routing, throttle
-- ============================================================================

local eventFrame = CreateFrame("Frame", "BarWardenEventFrame", UIParent)
local registeredEvents = {}
local eventHandlers = {}
local throttleTimers = {}

local UNIT_HEALTH_THROTTLE = 0.25 -- 4 Hz max

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
end

-- Rate-limit a handler: at most one call per `interval` seconds.
local function ThrottledHandler(event, interval, handler)
    return function(evt, ...)
        local now = GetTime()
        local last = throttleTimers[event] or 0
        if now - last < interval then return end
        throttleTimers[event] = now
        handler(evt, ...)
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
    { "UNIT_AURA",                 DispatchUnit("OnUnitAura") },
    { "PLAYER_TARGET_CHANGED",     DispatchFixed("OnTargetChanged", "target") },
    { "PLAYER_FOCUS_CHANGED",      DispatchFixed("OnFocusChanged",  "focus") },
    { "PLAYER_REGEN_ENABLED",      OnCombatStateChanged },
    { "PLAYER_REGEN_DISABLED",     OnCombatStateChanged },
    { "UNIT_HEALTH",               ThrottledHandler("UNIT_HEALTH", UNIT_HEALTH_THROTTLE, DispatchUnit("OnUnitHealth")) },
    { "PARTY_MEMBERS_CHANGED",     Dispatch("OnGroupChanged") },
    { "RAID_ROSTER_UPDATE",        Dispatch("OnGroupChanged") },
    { "BAG_UPDATE_COOLDOWN",       Dispatch("OnBagCooldownUpdate") },
    { "PLAYER_ENTERING_WORLD",     Dispatch("OnPlayerEnteringWorld") },
    { "UNIT_INVENTORY_CHANGED",    Dispatch("OnEnchantUpdate") },
    { "PLAYER_TOTEM_UPDATE",       Dispatch("OnTotemUpdate") },
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
