local addonName, ns = ...

-- ============================================================================
-- Options_Bars.lua - Tab 2: Bars / Groups configuration
-- ============================================================================

local TRACK_MODES = {
    "Cooldown", "Buff", "Debuff", "Proc",
    "Item", "Enchant MH", "Enchant OH", "Totem",
    -- Class resources (Combo Points/Runic Power/Soul Shards are event-driven;
    -- Runes is time-based with spellId as the slot number 1..6).
    "Combo Points", "Runes", "Runic Power", "Soul Shards",
}
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
            requireClass = nil,  -- set by class-starter presets; hides bar for other classes
            healthBelow = nil,
            inGroup = false,
            inRaid = false,
            hideWhileMounted = false,
            hideWhileResting = false,
            hideInVehicle = false,
            onlyInInstance = false,
            hideWhenInactive = false,
            showEmpty = true,
        },
        display = {
            progressDirection = "LTR",
            lingerTime = 0,
            barAlpha = 0.6,
            showName = nil,
            showIcon = nil,
            textFormat = nil,
            colorOverride = nil,
            textureOverride = nil,
            style = nil,
            -- Colour-by-time (nil = inherit global)
            colorByTime = nil,
            -- Glow on ready
            glowOnReady = false,
            -- Icon crop (nil = inherit global)
            iconCrop = nil,
            -- Per-bar scale multiplier (nil = 1.0 = group default)
            scaleOverride = nil,
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
        sortMode = "manual",
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
        if #frames >= (ns.MAX_FRAMES or 20) then
            ns:Print("Maximum of " .. (ns.MAX_FRAMES or 20) .. " groups reached.")
            return
        end
        local group = NewGroup("Group " .. (#frames + 1))
        table.insert(frames, group)
        selectedGroupIndex = #frames
        selectedBarIndex = nil
        frame:Refresh()
        ns:RebuildAllFrames()
    end)
    addGroupBtn:SetPoint("TOPLEFT", groupScrollFrame, "BOTTOMLEFT", 0, -4)

    local deleteGroupBtn = ns:CreateButton(leftPanel, "Delete", 54, function()
        if not selectedGroupIndex then ns:Print("Select a group first."); return end
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
        if not selectedGroupIndex then ns:Print("Select a group first."); return end
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

    -- Scrollable group settings area (below the group list and buttons)
    local groupSettingsScroll = CreateFrame("ScrollFrame", "BarWardenGroupSettingsScroll", leftPanel, "UIPanelScrollFrameTemplate")
    groupSettingsScroll:SetPoint("TOPLEFT", addGroupBtn, "BOTTOMLEFT", 0, -8)
    groupSettingsScroll:SetPoint("BOTTOMLEFT", leftPanel, "BOTTOMLEFT", 0, 19)
    groupSettingsScroll:SetWidth(170)

    local groupSettingsContent = CreateFrame("Frame", nil, groupSettingsScroll)
    groupSettingsContent:SetWidth(160)
    groupSettingsContent:SetHeight(340)
    groupSettingsScroll:SetScrollChild(groupSettingsContent)

    -- Group-settings schema: declarative via BuildSettings.
    -- All entries use get/set escape hatches because the target is the
    -- currently selected group (selectedGroupIndex), not a fixed DB path.

    local function getGroup()
        return selectedGroupIndex and BarWardenDB.frames[selectedGroupIndex]
    end

    local sortModeItems = {
        { text = "Manual",         value = "manual" },
        { text = "Remaining Time", value = "remaining" },
        { text = "Alphabetical",   value = "alpha" },
    }

    local GROUP_SETTINGS_SCHEMA = {
        { type = "editbox", label = "Group Name", width = 155,
          get = function() local g = getGroup(); return g and g.name or "" end,
          set = function(_, text)
              local g = getGroup(); if not g then return end
              g.name = text
              local gf = ns.groupFrames[selectedGroupIndex]
              if gf and gf.titleText then gf.titleText:SetText(text) end
              frame:Refresh()
          end,
          offsetX = 4 },
        { type = "toggle", label = "Show Group Name",
          tooltip = "Show or hide the group name on the bar frame.",
          get = function() local g = getGroup(); return g and g.showTitle ~= false end,
          set = function(_, checked)
              local g = getGroup(); if not g then return end
              g.showTitle = checked and true or false
              local gf = ns.groupFrames[selectedGroupIndex]
              if gf and gf.titleText then
                  if checked then gf.titleText:Show() else gf.titleText:Hide() end
              end
          end,
          offsetX = -6, spacing = 4 },
        { type = "slider", label = "Width", min = 50, max = 400, step = 5, width = 160,
          get = function() local g = getGroup(); return g and g.width or 200 end,
          set = function(_, value)
              local g = getGroup(); if not g then return end
              g.width = value
              local gf = ns.groupFrames[selectedGroupIndex]
              if gf then ns:UpdateGroupLayout(gf) end
          end,
          offsetX = 10, spacing = 12 },
        { type = "slider", label = "Scale", min = 0.5, max = 2.0, step = 0.1, width = 160,
          get = function() local g = getGroup(); return g and g.scale or 1.0 end,
          set = function(_, value)
              if not selectedGroupIndex then return end
              ns:SetFrameScale(selectedGroupIndex, value)
              local g = getGroup(); if g then g.scale = value end
          end,
          spacing = 16 },
        { type = "slider", label = "Columns", min = 1, max = 4, step = 1, width = 160,
          tooltip = "Number of columns the bars in this group are arranged into. "
               .. "1 = vertical stack (default); 2-4 splits the bars across that "
               .. "many columns side by side. Useful when tracking many bars in a "
               .. "compact footprint.",
          get = function() local g = getGroup(); return g and g.columns or 1 end,
          set = function(_, value)
              if selectedGroupIndex then ns:SetGroupColumns(selectedGroupIndex, value) end
          end,
          spacing = 16 },
        { type = "slider", label = "Background Opacity", min = 0, max = 1, step = 0.05, width = 160,
          get = function() local g = getGroup(); return g and (g.bgAlpha ~= nil and g.bgAlpha or 0.6) end,
          set = function(_, value)
              if selectedGroupIndex then ns:SetGroupBgAlpha(selectedGroupIndex, value) end
          end,
          spacing = 16 },
        { type = "slider", label = "Border Opacity", min = 0, max = 1, step = 0.05, width = 160,
          get = function() local g = getGroup(); return g and (g.borderAlpha ~= nil and g.borderAlpha or 0.8) end,
          set = function(_, value)
              if selectedGroupIndex then ns:SetGroupBorderAlpha(selectedGroupIndex, value) end
          end,
          spacing = 16 },
        { type = "dropdown", label = "Sort Mode", items = sortModeItems,
          get = function() local g = getGroup(); return g and g.sortMode or "manual" end,
          set = function(_, value)
              local g = getGroup(); if not g then return end
              g.sortMode = value
              local gf = ns.groupFrames[selectedGroupIndex]
              if gf then ns:UpdateGroupLayout(gf) end
          end,
          offsetX = -16, spacing = 28 },
    }

    local refreshGroupSettings = ns:BuildSettings(groupSettingsContent, GROUP_SETTINGS_SCHEMA, nil,
        { firstX = 0, firstY = 0 })

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
    -- Row layout: Name (90) + Mode (60) + Target (50) + padding = 220 px.
    -- The spell name was redundant with the bar name in nearly all cases
    -- and pushed the row out to 360 px with heavy trailing whitespace.
    local barScrollFrame = CreateFrame("ScrollFrame", "BarWardenBarScroll", rightPanel, "FauxScrollFrameTemplate")
    barScrollFrame:SetPoint("TOPLEFT", barHeader, "BOTTOMLEFT", 0, -6)
    barScrollFrame:SetSize(220, MAX_BAR_ROWS * BAR_LIST_HEIGHT)

    local barRows = {}
    for i = 1, MAX_BAR_ROWS do
        local row = CreateFrame("Button", "BarWardenBarRow" .. i, rightPanel)
        row:SetSize(220, BAR_LIST_HEIGHT)
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
        nameText:SetWidth(90)
        row.nameText = nameText

        local modeText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        modeText:SetPoint("LEFT", nameText, "RIGHT", 4, 0)
        modeText:SetJustifyH("LEFT")
        modeText:SetWidth(60)
        row.modeText = modeText

        local targetText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        targetText:SetPoint("LEFT", modeText, "RIGHT", 4, 0)
        targetText:SetJustifyH("LEFT")
        targetText:SetWidth(50)
        row.targetText = targetText

        row:SetScript("OnClick", function(self)
            selectedBarIndex = self.index
            frame:Refresh()
        end)

        barRows[i] = row
    end

    -- Bar list buttons ("Bar" is implicit from the section header above).
    local addBarBtn = ns:CreateButton(rightPanel, "Add", 50, function()
        if not selectedGroupIndex then ns:Print("Select a group first."); return end
        local g = BarWardenDB.frames[selectedGroupIndex]
        if not g then return end
        local maxBars = ns.MAX_BARS_PER_FRAME or 30
        if #g.bars >= maxBars then
            ns:Print("Maximum of " .. maxBars .. " bars per group reached.")
            return
        end
        local bar = NewBar("Bar " .. (#g.bars + 1))
        table.insert(g.bars, bar)
        selectedBarIndex = #g.bars
        frame:Refresh()
        ns:RebuildAllFrames()
    end)
    addBarBtn:SetPoint("TOPLEFT", barScrollFrame, "BOTTOMLEFT", 0, -4)

    local deleteBarBtn = ns:CreateButton(rightPanel, "Delete", 50, function()
        if not selectedGroupIndex or not selectedBarIndex then ns:Print("Select a bar first."); return end
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
        if not selectedGroupIndex or not selectedBarIndex then ns:Print("Select a bar first."); return end
        local bars = BarWardenDB.frames[selectedGroupIndex].bars
        if selectedBarIndex <= 1 then return end
        bars[selectedBarIndex], bars[selectedBarIndex - 1] = bars[selectedBarIndex - 1], bars[selectedBarIndex]
        selectedBarIndex = selectedBarIndex - 1
        frame:Refresh()
        ns:RebuildAllFrames()
    end)
    moveUpBtn:SetPoint("LEFT", deleteBarBtn, "RIGHT", 2, 0)

    local moveDownBtn = ns:CreateButton(rightPanel, "Down", 40, function()
        if not selectedGroupIndex or not selectedBarIndex then ns:Print("Select a bar first."); return end
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
    ec:SetWidth(340)   -- initial width; OnShow resizes to match the scroll viewport
    ec:SetHeight(660)  -- tall enough for the single-column layout, including
                       -- the per-bar Bar Scale slider added in 2026-04-15 polish.
    editorScroll:SetScrollChild(ec)

    local editorHeader = ec:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    editorHeader:SetPoint("TOPLEFT", ec, "TOPLEFT", 0, 0)
    editorHeader:SetText("")
    editorHeader:SetHeight(1)

    -- Bar enabled checkbox
    local barEnabledCB = ns:CreateCheckbox(ec, "Enabled", "Enable or disable this bar", function(self, checked)
        local bar = frame:GetSelectedBar()
        if bar then
            bar.enabled = checked
            for _, liveBar in ipairs(ns:GetAllBars()) do
                if liveBar.barData == bar then
                    if checked then
                        local visual = ns:GetVisual()
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
            frame:Refresh()  -- updates the bar-list row on the left
            ns:RefreshBarSettings()
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
            ns:RefreshBarSettings()
        end
    end,
    "The spell, item, or totem this bar tracks. Accepts a spell name "
 .. "(e.g. 'Evasion'), a numeric spell/item ID, or multiple "
 .. "comma-separated names for one bar to match any of them "
 .. "(e.g. 'Rupture, Garrote'). Press Enter to apply.")
    spellEdit:SetPoint("TOPLEFT", barNameEdit, "BOTTOMLEFT", 0, -18)

    -- Single-column layout: Track Mode and Target stack vertically below
    -- Spell. The -16 x offset on the dropdowns compensates for WoW's
    -- invisible ~16 px left padding on UIDropDownMenu so the dropdown's
    -- label aligns with the edit-box labels above.

    -- Track Mode dropdown
    local trackModeDD = ns:CreateDropdown(ec, "Track Mode", TRACK_MODES, function(dd, value, index)
        local bar = frame:GetSelectedBar()
        if bar then
            bar.trackMode = value
            ns:RefreshBarSettings()
        end
    end)
    trackModeDD:SetPoint("TOPLEFT", spellEdit, "BOTTOMLEFT", -16, -18)

    -- Target dropdown
    local targetDD = ns:CreateDropdown(ec, "Target", TARGET_UNITS, function(dd, value, index)
        local bar = frame:GetSelectedBar()
        if bar then
            bar.unit = value
            bar.target = nil  -- clear legacy field so unit takes effect
            ns:RefreshBarSettings()
        end
    end)
    targetDD:SetPoint("TOPLEFT", trackModeDD, "BOTTOMLEFT", 0, -18)

    -- Only Mine checkbox: +16 x offset reverses the dropdown's -16 so
    -- this aligns with barNameEdit / spellEdit on the left.
    local onlyMineCB = ns:CreateCheckbox(ec, "Only Mine", "Only track auras cast by you", function(self, checked)
        local bar = frame:GetSelectedBar()
        if bar then
            bar.onlyMine = checked
            ns:RefreshBarSettings()
        end
    end)
    onlyMineCB:SetPoint("TOPLEFT", targetDD, "BOTTOMLEFT", 16, -6)

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
            ns:RefreshBarSettings()
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
            ns:RefreshBarSettings()
        end
    end)
    oocOnlyCB:SetPoint("TOPLEFT", combatOnlyCB, "BOTTOMLEFT", 0, -2)

    local inGroupCB = ns:CreateCheckbox(ec, "In Group", "Show only when in a group", function(self, checked)
        local bar = frame:GetSelectedBar()
        if bar then
            if not bar.conditions then bar.conditions = {} end
            bar.conditions.inGroup = checked
            ns:RefreshBarSettings()
        end
    end)
    inGroupCB:SetPoint("TOPLEFT", oocOnlyCB, "BOTTOMLEFT", 0, -2)

    local inRaidCB = ns:CreateCheckbox(ec, "In Raid", "Show only when in a raid", function(self, checked)
        local bar = frame:GetSelectedBar()
        if bar then
            if not bar.conditions then bar.conditions = {} end
            bar.conditions.inRaid = checked
            ns:RefreshBarSettings()
        end
    end)
    inRaidCB:SetPoint("TOPLEFT", inGroupCB, "BOTTOMLEFT", 0, -2)

    -- Smart-visibility conditions (player state).
    local mountedCB = ns:CreateCheckbox(ec, "Hide While Mounted",
        "Hide this bar while you are on a mount.", function(self, checked)
        local bar = frame:GetSelectedBar()
        if bar then
            if not bar.conditions then bar.conditions = {} end
            bar.conditions.hideWhileMounted = checked
            ns:RefreshBarSettings()
        end
    end)
    mountedCB:SetPoint("TOPLEFT", inRaidCB, "BOTTOMLEFT", 0, -2)

    local restingCB = ns:CreateCheckbox(ec, "Hide While Resting",
        "Hide this bar while in an inn or capital city (resting).", function(self, checked)
        local bar = frame:GetSelectedBar()
        if bar then
            if not bar.conditions then bar.conditions = {} end
            bar.conditions.hideWhileResting = checked
            ns:RefreshBarSettings()
        end
    end)
    restingCB:SetPoint("TOPLEFT", mountedCB, "BOTTOMLEFT", 0, -2)

    local vehicleCB = ns:CreateCheckbox(ec, "Hide In Vehicle",
        "Hide this bar while in a vehicle (siege engines, drakes, etc.).", function(self, checked)
        local bar = frame:GetSelectedBar()
        if bar then
            if not bar.conditions then bar.conditions = {} end
            bar.conditions.hideInVehicle = checked
            ns:RefreshBarSettings()
        end
    end)
    vehicleCB:SetPoint("TOPLEFT", restingCB, "BOTTOMLEFT", 0, -2)

    local instanceCB = ns:CreateCheckbox(ec, "Only In Instance",
        "Only show this bar inside a dungeon, raid, arena, or battleground.", function(self, checked)
        local bar = frame:GetSelectedBar()
        if bar then
            if not bar.conditions then bar.conditions = {} end
            bar.conditions.onlyInInstance = checked
            ns:RefreshBarSettings()
        end
    end)
    instanceCB:SetPoint("TOPLEFT", vehicleCB, "BOTTOMLEFT", 0, -2)

    local hideInactiveCB = ns:CreateCheckbox(ec, "Hide When Inactive", "Hide bar when not tracking", function(self, checked)
        local bar = frame:GetSelectedBar()
        if bar then
            if not bar.conditions then bar.conditions = {} end
            bar.conditions.hideWhenInactive = checked
            ns:RefreshBarSettings()
        end
    end)
    hideInactiveCB:SetPoint("TOPLEFT", instanceCB, "BOTTOMLEFT", 0, -2)

    local showEmptyCB = ns:CreateCheckbox(ec, "Show Empty Bar", "Show bar even when not active", function(self, checked)
        local bar = frame:GetSelectedBar()
        if bar then
            if not bar.conditions then bar.conditions = {} end
            bar.conditions.showEmpty = checked
            ns:RefreshBarSettings()
        end
    end)
    showEmptyCB:SetPoint("TOPLEFT", hideInactiveCB, "BOTTOMLEFT", 0, -2)

    local healthEdit = ns:CreateEditBox(ec, "Health Below %", 60, function(self, text)
        local bar = frame:GetSelectedBar()
        if bar then
            if not bar.conditions then bar.conditions = {} end
            local val = tonumber(text)
            bar.conditions.healthBelow = (val and val > 0 and val <= 100) and val or nil
            ns:RefreshBarSettings()
        end
    end,
    "Only show this bar when your own HP is below this percentage. "
 .. "Useful for execute-range spells (Kill Shot, Hammer of Wrath, "
 .. "Execute) and panic buttons (Healthstone). Enter a number 1-100 "
 .. "and press Enter to apply, or leave empty to disable.")
    healthEdit:SetPoint("TOPLEFT", showEmptyCB, "BOTTOMLEFT", 6, -18)

    local requireBuffEdit = ns:CreateEditBox(ec, "Require Buff", 140, function(self, text)
        local bar = frame:GetSelectedBar()
        if bar then
            if not bar.conditions then bar.conditions = {} end
            bar.conditions.requireBuff = (text and text ~= "") and text or nil
            ns:RefreshBarSettings()
        end
    end,
    "Only show this bar while you have the named buff active. "
 .. "Accepts a buff name or spell ID. Useful for state-gated abilities "
 .. "(stealth-only cooldowns, bear-form abilities, proc reactions). "
 .. "Press Enter to apply, or leave empty to disable.")
    requireBuffEdit:SetPoint("TOPLEFT", healthEdit, "BOTTOMLEFT", 0, -18)

    -- ========================================================================
    -- DISPLAY OPTIONS SECTION
    -- ========================================================================
    local displayHeader = ec:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    displayHeader:SetPoint("TOPLEFT", requireBuffEdit, "BOTTOMLEFT", 0, -12)
    displayHeader:SetText("Display Options")

    local lingerSlider = ns:CreateSlider(ec, "Linger Time (sec)", 0, 5, 0.5, function(self, value)
        local bar = frame:GetSelectedBar()
        if bar then
            bar.display.lingerTime = value
            ns:RefreshBarSettings()
        end
    end,
    "After a tracked cooldown or buff expires, the bar holds at 0 for "
 .. "this many seconds before fading out. Pairs nicely with Glow on "
 .. "Ready so you can see the moment a spell came off cooldown. "
 .. "Set to 0 for the bar to disappear instantly on expiry.")
    lingerSlider:SetPoint("TOPLEFT", displayHeader, "BOTTOMLEFT", 4, -24)
    lingerSlider:SetWidth(180)

    -- Per-bar scale override. Writes nil back to the DB when value is 1 so
    -- the bar stays on "group default" rather than an explicit 1x override.
    local scaleSlider = ns:CreateSlider(ec, "Bar Scale", 0.5, 2.0, 0.1, function(self, value)
        local bar = frame:GetSelectedBar()
        if bar then
            bar.display.scaleOverride = (value ~= 1.0) and value or nil
            ns:RefreshBarSettings()
        end
    end,
    "Scale this bar individually. 1.0 is the group default. Values above "
 .. "1.0 may visually overlap neighbouring bars in multi-column groups; "
 .. "increase Bar Spacing in the Visuals tab or use a single-column group "
 .. "to compensate.")
    scaleSlider:SetPoint("TOPLEFT", lingerSlider, "BOTTOMLEFT", 0, -24)
    scaleSlider:SetWidth(180)

    local showBarNameCB = ns:CreateCheckbox(ec, "Show Bar Name",
        "Display the Bar Name text on this bar.", function(self, checked)
        local bar = frame:GetSelectedBar()
        if bar then
            bar.display.showName = checked and true or false
            ns:RefreshBarSettings()
        end
    end)
    showBarNameCB:SetPoint("TOPLEFT", scaleSlider, "BOTTOMLEFT", 0, -24)

    local showBarIconCB = ns:CreateCheckbox(ec, "Show Icon",
        "Display the spell icon on this bar.", function(self, checked)
        local bar = frame:GetSelectedBar()
        if bar then
            bar.display.showIcon = checked and true or false
            ns:RefreshBarSettings()
        end
    end)
    showBarIconCB:SetPoint("TOPLEFT", showBarNameCB, "BOTTOMLEFT", 0, -2)

    local barOpacitySlider = ns:CreateSlider(ec, "Bar Darkness", 0, 100, 1, function(self, value)
        local bar = frame:GetSelectedBar()
        if bar then
            bar.display.barAlpha = value / 100
            ns:RefreshBarSettings()
        end
    end,
    "How dark the bar's empty/unfilled background is. 0 = fully "
 .. "transparent (invisible background), 100 = solid black background. "
 .. "Lower values make the filled portion stand out more; higher "
 .. "values make empty bars easier to see at a glance.")
    barOpacitySlider:SetPoint("TOPLEFT", showBarIconCB, "BOTTOMLEFT", 4, -24)
    barOpacitySlider:SetWidth(180)

    local sparkleCB = ns:CreateCheckbox(ec, "Sparkle Alert",
        "Flash the bar when the timer is about to expire.", function(self, checked)
        local bar = frame:GetSelectedBar()
        if bar then
            bar.display.sparkleAlert = checked and true or false
            ns:RefreshBarSettings()
        end
    end)
    sparkleCB:SetPoint("TOPLEFT", barOpacitySlider, "BOTTOMLEFT", -4, -24)

    local sparkleThresholdSlider = ns:CreateSlider(ec, "Alert Threshold (sec)", 1, 15, 1, function(self, value)
        local bar = frame:GetSelectedBar()
        if bar then
            bar.display.sparkleThreshold = value
            ns:RefreshBarSettings()
        end
    end,
    "When Sparkle Alert is enabled, the bar flashes once the remaining "
 .. "time drops below this many seconds. Lower = later warning; higher "
 .. "= more lead time. Has no effect unless Sparkle Alert is ticked.")
    sparkleThresholdSlider:SetPoint("TOPLEFT", sparkleCB, "BOTTOMLEFT", 4, -20)
    sparkleThresholdSlider:SetWidth(180)

    local colorSwatch = ns:CreateColorSwatch(ec, "Color Override", { r = 1, g = 1, b = 1, a = 1 }, function(self, color)
        local bar = frame:GetSelectedBar()
        if bar then
            bar.display.colorOverride = { r = color.r, g = color.g, b = color.b }
            ns:RefreshBarSettings()
        end
    end)
    colorSwatch:SetPoint("TOPLEFT", sparkleThresholdSlider, "BOTTOMLEFT", -4, -8)

    -- Colour by Time (per-bar override)
    local colorByTimeCB = ns:CreateCheckbox(ec, "Colour by Time",
        "Bar colour changes from green to red as the timer counts down.", function(self, checked)
        local bar = frame:GetSelectedBar()
        if bar then
            bar.display.colorByTime = checked and true or false
            ns:RefreshBarSettings()
        end
    end)
    colorByTimeCB:SetPoint("TOPLEFT", colorSwatch, "BOTTOMLEFT", -4, -12)

    local cbtHighSlider = ns:CreateSlider(ec, "High Threshold (sec)", 1, 30, 1, function(self, value)
        local bar = frame:GetSelectedBar()
        if bar then
            bar.display.colorHighSeconds = value
            ns:RefreshBarSettings()
        end
    end,
    "When Colour by Time is enabled, the bar stays green while "
 .. "remaining time is at or above this many seconds, then fades "
 .. "toward yellow as it counts down. Set higher for earlier warning; "
 .. "lower to keep the bar green for longer.")
    cbtHighSlider:SetPoint("TOPLEFT", colorByTimeCB, "BOTTOMLEFT", 4, -20)
    cbtHighSlider:SetWidth(180)

    local cbtMedSlider = ns:CreateSlider(ec, "Med Threshold (sec)", 1, 30, 1, function(self, value)
        local bar = frame:GetSelectedBar()
        if bar then
            bar.display.colorMedSeconds = value
            ns:RefreshBarSettings()
        end
    end,
    "When Colour by Time is enabled, the bar fades from yellow to red "
 .. "once remaining time drops below this many seconds. Should be "
 .. "lower than High Threshold; the gap between them is the "
 .. "yellow zone.")
    cbtMedSlider:SetPoint("TOPLEFT", cbtHighSlider, "BOTTOMLEFT", 0, -24)
    cbtMedSlider:SetWidth(180)

    -- Glow on Ready
    local glowOnReadyCB = ns:CreateCheckbox(ec, "Glow on Ready",
        "Flash the icon when the cooldown finishes and the spell is ready.", function(self, checked)
        local bar = frame:GetSelectedBar()
        if bar then
            bar.display.glowOnReady = checked and true or false
            ns:RefreshBarSettings()
        end
    end)
    glowOnReadyCB:SetPoint("TOPLEFT", cbtMedSlider, "BOTTOMLEFT", -4, -20)

    -- Glow duration slider
    local glowDurationSlider = ns:CreateSlider(ec, "Glow Duration (sec)", 1, 10, 1, function(self, value)
        local bar = frame:GetSelectedBar()
        if bar then
            bar.display.glowDuration = value
            ns:RefreshBarSettings()
        end
    end,
    "How long the icon keeps pulsing when Glow on Ready fires "
 .. "(spell comes off cooldown / buff expires). Has no effect unless "
 .. "Glow on Ready is ticked.")
    glowDurationSlider:SetPoint("TOPLEFT", glowOnReadyCB, "BOTTOMLEFT", 4, -20)
    glowDurationSlider:SetWidth(180)

    -- Crop Icon (per-bar override)
    local cropIconCB = ns:CreateCheckbox(ec, "Crop Icon",
        "Trim icon border pixels to prevent stretching.", function(self, checked)
        local bar = frame:GetSelectedBar()
        if bar then
            bar.display.iconCrop = checked and true or false
            ns:RefreshBarSettings()
        end
    end)
    cropIconCB:SetPoint("TOPLEFT", glowDurationSlider, "BOTTOMLEFT", -4, -20)

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
                row.targetText:SetText(b.unit or b.target or "")
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
        mountedCB:SetChecked(cond.hideWhileMounted)
        restingCB:SetChecked(cond.hideWhileResting)
        vehicleCB:SetChecked(cond.hideInVehicle)
        instanceCB:SetChecked(cond.onlyInInstance)
        hideInactiveCB:SetChecked(cond.hideWhenInactive)
        showEmptyCB:SetChecked(cond.showEmpty)
        healthEdit:SetText(cond.healthBelow and tostring(cond.healthBelow) or "")
        requireBuffEdit:SetText(cond.requireBuff or "")

        -- Display options. Guard against bar.display being nil; older saved
        -- bars (pre-display-table) would otherwise silent-error on the first
        -- field access, crash UpdateBarEditor and leave the panel blank.
        local display = bar.display or {}
        lingerSlider:SetValue(display.lingerTime or 0)
        scaleSlider:SetValue(display.scaleOverride or 1.0)
        showBarNameCB:SetChecked(display.showName)
        showBarIconCB:SetChecked(display.showIcon)
        barOpacitySlider:SetValue((display.barAlpha or 0.6) * 100)
        sparkleCB:SetChecked(display.sparkleAlert)
        sparkleThresholdSlider:SetValue(display.sparkleThreshold or 5)

        if display.colorOverride then
            colorSwatch.color.r = display.colorOverride.r
            colorSwatch.color.g = display.colorOverride.g
            colorSwatch.color.b = display.colorOverride.b
            colorSwatch.swatch:SetTexture(display.colorOverride.r, display.colorOverride.g, display.colorOverride.b, 1)
        else
            colorSwatch.swatch:SetTexture(1, 1, 1, 1)
        end

        -- New feature controls
        colorByTimeCB:SetChecked(display.colorByTime)
        cbtHighSlider:SetValue(display.colorHighSeconds or 10)
        cbtMedSlider:SetValue(display.colorMedSeconds or 5)
        glowOnReadyCB:SetChecked(display.glowOnReady)
        glowDurationSlider:SetValue(display.glowDuration or 3)
        cropIconCB:SetChecked(display.iconCrop)
    end

    local function UpdateGroupName()
        refreshGroupSettings()
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

    -- Resize the editor-content frame to match the scroll viewport so the
    -- per-bar editor uses whatever width the InterfaceOptionsFrame gives us.
    -- Mirrors the pattern in Options_Visuals.lua.
    frame:SetScript("OnShow", function(self)
        local w = editorScroll:GetWidth()
        if w and w > 100 then
            ec:SetWidth(w)
        end
        if self.Refresh then self:Refresh() end
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
