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

    -- Spark position: manual calculation.
    -- GetStatusBarTexture():RIGHT does not track the fill edge in WoW 3.3.5a —
    -- the texture anchor reflects the full region, not the clipped fill width.
    -- Multiplying barWidth * progress gives the correct pixel offset every frame,
    -- and correctly follows mid-flight duration reductions (haste, talents, etc.).
    if self.sparkFrame and self.sparkFrame:IsShown() then
        local barWidth = self:GetWidth()
        if barWidth and barWidth > 0 then
            self.sparkFrame:ClearAllPoints()
            self.sparkFrame:SetPoint("CENTER", self, "LEFT", barWidth * progress, 0)
        end
    end

    -- Throttled: expensive text formatting (10 Hz)
    self.textElapsed = (self.textElapsed or 0) + elapsed
    if self.textElapsed >= TEXT_THROTTLE then
        self.textElapsed = 0
        local visual = BarWardenDB and BarWardenDB.visual or ns.DEFAULTS.visual
        local textFormat = visual.textFormat or "NAME_DURATION"

        if textFormat == "NAME_STACKS" or textFormat == "STACKS" then
            if self.timeText and self.timeText:IsShown() then
                local stacks = self.stacks or 0
                self.timeText:SetText(stacks > 0 and tostring(stacks) or "")
            end
        elseif textFormat ~= "NAME_ONLY" then
            -- NAME_DURATION, DURATION, or anything else: show seconds countdown
            if self.timeText and self.timeText:IsShown() then
                self.timeText:SetFormattedText("%.1f", remaining)
            end
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

    -- Apply visual config (texture, color, text) now that the bar is activating
    if ns.ApplyVisualConfig then
        ns:ApplyVisualConfig(bar)
    end

    -- Icon and name are set by the caller (ScanBar) from CheckTracker results.

    -- Ensure the parent group frame is visible and layout is updated
    local parent = bar:GetParent()
    if parent then
        if not parent:IsShown() then
            parent:Show()
        end
        if ns.UpdateGroupLayout then
            ns:UpdateGroupLayout(parent)
        end
    end

    local visual = BarWardenDB and BarWardenDB.visual or ns.DEFAULTS.visual
    bar:SetAlpha(visual.activeAlpha or 1.0)

    -- Name is set by caller; here we ensure the field is non-nil at minimum.
    if bar.nameText and bar.nameText:GetText() == "" then
        local bd = bar.barData
        local displayName = (bd and (bd.spellName or bd.name)) or ""
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

    -- Reset spark to the left edge so it doesn't float mid-bar on an inactive bar.
    -- OnUpdate is already stopped so nothing will reposition it until reactivation.
    if bar.sparkFrame then
        bar.sparkFrame:ClearAllPoints()
        bar.sparkFrame:SetPoint("CENTER", bar, "LEFT", 0, 0)
    end

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
    if bar.barState == BAR_STATE.ACTIVE then
        bar:SetScript("OnUpdate", nil)
        activeBars[bar] = nil
        bar.barState = BAR_STATE.INACTIVE
        bar:SetValue(0)
    end
    bar:Hide()
end

-- Ensure a bar is shown at inactive alpha (restores it when conditions become met)
local function EnsureBarVisible(bar)
    if bar:IsShown() then return end
    local cond = bar.barData and bar.barData.conditions
    if cond and cond.hideWhenInactive then return end
    local visual = BarWardenDB and BarWardenDB.visual or ns.DEFAULTS.visual
    bar:SetAlpha(visual.inactiveAlpha or 0.3)
    bar:Show()
    -- If showAll=true the group should always be visible
    local parent = bar:GetParent()
    if parent and not parent:IsShown() and BarWardenDB and BarWardenDB.global.showAll then
        parent:Show()
        if ns.UpdateGroupLayout then ns:UpdateGroupLayout(parent) end
    end
end

-- ----------------------------------------------------------------------------
-- ScanBar: Evaluate one bar against current game state via Trackers.lua.
-- unitFilter: if set, Buff/Debuff/Proc bars targeting other units are skipped.
-- ----------------------------------------------------------------------------

