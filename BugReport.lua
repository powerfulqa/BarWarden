-- BugReport.lua - Copyable diagnostic report frame.
-- Author:  Serv
-- Source:  https://github.com/powerfulqa/BarWarden
-- License: see LICENSE; attribution preservation is required.

local addonName, ns = ...

-- ============================================================================
-- BugReport.lua - Copyable diagnostic report frame for /bw bugreport
-- ============================================================================

local FRAME_WIDTH = 520
local FRAME_HEIGHT = 420

local reportFrame

-- ----------------------------------------------------------------------------
-- State name lookup
-- ----------------------------------------------------------------------------
local STATE_NAMES = {
    [0] = "INACTIVE",
    [1] = "ACTIVE",
    [2] = "LINGERING",
}

local FormatUptime = ns.FormatUptime

-- ----------------------------------------------------------------------------
-- Generate the report string
-- ----------------------------------------------------------------------------
-- Exposed on ns (rather than kept local) so tests/test_bug_report.lua can
-- call it directly without going through ns:ShowBugReport, which needs
-- CreateFrame and is out of scope for the logic test harness.
function ns:GenerateBugReport()
    local lines = {}
    local function add(text)
        lines[#lines + 1] = text or ""
    end

    add("=== BarWarden Bug Report ===")
    add(string.format("Version: %s", ns.version or "unknown"))
    add(string.format("Source:  %s  (by %s)", ns.url or "?", ns.author or "?"))
    add(string.format("Watermark: %s", _G["__BarWarden_watermark"] or "?"))

    local version, buildNum, _, tocVersion = GetBuildInfo()
    add(string.format("Client: %s  Build: %s  TOC: %s", version or "?", buildNum or "?", tostring(tocVersion or "?")))

    local _, class = UnitClass("player")
    local level = UnitLevel("player")
    local name = UnitName("player")
    add(string.format("Character: %s (%s level %d)", name or "?", class or "?", level or 0))
    add(string.format("Date: %s", date("%Y-%m-%d %H:%M:%S")))
    add("")

    -- Global settings
    add("--- Settings ---")
    if ns.db and ns.db.global then
        local g = ns.db.global
        add(string.format("Enabled: %s", tostring(g.enabled)))
        add(string.format("Locked: %s", tostring(g.locked)))
        local minimapShown = ns.db.minimap and not ns.db.minimap.hide
        add(string.format("MinimapIcon: %s", tostring(minimapShown)))
    else
        add("DB not loaded")
    end
    add(string.format("Schema: %s", tostring(ns.db and ns.db.schemaVersion or "nil")))
    add("")

    -- Visual config
    add("--- Visual Config ---")
    if ns.db and ns.db.visual then
        local v = ns.db.visual
        add(string.format("Texture: %s", tostring(v.texture)))
        add(string.format("ColorMode: %s", tostring(v.colorMode)))
        add(string.format("BarSize: %dx%d", v.barWidth or 0, v.barHeight or 0))
        add(string.format("FontSize: %s", tostring(v.fontSize)))
        add(string.format("StackFontSize: %s", tostring(v.stackFontSize)))
        local sc = v.stackColor
        add(string.format("StackColor: %s", sc
            and string.format("%.2f,%.2f,%.2f", sc.r or 0, sc.g or 0, sc.b or 0)
            or "nil"))
        add(string.format("TextFormat: %s", tostring(v.textFormat)))
        add(string.format("DurationStyle: %s", tostring(v.durationStyle)))
        add(string.format("IconSize: %s  IconPos: %s", tostring(v.iconSize), tostring(v.iconPosition)))
        add(string.format("ShowSpark: %s", tostring(v.showSpark)))
        add(string.format("ActiveAlpha: %s  InactiveAlpha: %s", tostring(v.activeAlpha), tostring(v.inactiveAlpha)))
    end
    add("")

    -- Groups and bars
    add("--- Groups & Bars ---")
    if ns.db and ns.db.frames then
        for gi, frameData in ipairs(ns.db.frames) do
            -- bgAlpha/borderAlpha always print (not gated behind "only when
            -- set" like the overrides below): both have a live default
            -- (0.6 / 0.8) applied at read time elsewhere, so the group
            -- always has an effective opacity and the report should show
            -- what it actually is. `~= nil` (not a plain `or`) so an
            -- explicit 0 - the value that makes a group invisible - reads
            -- as 0.00, not the 0.6/0.8 default.
            add(string.format("Group %d: \"%s\" (w=%d, cols=%d, scale=%.1f, sort=%s, grow=%s, enabled=%s, bgAlpha=%.2f, borderAlpha=%.2f)",
                gi,
                frameData.name or "unnamed",
                frameData.width or 0,
                frameData.columns or 1,
                frameData.scale or 1.0,
                tostring(frameData.sortMode or "manual"),
                tostring(frameData.growDirection or "DOWN"),
                tostring(frameData.enabled ~= false),
                frameData.bgAlpha ~= nil and frameData.bgAlpha or 0.6,
                frameData.borderAlpha ~= nil and frameData.borderAlpha or 0.8))

            -- Group-level visual overrides (v2): only present when set.
            -- iconOnly and barStyle folded in here alongside texture/colour
            -- since both change how the group draws and have each caused
            -- "why does my group look wrong" confusion on their own.
            -- textFormat is a group-level override too (GROUP_SETTINGS_SCHEMA
            -- in Options_Bars.lua) but was missing from this line entirely;
            -- added for the same reason as barTexture next to it.
            local gover = {}
            if frameData.barTexture then
                gover[#gover + 1] = "texture=" .. tostring(frameData.barTexture)
            end
            if frameData.textFormat and frameData.textFormat ~= "" then
                gover[#gover + 1] = "textFormat=" .. tostring(frameData.textFormat)
            end
            if frameData.barStyle and frameData.barStyle ~= "" then
                gover[#gover + 1] = "barStyle=" .. tostring(frameData.barStyle)
            end
            if frameData.iconOnly then
                gover[#gover + 1] = "iconOnly"
            end
            if frameData.barColor then
                gover[#gover + 1] = string.format("colour=%.2f,%.2f,%.2f",
                    frameData.barColor.r or 0, frameData.barColor.g or 0, frameData.barColor.b or 0)
            end
            if #gover > 0 then add("    overrides: " .. table.concat(gover, ", ")) end

            -- Group-level conditions (v2).
            local gc = frameData.groupConditions
            if gc then
                local gcp = {}
                if gc.combatOnly       then gcp[#gcp + 1] = "combatOnly" end
                if gc.outOfCombatOnly  then gcp[#gcp + 1] = "outOfCombatOnly" end
                if gc.hideWhileMounted then gcp[#gcp + 1] = "hideMounted" end
                if gc.hideWhileResting then gcp[#gcp + 1] = "hideResting" end
                if gc.hideInVehicle    then gcp[#gcp + 1] = "hideInVehicle" end
                if gc.onlyInInstance   then gcp[#gcp + 1] = "onlyInInstance" end
                if #gcp > 0 then add("    groupConditions: " .. table.concat(gcp, ", ")) end
            end

            -- Auto tracking (v2): only present when this group actually has
            -- a feed picked, so an ordinary hand-built group gains nothing
            -- beyond this check. This is the setting that decides whether a
            -- group is an auto-tracking group at all - previously invisible
            -- in the report, which is exactly what made "is this an
            -- auto-track group" a recurring question when diagnosing a
            -- group that shows or hides unexpectedly.
            if frameData.autoTrack and frameData.autoTrack ~= "" then
                add(string.format(
                    "    autoTrack: feed=%s, maxBars=%d, maxDuration=%d, onlyMine=%s, skipTracked=%s, stableOrder=%s, includePermanent=%s",
                    tostring(frameData.autoTrack),
                    frameData.autoMaxBars or 10,
                    frameData.autoMaxDuration ~= nil and frameData.autoMaxDuration or 300,
                    tostring(frameData.autoOnlyMine == true),
                    tostring(frameData.autoSkipTracked == true),
                    tostring(frameData.autoStableOrder == true),
                    tostring(frameData.autoIncludePermanent == true)))
            end

            -- Alt-click ban list (Bar.lua's alt-click handler on an auto bar).
            -- A count is enough diagnostically; listing every banned spell
            -- would bloat the report. Kept independent of the autoTrack
            -- check above: switching the feed off does not clear the list,
            -- so a stale ban list is itself worth surfacing.
            if frameData.autoBanned then
                local bannedCount = 0
                for _ in pairs(frameData.autoBanned) do bannedCount = bannedCount + 1 end
                if bannedCount > 0 then
                    add(string.format("    autoBanned: %d hidden", bannedCount))
                end
            end

            for bi, bar in ipairs(frameData.bars or {}) do
                local spellStr = tostring(bar.spellName or bar.spellId or bar.itemId or "none")
                local mode = bar.trackMode or "?"
                local unit = bar.unit or "player"

                -- Find the live bar frame to get state
                local stateStr = "N/A"
                for _, liveBar in ipairs(ns.allBars or {}) do
                    if liveBar.barData == bar then
                        stateStr = STATE_NAMES[liveBar.barState] or tostring(liveBar.barState)
                        if liveBar.barState == 1 and liveBar.expirationTime then
                            local rem = liveBar.expirationTime - GetTime()
                            stateStr = stateStr .. string.format(" remaining=%.1f", rem)
                        end
                        break
                    end
                end

                add(string.format("  Bar %d: [%s] spell=%s unit=%s state=%s",
                    bi, mode, spellStr, unit, stateStr))

                -- Conditions
                local cond = bar.conditions
                if cond then
                    local condParts = {}
                    if cond.combatOnly then condParts[#condParts + 1] = "combatOnly" end
                    if cond.outOfCombatOnly then condParts[#condParts + 1] = "outOfCombatOnly" end
                    if cond.hideWhileMounted then condParts[#condParts + 1] = "hideMounted" end
                    if cond.hideWhileResting then condParts[#condParts + 1] = "hideResting" end
                    if cond.hideInVehicle then condParts[#condParts + 1] = "hideInVehicle" end
                    if cond.onlyInInstance then condParts[#condParts + 1] = "onlyInInstance" end
                    if cond.hideWhenInactive then condParts[#condParts + 1] = "hideWhenInactive" end
                    if cond.showEmpty then condParts[#condParts + 1] = "showEmpty" end
                    if cond.inGroup then condParts[#condParts + 1] = "inGroup" end
                    if cond.inRaid then condParts[#condParts + 1] = "inRaid" end
                    if cond.healthBelow then condParts[#condParts + 1] = "healthBelow=" .. tostring(cond.healthBelow) end
                    if cond.requireBuff then condParts[#condParts + 1] = "requireBuff=" .. tostring(cond.requireBuff) end
                    if #condParts > 0 then
                        add("    conditions: " .. table.concat(condParts, ", "))
                    end
                end

                -- Per-bar display overrides (only fields that differ from the
                -- defaults are set, so this lists exactly what the user changed).
                local disp = bar.display
                if disp then
                    local dispParts = {}
                    if disp.lingerTime and disp.lingerTime > 0 then dispParts[#dispParts + 1] = "linger=" .. tostring(disp.lingerTime) end
                    if disp.scaleOverride then dispParts[#dispParts + 1] = "scale=" .. tostring(disp.scaleOverride) end
                    if disp.showName ~= nil then dispParts[#dispParts + 1] = "showName=" .. tostring(disp.showName) end
                    if disp.showIcon ~= nil then dispParts[#dispParts + 1] = "showIcon=" .. tostring(disp.showIcon) end
                    if disp.iconCrop ~= nil then dispParts[#dispParts + 1] = "iconCrop=" .. tostring(disp.iconCrop) end
                    if disp.barAlpha ~= nil then dispParts[#dispParts + 1] = string.format("barAlpha=%.2f", disp.barAlpha) end
                    if disp.colorOverride then
                        dispParts[#dispParts + 1] = string.format("colour=%.2f,%.2f,%.2f",
                            disp.colorOverride.r or 0, disp.colorOverride.g or 0, disp.colorOverride.b or 0)
                    end
                    if disp.colorByTime then dispParts[#dispParts + 1] = "colorByTime" end
                    if disp.sparkleAlert then dispParts[#dispParts + 1] = "sparkleAlert=" .. tostring(disp.sparkleThreshold or 5) end
                    if disp.glowOnReady then dispParts[#dispParts + 1] = "glow=" .. tostring(disp.glowDuration or 3) end
                    if disp.pulseOnReady then dispParts[#dispParts + 1] = "pulseOnReady" end
                    if #dispParts > 0 then
                        add("    display: " .. table.concat(dispParts, ", "))
                    end
                end
            end
        end
    else
        add("No frame data loaded.")
    end
    add("")

    -- Activity statistics (from ActivityTracker)
    add("--- Activity Statistics ---")
    local sessionDuration = time() - (ns.sessionStartTime or time())
    add(string.format("Session duration: %dm %ds", math.floor(sessionDuration / 60), sessionDuration % 60))
    local hasStats = false
    local allKeys = ns.GetAllActivityKeys and ns:GetAllActivityKeys() or {}
    for key in pairs(allKeys) do
        hasStats = true
        local name, _, category = ns:GetActivityMeta(key)
        local session = ns.activitySession and ns.activitySession[key]
        local persistent = ns.db and ns.db.activity and ns.db.activity[key]
        local sAct = session and session.activations or 0
        local sUp  = session and session.uptime or 0
        local pAct = persistent and persistent.activations or 0
        local pUp  = persistent and persistent.uptime or 0
        add(string.format("  [%s] %s: %d / %s (session) | %d / %s (all-time)",
            category or "?", name or key, sAct, FormatUptime(sUp), pAct, FormatUptime(pUp)))
    end
    if not hasStats then
        add("  No activity recorded yet.")
    end

    return table.concat(lines, "\n")
end

-- ----------------------------------------------------------------------------
-- Create the report frame (once, reused)
-- ----------------------------------------------------------------------------
local function CreateReportFrame()
    local f = CreateFrame("Frame", "BarWardenBugReportFrame", UIParent)
    f:SetWidth(FRAME_WIDTH)
    f:SetHeight(FRAME_HEIGHT)
    f:SetPoint("CENTER")
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    f:SetBackdropColor(0, 0, 0, 1)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    -- TOOLTIP strata + toplevel so the report floats above the Interface
    -- Options window instead of being buried behind it (matches EC's report).
    f:SetFrameStrata("TOOLTIP")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)

    -- Close on Escape
    tinsert(UISpecialFrames, "BarWardenBugReportFrame")

    -- Title
    local titleText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleText:SetPoint("TOP", f, "TOP", 0, -16)
    titleText:SetText("BarWarden Bug Report (Ctrl+A to select all, Ctrl+C to copy)")

    -- Close button
    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -5, -5)

    -- Scroll frame
    local scrollFrame = CreateFrame("ScrollFrame", "BarWardenBugReportScroll", f, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -40)
    scrollFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -36, 16)

    -- EditBox inside scroll frame
    local editBox = CreateFrame("EditBox", "BarWardenBugReportEditBox", scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(false)
    editBox:SetFontObject(GameFontHighlightSmall)
    editBox:SetWidth(scrollFrame:GetWidth() - 10)
    editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() f:Hide() end)

    scrollFrame:SetScrollChild(editBox)
    f.editBox = editBox

    f:Hide()
    return f
end

-- ----------------------------------------------------------------------------
-- Public API
-- ----------------------------------------------------------------------------

function ns:ShowBugReport()
    if not reportFrame then
        reportFrame = CreateReportFrame()
    end

    local report = self:GenerateBugReport()
    reportFrame.editBox:SetText(report)
    reportFrame.editBox:SetWidth(reportFrame:GetWidth() - 56)
    reportFrame:Show()
    reportFrame.editBox:SetFocus()
    reportFrame.editBox:HighlightText()
end
