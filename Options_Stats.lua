local addonName, ns = ...

-- ============================================================================
-- Options_Stats.lua - Tab 5: Statistics
-- ============================================================================

local STAT_ROW_HEIGHT = 18
local MAX_STAT_ROWS = 7

-- ============================================================================
-- Helper: format uptime seconds into readable string
-- ============================================================================
local function FormatUptime(seconds)
    if not seconds or seconds <= 0 then return "0s" end
    if seconds < 60 then
        return string.format("%.1fs", seconds)
    end
    if seconds < 3600 then
        local m = math.floor(seconds / 60)
        local s = math.floor(seconds % 60)
        return string.format("%dm %ds", m, s)
    end
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds - h * 3600) / 60)
    return string.format("%dh %dm", h, m)
end

-- ============================================================================
-- Helper: get sorted stat keys from both session and persistent tables
-- ============================================================================
local function GetSortedStatKeys()
    local keys = {}
    local seen = {}
    for key in pairs(ns.sessionStats or {}) do
        if not seen[key] then
            keys[#keys + 1] = key
            seen[key] = true
        end
    end
    for key in pairs(ns.db and ns.db.stats or {}) do
        if not seen[key] then
            keys[#keys + 1] = key
            seen[key] = true
        end
    end
    table.sort(keys)
    return keys
end

-- ============================================================================
-- Main Tab Creation
-- ============================================================================

local function CreateStatsTab(parent)
    local frame = CreateFrame("Frame", "BarWardenStatsTab", parent)
    frame:SetAllPoints(parent)
    frame:Hide()

    -- Title
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -80)
    title:SetText("Statistics")

    local desc = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    desc:SetText("Per-bar activation counts and uptime tracking.")

    -- Session duration label
    local sessionLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sessionLabel:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -8)
    frame.sessionLabel = sessionLabel

    -- Group labels row ("Session" and "All-Time" above their columns)
    local groupLabelFrame = CreateFrame("Frame", nil, frame)
    groupLabelFrame:SetPoint("TOPLEFT", sessionLabel, "BOTTOMLEFT", 0, -8)
    groupLabelFrame:SetSize(400, 14)

    local gSession = groupLabelFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    gSession:SetPoint("LEFT", groupLabelFrame, "LEFT", 128, 0)
    gSession:SetText("--- Session ---")
    gSession:SetWidth(118)
    gSession:SetJustifyH("CENTER")
    gSession:SetTextColor(0.5, 0.8, 1.0)

    local gAllTime = groupLabelFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    gAllTime:SetPoint("LEFT", gSession, "RIGHT", 8, 0)
    gAllTime:SetText("--- All-Time ---")
    gAllTime:SetWidth(118)
    gAllTime:SetJustifyH("CENTER")
    gAllTime:SetTextColor(1.0, 0.82, 0.0)

    -- Column headers
    local headerFrame = CreateFrame("Frame", nil, frame)
    headerFrame:SetPoint("TOPLEFT", groupLabelFrame, "BOTTOMLEFT", 0, -2)
    headerFrame:SetSize(400, 14)

    local hName = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hName:SetPoint("LEFT", headerFrame, "LEFT", 4, 0)
    hName:SetText("Bar")
    hName:SetWidth(120)
    hName:SetJustifyH("LEFT")

    local hSessAct = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hSessAct:SetPoint("LEFT", hName, "RIGHT", 4, 0)
    hSessAct:SetText("Procs")
    hSessAct:SetWidth(55)
    hSessAct:SetJustifyH("RIGHT")

    local hSessUp = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hSessUp:SetPoint("LEFT", hSessAct, "RIGHT", 4, 0)
    hSessUp:SetText("Uptime")
    hSessUp:SetWidth(55)
    hSessUp:SetJustifyH("RIGHT")

    local hAllAct = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hAllAct:SetPoint("LEFT", hSessUp, "RIGHT", 4, 0)
    hAllAct:SetText("Procs")
    hAllAct:SetWidth(55)
    hAllAct:SetJustifyH("RIGHT")

    local hAllUp = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hAllUp:SetPoint("LEFT", hAllAct, "RIGHT", 4, 0)
    hAllUp:SetText("Uptime")
    hAllUp:SetWidth(55)
    hAllUp:SetJustifyH("RIGHT")

    -- Stat list (FauxScrollFrame)
    local listFrame = CreateFrame("Frame", "BarWardenStatList", frame)
    listFrame:SetPoint("TOPLEFT", headerFrame, "BOTTOMLEFT", 0, -4)
    listFrame:SetSize(400, MAX_STAT_ROWS * STAT_ROW_HEIGHT + 4)

    local listBg = listFrame:CreateTexture(nil, "BACKGROUND")
    listBg:SetAllPoints()
    listBg:SetTexture(0, 0, 0, 0.3)

    local scrollFrame = CreateFrame("ScrollFrame", "BarWardenStatScrollFrame", listFrame, "FauxScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 2, -2)
    scrollFrame:SetPoint("BOTTOMRIGHT", -22, 2)

    local rows = {}
    for i = 1, MAX_STAT_ROWS do
        local row = CreateFrame("Frame", "BarWardenStatRow" .. i, listFrame)
        row:SetSize(374, STAT_ROW_HEIGHT)
        if i == 1 then
            row:SetPoint("TOPLEFT", listFrame, "TOPLEFT", 2, -2)
        else
            row:SetPoint("TOPLEFT", rows[i - 1], "BOTTOMLEFT", 0, 0)
        end

        local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        nameText:SetPoint("LEFT", row, "LEFT", 4, 0)
        nameText:SetWidth(120)
        nameText:SetJustifyH("LEFT")
        row.nameText = nameText

        local sessActText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        sessActText:SetPoint("LEFT", nameText, "RIGHT", 4, 0)
        sessActText:SetWidth(55)
        sessActText:SetJustifyH("RIGHT")
        row.sessActText = sessActText

        local sessUpText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        sessUpText:SetPoint("LEFT", sessActText, "RIGHT", 4, 0)
        sessUpText:SetWidth(55)
        sessUpText:SetJustifyH("RIGHT")
        row.sessUpText = sessUpText

        local allActText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        allActText:SetPoint("LEFT", sessUpText, "RIGHT", 4, 0)
        allActText:SetWidth(55)
        allActText:SetJustifyH("RIGHT")
        row.allActText = allActText

        local allUpText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        allUpText:SetPoint("LEFT", allActText, "RIGHT", 4, 0)
        allUpText:SetWidth(55)
        allUpText:SetJustifyH("RIGHT")
        row.allUpText = allUpText

        rows[i] = row
    end

    -- ========================================================================
    -- Refresh stat list
    -- ========================================================================
    function frame:RefreshList()
        local keys = GetSortedStatKeys()
        local offset = FauxScrollFrame_GetOffset(scrollFrame)
        FauxScrollFrame_Update(scrollFrame, #keys, MAX_STAT_ROWS, STAT_ROW_HEIGHT)

        -- Update session duration label
        local sessionDuration = time() - (ns.sessionStartTime or time())
        sessionLabel:SetText(string.format("Session duration: %dm %ds",
            math.floor(sessionDuration / 60), sessionDuration % 60))

        for i = 1, MAX_STAT_ROWS do
            local row = rows[i]
            local index = i + offset
            if index <= #keys then
                local key = keys[index]
                local session = ns.sessionStats and ns.sessionStats[key] or { activations = 0, uptime = 0 }
                local allTime = ns.db and ns.db.stats and ns.db.stats[key] or { activations = 0, uptime = 0 }

                -- Display just the spell identifier from "GroupName:Mode:Spell"
                local displayName = key:match("^[^:]+:[^:]+:(.+)$") or key
                row.nameText:SetText(displayName)
                row.sessActText:SetText(tostring(session.activations))
                row.sessUpText:SetText(FormatUptime(session.uptime))
                row.allActText:SetText(tostring(allTime.activations))
                row.allUpText:SetText(FormatUptime(allTime.uptime))
                row:Show()
            else
                row:Hide()
            end
        end
    end

    scrollFrame:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, STAT_ROW_HEIGHT, function() frame:RefreshList() end)
    end)

    -- ========================================================================
    -- Buttons
    -- ========================================================================
    local resetSessionBtn = ns:CreateButton(frame, "Reset Session", 120, function()
        wipe(ns.sessionStats)
        ns.sessionStartTime = time()
        frame:RefreshList()
        ns:Print("Session statistics reset.")
    end)
    resetSessionBtn:SetPoint("TOPLEFT", listFrame, "BOTTOMLEFT", 0, -8)

    local resetAllBtn = ns:CreateButton(frame, "Reset All Stats", 120, function()
        StaticPopup_Show("BARWARDEN_CONFIRM_STATS_RESET", nil, nil, {
            onAccept = function()
                wipe(ns.sessionStats)
                ns.sessionStartTime = time()
                if ns.db and ns.db.stats then
                    wipe(ns.db.stats)
                end
                frame:RefreshList()
                ns:Print("All statistics reset.")
            end,
        })
    end)
    resetAllBtn:SetPoint("LEFT", resetSessionBtn, "RIGHT", 4, 0)

    -- Refresh when shown
    frame:SetScript("OnShow", function(self)
        self:RefreshList()
    end)

    return frame
end

-- ============================================================================
-- Register tab when options panel is created
-- ============================================================================
local orig = ns.CreateOptionsPanel
ns.CreateOptionsPanel = function(self)
    local panel = orig(self)
    local tab = CreateStatsTab(panel)
    ns.optionsTabs[5] = tab
    return panel
end
