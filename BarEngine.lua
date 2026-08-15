-- BarEngine.lua - Bar state machine, OnUpdate, scan loop, resource bars.
-- Author:  Serv
-- Source:  https://github.com/powerfulqa/BarWarden
-- License: see LICENSE; attribution preservation is required.

local addonName, ns = ...

-- ============================================================================
-- BarEngine.lua - OnUpdate state machine, bar activation/deactivation, scanning
-- ============================================================================

local GetTime = GetTime
local floor, sin, abs, pi = math.floor, math.sin, math.abs, math.pi
local pairs, ipairs, wipe = pairs, ipairs, wipe

-- Bar.lua loads before BarEngine.lua (see .toc), so ns.GetTimeBasedColor is
-- defined by the time this upvalue is captured at file scope. Hoisted to
-- avoid the per-frame `ns.` field lookup inside Bar_OnUpdate.
local GetTimeBasedColor = ns.GetTimeBasedColor

-- Sentinel used by Bar_OnUpdate when a bar's display table is absent. Sharing
-- a single frozen-ish empty table avoids allocating `{}` every frame.
local EMPTY_DISPLAY = {}

-- ----------------------------------------------------------------------------
-- Bar State Enum
-- ----------------------------------------------------------------------------

local BAR_STATE = {
    INACTIVE  = 0,
    ACTIVE    = 1,
    LINGERING = 2,
}

ns.BAR_STATE = BAR_STATE

-- Monotonic counter behind Sort Mode "As They Come" (FrameManager.lua's
-- CompareAppearance). Bumped only on an INACTIVE/LINGERING -> ACTIVE
-- transition (see ActivateBar / ActivateStaticBar), so a bar keeps its slot
-- through refreshes and only moves when it actually restarts.
local appearanceSeq = 0

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

-- Returns true when every bar in a group is hidden, meaning the group
-- frame itself should hide (no visible backdrop/title with nothing in it).
local function AreAllBarsHidden(group)
    if not group or not group.bars then return false end
    -- A group with no bars yet stays on screen (see UpdateGroupLayout, which
    -- gives it a solid backdrop): a new group is created at the centre of the
    -- screen, and hiding it meant the user could not tell it had been added,
    -- let alone drag it somewhere useful. It starts behaving normally as soon
    -- as it has a bar.
    if #group.bars == 0 then return false end

    for _, b in ipairs(group.bars) do
        if b:IsShown() then return false end
    end

    -- Every bar/slot is hidden - the group is "empty". Whether that hides
    -- the group's frame (and with it the title Show Group Name draws as a
    -- child of that frame) is the group's own Hide When Inactive call now,
    -- not the lock state: see ns:ShouldHideEmptyGroup (Conditions.lua) for
    -- the full truth table.
    local groupData = group.frameIndex and BarWardenDB and BarWardenDB.frames
                      and BarWardenDB.frames[group.frameIndex]
    local isUnlocked = BarWardenDB and BarWardenDB.global and not BarWardenDB.global.locked

    -- A group whose own conditions (Combat Only, Hide Mounted, etc) currently
    -- fail must hide regardless of lock state, so the auto-group unlocked
    -- carve-out below can't swallow an explicit "hide this" as if the group
    -- were merely empty. This re-runs the same check ScanBar/ScanAutoGroup
    -- already made this pass, but only for a group that reached this point
    -- with every bar hidden - never the common case of a group with visible
    -- bars, which bails out above before this line ever runs. One cheap
    -- table-driven evaluation on that reduced set is not the same cost as
    -- adding a check per bar per scan.
    local conditionsFailed = groupData and groupData.groupConditions
                              and not ns:EvaluateConditions(nil, groupData.groupConditions)

    return ns:ShouldHideEmptyGroup(groupData, group.isAutoGroup, not isUnlocked, conditionsFailed)
end

-- Wrap a scan body: increment depth, run fn, decrement, flush on exit.
-- pcall guards the body so an error inside a scan (e.g. odd private-server aura
-- data) can never leave scanDepth stuck > 0 - which would make every later
-- MarkGroupDirty defer forever and freeze all layout until /reload. The error is
-- still surfaced through the default handler (visible with scriptErrors 1).
local function RunScan(fn, ...)
    scanDepth = scanDepth + 1
    local ok, err = pcall(fn, ...)
    scanDepth = scanDepth - 1
    if scanDepth == 0 then
        FlushDirtyLayouts()
    end
    if not ok and geterrorhandler then
        geterrorhandler()(err)
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
        local barData = bar.barData
        local display = barData and barData.display
        local glowDur = (display and display.glowDuration) or DEFAULT_GLOW_DURATION
        local age = now - startTime
        if age >= glowDur then
            -- Restore normal state: re-apply visuals and re-hide if needed
            ns:ApplyVisualConfig(bar)
            if ns:ResolveHideWhenInactive(bar) and bar.barState == BAR_STATE.INACTIVE then
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
            local pulse = 0.5 + 0.5 * sin(age * 6 * pi)
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
        local m = floor(remaining / 60)
        local s = floor(remaining - m * 60)
        return m > 0 and string.format("%d:%02d", m, s) or string.format("%d", s)
    elseif style == "SHORT" then
        local m = floor(remaining / 60)
        local s = floor(remaining - m * 60)
        return m > 0 and string.format("%dm %ds", m, s) or string.format("%ds", s)
    elseif style == "AUTO" then
        if remaining >= 3600 then
            local h = floor(remaining / 3600)
            local m = floor((remaining - h * 3600) / 60)
            return string.format("%d:%02d:%02d", h, m, floor(remaining - h * 3600 - m * 60))
        elseif remaining >= 60 then
            local m = floor(remaining / 60)
            local s = floor(remaining - m * 60)
            return string.format("%d:%02d", m, s)
        end
        return string.format("%.1f", remaining)
    end
    -- DECIMAL (default)
    return string.format("%.1f", remaining)