local function ScanBar(bar, unitFilter)
    local bd = bar.barData
    if not bd or bd.enabled == false then return end

    -- Unit filter: skip Buff/Debuff/Proc bars not matching the event's unit
    if unitFilter then
        local mode = bd.trackMode
        if mode == "Buff" or mode == "Debuff" or mode == "Proc" then
            local defaultUnit = (mode == "Debuff") and "target" or "player"
            local barUnit = bd.unit or defaultUnit
            if barUnit ~= unitFilter then return end
        end
    end

    -- Condition check: hide bar without disrupting tracking state
    if not BarConditionsMet(bar) then
        HideBarForConditions(bar)
        return
    end
    EnsureBarVisible(bar)

    -- Dispatch to canonical tracker (Trackers.lua)
    local isActive, remaining, duration, icon, name, stacks = ns:CheckTracker(bd)

    -- Always apply icon and name whenever the tracker resolves them — even when
    -- the spell is inactive. This ensures the icon shows on login without needing
    -- the ability to be on cooldown/active first.
    if bar.iconTexture and icon then
        bar.iconTexture:SetTexture(icon)
    end

    if isActive and remaining and remaining > 0 then
        local expirationTime = GetTime() + remaining
        -- Use 0.05s tolerance to suppress redundant ActivateBar calls from server jitter,
        -- but always sync icon and name so spell changes take effect immediately.
        if bar.barState ~= BAR_STATE.ACTIVE
           or math.abs((bar.expirationTime or 0) - expirationTime) > 0.05 then
            ns:ActivateBar(bar, expirationTime, duration or remaining)
        end
        bar.stacks = stacks or 0
        if bar.nameText and name then
            bar.nameText:SetText(name)
        end
    elseif bar.barState == BAR_STATE.ACTIVE then
        local lingerTime = (bd.display and bd.display.lingerTime) or 0
        if lingerTime > 0 then
            bar.barState = BAR_STATE.LINGERING
            bar.lingerRemaining = lingerTime
            bar:SetValue(0)
            if bar.timeText then bar.timeText:SetText("0.0") end
        else
            ns:DeactivateBar(bar)
        end
    end
end

-- ----------------------------------------------------------------------------
-- ScanAllBars: Check all registered bars against current game state.
-- unit: optional unit filter passed to ScanBar for Buff/Debuff/Proc bars.
-- ----------------------------------------------------------------------------

function ns:ScanAllBars(unit)
    local bars = ns:GetAllBars()
    if not bars or #bars == 0 then return end
    for _, bar in ipairs(bars) do
        ScanBar(bar, unit)
    end
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
-- Each handler filters bars by relevant track mode(s) to avoid wasteful scans.
-- ----------------------------------------------------------------------------

function ns:OnSpellCooldownUpdate()
    local bars = ns:GetAllBars()
    if not bars or #bars == 0 then return end
    for _, bar in ipairs(bars) do
        if bar.barData and bar.barData.trackMode == "Cooldown" then
            ScanBar(bar, nil)
        end
    end
end

function ns:OnUnitAura(unit)
    local bars = ns:GetAllBars()
    if not bars or #bars == 0 then return end
    for _, bar in ipairs(bars) do
        local mode = bar.barData and bar.barData.trackMode
        if mode == "Buff" or mode == "Debuff" or mode == "Proc" then
            ScanBar(bar, unit)
        end
    end
end

function ns:OnTargetChanged()
    local bars = ns:GetAllBars()
    if not bars or #bars == 0 then return end
    for _, bar in ipairs(bars) do
        local mode = bar.barData and bar.barData.trackMode
        if mode == "Buff" or mode == "Debuff" or mode == "Proc" then
            ScanBar(bar, "target")
        end
    end
end

function ns:OnFocusChanged()
    local bars = ns:GetAllBars()
    if not bars or #bars == 0 then return end
    for _, bar in ipairs(bars) do
        local mode = bar.barData and bar.barData.trackMode
        if mode == "Buff" or mode == "Debuff" or mode == "Proc" then
            ScanBar(bar, "focus")
        end
    end
end

function ns:OnBagCooldownUpdate()
    local bars = ns:GetAllBars()
    if not bars or #bars == 0 then return end
    for _, bar in ipairs(bars) do
        if bar.barData and bar.barData.trackMode == "Item" then
            ScanBar(bar, nil)
        end
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
    -- Re-evaluate health-threshold conditions (unit may affect requireBuff check)
    ns:ScanAllBars()
end
