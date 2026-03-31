local addonName, ns = ...

-- ============================================================================
-- BarEngine.lua - OnUpdate state machine, bar activation/deactivation, scanning
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Bar State Enum
-- ----------------------------------------------------------------------------

local BAR_STATE = {
    INACTIVE  = 0,
    ACTIVE    = 1,
    LINGERING = 2,
}

ns.BAR_STATE = BAR_STATE

-- ----------------------------------------------------------------------------
-- Constants
-- ----------------------------------------------------------------------------

local TEXT_THROTTLE = 0.1  -- text updates 10x/sec (10 Hz)
local GCD_THRESHOLD = 1.5  -- ignore GCD triggers

-- ----------------------------------------------------------------------------
-- Active bars registry
-- ----------------------------------------------------------------------------

local activeBars = {}
ns.activeBars = activeBars

-- Flat list of all bar WoW frames across all group frames.
-- Rebuilt by ns:RebuildAllBarsCache() called from FrameManager after
-- RebuildAllFrames. GetAllBars() returns this; without it every scan
-- gets an empty table and nothing ever tracks.
ns.allBars = {}

-- ----------------------------------------------------------------------------
-- Bar_OnUpdate: Smooth bar fill every frame, throttled text at 10 Hz
-- ----------------------------------------------------------------------------

local function Bar_OnUpdate(self, elapsed)
    local now = GetTime()

    -- Handle lingering state
    if self.barState == BAR_STATE.LINGERING then
        self.lingerRemaining = self.lingerRemaining - elapsed
        if self.lingerRemaining <= 0 then
            ns:DeactivateBar(self)
        end
        return
    end

    -- Active state
    local remaining = self.expirationTime - now
    if remaining <= 0 then
        -- Cooldown/buff has expired
        local display = self.barData and self.barData.display or {}
        local lingerTime = display.lingerTime or 0
        if lingerTime > 0 then
            -- Transition to lingering
            self.barState = BAR_STATE.LINGERING
            self.lingerRemaining = lingerTime
            self:SetValue(0)
            if self.timeText and self.timeText:IsShown() then
                self.timeText:SetText("0.0")
            end
            return
        end
        ns:DeactivateBar(self)
        return
    end

    -- Every frame: smooth bar movement
    local duration = self.duration or 1
    local progress = remaining / duration
    if progress < 0 then progress = 0 end
    if progress > 1 then progress = 1 end
    self:SetMinMaxValues(0, 1)
    self:SetValue(progress)

    -- Spark position update (every frame)
    if self.sparkFrame and self.sparkFrame:IsShown() then
        local barWidth = self:GetWidth()
        local display = self.barData and self.barData.display or {}
        local direction = display.progressDirection or "LTR"
        local sparkX
        if direction == "RTL" then
            sparkX = barWidth * (1 - progress)
        else
            sparkX = barWidth * progress
        end
        -- Clamp so the spark centre never goes outside bar bounds
        local half = (self.sparkFrame:GetWidth() or 16) * 0.5
        sparkX = math.max(half, math.min(barWidth - half, sparkX))
        self.sparkFrame:ClearAllPoints()
        self.sparkFrame:SetPoint("CENTER", self, "LEFT", sparkX, 0)
    end

    -- Throttled: expensive text formatting
    self.textElapsed = (self.textElapsed or 0) + elapsed
    if self.textElapsed >= TEXT_THROTTLE then
        self.textElapsed = 0
        if self.timeText and self.timeText:IsShown() then
            self.timeText:SetFormattedText("%.1f", remaining)
        end
    end
end

ns.Bar_OnUpdate = Bar_OnUpdate

-- ----------------------------------------------------------------------------
-- ActivateBar: Start tracking a bar with given expiration and duration
-- ----------------------------------------------------------------------------

function ns:ActivateBar(bar, expirationTime, duration)
    if not bar then return end

    bar.expirationTime = expirationTime
    bar.duration = duration
    bar.barState = BAR_STATE.ACTIVE
    bar.textElapsed = 0
    bar.lingerRemaining = 0

    -- Set initial bar range
    bar:SetMinMaxValues(0, 1)

    -- Set OnUpdate handler
    bar:SetScript("OnUpdate", Bar_OnUpdate)

    -- Ensure the parent group frame is visible (covers the showAll=false case)
    local parent = bar:GetParent()
    if parent and not parent:IsShown() then
        parent:Show()
        if ns.UpdateGroupLayout then
            ns:UpdateGroupLayout(parent)
        end
    end

    -- Apply visual config (texture, color, text) now that the bar is activating
    if ns.ApplyVisualConfig then
        ns:ApplyVisualConfig(bar)
    end

    local visual = BarWardenDB and BarWardenDB.visual or ns.DEFAULTS.visual
    bar:SetAlpha(visual.activeAlpha or 1.0)

    -- Update displayed name and icon
    if bar.nameText then
        local bd = bar.barData
        local displayName = bd and (bd.spellName or bd.name or
            (type(bd.spell) == "string" and bd.spell or nil) or "") or ""
        bar.nameText:SetText(displayName)
    end

    bar:Show()

    -- Register in active bars
    activeBars[bar] = true
