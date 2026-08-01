-- Options_Bars.lua - Bars / Groups tab (group-and-bar editor).
-- Author:  Serv
-- Source:  https://github.com/powerfulqa/BarWarden
-- License: see LICENSE; attribution preservation is required.

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
-- Lists show up to this many rows (the box grows with the item count, minimum
-- one line) before they start scrolling. Six keeps the settings/editor below
-- visible even at the smallest window size; Groups and Bars use the same cap.
local MAX_GROUP_ROWS = 6
local MAX_BAR_ROWS = 6

-- Blizzard's FauxScrollFrame_Update HIDES the whole scroll frame when the list
-- fits without scrolling. Both lists have the rest of their column anchored to
-- that frame (the buttons, then the settings block below them), and anchoring
-- to a frame that gets hidden out from under you strands the dependants - they
-- fall back towards the panel origin and the page visibly comes apart until
-- something re-shows the frame.
--
-- Deleting the 7th group is the exact trigger: 7 > 6 keeps it shown, dropping
-- back to 6 hides it. Adding a group put it right again, which is what made the
-- bug look like it was about deleting.
--
-- So keep the scroll frame itself shown always and hide only its scrollbar,
-- which is what the auto-hide elsewhere in the addon does too.
--
-- EC-TRAP: the Show() below looks redundant right after FauxScrollFrame_Update
-- and is not. Removing it re-breaks the Bar Control page whenever a list drops
-- from 7 items to 6. Never anchor anything to a frame Blizzard's own helpers
-- show and hide.
local function KeepListFrameShown(scrollFrame, scrollBarName, needsScrollBar)
    if not scrollFrame then return end
    scrollFrame:Show()
    local sb = _G[scrollBarName]
    if sb then
        if needsScrollBar then sb:Show() else sb:Hide() end
    end
end