end

-- Resolve the text format for a bar: the bar's group may override the global
-- Visuals setting, so one group can show stacks without changing every other
-- bar. Precedence is group then global (a per-bar override would slot in ahead
-- of the group if one is ever added).
function ns:GetBarTextFormat(bar)
    local visual = ns:GetVisual()
    local groupData = bar and bar.frameIndex and BarWardenDB and BarWardenDB.frames
                      and BarWardenDB.frames[bar.frameIndex]
    local groupFormat = groupData and groupData.textFormat
    if groupFormat and groupFormat ~= "" then return groupFormat end
    return visual.textFormat or "NAME_DURATION"
end

-- Show or hide the icon-corner stack badge. The single place that decides,
-- so every activation path stays consistent. Reparents between the icon and
-- the bar so the badge survives icons being turned off.
function ns:RenderBarStacks(bar)
    local fs = bar and bar.stackText
    if not fs then return end

    local visual = ns:GetVisual()
    local show = ns:ShouldShowStackBadge(bar.stacks, ns:GetBarTextFormat(bar),
                                         visual.showStacks, bar.isResourceBar)
    if not show then
        fs:Hide()
        return
    end

    -- Anchor to the icon when it is visible, otherwise fall back to the bar's
    -- own corner (a child of a hidden icon frame would be hidden too).
    local iconShown = bar.icon and bar.icon:IsShown()
    local target = iconShown and bar.icon or bar
    if fs:GetParent() ~= target then fs:SetParent(target) end
    fs:ClearAllPoints()
    if iconShown then
        fs:SetPoint("BOTTOMRIGHT", bar.icon, "BOTTOMRIGHT", -1, 1)
    else
        fs:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -2, 2)
    end

    -- Size and colour are configurable per bar, per group, or addon-wide
    -- (bar wins, then group, then the Visuals tab default) - resolved through
    -- ns:GetStackFontSize / ns:GetStackColor (Conditions.lua) rather than
    -- read off `visual` directly, same as every other bar/group override.
    -- The font itself stays fixed (not the configured bar font) so the
    -- number stays legible at any size, matching the fixed template this
    -- replaced. SetFont MUST run before SetText below: on 3.3.5a it can
    -- clear a fontstring's existing text (see the same note in
    -- ns:BuildBarsForFrame, FrameManager.lua).
    local stackFontSize = ns:GetStackFontSize(bar)
    fs:SetFont("Fonts\\ARIALN.TTF", stackFontSize, "THICKOUTLINE, MONOCHROME")
    local stackColor = ns:GetStackColor(bar)
    fs:SetTextColor(stackColor.r, stackColor.g, stackColor.b)

    fs:SetText(tostring(bar.stacks))
    fs:Show()
end

-- Static (permanent aura) bars never deplete, so they carry no OnUpdate and
-- their text is not refreshed on a timer. This must therefore be called both
-- at activation and whenever the stack count changes on an already-active
-- bar, or a stack-format bar would freeze on the count it had when it started.
function ns:UpdateStaticBarText(bar)
    if not bar or not bar.timeText then return end
    local textFormat = ns:GetBarTextFormat(bar)
    local stacks = bar.stacks or 0
    if (textFormat == "NAME_STACKS" or textFormat == "STACKS") and stacks > 0 then
        bar.timeText:SetText(tostring(stacks))
    else
        bar.timeText:SetText("")  -- permanent aura: no time to show
    end
end