end

-- ----------------------------------------------------------------------------
-- DeactivateBar: Stop tracking and handle cleanup
-- ----------------------------------------------------------------------------

function ns:DeactivateBar(bar)
    if not bar then return end

    bar.barState = BAR_STATE.INACTIVE
    bar.expirationTime = nil
    bar.duration = nil
    bar.textElapsed = nil
    bar.lingerRemaining = nil

    -- Stop OnUpdate (save CPU)
    bar:SetScript("OnUpdate", nil)

    -- Reset bar display
    bar:SetValue(0)
    -- Keep name visible so user can see which spell the bar tracks
    if bar.nameText then
        local bd = bar.barData
        local displayName = bd and (bd.spellName or bd.name or
            (type(bd.spell) == "string" and bd.spell or nil) or "") or ""
        bar.nameText:SetText(displayName)
    end
    if bar.timeText then
        bar.timeText:SetText("")
    end

    -- Apply inactive alpha or hide if hideWhenInactive is set
    local cond = bar.barData and bar.barData.conditions
    if cond and cond.hideWhenInactive then
        bar:Hide()
    else
        local visual = BarWardenDB and BarWardenDB.visual or ns.DEFAULTS.visual
        bar:SetAlpha(visual.inactiveAlpha or 0.3)
        bar:Show()
    end

    -- Remove from active bars
    activeBars[bar] = nil

    -- If showAll=false, hide the group frame once all its bars are inactive
    if BarWardenDB and not BarWardenDB.global.showAll then
        local parent = bar:GetParent()
        if parent and parent.bars then
            local anyActive = false
            for _, b in ipairs(parent.bars) do
                if activeBars[b] then
                    anyActive = true
                    break
                end
            end
            if not anyActive then
                parent:Hide()
            end
        end
    end
end

-- ----------------------------------------------------------------------------
-- DeactivateAllBars: Stop all active bars (used when addon is disabled)
-- ----------------------------------------------------------------------------

function ns:DeactivateAllBars()
    for bar in pairs(activeBars) do
        ns:DeactivateBar(bar)
    end
end

-- ----------------------------------------------------------------------------
-- Condition helper: returns true if bar should be visible right now
-- ----------------------------------------------------------------------------

local function BarConditionsMet(bar)
    if not bar.barData then return true end
    local cond = bar.barData.conditions
    if not cond then return true end
    return ns:EvaluateConditions(bar.barData, cond)
end

-- Hide a bar that fails conditions without disrupting active tracking state
local function HideBarForConditions(bar)
    bar:Hide()
    bar:SetScript("OnUpdate", nil)
    activeBars[bar] = nil
    bar.barState = BAR_STATE.INACTIVE
end

-- ----------------------------------------------------------------------------
-- Per-Mode Scan Dispatchers
-- ----------------------------------------------------------------------------

local function ScanCooldownBars(bars)
    for _, bar in ipairs(bars) do
        if bar.barData and bar.barData.trackMode == "Cooldown" and bar.barData.enabled then
            if not BarConditionsMet(bar) then
                HideBarForConditions(bar)
            else
                -- Support both old schema (.spell/.spellInput) and UI schema (.spellId/.spellName)
                local spellInput = bar.barData.spellInput or bar.barData.spell
                    or bar.barData.spellId or bar.barData.spellName
                if spellInput then
                    local start, duration, enabled = GetSpellCooldown(spellInput)
                    if enabled == 1 and duration and duration > GCD_THRESHOLD then
                        local expirationTime = start + duration
                        if bar.barState ~= BAR_STATE.ACTIVE or bar.expirationTime ~= expirationTime then
                            ns:ActivateBar(bar, expirationTime, duration)
                        end
                    elseif bar.barState == BAR_STATE.ACTIVE then
                        -- Cooldown ended or was GCD
                        local display = bar.barData.display or {}
                        local lingerTime = display.lingerTime or 0
                        if lingerTime > 0 then
                            bar.barState = BAR_STATE.LINGERING
                            bar.lingerRemaining = lingerTime
                            bar:SetValue(0)
                        else
                            ns:DeactivateBar(bar)
                        end
                    end
                end
            end
        end
    end
end

local function ScanBuffBars(bars, unit)
    for _, bar in ipairs(bars) do
        if bar.barData and bar.barData.trackMode == "Buff" and bar.barData.enabled then
            local targetUnit = bar.barData.unit or bar.barData.target or "player"
            if not unit or unit == targetUnit then
                if not BarConditionsMet(bar) then
                    HideBarForConditions(bar)
                else
                    local spellName = bar.barData.spellName or bar.barData.spellInput or bar.barData.spell
                    if spellName then
                        local found = false
                        for i = 1, 40 do
                            local name, _, _, _, _, duration, expTime = UnitBuff(targetUnit, i)
                            if not name then break end
                            if name == spellName then
                                found = true
                                if duration and duration > 0 then
                                    if bar.barState ~= BAR_STATE.ACTIVE or bar.expirationTime ~= expTime then
                                        ns:ActivateBar(bar, expTime, duration)
                                    end
                                end
                                break
                            end
                        end
                        if not found and bar.barState == BAR_STATE.ACTIVE then
                            ns:DeactivateBar(bar)
                        end
                    end
                end
            end
        end
    end
