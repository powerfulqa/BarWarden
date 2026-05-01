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
local MAX_STAT_ROWS = 8
local ICON_SIZE = 16

local CATEGORY_FILTERS = {
    { text = "All",            value = "All" },
    { text = "Auras",          value = "Aura" },     -- virtual: Buff + Debuff
    { text = "Buffs",          value = "Buff" },
    { text = "Target Debuffs", value = "Debuff" },
    { text = "Cooldowns",      value = "Cooldown" },
    { text = "Enchants",       value = "Enchant" },
    { text = "Totems",         value = "Totem" },
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

local FormatUptime = ns.FormatUptime

-- ============================================================================
-- Sort: extract the numeric value for a key on the requested column.
-- ============================================================================
local function GetSortValue(key, column)
    if column == "sessProcs" then
        local s = ns.activitySession and ns.activitySession[key]
        return s and s.activations or 0
    elseif column == "sessUptime" then
        local s = ns.activitySession and ns.activitySession[key]
        return s and s.uptime or 0
    elseif column == "allProcs" then
        local p = ns.db and ns.db.activity and ns.db.activity[key]
        return p and p.activations or 0
    elseif column == "allUptime" then
        local p = ns.db and ns.db.activity and ns.db.activity[key]
        return p and p.uptime or 0
    end
    return 0
end

-- ============================================================================
-- Helper: build a filtered + sorted list of activity keys.
-- `searchText` is an optional substring filter applied to the spell name
-- (case-insensitive). Pass nil or empty to disable the text filter.
-- `sortColumn` is one of sessProcs / sessUptime / allProcs / allUptime.
-- `sortDirection` is "asc" or "desc". Alphabetical-by-name is the tiebreak.
-- ============================================================================
local function GetFilteredKeys(categoryFilter, searchText, sortColumn, sortDirection)
    local allKeys = ns.GetAllActivityKeys and ns:GetAllActivityKeys() or {}
    local result = {}
    local needle = (searchText and searchText ~= "") and searchText:lower() or nil

    for key in pairs(allKeys) do
        local name, _, category = ns:GetActivityMeta(key)
        local categoryMatch =
               categoryFilter == "All"
            or (categoryFilter == "Aura" and (category == "Buff" or category == "Debuff"))
            or category == categoryFilter
        local searchMatch = true
        if needle then
            searchMatch = name and name:lower():find(needle, 1, true) ~= nil
        end
        if categoryMatch and searchMatch then
            result[#result + 1] = key
        end
    end

    local ascending = sortDirection == "asc"
    table.sort(result, function(a, b)
        local aName = ns:GetActivityMeta(a) or ""
        local bName = ns:GetActivityMeta(b) or ""
        if sortColumn == "name" then
            if ascending then return aName < bName else return aName > bName end
        end
        local av = GetSortValue(a, sortColumn)
        local bv = GetSortValue(b, sortColumn)
        if av ~= bv then
            if ascending then return av < bv else return av > bv end
        end
        return aName < bName  -- alphabetical tiebreak
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
    local searchText = ""
    local sortColumn = "sessProcs"   -- sessProcs | sessUptime | allProcs | allUptime
    local sortDirection = "desc"     -- "asc" | "desc"
    local sortHeaders = {}           -- sortKey -> { btn = <Button>, baseText = <string> }

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

    -- Search filter: live substring match on spell name. Uses OnTextChanged
    -- (not the default CreateEditBox commit-on-exit) so the list filters as
    -- the user types.
    local searchEdit = ns:CreateEditBox(frame, "Search", 95, nil,
        "Filter the list by a substring of the spell name. Case-insensitive.")
    searchEdit:HookScript("OnTextChanged", function(self)
        searchText = self:GetText() or ""
        selectedKey = nil
        frame:RefreshList()
    end)

    -- Group labels row ("Session" and "All-Time" above their columns)
    local groupLabelFrame = CreateFrame("Frame", nil, frame)
    groupLabelFrame:SetPoint("TOPLEFT", sessionLabel, "BOTTOMLEFT", 0, -8)
    groupLabelFrame:SetSize(380, 14)

    local gSession = groupLabelFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    gSession:SetPoint("LEFT", groupLabelFrame, "LEFT", 140, 0)
    gSession:SetText("--- Session ---")
    gSession:SetWidth(100)
    gSession:SetJustifyH("CENTER")
    gSession:SetTextColor(0.5, 0.8, 1.0)

    local gAllTime = groupLabelFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    gAllTime:SetPoint("LEFT", gSession, "RIGHT", 8, 0)
    gAllTime:SetText("--- All-Time ---")
    gAllTime:SetWidth(100)
    gAllTime:SetJustifyH("CENTER")
    gAllTime:SetTextColor(1.0, 0.82, 0.0)

    -- Column headers
    local headerFrame = CreateFrame("Frame", nil, frame)
    headerFrame:SetPoint("TOPLEFT", groupLabelFrame, "BOTTOMLEFT", 0, -2)
    headerFrame:SetSize(380, 14)

    local hIcon = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hIcon:SetPoint("LEFT", headerFrame, "LEFT", 4, 0)
    hIcon:SetText("")
    hIcon:SetWidth(ICON_SIZE + 4)

    -- Build a clickable column header. The button is the click region; the
    -- inner FontString carries the label and gains an arrow indicator
    -- ("▼"/"▲") when this column is the active sort. Hover brightens the
    -- text so the click affordance is visible. `justify` is "LEFT" or "RIGHT"
    -- to match the column's data alignment; `defaultDir` is the direction
    -- used when this column first becomes active ("asc" for name, "desc" for
    -- numeric columns where high-first reads naturally).
    local function MakeSortHeader(anchor, anchorPoint, offsetX, width, baseText, sortKey, justify, defaultDir)
        local btn = CreateFrame("Button", nil, headerFrame)
        btn:SetSize(width, 14)
        btn:SetPoint("LEFT", anchor, anchorPoint, offsetX, 0)
        local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetAllPoints(btn)
        fs:SetJustifyH(justify or "RIGHT")
        fs:SetText(baseText)
        btn.fs = fs
        btn:SetScript("OnEnter", function(self) self.fs:SetTextColor(1, 1, 1) end)
        btn:SetScript("OnLeave", function(self) self.fs:SetTextColor(1, 0.82, 0) end)
        btn:SetScript("OnClick", function()
            if sortColumn == sortKey then
                sortDirection = (sortDirection == "desc") and "asc" or "desc"
            else
                sortColumn = sortKey
                sortDirection = defaultDir or "desc"
            end
            frame:RefreshList()
        end)
        sortHeaders[sortKey] = { btn = btn, baseText = baseText }
        return btn
    end

    local hName    = MakeSortHeader(hIcon,    "RIGHT", 2, 110, "Name",   "name",       "LEFT",  "asc")
    local hSessAct = MakeSortHeader(hName,    "RIGHT", 4, 40,  "Procs",  "sessProcs",  "RIGHT", "desc")
    local hSessUp  = MakeSortHeader(hSessAct, "RIGHT", 4, 50,  "Uptime", "sessUptime", "RIGHT", "desc")
    local hAllAct  = MakeSortHeader(hSessUp,  "RIGHT", 8, 40,  "Procs",  "allProcs",   "RIGHT", "desc")
    local hAllUp   = MakeSortHeader(hAllAct,  "RIGHT", 4, 50,  "Uptime", "allUptime",  "RIGHT", "desc")

    -- ========================================================================
    -- Stat list (FauxScrollFrame)
    -- ========================================================================
    local listFrame = CreateFrame("Frame", "BarWardenStatList", frame)
    listFrame:SetPoint("TOPLEFT", headerFrame, "BOTTOMLEFT", 0, -4)
    listFrame:SetSize(380, MAX_STAT_ROWS * STAT_ROW_HEIGHT + 4)

    local listBg = listFrame:CreateTexture(nil, "BACKGROUND")
    listBg:SetAllPoints()
    listBg:SetTexture(0, 0, 0, 0.3)

    local scrollFrame = CreateFrame("ScrollFrame", "BarWardenStatScrollFrame", listFrame, "FauxScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 2, -2)
    scrollFrame:SetPoint("BOTTOMRIGHT", -22, 2)

    local rows = {}
    for i = 1, MAX_STAT_ROWS do
        local row = CreateFrame("Button", "BarWardenStatRow" .. i, listFrame)
        row:SetSize(354, STAT_ROW_HEIGHT)
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

        -- Mouse-overlay button for the icon tooltip. Textures cannot carry
        -- script handlers in 3.3.5a, so an invisible Button sized to the icon
        -- drives OnEnter/OnLeave. A Button (not a Frame) means clicks on the
        -- icon still select the row instead of being silently swallowed.
        -- Mirrors the spellId-hyperlink fallback chain from Bar.lua's bar-icon
        -- tooltip.
        local iconHover = CreateFrame("Button", nil, row)
        iconHover:SetAllPoints(iconTex)
        iconHover:SetScript("OnEnter", function(self)
            local key = row.activityKey
            if not key then return end
            local name, _, _, spellId = ns:GetActivityMeta(key)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if spellId and spellId ~= 0 then
                GameTooltip:SetHyperlink("spell:" .. spellId)
            else
                GameTooltip:AddLine(name or key, 1, 1, 1)
                GameTooltip:Show()
            end
        end)
        iconHover:SetScript("OnLeave", function() GameTooltip:Hide() end)
        iconHover:SetScript("OnClick", function()
            selectedKey = row.activityKey
            frame:RefreshList()
        end)
        row.iconHover = iconHover

        local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        nameText:SetPoint("LEFT", iconTex, "RIGHT", 4, 0)
        nameText:SetWidth(106)
        nameText:SetJustifyH("LEFT")
        row.nameText = nameText

        local sessActText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        sessActText:SetPoint("LEFT", nameText, "RIGHT", 4, 0)
        sessActText:SetWidth(40)
        sessActText:SetJustifyH("RIGHT")
        row.sessActText = sessActText

        local sessUpText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        sessUpText:SetPoint("LEFT", sessActText, "RIGHT", 4, 0)
        sessUpText:SetWidth(50)
        sessUpText:SetJustifyH("RIGHT")
        row.sessUpText = sessUpText

        local allActText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        allActText:SetPoint("LEFT", sessUpText, "RIGHT", 8, 0)
        allActText:SetWidth(40)
        allActText:SetJustifyH("RIGHT")
        row.allActText = allActText

        local allUpText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        allUpText:SetPoint("LEFT", allActText, "RIGHT", 4, 0)
        allUpText:SetWidth(50)
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
    createBarBtn:SetPoint("TOPLEFT", listFrame, "BOTTOMLEFT", 0, -24)

    -- Group picker dropdown (no label; sits next to Create Bar button)
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

    -- Search sits alongside the group dropdown (same row as Create Bar).
    -- Filter dropdown stays on the reset row below.
    searchEdit:SetPoint("LEFT", groupDD, "RIGHT", 3, 1)
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
    -- Update each sortable header's text to show an arrow next to the
    -- currently active sort column. Called from RefreshList so the indicator
    -- stays in sync after any state change.
    local function UpdateHeaderArrows()
        local arrow = (sortDirection == "asc") and " ▲" or " ▼"
        for key, h in pairs(sortHeaders) do
            if key == sortColumn then
                h.btn.fs:SetText(h.baseText .. arrow)
            else
                h.btn.fs:SetText(h.baseText)
            end
        end
    end

    function frame:RefreshList()
        UpdateHeaderArrows()
        filteredKeys = GetFilteredKeys(selectedFilter, searchText, sortColumn, sortDirection)
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
        self._refreshAccum = 0
        self:RefreshList()
    end)

    -- Auto-refresh: WoW only runs OnUpdate on shown frames, so when another
    -- options tab is active this frame is hidden and the handler doesn't
    -- fire at all. No explicit visibility gate needed. 2s cadence means
    -- activations and uptime update live (session timer ticks, new procs
    -- appear) without forcing the user to re-click onto a row to redraw.
    local AUTO_REFRESH_INTERVAL = 2.0
    frame._refreshAccum = 0
    frame:SetScript("OnUpdate", function(self, elapsed)
        self._refreshAccum = self._refreshAccum + elapsed
        if self._refreshAccum >= AUTO_REFRESH_INTERVAL then
            self._refreshAccum = 0
            self:RefreshList()
        end
    end)

    return frame
end

ns:RegisterOptionsTab(5, CreateStatsTab)