-- UpdateBarText: throttled text formatting, called from Bar_OnUpdate.
local function UpdateBarText(bar, remaining, visual)
    if not bar.timeText or not bar.timeText:IsShown() then return end

    local textFormat = ns:GetBarTextFormat(bar)

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

    -- Hoist display + visual once for all per-frame work below
    local display = (self.barData and self.barData.display) or EMPTY_DISPLAY

    -- Active state
    local remaining = self.expirationTime - now
    if remaining <= 0 then
        -- Cooldown/buff has expired. ns:GetBarLingerTime (Conditions.lua)
        -- falls through to the group's Linger Time when this bar has none.
        local lingerTime = ns:GetBarLingerTime(self)
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

    local visual = ns:GetVisual()

    -- Every frame: smooth bar movement. Min/max is set to (0, 1) at bar
    -- activation (ActivateBar / UpdateResourceBar) and never changes, so we
    -- skip the redundant per-frame SetMinMaxValues call.
    local duration = self.duration or 1
    local progress = remaining / duration
    if progress < 0 then progress = 0 end
    if progress > 1 then progress = 1 end
    self:SetValue(progress)

    -- Colour-by-time / Bar Alerts: override bar colour based on remaining
    -- seconds or the alert window. self.duration (not the `duration` local
    -- above, which defaults a nil/permanent bar to 1) is passed through
    -- verbatim so percent-mode alerts read a static bar's true "no full
    -- length" state instead of a false stand-in.
    local cbtr, cbtg, cbtb = GetTimeBasedColor(remaining, display, visual, self.duration)
    if cbtr then
        self:SetStatusBarColor(cbtr, cbtg, cbtb)
    end

    -- Spark position: manual calculation.
    -- GetStatusBarTexture():RIGHT does not track the fill edge in WoW 3.3.5a:
    -- the texture anchor reflects the full region, not the clipped fill width.
    -- Cache the integer pixel position to avoid ClearAllPoints/SetPoint every frame.
    if self.sparkFrame and self.sparkFrame:IsShown() then
        local barWidth = self:GetWidth()
        if barWidth and barWidth > 0 then
            local sparkX = floor(barWidth * progress + 0.5)
            if sparkX ~= self._lastSparkX then
                self._lastSparkX = sparkX
                self.sparkFrame:ClearAllPoints()
                self.sparkFrame:SetPoint("CENTER", self, "LEFT", sparkX, 0)
            end
        end
    end

    -- Bar Alerts: flash the bar once inside its alert window, provided the
    -- chosen action includes Sparkle. ns:IsBarAlerting (Conditions.lua) is
    -- the single source of truth for "inside the window" (seconds vs.
    -- percent), so that arithmetic lives in one pure, tested place instead
    -- of being re-derived here; a Colour-only action must not flash at all.
    if display.sparkleAlert then
        local alerting = ns:IsBarAlerting(display, remaining, self.duration)
        local action = display.alertAction or "SPARKLE"
        if alerting and (action == "SPARKLE" or action == "BOTH") then
            local pulse = 0.65 + 0.35 * sin(now * 6 * pi)
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

-- ----------------------------------------------------------------------------
-- ActivateBar: Start tracking a bar with given expiration and duration
-- ----------------------------------------------------------------------------

function ns:ActivateBar(bar, expirationTime, duration)
    if not bar then return end

    ns:CancelBarGlow(bar)

    -- Sort Mode "As They Come" orders bars by when they started, so the stamp
    -- must survive refreshes: only a bar that was not already running takes a
    -- new one. Read barState BEFORE the assignment below overwrites it.
    if bar.barState ~= BAR_STATE.ACTIVE then
        appearanceSeq = appearanceSeq + 1
        bar.appearanceOrder = appearanceSeq
    end

    bar.expirationTime = expirationTime
    bar.duration = duration
    bar.barState = BAR_STATE.ACTIVE
    bar.textElapsed = 0
    bar.lingerRemaining = 0
    -- Clear resource-bar flag so a bar switching from resource mode back to
    -- a time-based mode reverts to the standard OnUpdate countdown path.
    bar.isResourceBar = false
    bar.isStaticBar = false

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

    bar.isResourceBar = true
    bar.isStaticBar = false
    bar.barState = BAR_STATE.ACTIVE
    bar.stacks = stacks or current or 0
    bar.expirationTime = nil
    bar.duration = max
    bar.textElapsed = nil
    bar.lingerRemaining = 0

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
    --
    -- The resources auto-track group's Value Text setting (group.
    -- autoResourceValueText: nil/"" current-max, "PERCENT", "BOTH") overrides
    -- the default current/max rendering below. It is group-only with no
    -- per-bar equivalent (like `iconOnly`; see docs/ADDON_GUIDE.md's group
    -- overrides table), so it is read straight off groupData here rather
    -- than through a dedicated resolver, and a hand-placed resource bar with
    -- no such group setting keeps exactly its previous current/max text.
    if bar.timeText then
        local textFormat = ns:GetBarTextFormat(bar)
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
            local groupData = bar.frameIndex and BarWardenDB and BarWardenDB.frames
                              and BarWardenDB.frames[bar.frameIndex]
            local valueText = groupData and groupData.autoResourceValueText
            if valueText == "PERCENT" or valueText == "BOTH" then
                local percent = 0
                if maxLabel > 0 then
                    percent = floor(((current or 0) / maxLabel) * 100 + 0.5)
                end
                if valueText == "PERCENT" then
                    bar.timeText:SetText(string.format("%d%%", percent))
                else
                    bar.timeText:SetText(string.format("%d/%d (%d%%)", current or 0, maxLabel, percent))
                end
            else
                bar.timeText:SetText(string.format("%d/%d", current or 0, maxLabel))
            end
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
-- ActivateStaticBar: full, non-depleting bar for a permanent (no-duration)
-- aura, used as a "present / absent" indicator. Like UpdateResourceBar it
-- attaches no OnUpdate (nothing to count down); unlike it, the fill is always
-- full and the timer text is blank (or the stack count).
-- ----------------------------------------------------------------------------