end

local function ScanDebuffBars(bars, unit)
    for _, bar in ipairs(bars) do
        if bar.barData and bar.barData.trackMode == "Debuff" and bar.barData.enabled then
            local targetUnit = bar.barData.unit or bar.barData.target or "target"
            if not unit or unit == targetUnit then
                if not BarConditionsMet(bar) then
                    HideBarForConditions(bar)
                else
                    local spellName = bar.barData.spellName or bar.barData.spellInput or bar.barData.spell
                    if spellName then
                        local found = false
                        for i = 1, 40 do
                            local name, _, _, _, _, duration, expTime = UnitDebuff(targetUnit, i)
                            if not name then break end
                            if name == spellName then
                                found = true
                                if duration and duration > 0 then
                                    if bar.barState ~= BAR_STATE.ACTIVE or bar.expirationTime ~= expTime then
                                        ns:ActivateBar(bar, expTime, duration)
                                    end
                                end
                                break
                            end
                        end
                        if not found and bar.barState == BAR_STATE.ACTIVE then
                            ns:DeactivateBar(bar)
                        end
                    end
                end
            end
        end
    end
end

local function ScanItemBars(bars)
    for _, bar in ipairs(bars) do
        if bar.barData and bar.barData.trackMode == "Item" and bar.barData.enabled then
            if not BarConditionsMet(bar) then
                HideBarForConditions(bar)
            else
                local itemId = bar.barData.itemId or bar.barData.spellInput
                    or bar.barData.spell or bar.barData.spellId or bar.barData.spellName
                if itemId then
                    local start, duration, enabled = GetItemCooldown(itemId)
                    if enabled == 1 and duration and duration > GCD_THRESHOLD then
                        local expirationTime = start + duration
                        if bar.barState ~= BAR_STATE.ACTIVE or bar.expirationTime ~= expirationTime then
                            ns:ActivateBar(bar, expirationTime, duration)
                        end
                    elseif bar.barState == BAR_STATE.ACTIVE then
                        ns:DeactivateBar(bar)
                    end
                end
            end
        end
    end
end

-- ----------------------------------------------------------------------------
-- ScanAllBars: Check all registered bars against current game state
-- ----------------------------------------------------------------------------

function ns:ScanAllBars(unit)
    local bars = ns:GetAllBars()
    if not bars or #bars == 0 then return end

    ScanCooldownBars(bars)
    ScanBuffBars(bars, unit)
    ScanDebuffBars(bars, unit)
    ScanItemBars(bars)
end

-- ----------------------------------------------------------------------------
-- GetAllBars: Retrieve all bar frames from registered frames
-- Returns a flat list of all bar frames across all groups
-- ----------------------------------------------------------------------------

-- RebuildAllBarsCache: flatten all group frame bar lists into ns.allBars.
-- Must be called after RebuildAllFrames / BuildBarsForFrame in FrameManager.
function ns:RebuildAllBarsCache()
    local flat = {}
    for _, group in pairs(ns.groupFrames or {}) do
        if group.bars then
            for _, bar in ipairs(group.bars) do
                flat[#flat + 1] = bar
            end
        end
    end
    ns.allBars = flat
end

function ns:GetAllBars()
    return ns.allBars or {}
end

-- ----------------------------------------------------------------------------
-- Event Handler Hooks (called from Events.lua dispatch)
-- ----------------------------------------------------------------------------

function ns:OnSpellCooldownUpdate()
    local bars = ns:GetAllBars()
    if bars and #bars > 0 then
        ScanCooldownBars(bars)
    end
end

function ns:OnUnitAura(unit)
    local bars = ns:GetAllBars()
    if bars and #bars > 0 then
        ScanBuffBars(bars, unit)
        ScanDebuffBars(bars, unit)
    end
end

function ns:OnTargetChanged(unit)
    local bars = ns:GetAllBars()
    if bars and #bars > 0 then
        ScanDebuffBars(bars, "target")
        ScanBuffBars(bars, "target")
    end
end

function ns:OnFocusChanged(unit)
    local bars = ns:GetAllBars()
    if bars and #bars > 0 then
        ScanDebuffBars(bars, "focus")
        ScanBuffBars(bars, "focus")
    end
end

function ns:OnBagCooldownUpdate()
    local bars = ns:GetAllBars()
    if bars and #bars > 0 then
        ScanItemBars(bars)
    end
end

function ns:OnPlayerEnteringWorld()
    ns:ScanAllBars()
end

function ns:OnCombatStateChanged(inCombat)
    -- Re-evaluate conditions for combat-gated bars
    ns:ScanAllBars()
end

function ns:OnGroupChanged()
    -- Re-evaluate conditions for group/raid-gated bars
    ns:ScanAllBars()
end

function ns:OnUnitHealth(unit)
    -- Re-evaluate health-threshold conditions
    local bars = ns:GetAllBars()
    if bars and #bars > 0 then
        ScanBuffBars(bars, unit)
        ScanDebuffBars(bars, unit)
    end
end
