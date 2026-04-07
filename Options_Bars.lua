local addonName, ns = ...

-- ============================================================================
-- Options_Bars.lua - Tab 2: Bars / Groups configuration
-- ============================================================================

local TRACK_MODES = { "Cooldown", "Buff", "Debuff", "Proc", "Item" }
local TARGET_UNITS = { "player", "target", "focus", "pet", "mouseover" }
local GROUP_LIST_HEIGHT = 16
local BAR_LIST_HEIGHT = 16
local MAX_GROUP_ROWS = 5
local MAX_BAR_ROWS = 5

-- Helper: create a new default bar table
local function NewBar(name)
    return {
        name = name or "New Bar",
        enabled = true,
        trackMode = "Cooldown",
        target = "player",
        spellName = "",
        spellId = nil,
        itemId = nil,
        onlyMine = true,
        conditions = {
            combatOnly = false,
            outOfCombatOnly = false,
            requireBuff = nil,
            healthBelow = nil,
            inGroup = false,
            inRaid = false,
            hideWhenInactive = false,
            showEmpty = true,
        },
        display = {
            progressDirection = "LTR",
            lingerTime = 0,
            showIcon = nil,
            showText = nil,
            textFormat = nil,
            colorOverride = nil,
            textureOverride = nil,
            style = nil,
        },
    }
end

-- Helper: create a new default group (frame) table
local function NewGroup(name)
    return {
        name = name or "New Group",
        enabled = true,
        locked = true,
        visible = true,
        position = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 0 },
        width = 200,
        columns = 1,
        bgAlpha = 0.6,
        borderAlpha = 0.8,
        scale = 1.0,
        bars = {},
    }
end

-- ============================================================================
-- Main Tab Creation
-- ============================================================================

local selectedGroupIndex = nil
local selectedBarIndex = nil

