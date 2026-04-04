local addonName, ns = ...

-- ============================================================================
-- Events.lua - Central event dispatcher: register/unregister, routing, throttle
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Event Frame
-- ----------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame", "BarWardenEventFrame", UIParent)
local registeredEvents = {}
local eventHandlers = {}
local throttleTimers = {}

-- ----------------------------------------------------------------------------
-- Throttle Configuration
-- ----------------------------------------------------------------------------

local UNIT_HEALTH_THROTTLE = 0.25 -- 4 Hz max

-- ----------------------------------------------------------------------------
-- Event Handler Routing Table
-- ----------------------------------------------------------------------------

local function OnEvent(self, event, ...)
    local handler = eventHandlers[event]
    if handler then
        handler(event, ...)
    end
end

eventFrame:SetScript("OnEvent", OnEvent)

-- ----------------------------------------------------------------------------
-- Event Registration Wrappers
-- ----------------------------------------------------------------------------

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

-- ----------------------------------------------------------------------------
-- Throttled Handler Wrapper
-- ----------------------------------------------------------------------------

local function ThrottledHandler(event, interval, handler)
    return function(evt, ...)
        local now = GetTime()
        local last = throttleTimers[event] or 0
        if now - last < interval then
            return
        end
        throttleTimers[event] = now
        handler(evt, ...)
    end
end

-- ----------------------------------------------------------------------------
-- Core Event Handlers
-- ----------------------------------------------------------------------------

local function OnSpellCooldownUpdate(event, ...)
    if ns.OnSpellCooldownUpdate then
        ns:OnSpellCooldownUpdate()
    end
end

local function OnUnitAura(event, unit)
    if ns.OnUnitAura then
        ns:OnUnitAura(unit)
    end
end

local function OnTargetChanged(event, ...)
    if ns.OnTargetChanged then
        ns:OnTargetChanged("target")
    end
end

local function OnFocusChanged(event, ...)
    if ns.OnFocusChanged then
        ns:OnFocusChanged("focus")
    end
end

local function OnCombatStateChanged(event, ...)
    if ns.OnCombatStateChanged then
        ns:OnCombatStateChanged(event == "PLAYER_REGEN_DISABLED")
    end
end

local function OnUnitHealth(event, unit)
    if ns.OnUnitHealth then
        ns:OnUnitHealth(unit)
    end
end

local function OnGroupChanged(event, ...)
    if ns.OnGroupChanged then
        ns:OnGroupChanged()
    end
end

local function OnBagCooldownUpdate(event, ...)
    if ns.OnBagCooldownUpdate then
        ns:OnBagCooldownUpdate()
    end
end

local function OnPlayerEnteringWorld(event, ...)
    if ns.OnPlayerEnteringWorld then
        ns:OnPlayerEnteringWorld()
    end
end

local function OnActionbarCooldownUpdate(event, ...)
    if ns.OnSpellCooldownUpdate then
        ns:OnSpellCooldownUpdate()
    end
end

-- ----------------------------------------------------------------------------
-- Event Registration Sets
-- ----------------------------------------------------------------------------

local GAMEPLAY_EVENTS = {
    { "SPELL_UPDATE_COOLDOWN",          OnSpellCooldownUpdate },
    { "ACTIONBAR_UPDATE_COOLDOWN",      OnActionbarCooldownUpdate },
    { "UNIT_AURA",                      OnUnitAura },
    { "PLAYER_TARGET_CHANGED",          OnTargetChanged },
    { "PLAYER_FOCUS_CHANGED",           OnFocusChanged },
    { "PLAYER_REGEN_ENABLED",           OnCombatStateChanged },
    { "PLAYER_REGEN_DISABLED",          OnCombatStateChanged },
    { "UNIT_HEALTH",                    ThrottledHandler("UNIT_HEALTH", UNIT_HEALTH_THROTTLE, OnUnitHealth) },
    { "PARTY_MEMBERS_CHANGED",          OnGroupChanged },
    { "RAID_ROSTER_UPDATE",             OnGroupChanged },
    { "BAG_UPDATE_COOLDOWN",            OnBagCooldownUpdate },
    { "PLAYER_ENTERING_WORLD",          OnPlayerEnteringWorld },
}

-- ----------------------------------------------------------------------------
-- Enable / Disable All Gameplay Events
-- ----------------------------------------------------------------------------

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

-- ----------------------------------------------------------------------------
-- Global Enable / Disable (called from Core.lua)
-- ----------------------------------------------------------------------------

function ns:SetAddonEnabled(enabled)
    if enabled then
        ns:EnableEvents()
    else
        ns:DisableEvents()
    end
end

-- ----------------------------------------------------------------------------
-- Expose event frame for external use if needed
-- ----------------------------------------------------------------------------

ns.eventFrame = eventFrame
