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
-- Deferred Layout
-- During a scan pass many bars may change visibility in the same group.
-- Rather than calling UpdateGroupLayout after every individual change
-- (which thrashes the layout and can size bars before they are shown),
-- we mark groups dirty and flush once at the end of the scan.
-- Code paths that run OUTSIDE a scan (e.g. Bar_OnUpdate expiry, manual
-- refresh) call UpdateGroupLayout directly.
-- ----------------------------------------------------------------------------

local dirtyGroups = {}
local scanDepth = 0  -- >0 means we are inside a scan pass

local function MarkGroupDirty(group)
    if not group then return end
    if scanDepth > 0 then
        dirtyGroups[group] = true
    else
        -- Outside a scan pass: apply immediately
        if ns.UpdateGroupLayout then
            ns:UpdateGroupLayout(group)
        end
    end
end

local function FlushDirtyLayouts()
    for group in pairs(dirtyGroups) do
        if ns.UpdateGroupLayout then
            ns:UpdateGroupLayout(group)
        end
    end
    wipe(dirtyGroups)
end

-- Wrap a scan body: increment depth, run fn, decrement, flush on exit.
local function RunScan(fn, ...)
    scanDepth = scanDepth + 1
    fn(...)
    scanDepth = scanDepth - 1
    if scanDepth == 0 then
        FlushDirtyLayouts()
    end
end

-- ----------------------------------------------------------------------------
-- Glow on Ready: animate glow texture for ~3 seconds after cooldown/buff ends.
-- Uses a standalone timer frame so it works even when the bar is hidden.
-- ----------------------------------------------------------------------------
local DEFAULT_GLOW_DURATION = 3.0
local glowTimerFrame = CreateFrame("Frame", "BarWardenGlowTimer", UIParent)
glowTimerFrame:Hide()
local activeGlows = {}

glowTimerFrame:SetScript("OnUpdate", function(self, elapsed)
    local now = GetTime()
    local anyActive = false
    for bar, startTime in pairs(activeGlows) do
        local glowDur = (bar.barData and bar.barData.display and bar.barData.display.glowDuration) or DEFAULT_GLOW_DURATION
        local age = now - startTime
        if age >= glowDur then
            -- Restore normal state: re-apply visuals and re-hide if needed
            if ns.ApplyVisualConfig then ns:ApplyVisualConfig(bar) end
            local cond = bar.barData and bar.barData.conditions
            if cond and cond.hideWhenInactive and bar.barState == BAR_STATE.INACTIVE then
                bar:Hide()
                local parent = bar:GetParent()
                if parent and parent:IsShown() then
                    MarkGroupDirty(parent)
                end
            else
                local visual = BarWardenDB and BarWardenDB.visual or ns.DEFAULTS.visual
                bar:SetAlpha(visual.inactiveAlpha or 0.3)
            end
            activeGlows[bar] = nil
        else
            anyActive = true
            -- Flash the entire bar between white and normal colour
            local pulse = 0.5 + 0.5 * math.sin(age * 6 * math.pi)
            bar:SetStatusBarColor(1, 1, 1, pulse)
            bar:SetAlpha(0.6 + 0.4 * pulse)
            bar:Show()
        end
    end
    if not anyActive then self:Hide() end
end)

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

    -- Colour-by-time: override bar colour based on remaining seconds
    local display = self.barData and self.barData.display or {}
    local visual  = BarWardenDB and BarWardenDB.visual or ns.DEFAULTS.visual
    local cbtr, cbtg, cbtb = ns.GetTimeBasedColor(remaining, display, visual)
    if cbtr then
        self:SetStatusBarColor(cbtr, cbtg, cbtb)
    end

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

    -- Sparkle alert: flash the bar when timer is below threshold
    if display and display.sparkleAlert then
        local threshold = display.sparkleThreshold or 5
        if remaining <= threshold then
            -- Pulse between 0.3 and 1.0 alpha using a sine wave (~3 Hz)
            local pulse = 0.65 + 0.35 * math.sin(now * 6 * math.pi)
            self:SetAlpha(pulse)
        else
            -- Restore normal active alpha when above threshold
            local visual = BarWardenDB and BarWardenDB.visual or ns.DEFAULTS.visual
            self:SetAlpha(visual.activeAlpha or 1.0)
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
            -- NAME_DURATION, DURATION, or anything else: show countdown
            if self.timeText and self.timeText:IsShown() then
                local style = visual.durationStyle or "DECIMAL"
                local text
                if style == "SECONDS" then
                    text = string.format("%d", remaining)
                elseif style == "MINSEC" then
                    local m = math.floor(remaining / 60)
                    local s = math.floor(remaining - m * 60)
                    if m > 0 then
                        text = string.format("%d:%02d", m, s)
                    else
                        text = string.format("%d", s)
                    end
                elseif style == "SHORT" then
                    local m = math.floor(remaining / 60)
                    local s = math.floor(remaining - m * 60)
                    if m > 0 then
                        text = string.format("%dm %ds", m, s)
                    else
                        text = string.format("%ds", s)
                    end
                elseif style == "AUTO" then
                    if remaining >= 3600 then
                        local h = math.floor(remaining / 3600)
                        local m = math.floor((remaining - h * 3600) / 60)
                        text = string.format("%d:%02d:%02d", h, m, math.floor(remaining - h * 3600 - m * 60))
                    elseif remaining >= 60 then
                        local m = math.floor(remaining / 60)
                        local s = math.floor(remaining - m * 60)
                        text = string.format("%d:%02d", m, s)
                    else
                        text = string.format("%.1f", remaining)
                    end
                else -- DECIMAL (default)
                    text = string.format("%.1f", remaining)
                end
                self.timeText:SetText(text)
            end
        end
    end
