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
            -- Glow on ready / pulse on ready
            glowOnReady = false,
            pulseOnReady = false,
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
        groupConditions = {},
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
    groupSettingsContent:SetWidth(180)
    groupSettingsContent:SetHeight(500)
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

        -- Group-level visibility conditions. These hide the ENTIRE group
        -- (frame + all bars) when the condition fails, saving the user from
        -- ticking the same checkbox on every bar individually.
        { type = "header", text = "Group Conditions", spacing = 16, offsetX = 10 },
        { type = "toggle", label = "Combat Only",
          tooltip = "Hide this entire group when out of combat.",
          get = function() local g = getGroup(); return g and g.groupConditions and g.groupConditions.combatOnly end,
          set = function(_, v) local g = getGroup(); if not g then return end
              if not g.groupConditions then g.groupConditions = {} end
              g.groupConditions.combatOnly = v
              if v then g.groupConditions.outOfCombatOnly = false end
              ns:RefreshBarSettings() end,
          spacing = 4 },
        { type = "toggle", label = "Out of Combat Only",
          tooltip = "Hide this entire group when in combat.",
          get = function() local g = getGroup(); return g and g.groupConditions and g.groupConditions.outOfCombatOnly end,
          set = function(_, v) local g = getGroup(); if not g then return end
              if not g.groupConditions then g.groupConditions = {} end
              g.groupConditions.outOfCombatOnly = v
              if v then g.groupConditions.combatOnly = false end
              ns:RefreshBarSettings() end,
          spacing = 2 },
        { type = "toggle", label = "Hide Mounted",
          tooltip = "Hide this entire group while mounted.",
          get = function() local g = getGroup(); return g and g.groupConditions and g.groupConditions.hideWhileMounted end,
          set = function(_, v) local g = getGroup(); if not g then return end
              if not g.groupConditions then g.groupConditions = {} end; g.groupConditions.hideWhileMounted = v; ns:RefreshBarSettings() end,
          spacing = 2 },
        { type = "toggle", label = "Hide Resting",
          tooltip = "Hide this entire group while in an inn or capital city.",
          get = function() local g = getGroup(); return g and g.groupConditions and g.groupConditions.hideWhileResting end,
          set = function(_, v) local g = getGroup(); if not g then return end
              if not g.groupConditions then g.groupConditions = {} end; g.groupConditions.hideWhileResting = v; ns:RefreshBarSettings() end,
          spacing = 2 },
        { type = "toggle", label = "Hide In Vehicle",
          tooltip = "Hide this entire group while in a vehicle.",
          get = function() local g = getGroup(); return g and g.groupConditions and g.groupConditions.hideInVehicle end,
          set = function(_, v) local g = getGroup(); if not g then return end
              if not g.groupConditions then g.groupConditions = {} end; g.groupConditions.hideInVehicle = v; ns:RefreshBarSettings() end,
          spacing = 2 },
        { type = "toggle", label = "Only In Instance",
          tooltip = "Only show this entire group inside a dungeon, raid, arena, or battleground.",
          get = function() local g = getGroup(); return g and g.groupConditions and g.groupConditions.onlyInInstance end,
          set = function(_, v) local g = getGroup(); if not g then return end
              if not g.groupConditions then g.groupConditions = {} end; g.groupConditions.onlyInInstance = v; ns:RefreshBarSettings() end,
          spacing = 2 },
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
    -- CONDITIONS + DISPLAY: declarative schema (ns:BuildSettings).
    --
    -- All entries use get/set closures (not db paths) because the target bar
    -- is dynamic: it changes whenever the user selects a different bar in the
    -- list. refreshEditorSettings() is called from UpdateBarEditor on every
    -- bar selection change, re-reading all values from the new bar.
    -- ========================================================================

    local editorWidgets = {}

    -- GetSelectedBar is defined later in CreateBarsTab. At BuildSettings
    -- build time the method doesn't exist yet, so guard against nil.
    local function getBar()
        return frame.GetSelectedBar and frame:GetSelectedBar() or nil
    end
    local function getCond()
        local bar = getBar()
        return bar and (bar.conditions or {}) or {}
    end
    local function getDisp()
        local bar = getBar()
        return bar and (bar.display or {}) or {}
    end

    -- Factory: condition-toggle schema entry (1 line per checkbox)
    local function condCheck(label, field, tip, extra)
        local e = { type = "toggle", label = label, tooltip = tip,
            get = function() return getCond()[field] end,
            set = function(_, v)
                local bar = getBar(); if not bar then return end
                if not bar.conditions then bar.conditions = {} end
                bar.conditions[field] = v
                ns:RefreshBarSettings()
            end,
            spacing = 2 }
        if extra then for k, v in pairs(extra) do e[k] = v end end
        return e
    end

    -- Factory: display-toggle schema entry
    local function dispCheck(label, field, tip, extra)
        local e = { type = "toggle", label = label, tooltip = tip,
            get = function() return getDisp()[field] end,
            set = function(_, v)
                local bar = getBar(); if not bar then return end
                if not bar.display then bar.display = {} end
                bar.display[field] = v and true or false
                ns:RefreshBarSettings()
            end,
            spacing = 2 }
        if extra then for k, v in pairs(extra) do e[k] = v end end
        return e
    end

    -- Factory: display-slider schema entry
    local function dispSlider(label, field, mn, mx, st, default, tip, extra)
        local e = { type = "slider", label = label, tooltip = tip,
            min = mn, max = mx, step = st, width = 180,
            get = function() return getDisp()[field] or default end,
            set = function(_, v)
                local bar = getBar(); if not bar then return end
                if not bar.display then bar.display = {} end
                bar.display[field] = v
                ns:RefreshBarSettings()
            end,
            spacing = 24, offsetX = 4 }
        if extra then for k, v in pairs(extra) do e[k] = v end end
        return e
    end

    local EDITOR_SCHEMA = {
        -- ---- Conditions ----
        { type = "header", text = "Conditions" },

        -- Combat / OOC are mutually exclusive: set writes both DB fields,
        -- onChange visually unchecks the partner widget via editorWidgets ref.
        { type = "toggle", id = "combatOnly", label = "Combat Only",
          tooltip = "Show only in combat",
          get = function() return getCond().combatOnly end,
          set = function(_, v)
              local bar = getBar(); if not bar then return end
              if not bar.conditions then bar.conditions = {} end
              bar.conditions.combatOnly = v
              if v then bar.conditions.outOfCombatOnly = false end
              ns:RefreshBarSettings()
          end,
          onChange = function(v)
              if v and editorWidgets.oocOnly then editorWidgets.oocOnly:SetChecked(false) end
          end,
          spacing = 4 },

        { type = "toggle", id = "oocOnly", label = "Out of Combat Only",
          tooltip = "Show only out of combat",
          get = function() return getCond().outOfCombatOnly end,
          set = function(_, v)
              local bar = getBar(); if not bar then return end
              if not bar.conditions then bar.conditions = {} end
              bar.conditions.outOfCombatOnly = v
              if v then bar.conditions.combatOnly = false end
              ns:RefreshBarSettings()
          end,
          onChange = function(v)
              if v and editorWidgets.combatOnly then editorWidgets.combatOnly:SetChecked(false) end
          end,
          spacing = 2 },

        condCheck("In Group",            "inGroup",           "Show only when in a group"),
        condCheck("In Raid",             "inRaid",            "Show only when in a raid"),
        condCheck("Hide While Mounted",  "hideWhileMounted",  "Hide this bar while you are on a mount."),
        condCheck("Hide While Resting",  "hideWhileResting",  "Hide this bar while in an inn or capital city (resting)."),
        condCheck("Hide In Vehicle",     "hideInVehicle",     "Hide this bar while in a vehicle (siege engines, drakes, etc.)."),
        condCheck("Only In Instance",    "onlyInInstance",    "Only show this bar inside a dungeon, raid, arena, or battleground."),
        condCheck("Hide When Inactive",  "hideWhenInactive",  "Hide bar completely when not tracking anything."),
        condCheck("Show Empty Bar",      "showEmpty",         "Show bar at inactive alpha even when not active."),

        { type = "editbox", label = "Health Below %", width = 60,
          tooltip = "Only show this bar when your own HP is below this percentage. "
                 .. "Useful for execute-range spells (Kill Shot, Hammer of Wrath, "
                 .. "Execute) and panic buttons (Healthstone). Enter a number 1-100 "
                 .. "and press Enter to apply, or leave empty to disable.",
          get = function()
              local v = getCond().healthBelow
              return v and tostring(v) or ""
          end,
          set = function(_, text)
              local bar = getBar(); if not bar then return end
              if not bar.conditions then bar.conditions = {} end
              local val = tonumber(text)
              bar.conditions.healthBelow = (val and val > 0 and val <= 100) and val or nil
              ns:RefreshBarSettings()
          end,
          spacing = 18, offsetX = 6 },

        { type = "editbox", label = "Require Buff", width = 140,
          tooltip = "Only show this bar while you have the named buff active. "
                 .. "Accepts a buff name or spell ID. Useful for state-gated abilities "
                 .. "(stealth-only cooldowns, bear-form abilities, proc reactions). "
                 .. "Press Enter to apply, or leave empty to disable.",
          get = function() return getCond().requireBuff or "" end,
          set = function(_, text)
              local bar = getBar(); if not bar then return end
              if not bar.conditions then bar.conditions = {} end
              bar.conditions.requireBuff = (text and text ~= "") and text or nil
              ns:RefreshBarSettings()
          end,
          spacing = 18 },

        -- ---- Display Options ----
        { type = "header", text = "Display Options", spacing = 12 },

        dispSlider("Linger Time (sec)", "lingerTime", 0, 5, 0.5, 0,
            "After a tracked cooldown or buff expires, the bar holds at 0 for "
         .. "this many seconds before fading out. Pairs nicely with Glow on "
         .. "Ready so you can see the moment a spell came off cooldown. "
         .. "Set to 0 for the bar to disappear instantly on expiry."),

        { type = "slider", label = "Bar Scale",
          min = 0.5, max = 2.0, step = 0.1, width = 180,
          tooltip = "Scale this bar individually. 1.0 is the group default. Values above "
                 .. "1.0 may visually overlap neighbouring bars in multi-column groups; "
                 .. "increase Bar Spacing in the Visuals tab or use a single-column group "
                 .. "to compensate.",
          get = function() return getDisp().scaleOverride or 1.0 end,
          set = function(_, v)
              local bar = getBar(); if not bar then return end
              if not bar.display then bar.display = {} end
              bar.display.scaleOverride = (v ~= 1.0) and v or nil
              ns:RefreshBarSettings()
          end,
          spacing = 24 },

        dispCheck("Show Bar Name", "showName",
            "Display the Bar Name text on this bar.", { spacing = 24 }),
        dispCheck("Show Icon", "showIcon",
            "Display the spell icon on this bar."),

        { type = "slider", label = "Bar Darkness",
          min = 0, max = 100, step = 1, width = 180,
          tooltip = "How dark the bar's empty/unfilled background is. 0 = fully "
                 .. "transparent (invisible background), 100 = solid black background. "
                 .. "Lower values make the filled portion stand out more; higher "
                 .. "values make empty bars easier to see at a glance.",
          get = function() return (getDisp().barAlpha or 0.6) * 100 end,
          set = function(_, v)
              local bar = getBar(); if not bar then return end
              if not bar.display then bar.display = {} end
              bar.display.barAlpha = v / 100
              ns:RefreshBarSettings()
          end,
          spacing = 24, offsetX = 4 },

        dispCheck("Sparkle Alert", "sparkleAlert",
            "Flash the bar when the timer is about to expire.",
            { spacing = 24, offsetX = -4 }),

        dispSlider("Alert Threshold (sec)", "sparkleThreshold", 1, 15, 1, 5,
            "When Sparkle Alert is enabled, the bar flashes once the remaining "
         .. "time drops below this many seconds. Lower = later warning; higher "
         .. "= more lead time. Has no effect unless Sparkle Alert is ticked.",
            { spacing = 20 }),

        { type = "color", label = "Color Override",
          get = function()
              return getDisp().colorOverride or { r = 1, g = 1, b = 1 }
          end,
          set = function(_, color)
              local bar = getBar(); if not bar then return end
              if not bar.display then bar.display = {} end
              bar.display.colorOverride = { r = color.r, g = color.g, b = color.b }
              ns:RefreshBarSettings()
          end,
          spacing = 8, offsetX = -4 },

        dispCheck("Colour by Time", "colorByTime",
            "Bar colour changes from green to red as the timer counts down.",
            { spacing = 12, offsetX = -4 }),

        dispSlider("High Threshold (sec)", "colorHighSeconds", 1, 30, 1, 10,
            "When Colour by Time is enabled, the bar stays green while "
         .. "remaining time is at or above this many seconds, then fades "
         .. "toward yellow as it counts down. Set higher for earlier warning; "
         .. "lower to keep the bar green for longer.",
            { spacing = 20 }),

        dispSlider("Med Threshold (sec)", "colorMedSeconds", 1, 30, 1, 5,
            "When Colour by Time is enabled, the bar fades from yellow to red "
         .. "once remaining time drops below this many seconds. Should be "
         .. "lower than High Threshold; the gap between them is the "
         .. "yellow zone."),

        dispCheck("Glow on Ready", "glowOnReady",
            "Flash the icon when the cooldown finishes and the spell is ready.",
            { spacing = 20, offsetX = -4 }),

        dispCheck("Pulse on Ready", "pulseOnReady",
            "Flash the spell icon at the centre of the screen when this "
         .. "cooldown or buff expires. Gives a strong visual cue that the "
         .. "spell is available again, even if the bar is at the edge of "
         .. "your view.",
            { spacing = 8 }),

        dispSlider("Glow Duration (sec)", "glowDuration", 1, 10, 1, 3,
            "How long the icon keeps pulsing when Glow on Ready fires "
         .. "(spell comes off cooldown / buff expires). Has no effect unless "
         .. "Glow on Ready is ticked.",
            { spacing = 20 }),

        dispCheck("Crop Icon", "iconCrop",
            "Trim icon border pixels to prevent stretching.",
            { spacing = 20, offsetX = -4 }),
    }

    -- Container frame for the schema-managed region, anchored below the
    -- imperative identity widgets (barEnabled through onlyMine).
    local editorSettingsFrame = CreateFrame("Frame", nil, ec)
    editorSettingsFrame:SetPoint("TOPLEFT", onlyMineCB, "BOTTOMLEFT", 0, -12)
    editorSettingsFrame:SetWidth(340)
    editorSettingsFrame:SetHeight(800)

    local refreshEditorSettings = ns:BuildSettings(
        editorSettingsFrame, EDITOR_SCHEMA, editorWidgets,
        { firstX = 0, firstY = 0 })

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

        -- Conditions + Display: delegate to the BuildSettings Refresh closure.
        -- It re-reads all 28 fields from the currently-selected bar via the
        -- get closures in EDITOR_SCHEMA. Nil-safe (getCond/getDisp guard).
        refreshEditorSettings()
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
