local addonName, ns = ...

-- ============================================================================
-- Options_General.lua - Tab 1: General settings
-- ============================================================================

local function CreateGeneralTab(parent)
    local frame = CreateFrame("Frame", "BarWardenGeneralTab", parent)
    frame:SetAllPoints(parent)
    frame:Hide()

    local yOffset = -80

    -- -----------------------------------------------------------------------
    -- Enable/Disable Addon
    -- -----------------------------------------------------------------------
    local enableCB = ns:CreateCheckbox(frame, "Enable BarWarden",
        "Globally enable or disable BarWarden. When disabled, all frames are hidden and events are unregistered.",
        function(self, checked)
            ns:SetEnabled(checked)
            if checked then
                ns:RebuildAllFrames()
            end
        end)
    enableCB:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, yOffset)

    -- -----------------------------------------------------------------------
    -- Show/Hide All
    -- -----------------------------------------------------------------------
    local showAllCB = ns:CreateCheckbox(frame, "Show All Frames",
        "Toggle visibility of all bar frames.",
        function(self, checked)
            BarWardenDB.global.showAll = checked
            if checked then
                ns:ShowAllFrames()
            else
                ns:HideAllFrames()
            end
        end)
    showAllCB:SetPoint("TOPLEFT", enableCB, "BOTTOMLEFT", 0, -8)

    -- -----------------------------------------------------------------------
    -- Lock/Unlock All
    -- -----------------------------------------------------------------------
    local lockCB = ns:CreateCheckbox(frame, "Lock All Frames",
        "When locked, frames cannot be moved or resized.",
        function(self, checked)
            BarWardenDB.global.locked = checked
            if checked then
                ns:LockAllFrames()
            else
                ns:UnlockAllFrames()
            end
        end)
    lockCB:SetPoint("TOPLEFT", showAllCB, "BOTTOMLEFT", 0, -8)

    -- -----------------------------------------------------------------------
    -- Snap to Grid
    -- -----------------------------------------------------------------------
    local snapCB = ns:CreateCheckbox(frame, "Snap to Grid",
        "When enabled, frames will snap to a grid when moved.",
        function(self, checked)
            BarWardenDB.global.snapToGrid = checked
        end)
    snapCB:SetPoint("TOPLEFT", lockCB, "BOTTOMLEFT", 0, -8)

    -- Grid Size Slider
    local gridSlider = ns:CreateSlider(frame, "Grid Size", 2, 32, 2, function(self, value)
        BarWardenDB.global.gridSize = value
    end)
    gridSlider:SetPoint("TOPLEFT", snapCB, "BOTTOMLEFT", 4, -24)
    gridSlider:SetWidth(200)

    -- -----------------------------------------------------------------------
    -- Minimap Icon Toggle
    -- -----------------------------------------------------------------------
    local minimapCB = ns:CreateCheckbox(frame, "Show Minimap Icon",
        "Toggle the BarWarden minimap button.",
        function(self, checked)
            BarWardenDB.global.minimapIcon = checked
            ns:UpdateMinimapButtonVisibility()
        end)
    minimapCB:SetPoint("TOPLEFT", gridSlider, "BOTTOMLEFT", -4, -24)

    -- -----------------------------------------------------------------------
    -- Help Section
    -- -----------------------------------------------------------------------
    local helpHeader = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    helpHeader:SetPoint("TOPLEFT", minimapCB, "BOTTOMLEFT", 0, -24)
    helpHeader:SetText("Slash Commands")

    local helpText = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    helpText:SetPoint("TOPLEFT", helpHeader, "BOTTOMLEFT", 0, -6)
    helpText:SetJustifyH("LEFT")
    helpText:SetText(
        "|cffffd200/bw|r or |cffffd200/barwarden|r - Open configuration panel\n" ..
        "|cffffd200/bw lock|r - Toggle frame lock\n" ..
        "|cffffd200/bw show|r - Toggle frame visibility\n" ..
        "|cffffd200/bw reset|r - Reset frame positions"
    )

    local versionText = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    versionText:SetPoint("TOPLEFT", helpText, "BOTTOMLEFT", 0, -16)
    versionText:SetText("BarWarden v" .. (ns.version or "?") .. " | WoW 3.3.5a (Interface 30300)")

    -- -----------------------------------------------------------------------
    -- Refresh function
    -- -----------------------------------------------------------------------
    frame.Refresh = function()
        if not BarWardenDB then return end
        local g = BarWardenDB.global
        enableCB:SetChecked(g.enabled)
        showAllCB:SetChecked(g.showAll)
        lockCB:SetChecked(g.locked)
        snapCB:SetChecked(g.snapToGrid)
        gridSlider:SetValue(g.gridSize or 8)
        minimapCB:SetChecked(g.minimapIcon)
    end

    return frame
end

-- Register tab when options panel is created
local orig = ns.CreateOptionsPanel
ns.CreateOptionsPanel = function(self)
    local panel = orig(self)
    local tab = CreateGeneralTab(panel)
    ns.optionsTabs[1] = tab
    tab:Show()
    return panel
end
