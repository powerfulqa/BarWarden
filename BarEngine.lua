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

-- Valid values for visual.textFormat (see Options_Visuals schema):
--   "NAME_DURATION"  name on left, countdown on right (default)
--   "DURATION"       countdown only
--   "NAME_ONLY"      name only, no countdown
--   "NAME_STACKS"    name + stack count
--   "STACKS"         stack count only
--   "NONE"           no text at all
--
-- Valid values for visual.durationStyle:
--   "DECIMAL"   12.3           (default)
--   "SECONDS"   12
--   "MINSEC"    1:05
--   "SHORT"     1m 5s
--   "AUTO"      H:MM:SS / M:SS / X.X depending on magnitude

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
                local visual = ns:GetVisual()
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

-- Public: check whether a bar is currently running a glow-on-ready animation.
-- Used by RefreshAllBars (Core.lua) to avoid hiding a glowing bar early.
function ns:IsBarGlowing(bar)
    return activeGlows[bar] ~= nil
end

-- Public: cancel any active glow on a bar. Called during teardown so bars
-- released to the pool don't keep flashing via stale activeGlows references.
function ns:CancelBarGlow(bar)
    activeGlows[bar] = nil
end

-- ----------------------------------------------------------------------------
-- Pulse on Ready: centre-screen icon flash when a cooldown/buff expires.
-- Queues multiple pulses if several CDs expire at the same time; each plays
-- in sequence so they don't overlap.
-- ----------------------------------------------------------------------------

local PULSE_ICON_SIZE = 64
local PULSE_FADE_IN  = 0.15
local PULSE_HOLD     = 0.6
local PULSE_FADE_OUT = 0.5
local PULSE_TOTAL    = PULSE_FADE_IN + PULSE_HOLD + PULSE_FADE_OUT

local pulseFrame = CreateFrame("Frame", "BarWardenPulseFrame", UIParent)
pulseFrame:SetFrameStrata("TOOLTIP")
pulseFrame:SetFrameLevel(200)
pulseFrame:SetSize(PULSE_ICON_SIZE, PULSE_ICON_SIZE)
pulseFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
pulseFrame:Hide()

local pulseIcon = pulseFrame:CreateTexture(nil, "ARTWORK")
pulseIcon:SetAllPoints()

local pulseQueue = {}
local pulseActive = false
local pulseStartTime = 0

local function StartNextPulse()
    if #pulseQueue == 0 then
        pulseActive = false
        pulseFrame:Hide()
        return
    end
    local tex = table.remove(pulseQueue, 1)
    pulseIcon:SetTexture(tex)
    pulseIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    pulseStartTime = GetTime()
    pulseActive = true
    pulseFrame:SetAlpha(0)
    pulseFrame:Show()
end

pulseFrame:SetScript("OnUpdate", function(self, elapsed)
    if not pulseActive then return end
    local age = GetTime() - pulseStartTime

    if age < PULSE_FADE_IN then
        self:SetAlpha(age / PULSE_FADE_IN)
    elseif age < PULSE_FADE_IN + PULSE_HOLD then
        self:SetAlpha(1)
    elseif age < PULSE_TOTAL then
        self:SetAlpha(1 - (age - PULSE_FADE_IN - PULSE_HOLD) / PULSE_FADE_OUT)
    else
        StartNextPulse()
    end
end)