function ns:ActivateStaticBar(bar, icon, name, stacks)
    if not bar then return end
    ns:CancelBarGlow(bar)

    -- See ActivateBar: same stamp-on-transition rule for Sort Mode
    -- "As They Come", read before barState below is overwritten.
    if bar.barState ~= BAR_STATE.ACTIVE then
        appearanceSeq = appearanceSeq + 1
        bar.appearanceOrder = appearanceSeq
    end

    bar.isResourceBar = false
    bar.isStaticBar = true
    bar.barState = BAR_STATE.ACTIVE
    bar.stacks = stacks or 0
    bar.expirationTime = nil   -- no countdown
    bar.duration = nil
    bar.textElapsed = nil
    bar.lingerRemaining = 0

    bar:SetMinMaxValues(0, 1)
    bar:SetValue(1)                 -- full: the aura is present
    bar:SetScript("OnUpdate", nil)  -- static: never depletes

    if ns.ApplyVisualConfig then ns:ApplyVisualConfig(bar) end
    local visual = ns:GetVisual()
    bar:SetAlpha(visual.activeAlpha or 1.0)

    if bar.iconTexture and icon then bar.iconTexture:SetTexture(icon) end
    if bar.nameText then bar.nameText:SetText(ns.GetBarDisplayName(bar.barData)) end
    ns:UpdateStaticBarText(bar)
    if bar.sparkFrame then bar.sparkFrame:Hide() end
    if bar.cooldownFrame then bar.cooldownFrame:Hide() end

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

    bar.barState = BAR_STATE.INACTIVE
    -- Sort Mode "As They Come" stamp: this bar is no longer running, so it
    -- must not keep the slot it held. A future re-activation stamps a fresh,
    -- later order (see ActivateBar/ActivateStaticBar).
    bar.appearanceOrder = nil
    bar.expirationTime = nil
    bar.duration = nil
    bar.textElapsed = nil
    bar.lingerRemaining = nil
    bar.isResourceBar = false
    bar.isStaticBar = false
    bar.stacks = 0
    if bar.stackText then bar.stackText:Hide() end

    -- Stop OnUpdate (save CPU)
    bar:SetScript("OnUpdate", nil)

    -- Glow on ready: if enabled, flash the bar briefly to signal the spell is ready.
    -- skipGlow is true during teardown/rebuild so internal lifecycle events don't
    -- trigger glow animations as if a cooldown had just expired.
    -- ns:GetBarGlowOnReady/GetBarPulseOnReady (Conditions.lua) resolve the
    -- bar's own setting, falling through to the group's Custom Bar Effects
    -- override when the bar has none - which is the only way an auto-
    -- tracking slot (whose own display is never wired up) can glow/pulse.
    if not skipGlow and ns:GetBarGlowOnReady(bar) then
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
    if not skipGlow and ns:GetBarPulseOnReady(bar) then
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
    bar._lastSparkX = nil

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
    if not ns:IsBarEnabled(bar) then
        bar:Hide()
    elseif ns:ResolveHideWhenInactive(bar) and not activeGlows[bar] then
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

    if parent and AreAllBarsHidden(parent) then
        parent:Hide()
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
        if bar.barData and ns:IsBarEnabled(bar) then
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
    -- LINGERING counts as running too: OnUpdate does not tick on a hidden
    -- frame, so a lingering bar hidden by a condition kept its handler and its
    -- activeBars entry forever and never finished its linger.
    if bar.barState == BAR_STATE.ACTIVE or bar.barState == BAR_STATE.LINGERING then
        bar:SetScript("OnUpdate", nil)
        activeBars[bar] = nil
        bar.barState = BAR_STATE.INACTIVE
        bar.lingerRemaining = nil
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
    if ns:ResolveHideWhenInactive(bar) then return end
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

    -- Auto-tracking slots are driven by ScanAutoGroup, which writes their
    -- barData wholesale. Letting the per-bar scanner near them would have the
    -- two paths fighting over the same frame.
    if bar.isAutoBar then return end

    local bd = bar.barData
    if not bd or not ns:IsBarEnabled(bar) then return end

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
    local isActive, remaining, duration, icon, name, stacks, permanent = ns:CheckTracker(bd)

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

    -- Switch mode: show only whether the tracked thing is on, with no
    -- countdown. Reuses the static-bar path, which is already exactly this
    -- rendering for a permanent aura.
    if ns:IsSwitchBar(bar) then
        if isActive then
            if bar.barState ~= BAR_STATE.ACTIVE or not bar.isStaticBar then
                ns:ActivateStaticBar(bar, icon, name, stacks)
            else
                bar.stacks = stacks or 0
                ns:UpdateStaticBarText(bar)
            end
            ns:RenderBarStacks(bar)
        elseif bar.barState == BAR_STATE.ACTIVE or bar.barState == BAR_STATE.LINGERING then
            ns:DeactivateBar(bar)
        end
        return
    end

    -- Permanent aura present (no duration): show a static, full "present" bar.
    -- Guard on the static flag so a re-scan doesn't re-lay-out every poll tick.
    if isActive and permanent then
        if bar.barState ~= BAR_STATE.ACTIVE or not bar.isStaticBar then
            ns:ActivateStaticBar(bar, icon, name, stacks)
        else
            -- Already static: refresh the count in place. Static bars have no
            -- OnUpdate, so nothing else would redraw a changed stack count.
            bar.stacks = stacks or 0
            ns:UpdateStaticBarText(bar)
        end
        ns:RenderBarStacks(bar)
        return
    end

    -- Tracker reports active: activate or update the bar
    if isActive and remaining and remaining > 0 then
        local expirationTime = GetTime() + remaining
        -- 0.05s tolerance suppresses redundant ActivateBar calls from server jitter
        if bar.barState ~= BAR_STATE.ACTIVE
           or abs((bar.expirationTime or 0) - expirationTime) > 0.05 then
            ns:ActivateBar(bar, expirationTime, duration or remaining)
        end
        -- Keep the live stack count current even when only the stacks changed
        -- (a refresh that leaves the timer alone skips ActivateBar above). This
        -- is what the "Name + Stacks" / "Stacks Only" text formats read.
        bar.stacks = stacks or 0
        ns:RenderBarStacks(bar)
        if bar.iconTexture and icon then bar.iconTexture:SetTexture(icon) end
        if bar.nameText then bar.nameText:SetText(ns.GetBarDisplayName(bd)) end
        return
    end

    -- Tracker reports inactive: deactivate (with optional linger)
    if bar.barState ~= BAR_STATE.ACTIVE then return end

    -- ns:GetBarLingerTime falls through to the group's Linger Time when this
    -- bar has none (Conditions.lua); ScanBar never reaches an auto slot at
    -- all (bar.isAutoBar returns above), so this only matters for ordinary
    -- bars, but the resolver is nil-safe regardless.
    local lingerTime = ns:GetBarLingerTime(bar)
    -- A static (permanent-aura or switch-mode) bar carries no OnUpdate
    -- because it never depletes, and OnUpdate is the only thing that ends a
    -- linger. Letting one linger would strand it at 0 fill reading "0.0"
    -- until /reload - true whether the linger time came from the bar or, now,
    -- the group, so this guard still has to run after the resolver, not
    -- before it.
    if lingerTime > 0 and not bar.isStaticBar then
        bar.barState = BAR_STATE.LINGERING
        bar.lingerRemaining = lingerTime
        bar:SetValue(0)
        if bar.timeText then bar.timeText:SetText("0.0") end
    else
        ns:DeactivateBar(bar)
    end
