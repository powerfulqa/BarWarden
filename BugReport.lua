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

-- ----------------------------------------------------------------------------
-- Format uptime for the report
-- ----------------------------------------------------------------------------
local function FormatUptime(seconds)
    if not seconds or seconds <= 0 then return "0s" end
    if seconds < 60 then return string.format("%.1fs", seconds) end
    local m = math.floor(seconds / 60)
    local s = math.floor(seconds % 60)
    if m < 60 then return string.format("%dm %ds", m, s) end
    local h = math.floor(m / 60)
    m = m % 60
    return string.format("%dh %dm", h, m)
end

-- ----------------------------------------------------------------------------
-- Generate the report string
-- ----------------------------------------------------------------------------
local function GenerateReport()
    local lines = {}
    local function add(text)
        lines[#lines + 1] = text or ""
    end

    add("=== BarWarden Bug Report ===")
    add(string.format("Version: %s", ns.version or "unknown"))

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
        add(string.format("ShowAll: %s", tostring(g.showAll)))
        add(string.format("MinimapIcon: %s", tostring(g.minimapIcon)))
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
            add(string.format("Group %d: \"%s\" (cols=%d, scale=%.1f, enabled=%s)",
                gi,
                frameData.name or "unnamed",
                frameData.columns or 1,
                frameData.scale or 1.0,
                tostring(frameData.enabled ~= false)))
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

                -- Per-bar display overrides
                local disp = bar.display
                if disp then
                    local dispParts = {}
                    if disp.lingerTime and disp.lingerTime > 0 then dispParts[#dispParts + 1] = "linger=" .. tostring(disp.lingerTime) end
                    if disp.sparkleAlert then dispParts[#dispParts + 1] = "sparkleAlert=" .. tostring(disp.sparkleThreshold or 5) end
                    if disp.colorOverride then dispParts[#dispParts + 1] = "colorOverride" end
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

    -- Statistics
    add("--- Statistics ---")
    local sessionDuration = time() - (ns.sessionStartTime or time())
    add(string.format("Session duration: %dm %ds", math.floor(sessionDuration / 60), sessionDuration % 60))
    local hasStats = false
    local allKeys = {}
    for key in pairs(ns.sessionStats or {}) do allKeys[key] = true end
    for key in pairs(ns.db and ns.db.stats or {}) do allKeys[key] = true end
    for key in pairs(allKeys) do
        hasStats = true
        local session = ns.sessionStats and ns.sessionStats[key] or { activations = 0, uptime = 0 }
        local allTime = ns.db and ns.db.stats and ns.db.stats[key] or { activations = 0, uptime = 0 }
        add(string.format("  %s: %d act / %s uptime (session) | %d act / %s (all-time)",
            key, session.activations, FormatUptime(session.uptime),
            allTime.activations, FormatUptime(allTime.uptime)))
    end
    if not hasStats then
        add("  No statistics recorded yet.")
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
    f:SetFrameStrata("DIALOG")
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

    local report = GenerateReport()
    reportFrame.editBox:SetText(report)
    reportFrame.editBox:SetWidth(reportFrame:GetWidth() - 56)
    reportFrame:Show()
    reportFrame.editBox:SetFocus()
    reportFrame.editBox:HighlightText()
end