function ns:TriggerPulse(iconTexture)
    if not iconTexture then return end
    pulseQueue[#pulseQueue + 1] = iconTexture
    if not pulseActive then
        StartNextPulse()
    end
end

-- ----------------------------------------------------------------------------
-- FormatDuration: pure function mapping (seconds, style) → display string.
-- Extracted from Bar_OnUpdate to reduce nesting and isolate text logic.
-- ----------------------------------------------------------------------------

local function FormatDuration(remaining, style)
    if style == "SECONDS" then
        return string.format("%d", remaining)
    elseif style == "MINSEC" then
        local m = math.floor(remaining / 60)
        local s = math.floor(remaining - m * 60)
        return m > 0 and string.format("%d:%02d", m, s) or string.format("%d", s)
    elseif style == "SHORT" then
        local m = math.floor(remaining / 60)
        local s = math.floor(remaining - m * 60)
        return m > 0 and string.format("%dm %ds", m, s) or string.format("%ds", s)
    elseif style == "AUTO" then
        if remaining >= 3600 then
            local h = math.floor(remaining / 3600)
            local m = math.floor((remaining - h * 3600) / 60)
            return string.format("%d:%02d:%02d", h, m, math.floor(remaining - h * 3600 - m * 60))
        elseif remaining >= 60 then
            local m = math.floor(remaining / 60)
            local s = math.floor(remaining - m * 60)
            return string.format("%d:%02d", m, s)
        end
        return string.format("%.1f", remaining)
    end
    -- DECIMAL (default)
    return string.format("%.1f", remaining)
end

-- UpdateBarText: throttled text formatting, called from Bar_OnUpdate.
local function UpdateBarText(bar, remaining, visual)
    if not bar.timeText or not bar.timeText:IsShown() then return end

    local textFormat = visual.textFormat or "NAME_DURATION"

    if textFormat == "NAME_STACKS" or textFormat == "STACKS" then
        local stacks = bar.stacks or 0
        bar.timeText:SetText(stacks > 0 and tostring(stacks) or "")
    elseif textFormat ~= "NAME_ONLY" then
        bar.timeText:SetText(FormatDuration(remaining, visual.durationStyle or "DECIMAL"))
    end
end

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

    -- Hoist display + visual once for all per-frame work below
    local display = self.barData and self.barData.display or {}
    local visual = ns:GetVisual()

    -- Every frame: smooth bar movement
    local duration = self.duration or 1
    local progress = remaining / duration
    if progress < 0 then progress = 0 end
    if progress > 1 then progress = 1 end
    self:SetMinMaxValues(0, 1)
    self:SetValue(progress)

    -- Colour-by-time: override bar colour based on remaining seconds
    local cbtr, cbtg, cbtb = ns.GetTimeBasedColor(remaining, display, visual)
    if cbtr then
        self:SetStatusBarColor(cbtr, cbtg, cbtb)
    end

    -- Spark position: manual calculation.
    -- GetStatusBarTexture():RIGHT does not track the fill edge in WoW 3.3.5a:
    -- the texture anchor reflects the full region, not the clipped fill width.
    if self.sparkFrame and self.sparkFrame:IsShown() then
        local barWidth = self:GetWidth()
        if barWidth and barWidth > 0 then
            self.sparkFrame:ClearAllPoints()
            self.sparkFrame:SetPoint("CENTER", self, "LEFT", barWidth * progress, 0)
        end
    end

    -- Sparkle alert: flash the bar when timer is below threshold
    if display.sparkleAlert then
        local threshold = display.sparkleThreshold or 5
        if remaining <= threshold then
            local pulse = 0.65 + 0.35 * math.sin(now * 6 * math.pi)
            self:SetAlpha(pulse)
        else
            self:SetAlpha(visual.activeAlpha or 1.0)
        end
    end

    -- Throttled: text formatting (10 Hz)
    self.textElapsed = (self.textElapsed or 0) + elapsed
    if self.textElapsed >= TEXT_THROTTLE then
        self.textElapsed = 0
        UpdateBarText(self, remaining, visual)
    end
end

ns.Bar_OnUpdate = Bar_OnUpdate

-- Bar-level stats recording has been replaced by the passive ActivityTracker
-- (ActivityTracker.lua). These stubs exist so ActivateBar/DeactivateBar don't
-- need conditional checks; they're simply no-ops now.
local function RecordActivation(bar) end
local function RecordDeactivation(bar) end

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
    -- Clear resource-bar flag so a bar switching from resource mode back to
    -- a time-based mode reverts to the standard OnUpdate countdown path.
    bar.isResourceBar = false

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

    local visual = ns:GetVisual()
    bar:SetAlpha(visual.activeAlpha or 1.0)

    -- Drive the icon cooldown spiral. SetCooldown expects (start, duration)
    -- where start is when the CD began; we derive it from expirationTime.
    if bar.cooldownFrame then
        if visual.showCooldownSpiral ~= false and duration and duration > 0 then
            local start = expirationTime - duration
            bar.cooldownFrame:SetCooldown(start, duration)
            bar.cooldownFrame:Show()
        else
            bar.cooldownFrame:Hide()
        end
    end

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
-- UpdateResourceBar: static/event-driven bar update for value-based resources
-- (Combo Points, Runic Power, Soul Shards).
--
-- Unlike ActivateBar (time-based countdown), this path does NOT attach
-- Bar_OnUpdate. The bar's fill is set once per call from current/max and
-- stays put until the next event or scan pass refreshes it. This prevents
-- Bar_OnUpdate from "depleting" a bar that represents a static resource
-- value (e.g. 3 of 5 combo points) over time.
--
-- Runes do NOT come through here; their cooldown is time-based so they use
-- the standard ActivateBar path.
-- ----------------------------------------------------------------------------

function ns:UpdateResourceBar(bar, current, max, icon, name, stacks)
    if not bar then return end

    local wasInactive = (bar.barState ~= BAR_STATE.ACTIVE)

    bar.isResourceBar = true
    bar.barState = BAR_STATE.ACTIVE
    bar.stacks = stacks or current or 0
    bar.expirationTime = nil
    bar.duration = max
    bar.textElapsed = nil
    bar.lingerRemaining = 0

    if wasInactive then
        RecordActivation(bar)
    end

    bar:SetMinMaxValues(0, 1)
    local progress = 0
    if max and max > 0 then
        progress = current / max
    end
    if progress < 0 then progress = 0 end
    if progress > 1 then progress = 1 end
    bar:SetValue(progress)

    -- Resource bars don't tick; updates arrive via events or the 0.25 s scan
    bar:SetScript("OnUpdate", nil)

    if ns.ApplyVisualConfig then
        ns:ApplyVisualConfig(bar)
    end

    local visual = ns:GetVisual()
    bar:SetAlpha(visual.activeAlpha or 1.0)

    if bar.iconTexture and icon then
        bar.iconTexture:SetTexture(icon)
    end
    if bar.nameText then
        bar.nameText:SetText(ns.GetBarDisplayName(bar.barData))
    end
    -- Text. Default: "current/max" (e.g. "3/5"). Runes: "Ns" countdown while
    -- on CD, blank when ready (stacks carries ceil(cdRemaining)). Respects
    -- textFormat NONE / NAME_ONLY to suppress.
    if bar.timeText then
        local textFormat = visual.textFormat or "NAME_DURATION"
        local trackMode  = bar.barData and bar.barData.trackMode
        if textFormat == "NONE" or textFormat == "NAME_ONLY" then
            bar.timeText:SetText("")
        elseif trackMode == "Runes" then
            if stacks and stacks > 0 then
                bar.timeText:SetText(string.format("%ds", stacks))
            else
                bar.timeText:SetText("")
            end
        else
            local maxLabel = (max and max > 1) and max or 1
            bar.timeText:SetText(string.format("%d/%d", current or 0, maxLabel))
        end
    end

    -- Spark is irrelevant for a static fill bar, so hide it so it doesn't sit
    -- mid-bar where a previous time-based activation left it.
    if bar.sparkFrame then
        bar.sparkFrame:Hide()
    end

    -- Cooldown spiral is meaningless on a resource bar (no countdown).
    if bar.cooldownFrame then
        bar.cooldownFrame:Hide()
    end

    bar:Show()
    activeBars[bar] = true

    local parent = bar:GetParent()
    if parent then
        if not parent:IsShown() then parent:Show() end
        MarkGroupDirty(parent)
    end
end

-- ----------------------------------------------------------------------------
-- DeactivateBar: Stop tracking and handle cleanup
-- ----------------------------------------------------------------------------

function ns:DeactivateBar(bar, skipGlow)
    if not bar then return end

    -- Record uptime for statistics before clearing state
    RecordDeactivation(bar)

    bar.barState = BAR_STATE.INACTIVE
    bar.expirationTime = nil
    bar.duration = nil
    bar.textElapsed = nil
    bar.lingerRemaining = nil
    bar.isResourceBar = false

    -- Stop OnUpdate (save CPU)
    bar:SetScript("OnUpdate", nil)

    -- Glow on ready: if enabled, flash the bar briefly to signal the spell is ready.
    -- skipGlow is true during teardown/rebuild so internal lifecycle events don't
    -- trigger glow animations as if a cooldown had just expired.
    local glowDisplay = bar.barData and bar.barData.display
    if not skipGlow and glowDisplay and glowDisplay.glowOnReady then
        activeGlows[bar] = GetTime()
        bar:SetAlpha(1.0)
        bar:Show()
        -- Trigger layout so the glowing bar gets a proper position
        local parent = bar:GetParent()
        if parent then MarkGroupDirty(parent) end
        glowTimerFrame:Show()
    end

    -- Pulse on ready: centre-screen icon flash (Doom_CooldownPulse pattern).
    -- Uses the bar's current icon texture so the user sees which spell is ready.
    if not skipGlow and glowDisplay and glowDisplay.pulseOnReady then
        local tex = bar.iconTexture and bar.iconTexture:GetTexture()
        if tex then ns:TriggerPulse(tex) end
    end

    -- Reset bar display
    bar:SetValue(0)

    -- Reset spark to the left edge so it doesn't float mid-bar on an inactive bar.
    -- OnUpdate is already stopped so nothing will reposition it until reactivation.
    if bar.sparkFrame then
        bar.sparkFrame:ClearAllPoints()
        bar.sparkFrame:SetPoint("CENTER", bar, "LEFT", 0, 0)
    end

    -- Cooldown spiral: hide so a deactivated bar doesn't keep a stale sweep.
    if bar.cooldownFrame then
        bar.cooldownFrame:Hide()
    end

    -- Keep name visible so user can see which spell the bar tracks
    if bar.nameText then
        bar.nameText:SetText(ns.GetBarDisplayName(bar.barData))
    end
    if bar.timeText then
        bar.timeText:SetText("")
    end

    -- Apply inactive alpha or hide if hideWhenInactive is set.
    -- If a glow-on-ready animation just started, defer the hide until the
    -- glow finishes; the glow timer already checks hideWhenInactive on
    -- expiry and hides + relayouts at that point. Hiding now would cause
    -- the layout to reposition other bars, then the glow timer's per-frame
    -- Show() would force this bar visible at a stale position, overlapping.
    local cond = bar.barData and bar.barData.conditions
    if cond and cond.hideWhenInactive and not activeGlows[bar] then
        bar:Hide()
    else
        local visual = ns:GetVisual()
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

    -- Hide the group frame only if EVERY bar in it is either actively hidden
    -- (hideWhenInactive=true) or currently active (tracked by ActivateBar).
    -- If any bar wants to stay visible at inactive alpha (the default when
    -- hideWhenInactive is false), the group stays visible too.
    if parent and parent.bars then
        local anyWantVisible = false
        for _, b in ipairs(parent.bars) do
            if activeBars[b] then
                anyWantVisible = true
                break
            end
            local bc = b.barData and b.barData.conditions
            if not bc or not bc.hideWhenInactive then
                anyWantVisible = true
                break
            end
        end
        if not anyWantVisible then
            parent:Hide()
        end
    end
end

-- ----------------------------------------------------------------------------
-- DeactivateAllBars: Stop all active bars (used when addon is disabled)
-- ----------------------------------------------------------------------------

function ns:DeactivateAllBars()
    for bar in pairs(activeBars) do
        ns:DeactivateBar(bar, true)  -- skipGlow: addon disable, not gameplay expiry
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
    ns:Print("Test mode ON: all bars showing 30s countdown. Type /bw test to stop.")
end

function ns:DeactivateTestMode()
    ns.testMode = false
    local bars = ns:GetAllBars()
    for _, bar in ipairs(bars) do
        if bar.isTestBar then
            ns:DeactivateBar(bar, true)  -- skipGlow: test bars aren't real cooldowns
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
    -- Check both the bar AND its parent group: a bar can be "shown"
    -- (IsShown=true) while its parent is hidden (e.g. group conditions
    -- hid the group, then RefreshAllBars re-showed the bar without
    -- re-showing the parent). In that case we must still proceed to
    -- re-show the parent.
    local parent = bar:GetParent()
    if bar:IsShown() and (not parent or parent:IsShown()) then return end
    local cond = bar.barData and bar.barData.conditions
    if cond and cond.hideWhenInactive then return end
    local visual = ns:GetVisual()
    bar:SetAlpha(visual.inactiveAlpha or 0.3)
    bar:Show()

    if parent then
        if not parent:IsShown() then
            parent:Show()
        end
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
            local barUnit = bd.unit or ((mode == "Debuff") and "target" or "player")
            if barUnit ~= unitFilter then return end
        end
    end

    -- Group-level conditions: if the group has conditions (e.g. combatOnly,
    -- hideWhileMounted) that fail, hide the bar before checking per-bar
    -- conditions. Reuses ns:EvaluateConditions since the registered checks
    -- read field names from whatever table they're given.
    local groupData = bar.frameIndex and BarWardenDB and BarWardenDB.frames
                      and BarWardenDB.frames[bar.frameIndex]
    if groupData and groupData.groupConditions then
        if not ns:EvaluateConditions(nil, groupData.groupConditions) then
            HideBarForConditions(bar)
            return
        end
    end

    -- Per-bar condition check: hide bar without disrupting tracking state
    if not BarConditionsMet(bar) then
        HideBarForConditions(bar)
        return
    end

    EnsureBarVisible(bar)

    -- Dispatch to canonical tracker (Trackers.lua)
    local isActive, remaining, duration, icon, name, stacks = ns:CheckTracker(bd)

    -- Event-driven resource bars (Combo Points, Runic Power, Soul Shards).
    -- These use UpdateResourceBar instead of ActivateBar so Bar_OnUpdate's
    -- time-based depletion never runs on them. Runes are time-based and fall
    -- through to the standard path below.
    if ns:IsResourceTrackMode(bd.trackMode) then
        if isActive then
            ns:UpdateResourceBar(bar, remaining, duration, icon, name, stacks)
        elseif bar.barState == BAR_STATE.ACTIVE then
            ns:DeactivateBar(bar)
        end
        return
    end

    -- Tracker reports active: activate or update the bar
    if isActive and remaining and remaining > 0 then
        local expirationTime = GetTime() + remaining
        -- 0.05s tolerance suppresses redundant ActivateBar calls from server jitter
        if bar.barState ~= BAR_STATE.ACTIVE
           or math.abs((bar.expirationTime or 0) - expirationTime) > 0.05 then
            ns:ActivateBar(bar, expirationTime, duration or remaining)
        end
        if bar.iconTexture and icon then bar.iconTexture:SetTexture(icon) end
        if bar.nameText then bar.nameText:SetText(ns.GetBarDisplayName(bd)) end
        return
    end

    -- Tracker reports inactive: deactivate (with optional linger)
    if bar.barState ~= BAR_STATE.ACTIVE then return end

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

    -- Post-scan: hide group frames whose bars are ALL hidden (e.g. the whole
    -- group failed a group-level condition). Without this, the group backdrop
    -- and title bar would linger visually even though every bar inside is gone.
    for _, group in pairs(ns.groupFrames) do
        if group:IsShown() and group.bars then
            local anyVisible = false
            for _, b in ipairs(group.bars) do
                if b:IsShown() then anyVisible = true; break end
            end
            if not anyVisible then group:Hide() end
        end
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
    RunScan(function()
        for _, bar in ipairs(bars) do
            if bar.barData and bar.barData.trackMode == "Cooldown" then
                ScanBar(bar, nil)
            end
        end
    end)
end

function ns:OnUnitAura(unit)
    -- Activity tracking: passive aura monitoring
    if unit == "player" and ns.ScanBuffActivity then ns:ScanBuffActivity() end
    if unit == "target" and ns.ScanDebuffActivity then ns:ScanDebuffActivity() end

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
    -- Activity tracking: re-scan debuffs on the new target
    if ns.ScanDebuffActivity then ns:ScanDebuffActivity() end

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
    if ns.ScanEnchantActivity then ns:ScanEnchantActivity() end

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
    if ns.ScanTotemActivity then ns:ScanTotemActivity() end

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

-- Resource events: re-scan only bars whose trackMode matches the event source.
-- Runic Power and Soul Shards are picked up by the 0.25 s OnUpdate scan loop
-- (Core.lua); they deliberately don't have their own events to avoid the
-- volume of UNIT_POWER / BAG_UPDATE in raid combat.

function ns:OnComboPointsChanged(unit)
    if unit and unit ~= "player" then return end
    local bars = ns:GetAllBars()
    if not bars or #bars == 0 then return end
    RunScan(function()
        for _, bar in ipairs(bars) do
            if bar.barData and bar.barData.trackMode == "Combo Points" then
                ScanBar(bar, nil)
            end
        end
    end)
end

-- Handles both RUNE_POWER_UPDATE (cooldown state changed) and
-- RUNE_TYPE_UPDATE (death rune conversion swapped slot's type).
function ns:OnRuneUpdate()
    local bars = ns:GetAllBars()
    if not bars or #bars == 0 then return end
    RunScan(function()
        for _, bar in ipairs(bars) do
            if bar.barData and bar.barData.trackMode == "Runes" then
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