end

ns.Bar_OnUpdate = Bar_OnUpdate

-- ----------------------------------------------------------------------------
-- Statistics: Build a stable key for per-bar stat tracking
-- Key format: "GroupName:TrackMode:SpellIdentifier"
-- ----------------------------------------------------------------------------

function ns:GetBarStatsKey(bar)
    local bd = bar.barData
    if not bd then return nil end
    local parent = bar:GetParent()
    local groupName = "Unknown"
    if parent and parent.frameIndex then
        local frameData = BarWardenDB and BarWardenDB.frames and BarWardenDB.frames[parent.frameIndex]
        if frameData then groupName = frameData.name or groupName end
    end
    local mode = bd.trackMode or "Unknown"
    local id = bd.spellName or bd.spellId or bd.itemId or "Unknown"
    return groupName .. ":" .. mode .. ":" .. tostring(id)
end

local function RecordActivation(bar)
    local key = ns:GetBarStatsKey(bar)
    if not key then return end

    bar.activatedAt = GetTime()

    -- Session stats
    if ns.sessionStats then
        if not ns.sessionStats[key] then
            ns.sessionStats[key] = { activations = 0, uptime = 0 }
        end
        ns.sessionStats[key].activations = ns.sessionStats[key].activations + 1
    end

    -- Persistent stats
    if ns.db and ns.db.stats then
        if not ns.db.stats[key] then
            ns.db.stats[key] = { activations = 0, uptime = 0 }
        end
        ns.db.stats[key].activations = ns.db.stats[key].activations + 1
    end
end

local function RecordDeactivation(bar)
    if not bar.activatedAt then return end
    local elapsed = GetTime() - bar.activatedAt
    if elapsed <= 0 then bar.activatedAt = nil; return end

    local key = ns:GetBarStatsKey(bar)
    if not key then bar.activatedAt = nil; return end

    -- Session stats
    if ns.sessionStats and ns.sessionStats[key] then
        ns.sessionStats[key].uptime = ns.sessionStats[key].uptime + elapsed
    end

    -- Persistent stats
    if ns.db and ns.db.stats and ns.db.stats[key] then
        ns.db.stats[key].uptime = ns.db.stats[key].uptime + elapsed
    end

    bar.activatedAt = nil
end

-- ----------------------------------------------------------------------------
-- ActivateBar: Start tracking a bar with given expiration and duration
-- ----------------------------------------------------------------------------