local function CreateBarsTab(parent)
    local frame = CreateFrame("Frame", "BarWardenBarsTab", parent)
    frame:SetAllPoints(parent)
    frame:Hide()

    -- ========================================================================
    -- LEFT PANEL: Group List
    -- ========================================================================
    local leftPanel = CreateFrame("Frame", nil, frame)
    leftPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -80)
    leftPanel:SetSize(180, 360)

    local groupHeader = leftPanel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    groupHeader:SetPoint("TOPLEFT", leftPanel, "TOPLEFT", 0, 0)
    groupHeader:SetText("Groups")

    -- Group scroll frame
    local groupScrollFrame = CreateFrame("ScrollFrame", "BarWardenGroupScroll", leftPanel, "FauxScrollFrameTemplate")
    groupScrollFrame:SetPoint("TOPLEFT", groupHeader, "BOTTOMLEFT", 0, -6)
    groupScrollFrame:SetSize(170, MAX_GROUP_ROWS * GROUP_LIST_HEIGHT)

    local groupRows = {}
    for i = 1, MAX_GROUP_ROWS do
        local row = CreateFrame("Button", "BarWardenGroupRow" .. i, leftPanel)
        row:SetSize(170, GROUP_LIST_HEIGHT)
        if i == 1 then
            row:SetPoint("TOPLEFT", groupScrollFrame, "TOPLEFT", 0, 0)
        else
            row:SetPoint("TOPLEFT", groupRows[i - 1], "BOTTOMLEFT", 0, 0)
        end

        local highlight = row:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetTexture(1, 1, 1, 0.1)

        local selected = row:CreateTexture(nil, "BACKGROUND")
        selected:SetAllPoints()
        selected:SetTexture(0.2, 0.4, 0.8, 0.3)
        selected:Hide()
        row.selected = selected

        local text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        text:SetPoint("LEFT", row, "LEFT", 4, 0)
        text:SetJustifyH("LEFT")
        text:SetWidth(160)
        row.text = text

        row:SetScript("OnClick", function(self)
            selectedGroupIndex = self.index
            selectedBarIndex = nil
            frame:Refresh()
        end)

        groupRows[i] = row
    end

    -- Group buttons
    local addGroupBtn = ns:CreateButton(leftPanel, "Add", 54, function()
        local frames = BarWardenDB.frames
        local group = NewGroup("Group " .. (#frames + 1))
        table.insert(frames, group)
        selectedGroupIndex = #frames
        selectedBarIndex = nil
        frame:Refresh()
        ns:RebuildAllFrames()
    end)
    addGroupBtn:SetPoint("TOPLEFT", groupScrollFrame, "BOTTOMLEFT", 0, -4)

    local deleteGroupBtn = ns:CreateButton(leftPanel, "Delete", 54, function()
        if not selectedGroupIndex then return end
        local frames = BarWardenDB.frames
        local g = frames[selectedGroupIndex]
        if not g then return end
        local popup = StaticPopup_Show("BARWARDEN_CONFIRM_DELETE", g.name or "this group")
        if popup then
            popup.data = {
                onAccept = function()
                    table.remove(frames, selectedGroupIndex)
                    if selectedGroupIndex > #frames then
                        selectedGroupIndex = #frames > 0 and #frames or nil
                    end
                    selectedBarIndex = nil
                    frame:Refresh()
                    ns:RebuildAllFrames()
                end,
            }
        end
    end)
    deleteGroupBtn:SetPoint("LEFT", addGroupBtn, "RIGHT", 2, 0)

    local dupeGroupBtn = ns:CreateButton(leftPanel, "Dupe", 54, function()
        if not selectedGroupIndex then return end
        local frames = BarWardenDB.frames
        local g = frames[selectedGroupIndex]
        if not g then return end
        local copy = ns:CopyTable(g)
        copy.name = g.name .. " (copy)"
        copy.position.x = copy.position.x + 20
        copy.position.y = copy.position.y - 20
        table.insert(frames, copy)
        selectedGroupIndex = #frames
        selectedBarIndex = nil
        frame:Refresh()
        ns:RebuildAllFrames()
    end)
    dupeGroupBtn:SetPoint("LEFT", deleteGroupBtn, "RIGHT", 2, 0)

    -- Group name edit
    local groupNameEdit = ns:CreateEditBox(leftPanel, "Group Name", 170, function(self, text)
        if selectedGroupIndex and BarWardenDB.frames[selectedGroupIndex] then
            BarWardenDB.frames[selectedGroupIndex].name = text
            local gf = ns.groupFrames[selectedGroupIndex]
            if gf and gf.titleText then gf.titleText:SetText(text) end
            frame:Refresh()
        end
    end)
    groupNameEdit:SetPoint("TOPLEFT", addGroupBtn, "BOTTOMLEFT", 0, -12)

    -- Group width slider
    local groupWidthSlider = ns:CreateSlider(leftPanel, "Width", 50, 400, 5, function(self, value)
        if selectedGroupIndex and BarWardenDB.frames[selectedGroupIndex] then
            BarWardenDB.frames[selectedGroupIndex].width = value
            local gf = ns.groupFrames[selectedGroupIndex]
            if gf then ns:UpdateGroupLayout(gf) end
        end
    end)
    groupWidthSlider:SetPoint("TOPLEFT", groupNameEdit, "BOTTOMLEFT", 4, -16)
    groupWidthSlider:SetWidth(160)

    -- Group scale slider
    local groupScaleSlider = ns:CreateSlider(leftPanel, "Scale", 0.5, 2.0, 0.1, function(self, value)
        if selectedGroupIndex then
            ns:SetFrameScale(selectedGroupIndex, value)
            if BarWardenDB.frames[selectedGroupIndex] then
                BarWardenDB.frames[selectedGroupIndex].scale = value
            end
        end
    end)
    groupScaleSlider:SetPoint("TOPLEFT", groupWidthSlider, "BOTTOMLEFT", 0, -20)
    groupScaleSlider:SetWidth(160)

    -- Group columns slider (1-4)
    local groupColumnsSlider = ns:CreateSlider(leftPanel, "Columns", 1, 4, 1, function(self, value)
        if selectedGroupIndex then
            ns:SetGroupColumns(selectedGroupIndex, value)
        end
    end)
    groupColumnsSlider:SetPoint("TOPLEFT", groupScaleSlider, "BOTTOMLEFT", 0, -20)
    groupColumnsSlider:SetWidth(160)

    -- Group background opacity slider
    local groupBgAlphaSlider = ns:CreateSlider(leftPanel, "Background Opacity", 0, 1, 0.05, function(self, value)
        if selectedGroupIndex then
            ns:SetGroupBgAlpha(selectedGroupIndex, value)
        end
    end)
    groupBgAlphaSlider:SetPoint("TOPLEFT", groupColumnsSlider, "BOTTOMLEFT", 0, -20)
    groupBgAlphaSlider:SetWidth(160)

    -- Group border opacity slider
    local groupBorderAlphaSlider = ns:CreateSlider(leftPanel, "Border Opacity", 0, 1, 0.05, function(self, value)
        if selectedGroupIndex then
            ns:SetGroupBorderAlpha(selectedGroupIndex, value)
        end
    end)
    groupBorderAlphaSlider:SetPoint("TOPLEFT", groupBgAlphaSlider, "BOTTOMLEFT", 0, -20)
    groupBorderAlphaSlider:SetWidth(160)

    -- ========================================================================
    -- RIGHT PANEL: Bar List + Bar Editor
    -- ========================================================================
    local rightPanel = CreateFrame("Frame", nil, frame)
    rightPanel:SetPoint("TOPLEFT", leftPanel, "TOPRIGHT", 16, 0)
    rightPanel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 8)

    local barHeader = rightPanel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    barHeader:SetPoint("TOPLEFT", rightPanel, "TOPLEFT", 0, 0)
    barHeader:SetText("Bars")

    -- Bar scroll frame
    local barScrollFrame = CreateFrame("ScrollFrame", "BarWardenBarScroll", rightPanel, "FauxScrollFrameTemplate")
    barScrollFrame:SetPoint("TOPLEFT", barHeader, "BOTTOMLEFT", 0, -6)
    barScrollFrame:SetSize(360, MAX_BAR_ROWS * BAR_LIST_HEIGHT)

    local barRows = {}
    for i = 1, MAX_BAR_ROWS do
        local row = CreateFrame("Button", "BarWardenBarRow" .. i, rightPanel)
        row:SetSize(360, BAR_LIST_HEIGHT)
        if i == 1 then
            row:SetPoint("TOPLEFT", barScrollFrame, "TOPLEFT", 0, 0)
        else
            row:SetPoint("TOPLEFT", barRows[i - 1], "BOTTOMLEFT", 0, 0)
        end

        local highlight = row:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetTexture(1, 1, 1, 0.1)

        local selected = row:CreateTexture(nil, "BACKGROUND")
        selected:SetAllPoints()
        selected:SetTexture(0.2, 0.4, 0.8, 0.3)
        selected:Hide()
        row.selected = selected

        local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        nameText:SetPoint("LEFT", row, "LEFT", 4, 0)
        nameText:SetJustifyH("LEFT")
        nameText:SetWidth(120)
        row.nameText = nameText

        local modeText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        modeText:SetPoint("LEFT", row, "LEFT", 128, 0)
        modeText:SetJustifyH("LEFT")
        modeText:SetWidth(70)
        row.modeText = modeText

        local targetText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        targetText:SetPoint("LEFT", row, "LEFT", 200, 0)
        targetText:SetJustifyH("LEFT")
        targetText:SetWidth(70)
        row.targetText = targetText

        local spellText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        spellText:SetPoint("LEFT", row, "LEFT", 274, 0)
        spellText:SetJustifyH("LEFT")
        spellText:SetWidth(80)
        row.spellText = spellText

        row:SetScript("OnClick", function(self)
            selectedBarIndex = self.index
            frame:Refresh()
        end)

        barRows[i] = row
    end

    -- Bar list buttons
    local addBarBtn = ns:CreateButton(rightPanel, "Add Bar", 70, function()
        if not selectedGroupIndex then return end
        local g = BarWardenDB.frames[selectedGroupIndex]
        if not g then return end
        local bar = NewBar("Bar " .. (#g.bars + 1))
        table.insert(g.bars, bar)
        selectedBarIndex = #g.bars
        frame:Refresh()
        ns:RebuildAllFrames()
    end)
    addBarBtn:SetPoint("TOPLEFT", barScrollFrame, "BOTTOMLEFT", 0, -4)

    local deleteBarBtn = ns:CreateButton(rightPanel, "Delete Bar", 70, function()
        if not selectedGroupIndex or not selectedBarIndex then return end
        local g = BarWardenDB.frames[selectedGroupIndex]
        if not g then return end
        local bar = g.bars[selectedBarIndex]
        if not bar then return end
        local popup = StaticPopup_Show("BARWARDEN_CONFIRM_DELETE", bar.name or "this bar")
        if popup then
            popup.data = {
                onAccept = function()
                    table.remove(g.bars, selectedBarIndex)
                    if selectedBarIndex > #g.bars then
                        selectedBarIndex = #g.bars > 0 and #g.bars or nil
                    end
                    frame:Refresh()
                    ns:RebuildAllFrames()
                end,
            }
        end
    end)
    deleteBarBtn:SetPoint("LEFT", addBarBtn, "RIGHT", 2, 0)

    local moveUpBtn = ns:CreateButton(rightPanel, "Up", 40, function()
        if not selectedGroupIndex or not selectedBarIndex then return end
        local bars = BarWardenDB.frames[selectedGroupIndex].bars
        if selectedBarIndex <= 1 then return end
        bars[selectedBarIndex], bars[selectedBarIndex - 1] = bars[selectedBarIndex - 1], bars[selectedBarIndex]
        selectedBarIndex = selectedBarIndex - 1
        frame:Refresh()
        ns:RebuildAllFrames()
    end)
    moveUpBtn:SetPoint("LEFT", deleteBarBtn, "RIGHT", 2, 0)

    local moveDownBtn = ns:CreateButton(rightPanel, "Down", 40, function()
        if not selectedGroupIndex or not selectedBarIndex then return end
        local bars = BarWardenDB.frames[selectedGroupIndex].bars
        if selectedBarIndex >= #bars then return end
        bars[selectedBarIndex], bars[selectedBarIndex + 1] = bars[selectedBarIndex + 1], bars[selectedBarIndex]
        selectedBarIndex = selectedBarIndex + 1
        frame:Refresh()
        ns:RebuildAllFrames()
    end)
    moveDownBtn:SetPoint("LEFT", moveUpBtn, "RIGHT", 2, 0)

    -- ========================================================================
    -- BAR EDITOR SUB-PANEL (scroll frame so content doesn't clip)
    -- ========================================================================
    local editorPanel = CreateFrame("Frame", nil, rightPanel)
    editorPanel:SetPoint("TOPLEFT", addBarBtn, "BOTTOMLEFT", 0, -12)
    editorPanel:SetPoint("BOTTOMRIGHT", rightPanel, "BOTTOMRIGHT", 0, 0)

    local editorScroll = CreateFrame("ScrollFrame", "BarWardenBarEditorScrollFrame", editorPanel, "UIPanelScrollFrameTemplate")
    editorScroll:SetPoint("TOPLEFT",     editorPanel, "TOPLEFT",     0,   0)
    editorScroll:SetPoint("BOTTOMRIGHT", editorPanel, "BOTTOMRIGHT", -24, 0)

    local ec = CreateFrame("Frame", nil, editorScroll)  -- ec = editor content (scroll child)
    ec:SetWidth(340)
    ec:SetHeight(500)
    editorScroll:SetScrollChild(ec)

    local editorHeader = ec:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    editorHeader:SetPoint("TOPLEFT", ec, "TOPLEFT", 0, 0)
    editorHeader:SetText("Bar Settings")

    -- Bar enabled checkbox
    local barEnabledCB = ns:CreateCheckbox(ec, "Enabled", "Enable or disable this bar", function(self, checked)
        local bar = frame:GetSelectedBar()
        if bar then
            bar.enabled = checked
            for _, liveBar in ipairs(ns:GetAllBars()) do
                if liveBar.barData == bar then
                    if checked then
                        local visual = BarWardenDB and BarWardenDB.visual or ns.DEFAULTS.visual
                        liveBar:SetAlpha(visual.inactiveAlpha or 0.3)
                        liveBar:Show()
                    else
                        ns:DeactivateBar(liveBar)
                        liveBar:Hide()
                    end
                    break
                end
            end
            local gf = selectedGroupIndex and ns.groupFrames[selectedGroupIndex]
            if gf then ns:UpdateGroupLayout(gf) end
        end
    end)
    barEnabledCB:SetPoint("TOPLEFT", editorHeader, "BOTTOMLEFT", 0, -4)

    -- Bar name
    local barNameEdit = ns:CreateEditBox(ec, "Bar Name", 140, function(self, text)
        local bar = frame:GetSelectedBar()
        if bar then
            bar.name = text
            frame:Refresh()
        end
    end)
    barNameEdit:SetPoint("TOPLEFT", barEnabledCB, "BOTTOMLEFT", 6, -18)

    -- Spell Name / ID
    local spellEdit = ns:CreateEditBox(ec, "Spell Name or ID", 140, function(self, text)
        local bar = frame:GetSelectedBar()
        if bar then
            -- Clear all legacy fields so old values don't override the new one
            bar.spell = nil
            bar.spellInput = nil
            local id = tonumber(text)
            if id then
                bar.spellId = id
                bar.spellName = nil
            else
                bar.spellId = nil
                bar.spellName = text
            end
            ns:ScanAllBars()
        end
    end)
    spellEdit:SetPoint("TOPLEFT", barNameEdit, "BOTTOMLEFT", 0, -18)

    -- Only Mine checkbox
    local onlyMineCB = ns:CreateCheckbox(ec, "Only Mine", "Only track auras cast by you", function(self, checked)
        local bar = frame:GetSelectedBar()
        if bar then
            bar.onlyMine = checked
            ns:ScanAllBars()
        end
    end)
    onlyMineCB:SetPoint("TOPLEFT", spellEdit, "BOTTOMLEFT", 0, -6)

    -- Track Mode dropdown
    local trackModeDD = ns:CreateDropdown(ec, "Track Mode", TRACK_MODES, function(dd, value, index)
        local bar = frame:GetSelectedBar()
        if bar then
            bar.trackMode = value
            ns:ScanAllBars()
        end
    end)
    trackModeDD:SetPoint("TOPLEFT", barNameEdit, "TOPRIGHT", 20, 16)

    -- Target dropdown
    local targetDD = ns:CreateDropdown(ec, "Target", TARGET_UNITS, function(dd, value, index)
        local bar = frame:GetSelectedBar()
        if bar then
            bar.unit = value
            bar.target = nil  -- clear legacy field so unit takes effect
            ns:ScanAllBars()
        end
    end)
    targetDD:SetPoint("TOPLEFT", trackModeDD, "BOTTOMLEFT", 0, -18)

    -- ========================================================================
    -- CONDITIONS SECTION
    -- ========================================================================
    local condHeader = ec:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    condHeader:SetPoint("TOPLEFT", onlyMineCB, "BOTTOMLEFT", 0, -12)
    condHeader:SetText("Conditions")

    local combatOnlyCB
    local oocOnlyCB

    combatOnlyCB = ns:CreateCheckbox(ec, "Combat Only", "Show only in combat", function(self, checked)
        local bar = frame:GetSelectedBar()
        if bar then
            if not bar.conditions then bar.conditions = {} end
            bar.conditions.combatOnly = checked
            if checked then
                bar.conditions.outOfCombatOnly = false
                oocOnlyCB:SetChecked(false)
            end
        end
    end)
    combatOnlyCB:SetPoint("TOPLEFT", condHeader, "BOTTOMLEFT", 0, -4)

    oocOnlyCB = ns:CreateCheckbox(ec, "Out of Combat Only", "Show only out of combat", function(self, checked)
        local bar = frame:GetSelectedBar()
        if bar then
            if not bar.conditions then bar.conditions = {} end
            bar.conditions.outOfCombatOnly = checked
            if checked then
                bar.conditions.combatOnly = false
                combatOnlyCB:SetChecked(false)
            end
        end
    end)
    oocOnlyCB:SetPoint("TOPLEFT", combatOnlyCB, "BOTTOMLEFT", 0, -2)

    local inGroupCB = ns:CreateCheckbox(ec, "In Group", "Show only when in a group", function(self, checked)
        local bar = frame:GetSelectedBar()
        if bar then
            if not bar.conditions then bar.conditions = {} end
            bar.conditions.inGroup = checked
        end
    end)
    inGroupCB:SetPoint("TOPLEFT", oocOnlyCB, "BOTTOMLEFT", 0, -2)

    local inRaidCB = ns:CreateCheckbox(ec, "In Raid", "Show only when in a raid", function(self, checked)
        local bar = frame:GetSelectedBar()
        if bar then
            if not bar.conditions then bar.conditions = {} end
            bar.conditions.inRaid = checked
        end
    end)
    inRaidCB:SetPoint("TOPLEFT", inGroupCB, "BOTTOMLEFT", 0, -2)

    local hideInactiveCB = ns:CreateCheckbox(ec, "Hide When Inactive", "Hide bar when not tracking", function(self, checked)
        local bar = frame:GetSelectedBar()
        if bar then
            if not bar.conditions then bar.conditions = {} end
            bar.conditions.hideWhenInactive = checked
        end
    end)
    hideInactiveCB:SetPoint("TOPLEFT", inRaidCB, "BOTTOMLEFT", 0, -2)

    local showEmptyCB = ns:CreateCheckbox(ec, "Show Empty Bar", "Show bar even when not active", function(self, checked)
        local bar = frame:GetSelectedBar()
        if bar then
            if not bar.conditions then bar.conditions = {} end
            bar.conditions.showEmpty = checked
        end
    end)
    showEmptyCB:SetPoint("TOPLEFT", hideInactiveCB, "BOTTOMLEFT", 0, -2)

    local healthEdit = ns:CreateEditBox(ec, "Health Below %", 60, function(self, text)
        local bar = frame:GetSelectedBar()
        if bar then
            local val = tonumber(text)
            bar.conditions.healthBelow = (val and val > 0 and val <= 100) and val or nil
        end
    end)
    healthEdit:SetPoint("TOPLEFT", showEmptyCB, "BOTTOMLEFT", 6, -18)

    local requireBuffEdit = ns:CreateEditBox(ec, "Require Buff", 140, function(self, text)
        local bar = frame:GetSelectedBar()
        if bar then
            if not bar.conditions then bar.conditions = {} end
            bar.conditions.requireBuff = (text and text ~= "") and text or nil
        end
    end)
    requireBuffEdit:SetPoint("TOPLEFT", healthEdit, "BOTTOMLEFT", 0, -18)

    -- ========================================================================
    -- DISPLAY OPTIONS SECTION
    -- ========================================================================
    local displayHeader = ec:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    displayHeader:SetPoint("TOPLEFT", requireBuffEdit, "BOTTOMLEFT", 0, -12)
    displayHeader:SetText("Display Options")

    local lingerSlider = ns:CreateSlider(ec, "Linger Time (sec)", 0, 5, 0.5, function(self, value)
        local bar = frame:GetSelectedBar()
        if bar then bar.display.lingerTime = value end
    end)
    lingerSlider:SetPoint("TOPLEFT", displayHeader, "BOTTOMLEFT", 4, -24)
    lingerSlider:SetWidth(180)

    local showIconCB = ns:CreateCheckbox(ec, "Force Show Icon",
        "Force this bar to show its icon regardless of the global icon setting.", function(self, checked)
        local bar = frame:GetSelectedBar()
        if bar then
            bar.display.showIcon = checked or nil
            ns:RefreshAllBars()
        end
    end)
    showIconCB:SetPoint("TOPLEFT", lingerSlider, "BOTTOMLEFT", 0, -24)

    local showTextCB = ns:CreateCheckbox(ec, "Force Show Text",
        "Force this bar to show its name/timer text regardless of the global text setting.", function(self, checked)
        local bar = frame:GetSelectedBar()
        if bar then
            bar.display.showText = checked or nil
            ns:RefreshAllBars()
        end
    end)
    showTextCB:SetPoint("TOPLEFT", showIconCB, "BOTTOMLEFT", 0, -2)

    local colorSwatch = ns:CreateColorSwatch(ec, "Color Override", { r = 1, g = 1, b = 1, a = 1 }, function(self, color)
        local bar = frame:GetSelectedBar()
        if bar then
            bar.display.colorOverride = { r = color.r, g = color.g, b = color.b }
            ns:RefreshAllBars()
        end
    end)
    colorSwatch:SetPoint("TOPLEFT", showTextCB, "BOTTOMLEFT", 0, -8)

    -- ========================================================================
    -- HELPER: Get selected bar data
    -- ========================================================================
    function frame:GetSelectedBar()
        if not selectedGroupIndex or not selectedBarIndex then return nil end
        local g = BarWardenDB.frames[selectedGroupIndex]
        if not g then return nil end
        return g.bars[selectedBarIndex]
    end

    -- ========================================================================
    -- REFRESH
    -- ========================================================================
    local function UpdateGroupList()
        local frames = BarWardenDB and BarWardenDB.frames or {}
        local offset = FauxScrollFrame_GetOffset(groupScrollFrame)
        local total = #frames

        FauxScrollFrame_Update(groupScrollFrame, total, MAX_GROUP_ROWS, GROUP_LIST_HEIGHT)

        for i = 1, MAX_GROUP_ROWS do
            local row = groupRows[i]
            local idx = offset + i
            if idx <= total then
                local g = frames[idx]
                row.text:SetText(g.name or ("Group " .. idx))
                row.index = idx
                row:Show()
                if idx == selectedGroupIndex then
                    row.selected:Show()
                else
                    row.selected:Hide()
                end
            else
                row:Hide()
            end
        end
    end

    local function UpdateBarList()
        local bars = {}
        if selectedGroupIndex and BarWardenDB and BarWardenDB.frames[selectedGroupIndex] then
            bars = BarWardenDB.frames[selectedGroupIndex].bars or {}
        end
        local offset = FauxScrollFrame_GetOffset(barScrollFrame)
        local total = #bars

        FauxScrollFrame_Update(barScrollFrame, total, MAX_BAR_ROWS, BAR_LIST_HEIGHT)

        for i = 1, MAX_BAR_ROWS do
            local row = barRows[i]
            local idx = offset + i
            if idx <= total then
                local b = bars[idx]
                row.nameText:SetText(b.name or "")
                row.modeText:SetText(b.trackMode or "")
                row.targetText:SetText(b.target or "")
                row.spellText:SetText(b.spellName or "")
                row.index = idx
                row:Show()
                if idx == selectedBarIndex then
                    row.selected:Show()
                else
                    row.selected:Hide()
                end
            else
                row:Hide()
            end
        end
    end

    local function UpdateBarEditor()
        local bar = frame:GetSelectedBar()
        if not bar then
            editorPanel:Hide()
            return
        end
        editorPanel:Show()

        barEnabledCB:SetChecked(bar.enabled)
        barNameEdit:SetText(bar.name or "")
        spellEdit:SetText(bar.spellId and tostring(bar.spellId) or (bar.spellName or ""))
        onlyMineCB:SetChecked(bar.onlyMine)

        -- Track mode dropdown
        for i, mode in ipairs(TRACK_MODES) do
            if mode == bar.trackMode then
                UIDropDownMenu_SetSelectedID(trackModeDD, i)
                UIDropDownMenu_SetText(trackModeDD, mode)
                break
            end
        end

        -- Target dropdown (bar.unit is canonical after migration; bar.target is legacy fallback)
        local barUnit = bar.unit or bar.target or "player"
        for i, unit in ipairs(TARGET_UNITS) do
            if unit == barUnit then
                UIDropDownMenu_SetSelectedID(targetDD, i)
                UIDropDownMenu_SetText(targetDD, unit)
                break
            end
        end

        -- Conditions (guard: bars created outside the UI may lack this table)
        local cond = bar.conditions or {}
        combatOnlyCB:SetChecked(cond.combatOnly)
        oocOnlyCB:SetChecked(cond.outOfCombatOnly)
        inGroupCB:SetChecked(cond.inGroup)
        inRaidCB:SetChecked(cond.inRaid)
        hideInactiveCB:SetChecked(cond.hideWhenInactive)
        showEmptyCB:SetChecked(cond.showEmpty)
        healthEdit:SetText(cond.healthBelow and tostring(cond.healthBelow) or "")
        requireBuffEdit:SetText(cond.requireBuff or "")

        -- Display options
        lingerSlider:SetValue(bar.display.lingerTime or 0)
        showIconCB:SetChecked(bar.display.showIcon)
        showTextCB:SetChecked(bar.display.showText)

        if bar.display.colorOverride then
            colorSwatch.color.r = bar.display.colorOverride.r
            colorSwatch.color.g = bar.display.colorOverride.g
            colorSwatch.color.b = bar.display.colorOverride.b
            colorSwatch.swatch:SetTexture(bar.display.colorOverride.r, bar.display.colorOverride.g, bar.display.colorOverride.b, 1)
        else
            colorSwatch.swatch:SetTexture(1, 1, 1, 1)
        end
    end

    local function UpdateGroupName()
        if selectedGroupIndex and BarWardenDB and BarWardenDB.frames[selectedGroupIndex] then
            local g = BarWardenDB.frames[selectedGroupIndex]
            groupNameEdit:SetText(g.name or "")
            groupNameEdit:Show()
            groupWidthSlider:SetValue(g.width or 200)
            groupScaleSlider:SetValue(g.scale or 1.0)
            groupColumnsSlider:SetValue(g.columns or 1)
            groupBgAlphaSlider:SetValue(g.bgAlpha ~= nil and g.bgAlpha or 0.6)
            groupBorderAlphaSlider:SetValue(g.borderAlpha ~= nil and g.borderAlpha or 0.8)
        else
            groupNameEdit:SetText("")
        end
    end

    function frame:Refresh()
        if not BarWardenDB then return end

        -- Validate selection
        local frames = BarWardenDB.frames
        if selectedGroupIndex and (selectedGroupIndex < 1 or selectedGroupIndex > #frames) then
            selectedGroupIndex = #frames > 0 and 1 or nil
        end
        if selectedGroupIndex then
            local bars = frames[selectedGroupIndex].bars
            if selectedBarIndex and (selectedBarIndex < 1 or selectedBarIndex > #bars) then
                selectedBarIndex = #bars > 0 and 1 or nil
            end
        else
            selectedBarIndex = nil
        end

        UpdateGroupList()
        UpdateGroupName()
        UpdateBarList()
        UpdateBarEditor()
    end

    frame.Refresh = frame.Refresh

    -- FauxScrollFrame update hooks
    groupScrollFrame:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, GROUP_LIST_HEIGHT, UpdateGroupList)
    end)

    barScrollFrame:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, BAR_LIST_HEIGHT, UpdateBarList)
    end)

    return frame
end

-- ============================================================================
-- Register Tab
-- ============================================================================

local orig = ns.CreateOptionsPanel
ns.CreateOptionsPanel = function(self)
    local panel = orig(self)
    local tab = CreateBarsTab(panel)
    ns.optionsTabs[2] = tab
    return panel
end
