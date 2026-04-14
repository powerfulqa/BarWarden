local addonName, ns = ...

-- ============================================================================
-- Options_Stats.lua - Tab 5: Activity Tracker
--
-- Passive monitoring display. Shows all cooldowns, buffs, debuffs, enchants,
-- and totems detected on the player's character. Data comes from
-- ActivityTracker.lua. Users can filter by category and create bars directly
-- from the discovered spells.
-- ============================================================================

local STAT_ROW_HEIGHT = 18
local MAX_STAT_ROWS = 9
local ICON_SIZE = 16

local CATEGORY_FILTERS = {
    { text = "All",       value = "All" },
    { text = "Cooldowns", value = "Cooldown" },
    { text = "Buffs",     value = "Buff" },
    { text = "Debuffs",   value = "Debuff" },
    { text = "Enchants",  value = "Enchant" },
    { text = "Totems",    value = "Totem" },
}

-- Map activity category → bar trackMode
local CATEGORY_TO_TRACK_MODE = {
    Cooldown = "Cooldown",
    Buff     = "Buff",
    Debuff   = "Debuff",
    Enchant  = "Enchant MH",  -- default; Create Bar can refine
    Totem    = "Totem",
}

-- Map activity category → default unit
local CATEGORY_TO_UNIT = {
    Cooldown = "player",
    Buff     = "player",
    Debuff   = "target",
    Enchant  = "player",
    Totem    = "player",
}

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
-- Helper: build a filtered + sorted list of activity keys
-- ============================================================================
local function GetFilteredKeys(categoryFilter)
    local allKeys = ns.GetAllActivityKeys and ns:GetAllActivityKeys() or {}
    local result = {}

    for key in pairs(allKeys) do
        local _, _, category = ns:GetActivityMeta(key)
        if categoryFilter == "All" or category == categoryFilter then
            result[#result + 1] = key
        end
    end

    -- Sort by session activations descending (most active first)
    table.sort(result, function(a, b)
        local sa = ns.activitySession and ns.activitySession[a]
        local sb = ns.activitySession and ns.activitySession[b]
        local aAct = sa and sa.activations or 0
        local bAct = sb and sb.activations or 0
        if aAct ~= bAct then return aAct > bAct end
        -- Tie-break: alphabetical by name
        local aName = ns:GetActivityMeta(a) or ""
        local bName = ns:GetActivityMeta(b) or ""
        return aName < bName
    end)

    return result
end

-- ============================================================================
-- Main Tab Creation
-- ============================================================================

local function CreateStatsTab(parent)
    local frame = CreateFrame("Frame", "BarWardenStatsTab", parent)
    frame:SetAllPoints(parent)
    frame:Hide()

    local selectedKey = nil
    local selectedFilter = "All"
    local selectedGroupIdx = 1
    local filteredKeys = {}

    -- Title
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -80)
    title:SetText("Activity Tracker")

    local desc = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    desc:SetText("Passive monitoring of all spells, auras, and effects on your character.")

    -- Session duration label
    local sessionLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sessionLabel:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -8)
    frame.sessionLabel = sessionLabel

    -- Category filter dropdown (positioned with reset buttons at the bottom)
    local filterDD = ns:CreateDropdown(frame, "", CATEGORY_FILTERS, function(dd, value)
        selectedFilter = value
        selectedKey = nil
        frame:RefreshList()
    end)

    -- Group labels row ("Session" and "All-Time" above their columns)
    local groupLabelFrame = CreateFrame("Frame", nil, frame)
    groupLabelFrame:SetPoint("TOPLEFT", sessionLabel, "BOTTOMLEFT", 0, -8)
    groupLabelFrame:SetSize(460, 14)

    local gSession = groupLabelFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    gSession:SetPoint("LEFT", groupLabelFrame, "LEFT", 170, 0)
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
    headerFrame:SetSize(460, 14)

    local hIcon = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hIcon:SetPoint("LEFT", headerFrame, "LEFT", 4, 0)
    hIcon:SetText("")
    hIcon:SetWidth(ICON_SIZE + 4)

    local hName = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hName:SetPoint("LEFT", hIcon, "RIGHT", 2, 0)
    hName:SetText("Name")
    hName:SetWidth(140)
    hName:SetJustifyH("LEFT")

    local hSessAct = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hSessAct:SetPoint("LEFT", hName, "RIGHT", 4, 0)
    hSessAct:SetText("Procs")
    hSessAct:SetWidth(50)
    hSessAct:SetJustifyH("RIGHT")

    local hSessUp = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hSessUp:SetPoint("LEFT", hSessAct, "RIGHT", 4, 0)
    hSessUp:SetText("Uptime")
    hSessUp:SetWidth(55)
    hSessUp:SetJustifyH("RIGHT")

    local hAllAct = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hAllAct:SetPoint("LEFT", hSessUp, "RIGHT", 8, 0)
    hAllAct:SetText("Procs")
    hAllAct:SetWidth(50)
    hAllAct:SetJustifyH("RIGHT")

    local hAllUp = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hAllUp:SetPoint("LEFT", hAllAct, "RIGHT", 4, 0)
    hAllUp:SetText("Uptime")
    hAllUp:SetWidth(55)
    hAllUp:SetJustifyH("RIGHT")

    -- ========================================================================
    -- Stat list (FauxScrollFrame)
    -- ========================================================================
    local listFrame = CreateFrame("Frame", "BarWardenStatList", frame)
    listFrame:SetPoint("TOPLEFT", headerFrame, "BOTTOMLEFT", 0, -4)
    listFrame:SetSize(460, MAX_STAT_ROWS * STAT_ROW_HEIGHT + 4)

    local listBg = listFrame:CreateTexture(nil, "BACKGROUND")
    listBg:SetAllPoints()
    listBg:SetTexture(0, 0, 0, 0.3)

    local scrollFrame = CreateFrame("ScrollFrame", "BarWardenStatScrollFrame", listFrame, "FauxScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 2, -2)
    scrollFrame:SetPoint("BOTTOMRIGHT", -22, 2)

    local rows = {}
    for i = 1, MAX_STAT_ROWS do
        local row = CreateFrame("Button", "BarWardenStatRow" .. i, listFrame)
        row:SetSize(434, STAT_ROW_HEIGHT)
        if i == 1 then
            row:SetPoint("TOPLEFT", listFrame, "TOPLEFT", 2, -2)
        else
            row:SetPoint("TOPLEFT", rows[i - 1], "BOTTOMLEFT", 0, 0)
        end

        local highlight = row:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetTexture(1, 1, 1, 0.1)

        local selected = row:CreateTexture(nil, "BACKGROUND")
        selected:SetAllPoints()
        selected:SetTexture(0.2, 0.4, 0.8, 0.3)
        selected:Hide()
        row.selected = selected

        -- Icon
        local iconTex = row:CreateTexture(nil, "ARTWORK")
        iconTex:SetPoint("LEFT", row, "LEFT", 4, 0)
        iconTex:SetSize(ICON_SIZE, ICON_SIZE)
        iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.iconTex = iconTex

        local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        nameText:SetPoint("LEFT", iconTex, "RIGHT", 4, 0)
        nameText:SetWidth(136)
        nameText:SetJustifyH("LEFT")
        row.nameText = nameText

        local sessActText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        sessActText:SetPoint("LEFT", nameText, "RIGHT", 4, 0)
        sessActText:SetWidth(50)
        sessActText:SetJustifyH("RIGHT")
        row.sessActText = sessActText

        local sessUpText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        sessUpText:SetPoint("LEFT", sessActText, "RIGHT", 4, 0)
        sessUpText:SetWidth(55)
        sessUpText:SetJustifyH("RIGHT")
        row.sessUpText = sessUpText

        local allActText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        allActText:SetPoint("LEFT", sessUpText, "RIGHT", 8, 0)
        allActText:SetWidth(50)
        allActText:SetJustifyH("RIGHT")
        row.allActText = allActText

        local allUpText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        allUpText:SetPoint("LEFT", allActText, "RIGHT", 4, 0)
        allUpText:SetWidth(55)
        allUpText:SetJustifyH("RIGHT")
        row.allUpText = allUpText

        row:SetScript("OnClick", function(self)
            selectedKey = self.activityKey
            frame:RefreshList()
        end)

        rows[i] = row
    end

    -- ========================================================================
    -- Create Bar controls (below the list)
    -- ========================================================================
    local groupDD  -- forward declaration; assigned after the button
    local createBarBtn = ns:CreateButton(frame, "Create Bar", 90, function()
        if not selectedKey then
            ns:Print("Select a spell from the list first.")
            return
        end
        local name, icon, category, spellId = ns:GetActivityMeta(selectedKey)
        if not name then
            ns:Print("No data for the selected entry.")
            return
        end

        -- Find which group to add to
        local frames = BarWardenDB and BarWardenDB.frames
        if not frames or #frames == 0 then
            ns:Print("Create a group first in the Bars tab.")
            return
        end

        local groupIdx = selectedGroupIdx or 1
        local g = frames[groupIdx]
        if not g then
            ns:Print("Invalid group selection.")
            return
        end

        local maxBars = ns.MAX_BARS_PER_FRAME or 30
        if #g.bars >= maxBars then
            ns:Print("Maximum of " .. maxBars .. " bars per group reached.")
            return
        end

        -- Build the bar config
        local trackMode = CATEGORY_TO_TRACK_MODE[category] or "Cooldown"
        -- Refine enchant track mode from the key
        if category == "Enchant" then
            if selectedKey == "Enchant:OH" then
                trackMode = "Enchant OH"
            else
                trackMode = "Enchant MH"
            end
        end

        local newBar = {
            name = name,
            enabled = true,
            trackMode = trackMode,
            unit = CATEGORY_TO_UNIT[category] or "player",
            onlyMine = (category == "Debuff"),
            conditions = {
                combatOnly = false,
                outOfCombatOnly = false,
                hideWhenInactive = false,
                showEmpty = true,
            },
            display = {},
        }

        -- Set spell identifier
        if spellId and spellId ~= 0 then
            if trackMode == "Item" then
                newBar.itemId = spellId
            else
                newBar.spellId = spellId
            end
        elseif category == "Totem" then
            newBar.spellName = name
        end

        table.insert(g.bars, newBar)
        ns:RebuildAllFrames()
        ns:Print("Bar created for " .. name .. " in " .. (g.name or "Group " .. groupIdx) .. ".")
    end)
    createBarBtn:SetPoint("TOPLEFT", listFrame, "BOTTOMLEFT", 0, -8)

    -- Group picker dropdown (no label — sits next to Create Bar button)
    local groupItems = {}
    groupDD = ns:CreateDropdown(frame, "", groupItems, function() end)
    groupDD:SetPoint("LEFT", createBarBtn, "RIGHT", -4, -2)

    -- Helper to rebuild the group dropdown items, preserving the last selection
    local function RefreshGroupDropdown()
        local frames = BarWardenDB and BarWardenDB.frames or {}
        local items = {}
        for i, f in ipairs(frames) do
            items[i] = { text = f.name or ("Group " .. i), value = i }
        end
        UIDropDownMenu_Initialize(groupDD, function(self, level)
            for _, item in ipairs(items) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = item.text
                info.value = item.value
                info.func = function(btn)
                    selectedGroupIdx = btn:GetID()
                    UIDropDownMenu_SetSelectedID(groupDD, selectedGroupIdx)
                    UIDropDownMenu_SetText(groupDD, item.text)
                end
                UIDropDownMenu_AddButton(info)
            end
        end)
        -- Clamp to valid range then restore the last selection
        if #items > 0 then
            if selectedGroupIdx > #items then selectedGroupIdx = 1 end
            UIDropDownMenu_SetSelectedID(groupDD, selectedGroupIdx)
            UIDropDownMenu_SetText(groupDD, items[selectedGroupIdx].text)
        end
    end

    -- ========================================================================
    -- Reset buttons
    -- ========================================================================
    local resetSessionBtn = ns:CreateButton(frame, "Reset Session", 100, function()
        wipe(ns.activitySession)
        ns.sessionStartTime = time()
        selectedKey = nil
        frame:RefreshList()
        ns:Print("Session activity reset.")
    end)
    resetSessionBtn:SetPoint("TOPLEFT", createBarBtn, "BOTTOMLEFT", 0, -8)

    -- Position the filter dropdown on the same row as the reset buttons
    filterDD:SetPoint("LEFT", resetSessionBtn, "RIGHT", 99, -3)

    local resetAllBtn = ns:CreateButton(frame, "Reset All", 100, function()
        StaticPopup_Show("BARWARDEN_CONFIRM_STATS_RESET", nil, nil, {
            onAccept = function()
                wipe(ns.activitySession)
                ns.sessionStartTime = time()
                if ns.db and ns.db.activity then
                    wipe(ns.db.activity)
                end
                selectedKey = nil
                frame:RefreshList()
                ns:Print("All activity data reset.")
            end,
        })
    end)
    resetAllBtn:SetPoint("LEFT", resetSessionBtn, "RIGHT", 4, 0)

    -- ========================================================================
    -- Refresh
    -- ========================================================================
    function frame:RefreshList()
        filteredKeys = GetFilteredKeys(selectedFilter)
        local offset = FauxScrollFrame_GetOffset(scrollFrame)
        FauxScrollFrame_Update(scrollFrame, #filteredKeys, MAX_STAT_ROWS, STAT_ROW_HEIGHT)

        -- Session duration
        local sessionDuration = time() - (ns.sessionStartTime or time())
        sessionLabel:SetText(string.format("Session duration: %dm %ds",
            math.floor(sessionDuration / 60), sessionDuration % 60))

        -- Update filter dropdown text
        for _, item in ipairs(CATEGORY_FILTERS) do
            if item.value == selectedFilter then
                UIDropDownMenu_SetText(filterDD, item.text)
                break
            end
        end

        for i = 1, MAX_STAT_ROWS do
            local row = rows[i]
            local index = i + offset
            if index <= #filteredKeys then
                local key = filteredKeys[index]
                local name, icon, category, spellId = ns:GetActivityMeta(key)
                local session = ns.activitySession and ns.activitySession[key]
                local persistent = ns.db and ns.db.activity and ns.db.activity[key]

                row.activityKey = key
                row.iconTex:SetTexture(icon)
                row.nameText:SetText(name or key)
                row.sessActText:SetText(tostring(session and session.activations or 0))
                row.sessUpText:SetText(FormatUptime(session and session.uptime or 0))
                row.allActText:SetText(tostring(persistent and persistent.activations or 0))
                row.allUpText:SetText(FormatUptime(persistent and persistent.uptime or 0))

                if key == selectedKey then
                    row.selected:Show()
                else
                    row.selected:Hide()
                end
                row:Show()
            else
                row.activityKey = nil
                row:Hide()
            end
        end

        RefreshGroupDropdown()
    end

    scrollFrame:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, STAT_ROW_HEIGHT, function() frame:RefreshList() end)
    end)

    -- Refresh when shown
    frame:SetScript("OnShow", function(self)
        selectedKey = nil
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