function ns:ActivateBar(bar, expirationTime, duration)
    if not bar then return end

    local wasAlreadyActive = (bar.barState == BAR_STATE.ACTIVE)

    bar.expirationTime = expirationTime
    bar.duration = duration
    bar.barState = BAR_STATE.ACTIVE
    bar.textElapsed = 0
    bar.lingerRemaining = 0

    -- Only record stats on fresh activations, not expiry-drift re-entries
    if not wasAlreadyActive then
        RecordActivation(bar)
    end

    -- Set initial bar range
    bar:SetMinMaxValues(0, 1)

    -- Set OnUpdate handler
    bar:SetScript("OnUpdate", Bar_OnUpdate)

    -- Apply visual config (texture, color, text) now that the bar is activating
    if ns.ApplyVisualConfig then
        ns:ApplyVisualConfig(bar)
    end

    -- Icon and name are set by the caller (ScanBar) from CheckTracker results.

    local visual = BarWardenDB and BarWardenDB.visual or ns.DEFAULTS.visual
    bar:SetAlpha(visual.activeAlpha or 1.0)

    -- Name is set by caller; here we ensure the field is non-nil at minimum.
    if bar.nameText and bar.nameText:GetText() == "" then
        bar.nameText:SetText(ns.GetBarDisplayName(bar.barData))
    end

    -- Show the bar BEFORE requesting layout so that UpdateGroupLayout includes
    -- this bar when computing positions and sizes.  The previous ordering called
    -- UpdateGroupLayout while the bar was still hidden, causing it to appear at
    -- the stale template size (200x20) until the next layout pass.
    bar:Show()

    -- Register in active bars
    activeBars[bar] = true

    -- Ensure the parent group frame is visible and request layout
    local parent = bar:GetParent()
    if parent then
        if not parent:IsShown() then
            parent:Show()
        end
        MarkGroupDirty(parent)
    end
end

-- ----------------------------------------------------------------------------
-- DeactivateBar: Stop tracking and handle cleanup
-- ----------------------------------------------------------------------------

function ns:DeactivateBar(bar)
    if not bar then return end

    -- Record uptime for statistics before clearing state
    RecordDeactivation(bar)

    bar.barState = BAR_STATE.INACTIVE
    bar.expirationTime = nil
    bar.duration = nil
    bar.textElapsed = nil
    bar.lingerRemaining = nil

    -- Stop OnUpdate (save CPU)
    bar:SetScript("OnUpdate", nil)

    -- Glow on ready: if enabled, flash the bar briefly to signal the spell is ready.
    -- Uses a standalone timer frame so it works even if the bar would normally be hidden.
    local glowDisplay = bar.barData and bar.barData.display
    if glowDisplay and glowDisplay.glowOnReady then
        activeGlows[bar] = GetTime()
        bar:SetAlpha(1.0)
        bar:Show()
        -- Trigger layout so the glowing bar gets a proper position
        local parent = bar:GetParent()
        if parent then MarkGroupDirty(parent) end
        glowTimerFrame:Show()
    end

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
        bar.nameText:SetText(ns.GetBarDisplayName(bar.barData))
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

    -- Re-layout the group so bars reposition after this bar changed state.
    -- DeactivateBar can fire outside scan passes (from Bar_OnUpdate when a
    -- cooldown expires), so MarkGroupDirty handles both cases: inside a scan
    -- it defers; outside it applies immediately.
    local parent = bar:GetParent()
    if parent and parent:IsShown() then
        MarkGroupDirty(parent)
    end

    -- If showAll=false, hide the group frame once all its bars are inactive
    if BarWardenDB and not BarWardenDB.global.showAll then
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
-- Test/Preview Mode: show all bars with fake 30s timers
-- ----------------------------------------------------------------------------

ns.testMode = false

function ns:ActivateTestMode()
    ns.testMode = true
    local bars = ns:GetAllBars()
    local fakeExpiry = GetTime() + 30
    for _, bar in ipairs(bars) do
        if bar.barData and bar.barData.enabled ~= false then
            ns:ActivateBar(bar, fakeExpiry, 30)
            bar.isTestBar = true
        end
    end
    ns:Print("Test mode ON — all bars showing 30s countdown. Type /bw test to stop.")
end

function ns:DeactivateTestMode()
    ns.testMode = false
    local bars = ns:GetAllBars()
    for _, bar in ipairs(bars) do
        if bar.isTestBar then
            ns:DeactivateBar(bar)
            bar.isTestBar = nil
        end
    end
    ns:ScanAllBars()
    ns:Print("Test mode OFF.")
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

    -- Mark the parent group for re-layout
    local parent = bar:GetParent()
    if parent and parent:IsShown() then
        MarkGroupDirty(parent)
    end
end