end

-- ----------------------------------------------------------------------------
-- ScanAutoGroup: fill one auto-tracking group's slots from the live aura list.
--
-- unitFilter: when set (an event-driven scan), feeds for other units are left
-- alone, matching how ScanBar filters ordinary aura bars.
-- ----------------------------------------------------------------------------

-- Caches only the expensive half: one group's "already tracked elsewhere"
-- names (ns:GetTrackedAuraNames), keyed by frame index. Rebuilt lazily and
-- cleared on a full bar-cache rebuild and on any bar-settings refresh (see
-- InvalidateTrackedNames below), since either can change what counts as
-- "already tracked". Recomputing THIS per scan would walk the whole DB four
-- times a second for nothing.
--
-- The cheap half - honouring groupData.autoSkipTracked and folding in
-- groupData.autoBanned - is NOT cached: ns:BuildGroupSkipSet (Trackers.lua)
-- reruns on every scan so the setting and the ban list are always current,
-- rather than only being re-read the next time this cache happens to miss.
local trackedNamesCache = {}

-- Editing a bar's spell or its Enabled box changes what counts as "already
-- tracked", and neither path rebuilds the bar cache. The same edits can
-- also change what ns.GetBarDisplayName (Bar.lua) resolves for a bar with
-- no name of its own, so its id->name cache is wiped alongside this one
-- rather than needing its own separate invalidation call sites.
function ns:InvalidateTrackedNames()
    wipe(trackedNamesCache)
    if ns.InvalidateBarDisplayNameCache then ns:InvalidateBarDisplayNameCache() end
end

-- ScanAutoResourceGroup: fill a "resources" feed's slots from
-- ns:CollectResources. Unlike the aura branch below, there is no spell list,
-- no expiry, and no held/keepNames placement to worry about - the collector
-- already returns a stable, deterministic order (Health, current power type,
-- class resources, pinned extras), so a slot is just entries[i].
--
-- Every occupied slot goes through ns:UpdateResourceBar, never ns:ActivateBar:
-- a resource has no expiry, so it must never take the countdown path or
-- pick up a linger (mirrors how ScanBar branches on ns:IsResourceTrackMode
-- for an ordinary hand-placed resource bar, just applied per-slot instead of
-- per-bar).
local function ScanAutoResourceGroup(group, groupData, unit)
    local entries = ns:CollectResources({ pinned = groupData.autoPinnedResources, unit = unit })

    for i, bar in ipairs(group.bars) do
        local e  = entries[i]
        local bd = bar.barData
        if e then
            bd.enabled     = true
            bd.name        = e.label
            bd.spellId     = nil
            -- e.key ("mana", "health", "rune3", ...) is stamped onto the bar
            -- so GetBarColor (Bar.lua) can resolve the power-type default
            -- colour (ns:GetResourcePowerColor, Conditions.lua) without
            -- threading the collector's entry through the whole call chain.
            bd.resourceKey = e.key
            -- e.runeType (1 Blood, 2 Unholy, 3 Frost, 4 Death) is only ever
            -- set for the six rune entries; ns:GetResourcePowerColor
            -- (Conditions.lua) reads it off the bar to colour a rune by type
            -- instead of falling through to the addon-wide default.
            bd.runeType = e.runeType
            -- e.trackMode is only ever "Runes" (the six DK rune slots); every
            -- other resource leaves it nil, and UpdateResourceBar treats
            -- anything other than the literal string "Runes" the same way.
            bd.trackMode = e.trackMode or "Buff"
            ns:UpdateResourceBar(bar, e.current, e.max, e.icon, e.label, e.stacks or e.current)
        elseif bd.enabled then
            -- Slot just emptied (e.g. a rune slot that no longer applies
            -- after a spec/class change mid-session). Marking it unoccupied
            -- first sends DeactivateBar down its disabled-bar branch, which
            -- hides it instead of leaving a blank row - same as the aura
            -- branch below.
            bd.enabled     = false
            bd.name        = ""
            bd.resourceKey = nil
            bd.runeType    = nil
            ns:DeactivateBar(bar, true)
        end
    end
