local addonName, ns = ...

-- ============================================================================
-- MinimapButton.lua - Minimap icon: toggle config, drag to reposition
-- ============================================================================

local BUTTON_SIZE = 31
local ICON_RADIUS = 80  -- distance from minimap center
local DEFAULT_ANGLE = 220

local button

-- --------------------------------------------------------------------------
-- Positioning helpers
-- --------------------------------------------------------------------------

local function GetButtonPosition(angle)
    local rad = math.rad(angle)
    local x = math.cos(rad) * ICON_RADIUS
    local y = math.sin(rad) * ICON_RADIUS
    return x, y
end

local function UpdatePosition(angle)
    local x, y = GetButtonPosition(angle)
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

-- --------------------------------------------------------------------------
-- Drag handlers
-- --------------------------------------------------------------------------

local function OnDragStart()
    button.isDragging = true
    button:LockHighlight()
end

local function OnDragStop()
    button.isDragging = false
    button:UnlockHighlight()

    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    cx, cy = cx / scale, cy / scale

    local angle = math.deg(math.atan2(cy - my, cx - mx))
    if angle < 0 then angle = angle + 360 end

    if BarWardenDB and BarWardenDB.global then
        BarWardenDB.global.minimapIconPos = angle
    end
    UpdatePosition(angle)
end

local function OnUpdate()
    if not button.isDragging then return end

    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    cx, cy = cx / scale, cy / scale

    local angle = math.deg(math.atan2(cy - my, cx - mx))
    if angle < 0 then angle = angle + 360 end
    UpdatePosition(angle)
end

-- --------------------------------------------------------------------------
-- Tooltip
-- --------------------------------------------------------------------------

local function OnEnter(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    local enabled = BarWardenDB and BarWardenDB.global and BarWardenDB.global.enabled
    if enabled then
        GameTooltip:AddLine("BarWarden", 1, 1, 1)
    else
        GameTooltip:AddLine("BarWarden (Disabled)", 1, 0.4, 0.4)
    end
    GameTooltip:AddLine("Left-click to open options", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Right-click to enable/disable", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Drag to reposition", 0.8, 0.8, 0.8)
    GameTooltip:Show()
end

local function OnLeave()
    GameTooltip:Hide()
end

-- --------------------------------------------------------------------------
-- Click handler
-- --------------------------------------------------------------------------

local function OnClick(self, clickButton)
    if clickButton == "RightButton" then
        local enabled = BarWardenDB and BarWardenDB.global and BarWardenDB.global.enabled
        ns:SetEnabled(not enabled)
    else
        -- Use hardcoded name to match panel.name in Options.lua
        -- (addonName from folder is lowercase "barwarden", panel is "BarWarden")
        InterfaceOptionsFrame_OpenToCategory("BarWarden")
        InterfaceOptionsFrame_OpenToCategory("BarWarden")
    end
end

-- --------------------------------------------------------------------------
-- Create the button
-- --------------------------------------------------------------------------

local function CreateMinimapButton()
    button = CreateFrame("Button", "BarWardenMinimapButton", Minimap)
    button:SetFrameStrata("MEDIUM")
    button:SetWidth(BUTTON_SIZE)
    button:SetHeight(BUTTON_SIZE)
    button:SetFrameLevel(8)
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    -- Icon overlay
    local overlay = button:CreateTexture(nil, "OVERLAY")
    overlay:SetWidth(53)
    overlay:SetHeight(53)
    overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    overlay:SetPoint("TOPLEFT")

    -- Icon background
    local icon = button:CreateTexture(nil, "BACKGROUND")
    icon:SetWidth(20)
    icon:SetHeight(20)
    icon:SetTexture("Interface\\Icons\\Spell_Nature_EnchantArmor")
    icon:SetPoint("CENTER", 0, 1)
    button.icon = icon

    button:RegisterForClicks("AnyUp")
    button:RegisterForDrag("LeftButton")

    button:SetMovable(true)

    button:SetScript("OnClick", OnClick)
    button:SetScript("OnDragStart", OnDragStart)
    button:SetScript("OnDragStop", OnDragStop)
    button:SetScript("OnUpdate", OnUpdate)
    button:SetScript("OnEnter", OnEnter)
    button:SetScript("OnLeave", OnLeave)

    button.isDragging = false

    -- Position from saved data
    local angle = DEFAULT_ANGLE
    if BarWardenDB and BarWardenDB.global and BarWardenDB.global.minimapIconPos then
        angle = BarWardenDB.global.minimapIconPos
    end
    UpdatePosition(angle)

    return button
end

-- --------------------------------------------------------------------------
-- Public API
-- --------------------------------------------------------------------------

function ns:InitMinimapButton()
    if button then return end
    CreateMinimapButton()
    ns:UpdateMinimapButtonVisibility()
    ns:UpdateMinimapButtonState()
end

function ns:UpdateMinimapButtonVisibility()
    if not button then return end
    if BarWardenDB and BarWardenDB.global and BarWardenDB.global.minimapIcon then
        button:Show()
    else
        button:Hide()
    end
end

function ns:UpdateMinimapButtonState()
    if not button or not button.icon then return end
    local enabled = BarWardenDB and BarWardenDB.global and BarWardenDB.global.enabled
    -- Use pcall to prevent SetDesaturated errors from tainting the button frame
    local ok, desatOk = pcall(button.icon.SetDesaturated, button.icon, not enabled)
    if not ok or not desatOk then
        if not enabled then
            button.icon:SetVertexColor(0.5, 0.5, 0.5)
        else
            button.icon:SetVertexColor(1, 1, 1)
        end
    end
end

function ns:GetMinimapButton()
    return button
end