-- Ensure a bar is shown at inactive alpha (restores it when conditions become met)
local function EnsureBarVisible(bar)
    if bar:IsShown() then return end
    local cond = bar.barData and bar.barData.conditions
    if cond and cond.hideWhenInactive then return end
    local visual = BarWardenDB and BarWardenDB.visual or ns.DEFAULTS.visual
    bar:SetAlpha(visual.inactiveAlpha or 0.3)
    bar:Show()

    local parent = bar:GetParent()
    if parent then
        -- Ensure the group frame is visible
        if not parent:IsShown() and BarWardenDB and BarWardenDB.global.showAll then
            parent:Show()
        end
        -- Mark for re-layout so the group resizes and bars reposition
        MarkGroupDirty(parent)
    end
end

-- ----------------------------------------------------------------------------
-- ScanBar: Evaluate one bar against current game state via Trackers.lua.
-- unitFilter: if set, Buff/Debuff/Proc bars targeting other units are skipped.
-- ----------------------------------------------------------------------------

local function ScanBar(bar, unitFilter)
    -- Don't overwrite test mode bars with real scan data
    if ns.testMode and bar.isTestBar then return end
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
    local isActive, remaining, duration, icon, name = ns:CheckTracker(bd)

    if isActive and remaining and remaining > 0 then
        local expirationTime = GetTime() + remaining
        -- Use 0.05s tolerance to suppress redundant ActivateBar calls from server jitter,
        -- but always sync icon and name so spell changes take effect immediately.
        if bar.barState ~= BAR_STATE.ACTIVE
           or math.abs((bar.expirationTime or 0) - expirationTime) > 0.05 then
            ns:ActivateBar(bar, expirationTime, duration or remaining)
        end
        if bar.iconTexture and icon then
            bar.iconTexture:SetTexture(icon)
        end
        if bar.nameText then
            bar.nameText:SetText(ns.GetBarDisplayName(bar.barData))
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
    RunScan(function()
        for _, bar in ipairs(bars) do
            ScanBar(bar, unit)
        end
    end)
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
    RunScan(function()
        for _, bar in ipairs(bars) do
            if bar.barData and bar.barData.trackMode == "Cooldown" then
                ScanBar(bar, nil)
            end
        end
    end)
end

function ns:OnUnitAura(unit)
    local bars = ns:GetAllBars()
    if not bars or #bars == 0 then return end
    RunScan(function()
        for _, bar in ipairs(bars) do
            local mode = bar.barData and bar.barData.trackMode
            if mode == "Buff" or mode == "Debuff" or mode == "Proc" then
                ScanBar(bar, unit)
            end
        end
    end)
end

function ns:OnTargetChanged()
    local bars = ns:GetAllBars()
    if not bars or #bars == 0 then return end
    RunScan(function()
        for _, bar in ipairs(bars) do
            local mode = bar.barData and bar.barData.trackMode
            if mode == "Buff" or mode == "Debuff" or mode == "Proc" then
                ScanBar(bar, "target")
            end
        end
    end)
end

function ns:OnFocusChanged()
    local bars = ns:GetAllBars()
    if not bars or #bars == 0 then return end
    RunScan(function()
        for _, bar in ipairs(bars) do
            local mode = bar.barData and bar.barData.trackMode
            if mode == "Buff" or mode == "Debuff" or mode == "Proc" then
                ScanBar(bar, "focus")
            end
        end
    end)
end

function ns:OnBagCooldownUpdate()
    local bars = ns:GetAllBars()
    if not bars or #bars == 0 then return end
    RunScan(function()
        for _, bar in ipairs(bars) do
            if bar.barData and bar.barData.trackMode == "Item" then
                ScanBar(bar, nil)
            end
        end
    end)
end

function ns:OnEnchantUpdate()
    local bars = ns:GetAllBars()
    if not bars or #bars == 0 then return end
    RunScan(function()
        for _, bar in ipairs(bars) do
            if bar.barData and bar.barData.trackMode == "Enchant" then
                ScanBar(bar, nil)
            end
        end
    end)
end

function ns:OnTotemUpdate()
    local bars = ns:GetAllBars()
    if not bars or #bars == 0 then return end
    RunScan(function()
        for _, bar in ipairs(bars) do
            if bar.barData and bar.barData.trackMode == "Totem" then
                ScanBar(bar, nil)
            end
        end
    end)
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