end

function ns:ScanAutoGroup(frameIndex, unitFilter)
    local group = ns.groupFrames and ns.groupFrames[frameIndex]
    if not group or not group.isAutoGroup or not group.bars then return end

    local groupData = BarWardenDB and BarWardenDB.frames and BarWardenDB.frames[frameIndex]
    local feed = groupData and groupData.autoTrack
    local def  = feed and ns.AUTO_TRACK_FEEDS[feed]
    if not def then return end
    if unitFilter and def.unit ~= unitFilter then return end

    -- Group conditions gate the whole feed, exactly as they gate an ordinary
    -- group's bars inside ScanBar.
    if groupData.groupConditions
       and not ns:EvaluateConditions(nil, groupData.groupConditions) then
        for _, bar in ipairs(group.bars) do
            HideBarForConditions(bar)
        end
        return
    end

    if def.kind == "resource" then
        ScanAutoResourceGroup(group, groupData, def.unit)
        return
    end

    -- Read the setting BEFORE consulting the cache, so the expensive
    -- GetTrackedAuraNames lookup is skipped whenever the group has no use
    -- for it, while ns:BuildGroupSkipSet below still runs fresh every scan
    -- and re-checks this same setting itself.
    local tracked
    if groupData.autoSkipTracked then
        tracked = trackedNamesCache[frameIndex]
        if not tracked then
            tracked = ns:GetTrackedAuraNames(frameIndex)
            trackedNamesCache[frameIndex] = tracked
        end
    end
    local skipNames = ns:BuildGroupSkipSet(groupData, tracked)

    -- Gathered before the collect call so a still-held aura can be told apart
    -- from a merely short-lived one: without keepNames, CollectAutoAuras
    -- truncates by expiry alone and a held aura sitting outside the soonest-N
    -- would be cut before PlaceAutoAuras ever sees it, then read back as
    -- faded and free its slot. That is the exact reshuffle this option exists
    -- to stop.
    local held, keepNames
    if groupData.autoStableOrder then
        held = {}
        keepNames = {}
        for i, bar in ipairs(group.bars) do
            local bd = bar.barData
            -- A slot is occupied only while its bar is enabled; `enabled`
            -- doubles as the occupied flag for an auto slot.
            if bd and bd.enabled and bd.name ~= "" then
                held[i] = bd.name
                keepNames[string.lower(bd.name)] = true
            end
        end
    end

    local auras = ns:CollectAutoAuras(feed, {
        maxBars          = #group.bars,
        maxDuration      = groupData.autoMaxDuration or 0,
        onlyMine         = groupData.autoOnlyMine,
        skipNames        = skipNames,
        keepNames        = keepNames,
        includePermanent = groupData.autoIncludePermanent,
    })

    if groupData.autoStableOrder then
        auras = ns:PlaceAutoAuras(held, auras, #group.bars)
    end

    for i, bar in ipairs(group.bars) do
        local a  = auras[i]
        local bd = bar.barData
        if a then
            -- A slot changing spell has to re-activate even when the timer
            -- happens to line up, or the bar would keep the old fill.
            local changed = (bd.name ~= a.name)
            bd.enabled   = true
            bd.name      = a.name
            bd.spellId   = a.spellId
            bd.unit      = def.unit
            bd.trackMode = (def.kind == "buff") and "Buff" or "Debuff"
            if ns:IsSwitchBar(bar) or a.permanent then
                -- No timer to compare against, so activate on any state or
                -- identity change instead of the expiry-tolerance check below.
                -- a.permanent covers Include Always On: that aura has no
                -- expiry either, so it takes the same no-countdown path as a
                -- switch-mode bar.
                if changed or bar.barState ~= BAR_STATE.ACTIVE or not bar.isStaticBar then
                    ns:ActivateStaticBar(bar, a.icon, a.name, a.count)
                end
            -- 0.05s tolerance suppresses redundant ActivateBar calls from
            -- server jitter, matching ScanBar.
            elseif changed or bar.barState ~= BAR_STATE.ACTIVE
               or abs((bar.expirationTime or 0) - a.expirationTime) > 0.05 then
                ns:ActivateBar(bar, a.expirationTime, a.duration)
            end
            bar.stacks = a.count
            -- Keep a switch-mode bar's stack text live when only the count
            -- changes: ActivateStaticBar refreshes it on activation, but a
            -- same-spell rescan skips that branch and would otherwise freeze
            -- a stack-format bar on the count it had when it filled.
            if bar.isStaticBar then ns:UpdateStaticBarText(bar) end
            ns:RenderBarStacks(bar)
            if bar.iconTexture and a.icon then bar.iconTexture:SetTexture(a.icon) end
            if bar.nameText then bar.nameText:SetText(a.name) end
        elseif bd.enabled then
            -- Slot just emptied. Marking it unoccupied first is what sends
            -- DeactivateBar down its disabled-bar branch, which hides the bar
            -- instead of leaving a blank row in the middle of the group.
            bd.enabled = false
            bd.name    = ""
            bd.spellId = nil
            ns:DeactivateBar(bar, true)
        end
    end
end

local function ScanAutoGroups(unitFilter)
    if not ns.groupFrames then return end
    for idx, group in pairs(ns.groupFrames) do
        if group.isAutoGroup then
            ns:ScanAutoGroup(idx, unitFilter)
        end
    end
end

-- ----------------------------------------------------------------------------
-- ScanAllBars: Check all registered bars against current game state.
-- unit: optional unit filter passed to ScanBar for Buff/Debuff/Proc bars.
-- ----------------------------------------------------------------------------

function ns:ScanAllBars(unit)
    local bars = ns:GetAllBars()
    -- No early return on an empty bar list: auto groups are scanned by group,
    -- not by bar, and would be skipped by one.
    RunScan(function()
        for _, bar in ipairs(bars or {}) do
            ScanBar(bar, unit)
        end
        ScanAutoGroups(unit)
    end)

    -- Post-scan: hide group frames whose bars are ALL hidden (e.g. the whole
    -- group failed a group-level condition). Without this, the group backdrop
    -- and title bar would linger visually even though every bar inside is gone.
    for _, group in pairs(ns.groupFrames) do
        if group:IsShown() and AreAllBarsHidden(group) then
            group:Hide()
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
    -- Bars just changed, so which spells are "already tracked" may have too.
    wipe(trackedNamesCache)
    local flat = {}
    -- Most users have no auto group, and OnUnitAura/OnTargetChanged run on
    -- every throttled per-unit UNIT_AURA (hundreds of calls a second in a
    -- 25-man raid), so this flag lets those handlers skip ScanAutoGroups
    -- entirely instead of paying a RunScan + pcall for nothing.
    ns.hasAutoGroups = false
    for _, group in pairs(ns.groupFrames or {}) do
        if group.bars then
            for _, bar in ipairs(group.bars) do
                flat[#flat + 1] = bar
            end
        end
        if group.isAutoGroup then
            ns.hasAutoGroups = true
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

-- Shared scan helper: iterate all bars, scanning only those whose trackMode
-- is in the provided set. Avoids duplicating the get-bars / RunScan / filter
-- boilerplate across every event handler.
-- Mode sets are hoisted, not built per event: SPELL_UPDATE_COOLDOWN in
-- particular fires constantly in combat, and allocating a throwaway table for
-- every one of these handlers was needless garbage on a hot path.
local AURA_MODES     = ns.AURA_TRACK_MODES
local COOLDOWN_MODES = { Cooldown = true }
local ITEM_MODES     = { Item = true }
local ENCHANT_MODES  = { Enchant = true, ["Enchant MH"] = true, ["Enchant OH"] = true }
local TOTEM_MODES    = { Totem = true }
local COMBO_MODES    = { ["Combo Points"] = true }
local RUNE_MODES     = { Runes = true }

local function ScanBarsByMode(modes, unit)
    local bars = ns:GetAllBars()
    if not bars or #bars == 0 then return end
    RunScan(function()
        for _, bar in ipairs(bars) do
            local mode = bar.barData and bar.barData.trackMode
            if modes[mode] then
                ScanBar(bar, unit)
            end
        end
    end)
end

function ns:OnSpellCooldownUpdate()
    ScanBarsByMode(COOLDOWN_MODES, nil)
end

function ns:OnUnitAura(unit)
    -- Activity tracking: passive aura monitoring
    if unit == "player" and ns.ScanBuffActivity then ns:ScanBuffActivity() end
    if unit == "target" and ns.ScanDebuffActivity then ns:ScanDebuffActivity() end
    ScanBarsByMode(AURA_MODES, unit)
    -- Auto groups react on the event too, not just on the next 0.25s tick.
    if ns.hasAutoGroups then
        RunScan(ScanAutoGroups, unit)
    end
end

function ns:OnTargetChanged()
    ns:ScanDebuffActivity()
    if ns.ClearStableExpiry then ns:ClearStableExpiry("target") end
    ScanBarsByMode(AURA_MODES, "target")
    if ns.hasAutoGroups then
        RunScan(ScanAutoGroups, "target")
        -- Retargeting almost always changes who "targettarget" resolves to
        -- as well (a different creature, or none at all), and there is no
        -- PLAYER_TARGET_CHANGED-style event for that unit - only your OWN
        -- target change is ever announced. Rescanning it here removes up to
        -- one 0.25s tick of staleness on exactly the transition we already
        -- know just happened; the case this can't help with - your target
        -- switching who IT is attacking, with your own target unchanged -
        -- has no event at all on this client and is left to the periodic
        -- scan loop (see ns:OnUnitDisplayPowerChanged below for the one
        -- event that does reach it).
        RunScan(ScanAutoGroups, "targettarget")
    end
end

function ns:OnFocusChanged()
    if ns.ClearStableExpiry then ns:ClearStableExpiry("focus") end
    ScanBarsByMode(AURA_MODES, "focus")
end

function ns:OnBagCooldownUpdate()
    ScanBarsByMode(ITEM_MODES, nil)
end

function ns:OnEnchantUpdate()
    ns:ScanEnchantActivity()
    -- The UI stores "Enchant MH" / "Enchant OH"; keep the bare "Enchant" alias
    -- for any legacy bar. Without MH/OH here, enchant bars only refreshed on
    -- the 0.25s full scan instead of event-driven.
    ScanBarsByMode(ENCHANT_MODES, nil)
end

function ns:OnTotemUpdate()
    ns:ScanTotemActivity()
    ScanBarsByMode(TOTEM_MODES, nil)
end

-- Resource events: re-scan only bars whose trackMode matches the event source.
-- Runic Power and Soul Shards are picked up by the 0.25 s OnUpdate scan loop
-- (Core.lua); they deliberately don't have their own events to avoid the
-- volume of UNIT_POWER / BAG_UPDATE in raid combat.

function ns:OnComboPointsChanged(unit)
    if unit and unit ~= "player" then return end
    ScanBarsByMode(COMBO_MODES, nil)
end

-- Handles both RUNE_POWER_UPDATE (cooldown state changed) and
-- RUNE_TYPE_UPDATE (death rune conversion swapped slot's type).
function ns:OnRuneUpdate()
    ScanBarsByMode(RUNE_MODES, nil)
end

-- UNIT_DISPLAYPOWER fires when the unit's CURRENT power type changes (a
-- druid shifting Bear/Cat/Caster form, a shaman's Ghost Wolf, and so on) -
-- a handful of times per fight at most, unlike UNIT_POWER which fires on
-- every tick of every power bar and is deliberately NOT registered (see the
-- comment above OnComboPointsChanged): that volume in raid combat is exactly
-- the firehose this addon avoids. UNIT_DISPLAYPOWER's rarity is what makes it
-- safe to register outright. It IS unit-filtered the same way UNIT_AURA/
-- UNIT_HEALTH are elsewhere in this file: `unit` arrives as "target" or
-- "targettarget" when the unit that changed form is addressed that way from
-- the player's perspective, matching how Blizzard addresses every other
-- UNIT_* event here - this is the one event that DOES reach a form change
-- on your target's target directly (there is no PLAYER_TARGET_CHANGED-style
-- event for that unit at all; see ns:OnTargetChanged above for the other
-- half of keeping it current). The player's "resources" feed, the target's
-- "targetResources" feed, and the target's-target "totResources" feed all
-- read their current-power slot via UnitPowerType(unit) (ns:CollectResources,
-- Trackers.lua), so all three unit values matter now, not just "player";
-- passing `unit` through to ScanAutoGroups restricts the rescan to feeds on
-- that same unit rather than touching every auto group for an event that
-- only one of them can possibly care about. Without this, a form change
-- would still show correctly, just up to one 0.25s scan tick later -
-- registering the event only removes that tick of lag.
function ns:OnUnitDisplayPowerChanged(unit)
    if unit ~= "player" and unit ~= "target" and unit ~= "targettarget" then return end
    if ns.hasAutoGroups then
        RunScan(ScanAutoGroups, unit)
    end
end

function ns:OnPlayerEnteringWorld()
    ns:ScanAllBars()
    -- Re-resolve icons for inactive bars. GetSpellInfo(spellName) returns nil
    -- at ADDON_LOADED because the spell book isn't loaded yet, so name-based
    -- bars (Buff/Debuff/Proc) miss their icon during BuildBarsForFrame. By
    -- PLAYER_ENTERING_WORLD the spell book is ready and the lookup succeeds.
    if ns.ResolveBarIcon then
        for _, bar in ipairs(ns:GetAllBars()) do
            if bar.iconTexture and not bar.iconTexture:GetTexture() and bar.barData then
                local icon = ns.ResolveBarIcon(bar.barData)
                if icon then bar.iconTexture:SetTexture(icon) end
            end
        end
    end
end

function ns:OnCombatStateChanged(inCombat)
    -- Re-evaluate conditions for combat-gated bars
    ns:ScanAllBars()
    -- A Hide Blizzard Player/Target Frame request made mid-fight was
    -- deferred (see ns:ResolvePlayerFrameHidden, Conditions.lua);
    -- PLAYER_REGEN_ENABLED is exactly when it becomes safe to act on it, so
    -- re-apply both here too.
    if ns.ApplyPlayerFrameHidden then ns:ApplyPlayerFrameHidden() end
    if ns.ApplyTargetFrameHidden then ns:ApplyTargetFrameHidden() end
end

function ns:OnGroupChanged()
    -- Re-evaluate conditions for group/raid-gated bars
    ns:ScanAllBars()
    -- Version-probe the group so peers running BarWarden can tell us about a
    -- newer release. Channel matches the current group type; gated + throttled
    -- inside Comms.
    if ns.Comms then
        if GetNumRaidMembers() > 0 then
            ns.Comms.FireVersionProbe("RAID")
        elseif GetNumPartyMembers() > 0 then
            ns.Comms.FireVersionProbe("PARTY")
        end
    end
end

function ns:OnUnitHealth(unit)
    -- The only condition that reads unit health is `healthBelow` (Conditions.lua),
    -- which checks UnitHealth("player") exclusively. Ignore non-player ticks
    -- (party/raid) and only re-scan bars that actually opted in; otherwise a
    -- raid's worth of UNIT_HEALTH traffic would trigger full rescans at the
    -- event throttle rate for no behavioural reason.
    if unit and unit ~= "player" then return end
    local bars = ns:GetAllBars()
    if not bars or #bars == 0 then return end
    RunScan(function()
        for _, bar in ipairs(bars) do
            local bd = bar.barData
            if bd and bd.conditions and bd.conditions.healthBelow then
                ScanBar(bar, nil)
            end
        end
    end)
end
