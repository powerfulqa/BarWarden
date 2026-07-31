-- Options_Stats.lua - Activity Tracker stats tab.
-- Author:  Serv
-- Source:  https://github.com/powerfulqa/BarWarden
-- License: see LICENSE; attribution preservation is required.

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
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -16)
    title:SetText("Activity Tracker")
    ns:CreateHelpIcon(frame, title, "LEFT", "RIGHT", 8, 0, "activity-overview")

    local desc = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    desc:SetJustifyH("LEFT")
    if desc.SetWordWrap then desc:SetWordWrap(true) end
    if ns.ApplyWidth then ns:ApplyWidth(desc, 32) end
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

    -- The Activity table (group labels, headers, list) is a FIXED width sized
    -- to its columns + scrollbar, so it does NOT stretch across the window and
    -- the scrollbar sits right after the last column instead of floating far to
    -- the right. Columns are left-packed and fit within this width.
    local STAT_TABLE_WIDTH = 364
    local groupLabelFrame = CreateFrame("Frame", nil, frame)
    groupLabelFrame:SetPoint("TOPLEFT", sessionLabel, "BOTTOMLEFT", 0, -8)
    groupLabelFrame:SetWidth(STAT_TABLE_WIDTH)
    groupLabelFrame:SetHeight(14)

    -- Right-anchored to sit centred over the right-anchored numeric column
    -- pairs below (offsets match the header column maths).
    local gSession = groupLabelFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    gSession:SetPoint("RIGHT", groupLabelFrame, "RIGHT", -128, 0)
    gSession:SetText("--- Session ---")
    gSession:SetWidth(94)
    gSession:SetJustifyH("CENTER")
    gSession:SetTextColor(0.5, 0.8, 1.0)

    local gAllTime = groupLabelFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    gAllTime:SetPoint("RIGHT", groupLabelFrame, "RIGHT", -26, 0)
    gAllTime:SetText("--- All-Time ---")
    gAllTime:SetWidth(94)
    gAllTime:SetJustifyH("CENTER")
    gAllTime:SetTextColor(1.0, 0.82, 0.0)

    -- Column headers
    local headerFrame = CreateFrame("Frame", nil, frame)
    headerFrame:SetPoint("TOPLEFT", groupLabelFrame, "BOTTOMLEFT", 0, -2)
    headerFrame:SetWidth(STAT_TABLE_WIDTH)
    headerFrame:SetHeight(14)

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
    local function MakeSortHeader(anchor, anchorPoint, offsetX, width, baseText, sortKey, justify, defaultDir, selfPoint, tip)
        local btn = CreateFrame("Button", nil, headerFrame)
        btn:SetSize(width, 14)
        btn:SetPoint(selfPoint or "LEFT", anchor, anchorPoint, offsetX, 0)
        local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetAllPoints(btn)
        fs:SetJustifyH(justify or "RIGHT")
        fs:SetText(baseText)
        btn.fs = fs
        btn:SetScript("OnEnter", function(self)
            self.fs:SetTextColor(1, 1, 1)
            if tip then
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText(tip, 1, 1, 1, 1, true)
                GameTooltip:Show()
            end
        end)
        btn:SetScript("OnLeave", function(self)
            self.fs:SetTextColor(1, 0.82, 0)
            GameTooltip:Hide()
        end)
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

    -- Numeric columns are anchored from the RIGHT (fixed widths) so they stay
    -- put; the Name column flexes between the icon and the numeric block, so
    -- when the table narrows it is the name that truncates - the numbers always
    -- stay readable. The -26 on the rightmost column matches the row's scrollbar
    -- inset (-22) + padding so header and row columns line up.
    local hAllUp   = MakeSortHeader(headerFrame, "RIGHT", -26, 50, "Uptime", "allUptime",  "RIGHT", "desc", "RIGHT",
        "All-Time uptime: total time this effect has been active. Click to sort.")
    local hAllAct  = MakeSortHeader(hAllUp,      "LEFT",   -4, 40, "Procs",  "allProcs",   "RIGHT", "desc", "RIGHT",
        "All-Time procs: how many times this has fired in total. Click to sort.")
    local hSessUp  = MakeSortHeader(hAllAct,     "LEFT",   -8, 50, "Uptime", "sessUptime", "RIGHT", "desc", "RIGHT",
        "This session's uptime. Click to sort.")
    local hSessAct = MakeSortHeader(hSessUp,     "LEFT",   -4, 40, "Procs",  "sessProcs",  "RIGHT", "desc", "RIGHT",
        "This session's procs. Click to sort.")
    local hName    = MakeSortHeader(hIcon,       "RIGHT",   2, 60, "Name",   "name",       "LEFT",  "asc", nil,
        "Spell or effect name. Click to sort A-Z.")
    hName:SetPoint("RIGHT", hSessAct, "LEFT", -4, 0)  -- flex to the numeric block

    -- ========================================================================
    -- Stat list (FauxScrollFrame)
    -- ========================================================================
    local listFrame = CreateFrame("Frame", "BarWardenStatList", frame)
    listFrame:SetPoint("TOPLEFT", headerFrame, "BOTTOMLEFT", 0, -4)
    listFrame:SetWidth(STAT_TABLE_WIDTH)
    listFrame:SetHeight(MAX_STAT_ROWS * STAT_ROW_HEIGHT + 4)

    local listBg = listFrame:CreateTexture(nil, "BACKGROUND")
    listBg:SetAllPoints()
    listBg:SetTexture(0, 0, 0, 0.3)

    local scrollFrame = CreateFrame("ScrollFrame", "BarWardenStatScrollFrame", listFrame, "FauxScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 2, -2)
    scrollFrame:SetPoint("BOTTOMRIGHT", -22, 2)

    local rows = {}
    for i = 1, MAX_STAT_ROWS do
        -- Rows stretch to the list width so the hover/selection highlight spans
        -- the full box; the columns inside keep their fixed left-aligned layout.
        local row = CreateFrame("Button", "BarWardenStatRow" .. i, listFrame)
        row:SetHeight(STAT_ROW_HEIGHT)
        if i == 1 then
            row:SetPoint("TOPLEFT",  listFrame, "TOPLEFT",   2, -2)
            row:SetPoint("TOPRIGHT", listFrame, "TOPRIGHT", -22, -2)
        else
            row:SetPoint("TOPLEFT",  rows[i - 1], "BOTTOMLEFT",  0, 0)
            row:SetPoint("TOPRIGHT", rows[i - 1], "BOTTOMRIGHT", 0, 0)
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

        -- Numeric columns anchored from the RIGHT (fixed widths, aligned with
        -- the headers). The name flexes between the icon and the numeric block;
        -- when the table narrows it is the name that truncates, not the numbers.
        local allUpText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        allUpText:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        allUpText:SetWidth(50)
        allUpText:SetJustifyH("RIGHT")
        row.allUpText = allUpText

        local allActText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        allActText:SetPoint("RIGHT", allUpText, "LEFT", -4, 0)
        allActText:SetWidth(40)
        allActText:SetJustifyH("RIGHT")
        row.allActText = allActText

        local sessUpText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        sessUpText:SetPoint("RIGHT", allActText, "LEFT", -8, 0)
        sessUpText:SetWidth(50)
        sessUpText:SetJustifyH("RIGHT")
        row.sessUpText = sessUpText

        local sessActText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        sessActText:SetPoint("RIGHT", sessUpText, "LEFT", -4, 0)
        sessActText:SetWidth(40)
        sessActText:SetJustifyH("RIGHT")
        row.sessActText = sessActText

        local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        nameText:SetPoint("LEFT", iconTex, "RIGHT", 4, 0)
        nameText:SetPoint("RIGHT", sessActText, "LEFT", -4, 0)
        nameText:SetJustifyH("LEFT")
        if nameText.SetWordWrap then nameText:SetWordWrap(false) end
        row.nameText = nameText

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
    local createBarBtn = ns:CreateButton(frame, "Create Bar", 100, function()
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

    -- Search + filter anchoring is set below, after resetAllBtn exists (they
    -- form a third row aligned to the two button columns above).

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
    -- Reset All nudged right so its left edge lines up with the group dropdown
    -- (row above) and the filter dropdown (row below). Dropdowns sit ~14 px
    -- right of their frame (their left texture), hence the larger gap here than
    -- a plain button-to-button spacing.
    resetAllBtn:SetPoint("LEFT", resetSessionBtn, "RIGHT", 9, 0)

    -- Column layout for the two rows below the reset row:
    --   * Search sits directly under Create Bar / Reset Session and is anchored
    --     to BOTH bottom corners of Reset Session, so it is exactly the same
    --     width as the button; the +5 left offset cancels the edit box's left
    --     border texture so the visible box lines up with the button edge.
    --   * The filter is anchored DIRECTLY to the group dropdown (same widget
    --     type, 0 x-offset) so their left edges match exactly. The y offsets
    --     drop both onto the same row.
    searchEdit:SetPoint("TOPLEFT",  resetSessionBtn, "BOTTOMLEFT",  5, -22)
    searchEdit:SetPoint("TOPRIGHT", resetSessionBtn, "BOTTOMRIGHT", 0, -22)
    filterDD:SetPoint("TOPLEFT",    groupDD,          "BOTTOMLEFT",  0, -45)

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

    -- Empty-state line: shown when the list renders no rows. Distinguishes
    -- "nothing tracked yet" from "your search/filter hid everything".
    local emptyText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    emptyText:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", 6, -8)
    emptyText:SetJustifyH("LEFT")
    emptyText:Hide()

    function frame:RefreshList()
        UpdateHeaderArrows()
        filteredKeys = GetFilteredKeys(selectedFilter, searchText, sortColumn, sortDirection)
        local offset = FauxScrollFrame_GetOffset(scrollFrame)
        FauxScrollFrame_Update(scrollFrame, #filteredKeys, MAX_STAT_ROWS, STAT_ROW_HEIGHT)

        if #filteredKeys == 0 then
            -- GetAllActivityKeys returns a SET (string keys), so `#` is always 0.
            -- Test emptiness with next() to tell "nothing tracked yet" apart from
            -- "your search/filter hid everything".
            local allKeys = ns.GetAllActivityKeys and ns:GetAllActivityKeys() or {}
            if next(allKeys) == nil then
                emptyText:SetText("Activate bars and play to see tracking data here.")
            else
                emptyText:SetText("No effects match your search.")
            end
            emptyText:Show()
        else
            emptyText:Hide()
        end

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
    -- Responsive table width: fit the panel so it never clips off the right at
    -- the smallest window (the Name column truncates instead - still legible),
    -- capped at the natural column width so it does not stretch on a big window.
    local function reflowStatTable()
        local avail = frame:GetWidth()
        if not avail or avail < 50 then return end
        local w = math.min(avail - 32, STAT_TABLE_WIDTH)
        if w < 290 then w = 290 end
        groupLabelFrame:SetWidth(w)
        headerFrame:SetWidth(w)
        listFrame:SetWidth(w)

        -- Align the right-hand column of controls below the list (the two
        -- dropdowns and Reset All) to the table's right edge, so the whole
        -- panel reads as one block instead of stopping short. The left column
        -- (Create Bar / Reset Session / Search) stays a fixed 100 wide; these
        -- three fill the rest. Row left is the list's left, so the target
        -- right edge is `w`. Reset All is a plain button (no chrome): left
        -- ~109 px in, so width w-109 lands its right edge on `w`. A
        -- UIDropDownMenu frame sits ~96 px in and SetWidth adds ~25 px of
        -- template chrome, with the arrow button at the frame's right edge, so
        -- width w-124 puts the frame right - and the arrow - on `w` rather than
        -- clipping ~11 px past it.
        UIDropDownMenu_SetWidth(groupDD,  math.max(110, w - 124))
        UIDropDownMenu_SetWidth(filterDD, math.max(110, w - 124))
        resetAllBtn:SetWidth(math.max(90, w - 109))
    end

    frame:SetScript("OnShow", function(self)
        selectedKey = nil
        self._refreshAccum = 0
        reflowStatTable()
        self:RefreshList()
    end)
    frame:SetScript("OnSizeChanged", function() reflowStatTable() end)

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
            -- Skip the auto-refresh while a dropdown menu is open: RefreshList
            -- re-sets the dropdown text / re-initialises the group picker, which
            -- snaps an open menu shut mid-click. Don't reset the timer, so the
            -- refresh fires as soon as the menu closes. (The list is still fully
            -- interactive; only the 2s live tick is paused during selection.)
            if DropDownList1 and DropDownList1:IsShown() then return end
            self._refreshAccum = 0
            self:RefreshList()
        end
    end)

    return frame
end

ns:RegisterOptionsTab(5, CreateStatsTab)