-- Helper: create a new default bar table
local function NewBar(name)
    return {
        name = name or "New Bar",
        enabled = true,
        trackMode = "Cooldown",
        unit = "player",
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

    -- Drag-to-reorder: work out which row index the cursor is over in a
    -- FauxScrollFrame list, accounting for the scroll offset and UI scale.
    local function ComputeDropIndex(scrollFrame, rowHeight, total)
        local _, cy = GetCursorPosition()
        local scale = scrollFrame:GetEffectiveScale()
        local top = scrollFrame:GetTop()
        if not cy or not scale or scale == 0 or not top then return nil end
        local offset = FauxScrollFrame_GetOffset(scrollFrame) or 0
        local idx = offset + math.floor((top - cy / scale) / rowHeight) + 1
        if idx < 1 then idx = 1 end
        if idx > total then idx = total end
        return idx
    end

    -- ========================================================================
    -- LEFT PANEL: Group List
    -- ========================================================================
    local leftPanel = CreateFrame("Frame", nil, frame)
    -- v2: start near the top (no tab bar to clear) and fill the panel height, so
    -- the group list + settings use the full column instead of a 360px box.
    -- Groups tab content: fills the page below the title, above the tab bar.
    leftPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -44)
    leftPanel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 40)

    local groupHeader = leftPanel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    groupHeader:SetPoint("TOPLEFT", leftPanel, "TOPLEFT", 0, 0)
    groupHeader:SetText("Groups")
    ns:CreateHelpIcon(leftPanel, groupHeader, "LEFT", "RIGHT", 6, 0, "create-group")

    -- Group scroll frame
    -- List spans the full page width; its height is set dynamically in
    -- UpdateGroupList (grows with the group count, up to MAX_GROUP_ROWS rows,
    -- then scrolls). The buttons + settings below follow its bottom edge.
    local groupScrollFrame = CreateFrame("ScrollFrame", "BarWardenGroupScroll", leftPanel, "FauxScrollFrameTemplate")
    groupScrollFrame:SetPoint("TOPLEFT", groupHeader, "BOTTOMLEFT", 0, -6)
    -- Fixed width = the shared settings width, so the list + its selection
    -- highlight are contained at the same limit as the settings below, instead
    -- of the highlight stretching across the whole window.
    groupScrollFrame:SetWidth(ns.SETTINGS_MAX_WIDTH or 300)
    groupScrollFrame:SetHeight(MAX_GROUP_ROWS * GROUP_LIST_HEIGHT)

    local groupRows = {}
    for i = 1, MAX_GROUP_ROWS do
        local row = CreateFrame("Button", "BarWardenGroupRow" .. i, leftPanel)
        row:SetHeight(GROUP_LIST_HEIGHT)
        if i == 1 then
            row:SetPoint("TOPLEFT",  groupScrollFrame, "TOPLEFT",   0, 0)
            row:SetPoint("TOPRIGHT", groupScrollFrame, "TOPRIGHT", -22, 0)
        else
            row:SetPoint("TOPLEFT",  groupRows[i - 1], "BOTTOMLEFT",  0, 0)
            row:SetPoint("TOPRIGHT", groupRows[i - 1], "BOTTOMRIGHT", 0, 0)
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
        text:SetPoint("LEFT",  row, "LEFT",   4, 0)
        text:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        text:SetJustifyH("LEFT")
        row.text = text

        row:SetScript("OnClick", function(self)
            selectedGroupIndex = self.index
            selectedBarIndex = nil
            frame:Refresh()
        end)

        -- Drag-to-reorder groups (a plain click still selects).
        row:RegisterForDrag("LeftButton")
        row:SetScript("OnDragStart", function(self) frame._dragGroup = self.index end)
        row:SetScript("OnDragStop", function()
            local from = frame._dragGroup
            frame._dragGroup = nil
            local frames = BarWardenDB and BarWardenDB.frames
            if not from or not frames or #frames < 2 then return end
            local to = ComputeDropIndex(groupScrollFrame, GROUP_LIST_HEIGHT, #frames)
            if to and to ~= from then
                table.insert(frames, to, table.remove(frames, from))
                selectedGroupIndex = to
                selectedBarIndex = nil
                frame:Refresh()
                ns:RebuildAllFrames()
            end
        end)

        groupRows[i] = row
    end

    -- Group buttons: Add / Delete / Dupe split the list width into equal thirds
    -- so the row fills the panel even at its narrowest. Two gaps between three
    -- buttons; the last button absorbs the rounding remainder so the row's right
    -- edge lands exactly on the list's right edge.
    local GROUP_BTN_GAP  = 4
    local GROUP_ROW_W    = ns.SETTINGS_MAX_WIDTH or 300
    local groupBtnW      = math.floor((GROUP_ROW_W - 2 * GROUP_BTN_GAP) / 3)
    local groupBtnWLast  = GROUP_ROW_W - 2 * groupBtnW - 2 * GROUP_BTN_GAP

    -- Group buttons
    local addGroupBtn = ns:CreateButton(leftPanel, "Add", groupBtnW, function()
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

    local deleteGroupBtn = ns:CreateButton(leftPanel, "Delete", groupBtnW, function()
        if not selectedGroupIndex then ns:Print("Select a group first."); return end
        local frames = BarWardenDB.frames
        local g = frames[selectedGroupIndex]
        if not g then return end
        -- Capture the target group itself, not the live selection: the popup is
        -- not modal, so the user can click another row while it is open. Acting
        -- on the selection at accept time deleted whichever group they clicked
        -- last rather than the one the popup names.
        local targetGroup = g
        local popup = StaticPopup_Show("BARWARDEN_CONFIRM_DELETE", g.name or "this group")
        if popup then
            popup.data = {
                onAccept = function()
                    local idx
                    for i, f in ipairs(frames) do
                        if f == targetGroup then idx = i; break end
                    end
                    if not idx then
                        ns:Print("That group no longer exists.")
                        return
                    end
                    ns:BackupFrames("delete group")
                    table.remove(frames, idx)
                    if selectedGroupIndex and selectedGroupIndex > #frames then
                        selectedGroupIndex = #frames > 0 and #frames or nil
                    end
                    selectedBarIndex = nil
                    frame:Refresh()
                    ns:RebuildAllFrames()
                end,
            }
        end
    end)
    deleteGroupBtn:SetPoint("LEFT", addGroupBtn, "RIGHT", GROUP_BTN_GAP, 0)

    local dupeGroupBtn = ns:CreateButton(leftPanel, "Dupe", groupBtnWLast, function()
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
    dupeGroupBtn:SetPoint("LEFT", deleteGroupBtn, "RIGHT", GROUP_BTN_GAP, 0)

    -- Group settings sit BELOW the list + buttons and span the full page width
    -- (stacked layout, uniform with the Bars tab). This keeps the settings
    -- visible even at the smallest window size. The scroll fills the remaining
    -- height and reflows on resize.
    local groupSettingsHeader = leftPanel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    groupSettingsHeader:SetPoint("TOPLEFT", addGroupBtn, "BOTTOMLEFT", 0, -10)
    groupSettingsHeader:SetText("Group Settings")

    local groupSettingsScroll = CreateFrame("ScrollFrame", "BarWardenGroupSettingsScroll", leftPanel, "UIPanelScrollFrameTemplate")
    groupSettingsScroll:SetPoint("TOPLEFT", groupSettingsHeader, "BOTTOMLEFT", 0, -6)
    groupSettingsScroll:SetPoint("BOTTOMRIGHT", leftPanel, "BOTTOMRIGHT", -24, 0)

    local groupSettingsContent = CreateFrame("Frame", nil, groupSettingsScroll)
    groupSettingsContent:SetWidth(320)
    -- Generous fallback height so all group settings (down to the Group
    -- Conditions toggles) are reachable; fitGroupHeight() trims it once shown.
    groupSettingsContent:SetHeight(700)
    groupSettingsScroll:SetScrollChild(groupSettingsContent)

    -- Populated by BuildSettings (ids below); used to fill the group dropdowns
    -- to the panel width on resize, matching the Bars editor.
    local groupSettingsWidgets = {}

    -- Reflow the settings content to the live viewport width on resize, and
    -- fill the dropdowns (their box width is a template property, not an anchor).
    groupSettingsScroll:SetScript("OnSizeChanged", function(_, w)
        if w and w > 100 then
            -- Cap at the shared settings width (parity with the Bars editor).
            local cw = math.min(w, ns.SETTINGS_MAX_WIDTH or 300)
            groupSettingsContent:SetWidth(cw)
            local ddW = math.max(120, cw - 60)
            for _, id in ipairs({ "grpSortDD", "grpGrowthDD", "grpTextureDD", "grpTextFormatDD" }) do
                local dd = groupSettingsWidgets[id]
                if dd then UIDropDownMenu_SetWidth(dd, ddW) end
            end
        end
    end)

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

    local growDirectionItems = {
        { text = "Down (default)", value = "DOWN" },
        { text = "Up",             value = "UP" },
    }

    -- Per-group bar-texture choices: "Inherit" (use the addon-wide texture from
    -- the Visuals page) plus the shared media list. "Custom" is dropped here;
    -- a custom texture path stays a global-only setting.
    local groupTextureItems = { { text = "Inherit (default)", value = "" } }
    do
        local list = ns.LSMDropdownItems and ns:LSMDropdownItems("statusbar")
        if list then
            for _, item in ipairs(list) do
                if item.value ~= "Custom" then
                    groupTextureItems[#groupTextureItems + 1] = item
                end
            end
        else
            for _, n in ipairs({ "Flat", "Smooth", "Gloss", "Aluminum", "Armory" }) do
                groupTextureItems[#groupTextureItems + 1] = { text = n, value = n }
            end
        end
    end

    -- Text-format override list: Inherit plus the same formats the Visuals page
    -- offers, so one group can show stacks (or names only) without changing
    -- every other bar in the addon.
    local groupTextFormatItems = {
        { text = "Inherit (default)", value = ""              },
        { text = "Name + Duration",   value = "NAME_DURATION" },
        { text = "Name Only",         value = "NAME_ONLY"     },
        { text = "Duration Only",     value = "DURATION"      },
        { text = "Name + Stacks",     value = "NAME_STACKS"   },
        { text = "Stacks Only",       value = "STACKS"        },
        { text = "None",              value = "NONE"          },
    }

    -- Forward-declared so schema `set` closures below can re-run the group
    -- settings Refresh (e.g. to re-check the Custom Bar Colour toggle after the
    -- colour swatch writes g.barColor). Assigned by BuildSettings just below.
    local refreshGroupSettings

    local GROUP_SETTINGS_SCHEMA = {
        { type = "editbox", label = "Group Name", width = 155, stretch = true,
          tooltip = "A label for this group, shown on the frame when 'Show "
                 .. "Group Name' is ticked.",
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
        { type = "slider", label = "Width", min = 50, max = 400, step = 5, width = 150, stretch = true,
          tooltip = "How wide the bars in this group are, in pixels.",
          get = function() local g = getGroup(); return g and g.width or 200 end,
          set = function(_, value)
              local g = getGroup(); if not g then return end
              g.width = value
              local gf = ns.groupFrames[selectedGroupIndex]
              if gf then ns:UpdateGroupLayout(gf) end
          end,
          offsetX = 10, spacing = 12 },
        { type = "slider", label = "Scale", min = 0.5, max = 2.0, step = 0.1, width = 150, stretch = true,
          tooltip = "Overall size of this group. 1.00 is normal size.",
          get = function() local g = getGroup(); return g and g.scale or 1.0 end,
          set = function(_, value)
              if not selectedGroupIndex then return end
              ns:SetFrameScale(selectedGroupIndex, value)
              local g = getGroup(); if g then g.scale = value end
          end,
          spacing = 16 },
        { type = "slider", label = "Columns", min = 1, max = 4, step = 1, width = 150, stretch = true,
          tooltip = "Number of columns the bars in this group are arranged into. "
               .. "1 = vertical stack (default); 2-4 splits the bars across that "
               .. "many columns side by side. Useful when tracking many bars in a "
               .. "compact footprint.",
          get = function() local g = getGroup(); return g and g.columns or 1 end,
          set = function(_, value)
              if selectedGroupIndex then ns:SetGroupColumns(selectedGroupIndex, value) end
          end,
          spacing = 16 },
        { type = "slider", label = "Background Opacity", min = 0, max = 1, step = 0.05, width = 150, stretch = true,
          tooltip = "Opacity of this group's background panel. 0 hides it.",
          get = function() local g = getGroup(); return g and (g.bgAlpha ~= nil and g.bgAlpha or 0.6) end,
          set = function(_, value)
              if selectedGroupIndex then ns:SetGroupBgAlpha(selectedGroupIndex, value) end
          end,
          spacing = 16 },
        { type = "slider", label = "Border Opacity", min = 0, max = 1, step = 0.05, width = 150, stretch = true,
          tooltip = "Opacity of this group's border. 0 hides it.",
          get = function() local g = getGroup(); return g and (g.borderAlpha ~= nil and g.borderAlpha or 0.8) end,
          set = function(_, value)
              if selectedGroupIndex then ns:SetGroupBorderAlpha(selectedGroupIndex, value) end
          end,
          spacing = 16 },
        { type = "dropdown", id = "grpSortDD", label = "Sort Mode", items = sortModeItems, width = 130,
          tooltip = "Order the bars in this group: Manual (drag to reorder), by "
                 .. "remaining time, or alphabetically.",
          get = function() local g = getGroup(); return g and g.sortMode or "manual" end,
          set = function(_, value)
              local g = getGroup(); if not g then return end
              g.sortMode = value
              local gf = ns.groupFrames[selectedGroupIndex]
              if gf then ns:UpdateGroupLayout(gf) end
          end,
          offsetX = -16, spacing = 28 },
        { type = "dropdown", id = "grpGrowthDD", label = "Growth Direction", items = growDirectionItems, width = 130,
          tooltip = "Direction bars stack within this group. Down (default) "
               .. "grows bars downward from the title. Up grows bars upward, "
               .. "useful when you want the group anchored at the bottom of "
               .. "the screen.",
          get = function() local g = getGroup(); return g and g.growDirection or "DOWN" end,
          set = function(_, value)
              local g = getGroup(); if not g then return end
              g.growDirection = value
              local gf = ns.groupFrames[selectedGroupIndex]
              if gf then ns:UpdateGroupLayout(gf) end
          end,
          spacing = 16 },

        -- Group-level bar visuals. These override the addon-wide look from the
        -- Visuals page for just this group's bars; left on Inherit / off, they
        -- use the global default.
        { type = "header", text = "Bar Overrides", spacing = 16, offsetX = 10 },
        { type = "dropdown", id = "grpTextureDD", label = "Bar Texture", items = groupTextureItems, width = 150,
          tooltip = "Texture for this group's bars. Inherit uses the addon-wide "
               .. "texture set on the Visuals page.",
          get = function() local g = getGroup(); return g and g.barTexture or "" end,
          set = function(_, value)
              local g = getGroup(); if not g then return end
              g.barTexture = (value ~= "" and value) or nil
              ns:RefreshAllBars()
          end,
          offsetX = -16, spacing = 28 },
        { type = "dropdown", id = "grpTextFormatDD", label = "Text Format",
          items = groupTextFormatItems, width = 150,
          tooltip = "What this group's bars show as text. Inherit uses the "
               .. "addon-wide format set on the Visuals page.",
          get = function() local g = getGroup(); return g and g.textFormat or "" end,
          set = function(_, value)
              local g = getGroup(); if not g then return end
              g.textFormat = (value ~= "" and value) or nil
              ns:RefreshAllBars()
          end,
          offsetX = 0, spacing = 28 },
        { type = "toggle", label = "Custom Bar Colour",
          tooltip = "Give this group's bars their own colour instead of the "
               .. "addon-wide default. Turn off to go back to the default.",
          get = function() local g = getGroup(); return g and g.barColor ~= nil end,
          set = function(_, checked)
              local g = getGroup(); if not g then return end
              if checked then
                  g.barColor = g.barColor or { r = 0.2, g = 0.6, b = 1.0 }
              else
                  g.barColor = nil
              end
              ns:RefreshBarSettings()
              ns:RefreshAllBars()
          end,
          -- Show the swatch only while the override is on, matching how the
          -- Visuals page couples Colour Mode to its own swatch. It used to sit
          -- there permanently, and clicking it silently switched the override on.
          onChange = function(value)
              local sw = groupSettingsWidgets.grpColorSwatch
              if sw then
                  if value then sw:Show() else sw:Hide() end
              end
          end,
          offsetX = 10, spacing = 8 },
        { type = "color", id = "grpColorSwatch", label = "Bar Colour",
          get = function() local g = getGroup(); return (g and g.barColor) or { r = 0.2, g = 0.6, b = 1.0 } end,
          set = function(_, color)
              local g = getGroup(); if not g then return end
              g.barColor = { r = color.r, g = color.g, b = color.b }
              -- Picking a colour implies "custom colour on" - re-run Refresh so
              -- the Custom Bar Colour toggle reflects that immediately.
              if refreshGroupSettings then refreshGroupSettings() end
              ns:RefreshAllBars()
          end,
          offsetX = 10, spacing = 8 },

        -- Group-level visibility conditions. These hide the ENTIRE group
        -- (frame + all bars) when the condition fails, saving the user from
        -- ticking the same checkbox on every bar individually.
        { type = "header", text = "Group Conditions", spacing = 16, offsetX = 10, id = "grpCondHeader" },
        { type = "toggle", label = "Hide When Inactive",
          tooltip = "Controls the whole group once you use it: ticked hides "
               .. "every bar while it has nothing to show, unticked keeps them "
               .. "all visible even if individual bars are set to hide. Leave it "
               .. "alone to let each bar decide.",
          get = function() local g = getGroup(); return g and g.groupConditions and g.groupConditions.hideWhenInactive end,
          set = function(_, v) local g = getGroup(); if not g then return end
              if not g.groupConditions then g.groupConditions = {} end
              g.groupConditions.hideWhenInactive = v
              -- RefreshBarSettings already refreshes the live bars, matching
              -- the other group-condition toggles.
              ns:RefreshBarSettings() end,
          spacing = 4 },
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
        { type = "toggle", id = "groupLastWidget", label = "Only In Instance",
          tooltip = "Only show this entire group inside a dungeon, raid, arena, or battleground.",
          get = function() local g = getGroup(); return g and g.groupConditions and g.groupConditions.onlyInInstance end,
          set = function(_, v) local g = getGroup(); if not g then return end
              if not g.groupConditions then g.groupConditions = {} end; g.groupConditions.onlyInInstance = v; ns:RefreshBarSettings() end,
          spacing = 2 },
    }

    refreshGroupSettings = ns:BuildSettings(groupSettingsContent, GROUP_SETTINGS_SCHEMA, groupSettingsWidgets,
        { firstX = 0, firstY = 0 })

    -- Deep-link the Group Conditions section to its Help answer.
    if groupSettingsWidgets.grpCondHeader and ns.CreateHelpIcon then
        ns:CreateHelpIcon(groupSettingsContent, groupSettingsWidgets.grpCondHeader,
            "LEFT", "RIGHT", 6, 0, "group-conditions")
    end

    -- ========================================================================
    -- RIGHT PANEL: Bar List + Bar Editor
    -- ========================================================================
    -- Bars tab content: same full-page region as the Groups tab (they occupy
    -- the same space and are shown one at a time by the bottom tabs).
    local rightPanel = CreateFrame("Frame", nil, frame)
    rightPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -44)
    rightPanel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 40)

    local barHeader = rightPanel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    barHeader:SetPoint("TOPLEFT", rightPanel, "TOPLEFT", 0, 0)
    barHeader:SetText("Bars")
    ns:CreateHelpIcon(rightPanel, barHeader, "LEFT", "RIGHT", 6, 0, "add-bar")

    -- Bar list spans the full page width; its height is set dynamically in
    -- UpdateBarList (grows with the bar count, up to MAX_BAR_ROWS rows, then
    -- scrolls). The buttons + editor below follow its bottom edge.
    local barScrollFrame = CreateFrame("ScrollFrame", "BarWardenBarScroll", rightPanel, "FauxScrollFrameTemplate")
    barScrollFrame:SetPoint("TOPLEFT", barHeader, "BOTTOMLEFT", 0, -6)
    -- Fixed width = the shared settings width (the button-row / Paste-button
    -- edge), so the list + its selection highlight stop at the same limit as
    -- everything else instead of stretching across the whole window.
    barScrollFrame:SetWidth(ns.SETTINGS_MAX_WIDTH or 300)
    barScrollFrame:SetHeight(MAX_BAR_ROWS * BAR_LIST_HEIGHT)

    local barRows = {}
    for i = 1, MAX_BAR_ROWS do
        local row = CreateFrame("Button", "BarWardenBarRow" .. i, rightPanel)
        row:SetHeight(BAR_LIST_HEIGHT)
        if i == 1 then
            row:SetPoint("TOPLEFT",  barScrollFrame, "TOPLEFT",   0, 0)
            row:SetPoint("TOPRIGHT", barScrollFrame, "TOPRIGHT", -22, 0)
        else
            row:SetPoint("TOPLEFT",  barRows[i - 1], "BOTTOMLEFT",  0, 0)
            row:SetPoint("TOPRIGHT", barRows[i - 1], "BOTTOMRIGHT", 0, 0)
        end

        local highlight = row:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetTexture(1, 1, 1, 0.1)

        local selected = row:CreateTexture(nil, "BACKGROUND")
        selected:SetAllPoints()
        selected:SetTexture(0.2, 0.4, 0.8, 0.3)
        selected:Hide()
        row.selected = selected

        -- Columns sized to fit within the capped list width (name + mode +
        -- target all land before the list's right edge, no clipping).
        local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        nameText:SetPoint("LEFT", row, "LEFT", 4, 0)
        nameText:SetJustifyH("LEFT")
        nameText:SetWidth(120)
        row.nameText = nameText

        local modeText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        modeText:SetPoint("LEFT", nameText, "RIGHT", 6, 0)
        modeText:SetJustifyH("LEFT")
        modeText:SetWidth(70)
        row.modeText = modeText

        local targetText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        targetText:SetPoint("LEFT", modeText, "RIGHT", 6, 0)
        targetText:SetJustifyH("LEFT")
        targetText:SetWidth(56)
        row.targetText = targetText

        row:SetScript("OnClick", function(self)
            selectedBarIndex = self.index
            frame:Refresh()
        end)

        -- Drag-to-reorder bars within the selected group (click still selects).
        row:RegisterForDrag("LeftButton")
        row:SetScript("OnDragStart", function(self) frame._dragBar = self.index end)
        row:SetScript("OnDragStop", function()
            local from = frame._dragBar
            frame._dragBar = nil
            local g = selectedGroupIndex and BarWardenDB and BarWardenDB.frames[selectedGroupIndex]
            local bars = g and g.bars
            if not from or not bars or #bars < 2 then return end
            local to = ComputeDropIndex(barScrollFrame, BAR_LIST_HEIGHT, #bars)
            if to and to ~= from then
                table.insert(bars, to, table.remove(bars, from))
                selectedBarIndex = to
                frame:Refresh()
                ns:RebuildAllFrames()
            end
        end)

        barRows[i] = row
    end

    -- Bar list buttons: compact single row.
    -- +/- for add/delete, arrows for reorder, Dupe/Paste for copy-paste.
    local addBarBtn = ns:CreateButton(rightPanel, "+", 42, function()
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

    local deleteBarBtn = ns:CreateButton(rightPanel, "-", 42, function()
        if not selectedGroupIndex or not selectedBarIndex then ns:Print("Select a bar first."); return end
        local g = BarWardenDB.frames[selectedGroupIndex]
        if not g then return end
        local bar = g.bars[selectedBarIndex]
        if not bar then return end
        -- Capture the bar itself; the popup is not modal, so re-reading the
        -- selection at accept time could remove a different bar (or the wrong
        -- index of a different group) than the one the popup names.
        local targetBar = bar
        local popup = StaticPopup_Show("BARWARDEN_CONFIRM_DELETE", bar.name or "this bar")
        if popup then
            popup.data = {
                onAccept = function()
                    local idx
                    for i, b in ipairs(g.bars) do
                        if b == targetBar then idx = i; break end
                    end
                    if not idx then
                        ns:Print("That bar no longer exists.")
                        return
                    end
                    ns:BackupFrames("delete bar")
                    table.remove(g.bars, idx)
                    if selectedBarIndex and selectedBarIndex > #g.bars then
                        selectedBarIndex = #g.bars > 0 and #g.bars or nil
                    end
                    frame:Refresh()
                    ns:RebuildAllFrames()
                end,
            }
        end
    end)
    deleteBarBtn:SetPoint("LEFT", addBarBtn, "RIGHT", 1, 0)

    local moveUpBtn = ns:CreateButton(rightPanel, "Up", 44, function()
        if not selectedGroupIndex or not selectedBarIndex then ns:Print("Select a bar first."); return end
        local bars = BarWardenDB.frames[selectedGroupIndex].bars
        if selectedBarIndex <= 1 then return end
        bars[selectedBarIndex], bars[selectedBarIndex - 1] = bars[selectedBarIndex - 1], bars[selectedBarIndex]
        selectedBarIndex = selectedBarIndex - 1
        frame:Refresh()
        ns:RebuildAllFrames()
    end)
    moveUpBtn:SetPoint("LEFT", deleteBarBtn, "RIGHT", 1, 0)

    local moveDownBtn = ns:CreateButton(rightPanel, "Dn", 44, function()
        if not selectedGroupIndex or not selectedBarIndex then ns:Print("Select a bar first."); return end
        local bars = BarWardenDB.frames[selectedGroupIndex].bars
        if selectedBarIndex >= #bars then return end
        bars[selectedBarIndex], bars[selectedBarIndex + 1] = bars[selectedBarIndex + 1], bars[selectedBarIndex]
        selectedBarIndex = selectedBarIndex + 1
        frame:Refresh()
        ns:RebuildAllFrames()
    end)
    moveDownBtn:SetPoint("LEFT", moveUpBtn, "RIGHT", 1, 0)

    local copyBarBtn = ns:CreateButton(rightPanel, "Dupe", 60, function()
        if not selectedGroupIndex or not selectedBarIndex then ns:Print("Select a bar first."); return end
        local bar = frame:GetSelectedBar()
        if not bar then return end
        ns.copiedBar = ns:CopyTable(bar)
        ns:Print("Bar copied: " .. (bar.name or "unnamed"))
    end)
    copyBarBtn:SetPoint("LEFT", moveDownBtn, "RIGHT", 1, 0)

    local pasteBarBtn = ns:CreateButton(rightPanel, "Paste", 60, function()
        if not selectedGroupIndex then ns:Print("Select a group first."); return end
        if not ns.copiedBar then ns:Print("Nothing to paste. Copy a bar first."); return end
        local g = BarWardenDB.frames[selectedGroupIndex]
        if not g then return end
        local maxBars = ns.MAX_BARS_PER_FRAME or 30
        if #g.bars >= maxBars then
            ns:Print("Maximum of " .. maxBars .. " bars per group reached.")
            return
        end
        local pasted = ns:CopyTable(ns.copiedBar)
        pasted.name = (pasted.name or "Bar") .. " (paste)"
        table.insert(g.bars, pasted)
        selectedBarIndex = #g.bars
        frame:Refresh()
        ns:RebuildAllFrames()
        ns:Print("Bar pasted: " .. pasted.name)
    end)
    pasteBarBtn:SetPoint("LEFT", copyBarBtn, "RIGHT", 1, 0)

    -- ========================================================================
    -- BAR EDITOR SUB-PANEL (scroll frame so content doesn't clip)
    -- ========================================================================
    -- The editor sits BELOW the bar list + buttons and spans the full page
    -- width (stacked layout, uniform with the Groups tab). This keeps the
    -- editor visible even at the smallest window size. It fills the remaining
    -- height and reflows on resize.
    local editorHeader = rightPanel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    editorHeader:SetPoint("TOPLEFT", addBarBtn, "BOTTOMLEFT", 0, -10)
    editorHeader:SetText("Bar Settings")

    local editorPanel = CreateFrame("Frame", nil, rightPanel)
    editorPanel:SetPoint("TOPLEFT", editorHeader, "BOTTOMLEFT", 0, -6)
    editorPanel:SetPoint("BOTTOMRIGHT", rightPanel, "BOTTOMRIGHT", 0, 0)

    local editorScroll = CreateFrame("ScrollFrame", "BarWardenBarEditorScrollFrame", editorPanel, "UIPanelScrollFrameTemplate")
    editorScroll:SetPoint("TOPLEFT",     editorPanel, "TOPLEFT",     0,   0)
    editorScroll:SetPoint("BOTTOMRIGHT", editorPanel, "BOTTOMRIGHT", -24, 0)

    local ec = CreateFrame("Frame", nil, editorScroll)  -- ec = editor content (scroll child)
    ec:SetWidth(340)   -- initial width; OnShow resizes to match the scroll viewport
    -- Generous fallback height so the full single-column editor is always
    -- reachable; fitEditorHeight() trims it to the real content once the editor
    -- is first shown (a fixed 660 used to clip the lower half off the scroll).
    ec:SetHeight(1100)
    editorScroll:SetScrollChild(ec)

    -- Bar name (first field, flush top to match group editor layout)
    local barNameEdit = ns:CreateEditBox(ec, "", 130, function(self, text)
        local bar = frame:GetSelectedBar()
        if bar then
            bar.name = text
            frame:Refresh()  -- updates the bar-list row on the left
            ns:RefreshBarSettings()
        end
    end,
    "A label for this bar, shown in the list and (if Show Bar Name is on) on "
 .. "the bar itself.")
    barNameEdit:SetPoint("TOPLEFT", ec, "TOPLEFT", 4, 0)
    -- Stretch the name box to the editor width so it uses the space (reactive:
    -- ec reflows to the viewport, and the RIGHT anchor follows). Right margin
    -- matches the schema stretch pad so every field lines up on the right.
    barNameEdit:SetPoint("RIGHT", ec, "RIGHT", -6, 0)

    -- Bar enabled checkbox
    local barEnabledCB = ns:CreateCheckbox(ec, "Enabled", "Enable or disable this bar", function(self, checked)
        local bar = frame:GetSelectedBar()
        if bar then
            bar.enabled = checked
            -- A bar you switch off stops counting as "already tracked", so the
            -- auto-tracking duplicate filter has to recompute.
            if ns.InvalidateTrackedNames then ns:InvalidateTrackedNames() end
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
    barEnabledCB:SetPoint("TOPLEFT", barNameEdit, "BOTTOMLEFT", -6, -4)

    -- Spell Name / ID
    local spellEdit = ns:CreateEditBox(ec, "Spell Name or ID", 130, function(self, text)
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
    spellEdit:SetPoint("TOPLEFT", barEnabledCB, "BOTTOMLEFT", 6, -18)
    spellEdit:SetPoint("RIGHT", ec, "RIGHT", -6, 0)  -- stretch to editor width

    -- Single-column layout: Track Mode and Target stack vertically below
    -- Spell. The -16 x offset on the dropdowns compensates for WoW's
    -- invisible ~16 px left padding on UIDropDownMenu so the dropdown's
    -- label aligns with the edit-box labels above.

    -- Track Mode dropdown
    local trackModeDD = ns:CreateDropdown(ec, "Track Mode", TRACK_MODES, function(dd, value, index)
        local bar = frame:GetSelectedBar()
        if bar then
            bar.trackMode = value
            frame:Refresh()
            ns:RefreshBarSettings()
        end
    end,
    "What this bar watches: a spell cooldown, buff, debuff, proc, item "
 .. "cooldown, weapon enchant, totem, or a class resource.")
    UIDropDownMenu_SetWidth(trackModeDD, 180)
    trackModeDD:SetPoint("TOPLEFT", spellEdit, "BOTTOMLEFT", -16, -18)

    -- Target dropdown
    local targetDD = ns:CreateDropdown(ec, "Target", TARGET_UNITS, function(dd, value, index)
        local bar = frame:GetSelectedBar()
        if bar then
            bar.unit = value
            bar.target = nil  -- clear legacy field so unit takes effect
            frame:Refresh()
            ns:RefreshBarSettings()
        end
    end,
    "Whose buff or debuff this bar watches (you, your target, focus, pet, or "
 .. "mouseover). Ignored for cooldowns and items.")
    UIDropDownMenu_SetWidth(targetDD, 180)
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
            min = mn, max = mx, step = st, width = 140, stretch = true,
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
        { type = "header", text = "Conditions", id = "conditionsHeader" },

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

        { type = "editbox", label = "Health Below %", width = 60, stretch = true,
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

        { type = "editbox", label = "Require Buff", width = 130, stretch = true,
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
          min = 0.5, max = 2.0, step = 0.1, width = 140, stretch = true,
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
          min = 0, max = 100, step = 1, width = 140, stretch = true,
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
            { spacing = 20, offsetX = -4, id = "editorLastWidget" }),
    }

    -- Container frame for the schema-managed region, anchored below the
    -- imperative identity widgets (barEnabled through onlyMine).
    local editorSettingsFrame = CreateFrame("Frame", nil, ec)
    editorSettingsFrame:SetPoint("TOPLEFT", onlyMineCB, "BOTTOMLEFT", 0, -12)
    -- RIGHT-anchor to ec so the frame's right edge tracks the editor width; the
    -- schema's stretch widgets pin their RIGHT to this frame.
    editorSettingsFrame:SetPoint("RIGHT", ec, "RIGHT", 0, 0)
    editorSettingsFrame:SetHeight(800)

    local refreshEditorSettings = ns:BuildSettings(
        editorSettingsFrame, EDITOR_SCHEMA, editorWidgets,
        { firstX = 0, firstY = 0 })

    if editorWidgets.conditionsHeader then
        ns:CreateHelpIcon(editorSettingsFrame, editorWidgets.conditionsHeader,
            "LEFT", "RIGHT", 6, 0, "conditions-overview")
    end

    -- Reflow the editor content (and its schema-managed child) to the live
    -- viewport width, so the editor uses whatever width the right column has.
    local function reflowEditor(w)
        w = w or editorScroll:GetWidth()
        if w and w > 100 then
            -- Cap at the shared settings width so controls do not stretch
            -- absurdly wide on a large window (editorSettingsFrame tracks ec
            -- via its RIGHT anchor; the stretch widgets follow).
            local cw = math.min(w, ns.SETTINGS_MAX_WIDTH or 300)
            ec:SetWidth(cw)
            -- Dropdowns fill the same width (their box width is a template
            -- property, set here rather than via a RIGHT anchor).
            local ddW = math.max(120, cw - 60)
            if trackModeDD then UIDropDownMenu_SetWidth(trackModeDD, ddW) end
            if targetDD then UIDropDownMenu_SetWidth(targetDD, ddW) end
        end
    end
    editorScroll:SetScript("OnSizeChanged", function(_, w) reflowEditor(w) end)

    -- Trim the scroll children to their real content once laid out, so the
    -- scroll range covers every control (and no more). Runs once each - the
    -- widget set is fixed - and only when the panel is visible (GetBottom is nil
    -- while hidden). The generous fallback heights keep content reachable until
    -- then.
    local editorHeightDone, groupHeightDone
    local function fitEditorHeight()
        if editorHeightDone then return end
        local last = editorWidgets.editorLastWidget
        local top = ec:GetTop()
        local bottom = last and last:GetBottom()
        if top and bottom and top > bottom then
            ec:SetHeight(top - bottom + 24)
            editorHeightDone = true
        end
    end
    local function fitGroupHeight()
        if groupHeightDone then return end
        local last = groupSettingsWidgets.groupLastWidget
        local top = groupSettingsContent:GetTop()
        local bottom = last and last:GetBottom()
        if top and bottom and top > bottom then
            groupSettingsContent:SetHeight(top - bottom + 24)
            groupHeightDone = true
        end
    end

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
    -- Empty-state lines, shown when a list has no rows.
    local groupEmptyText = leftPanel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    groupEmptyText:SetPoint("TOPLEFT", groupScrollFrame, "TOPLEFT", 4, -4)
    groupEmptyText:SetWidth(170)
    groupEmptyText:SetJustifyH("LEFT")
    groupEmptyText:SetText("No groups yet. Click Add to create one.")
    groupEmptyText:Hide()

    local barEmptyText = rightPanel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    barEmptyText:SetPoint("TOPLEFT", barScrollFrame, "TOPLEFT", 4, -4)
    barEmptyText:SetWidth(180)
    barEmptyText:SetJustifyH("LEFT")
    barEmptyText:Hide()

    local function UpdateGroupList()
        local frames = BarWardenDB and BarWardenDB.frames or {}
        local offset = FauxScrollFrame_GetOffset(groupScrollFrame)
        local total = #frames

        -- Grow the list box to the item count (min one line, max MAX_GROUP_ROWS
        -- rows), so the buttons + settings below sit right under the list and
        -- stay visible at the smallest window; overflow scrolls.
        local shown = math.max(1, math.min(total, MAX_GROUP_ROWS))
        groupScrollFrame:SetHeight(shown * GROUP_LIST_HEIGHT)

        FauxScrollFrame_Update(groupScrollFrame, total, MAX_GROUP_ROWS, GROUP_LIST_HEIGHT)
        KeepListFrameShown(groupScrollFrame, "BarWardenGroupScrollScrollBar",
                           total > MAX_GROUP_ROWS)
        if total == 0 then groupEmptyText:Show() else groupEmptyText:Hide() end

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

        -- Grow the list box to the bar count (min one line, max MAX_BAR_ROWS
        -- rows); overflow scrolls. Uniform with the Groups tab.
        local shown = math.max(1, math.min(total, MAX_BAR_ROWS))
        barScrollFrame:SetHeight(shown * BAR_LIST_HEIGHT)

        FauxScrollFrame_Update(barScrollFrame, total, MAX_BAR_ROWS, BAR_LIST_HEIGHT)
        KeepListFrameShown(barScrollFrame, "BarWardenBarScrollScrollBar",
                           total > MAX_BAR_ROWS)
        if total == 0 then
            if selectedGroupIndex then
                barEmptyText:SetText("No bars in this group yet. Click + to add one.")
            else
                barEmptyText:SetText("Select a group on the Groups tab first.")
            end
            barEmptyText:Show()
        else
            barEmptyText:Hide()
        end

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
            editorHeader:Hide()
            return
        end
        editorPanel:Show()
        editorHeader:Show()
        if ns.After then ns:After(0, fitEditorHeight) end  -- trim scroll once shown

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
        -- Hide the settings column when no group is selected, so the right
        -- side isn't a panel of blank controls.
        if selectedGroupIndex then
            groupSettingsHeader:Show()
            groupSettingsScroll:Show()
            if ns.After then ns:After(0, fitGroupHeight) end  -- trim scroll once shown
        else
            groupSettingsHeader:Hide()
            groupSettingsScroll:Hide()
        end
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
            local bars = frames[selectedGroupIndex].bars or {}
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
    -- ========================================================================
    -- Page title + bottom tabs. "Bar Control" is a two-tab editor (Groups /
    -- Bars) rather than a flat panel, because managing groups and editing the
    -- bars inside them is a two-part workflow that shares one page.
    -- ========================================================================
    local pageTitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    pageTitle:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -16)
    pageTitle:SetText("Bar Control")

    local BC_TABS = { "Groups", "Bars" }
    local bcTabs = {}
    local function ShowBarControlTab(index)
        PanelTemplates_SetTab(frame, index)
        if index == 2 then
            rightPanel:Show()
            leftPanel:Hide()
        else
            leftPanel:Show()
            rightPanel:Hide()
        end
    end
    for i, label in ipairs(BC_TABS) do
        -- Named "<frameName>Tab<i>" so PanelTemplates_UpdateTabs finds them
        -- (and the v2-test rename stays correct since it derives from GetName).
        local tab = CreateFrame("Button", frame:GetName() .. "Tab" .. i, frame,
                                "CharacterFrameTabButtonTemplate")
        tab:SetText(label)
        tab:SetID(i)
        -- Larger tabs: scale the whole tab up (taller + bigger text) and pad it
        -- out well beyond its text width.
        tab:SetScale(1.3)
        if PanelTemplates_TabResize then PanelTemplates_TabResize(tab, 60) end
        tab:SetScript("OnClick", function(self)
            ShowBarControlTab(self:GetID())
            PlaySound("igCharacterInfoTab")
        end)
        if i == 1 then
            tab:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 8, 4)
        else
            tab:SetPoint("LEFT", bcTabs[i - 1], "RIGHT", -14, 0)
        end
        bcTabs[i] = tab
    end
    PanelTemplates_SetNumTabs(frame, #BC_TABS)
    ShowBarControlTab(1)

    frame:SetScript("OnShow", function(self)
        reflowEditor()
        if self.Refresh then self:Refresh() end
    end)

    return frame
end

ns:RegisterOptionsTab(2, CreateBarsTab)
