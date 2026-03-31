local addonName, ns = ...

-- ============================================================================
-- Bar.lua - Bar frame construction and visual configuration
-- ============================================================================

-- Texture lookup table
local TEXTURES = {
    ["Flat"]    = "Interface\\Buttons\\WHITE8x8",
    ["Glow"]    = "Interface\\AddOns\\BarWarden\\Textures\\Glow",
    ["Metal"]   = "Interface\\AddOns\\BarWarden\\Textures\\Metal",
    ["Leather"] = "Interface\\AddOns\\BarWarden\\Textures\\Leather",
}

-- ----------------------------------------------------------------------------
-- ResolveTexture: Get texture path from name or return custom path
-- ----------------------------------------------------------------------------
local function ResolveTexture(name)
    if not name or name == "" then
        return TEXTURES["Flat"]
    end
    return TEXTURES[name] or name
end

-- ----------------------------------------------------------------------------
-- GetBarColor: Determine bar color from config and bar data
-- ----------------------------------------------------------------------------
local function GetBarColor(bar, config)
    -- Per-bar color override
    local display = bar.barData and bar.barData.display
    if display and display.colorOverride then
        local c = display.colorOverride
        return c.r or 1, c.g or 1, c.b or 1
    end

    local visual = BarWardenDB and BarWardenDB.visual or ns.DEFAULTS.visual
    local colorMode = visual.colorMode or "CLASS"

    if colorMode == "CLASS" then
        return ns:GetPlayerClassColor()
    elseif colorMode == "TRACK_MODE" then
        local trackMode = bar.barData and bar.barData.trackMode or "Cooldown"
        local colors = visual.trackModeColors
        if colors and colors[trackMode] then
            local c = colors[trackMode]
            return c.r or 1, c.g or 1, c.b or 1
        end
        local dc = visual.defaultColor
        return dc.r or 0.2, dc.g or 0.6, dc.b or 1.0
    else -- "CUSTOM"
        local dc = visual.defaultColor
        return dc.r or 0.2, dc.g or 0.6, dc.b or 1.0
    end
end

-- ----------------------------------------------------------------------------
-- CreateBarFrame: Build a StatusBar from BarWardenBarTemplate
-- ----------------------------------------------------------------------------
local barCount = 0

function ns:CreateBarFrame(parent)
    barCount = barCount + 1
    local name = "BarWardenBar" .. barCount
    local bar = CreateFrame("StatusBar", name, parent or UIParent, "BarWardenBarTemplate")

    -- Cache child references
    bar.background   = _G[name .. "Background"]
    bar.border       = _G[name .. "Border"]
    bar.nameText     = _G[name .. "NameText"]
    bar.timeText     = _G[name .. "TimeText"]
    bar.icon         = _G[name .. "Icon"]
    bar.iconTexture  = _G[name .. "IconIconTexture"]
    bar.sparkFrame   = _G[name .. "SparkFrame"]
    bar.spark        = _G[name .. "SparkFrameSpark"]

    -- Set default StatusBar range
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)

    -- Default texture
    bar:SetStatusBarTexture(TEXTURES["Flat"])
    bar:GetStatusBarTexture():SetHorizTile(false)
    bar:GetStatusBarTexture():SetVertTile(false)

    -- Store bar-specific data
    bar.barData = nil  -- will be set when assigned to a tracking entry

    return bar
end

-- ----------------------------------------------------------------------------
-- ApplyVisualConfig: Apply visual settings to a bar frame
-- ----------------------------------------------------------------------------
function ns:ApplyVisualConfig(bar, config)
    if not bar then return end

    local visual = BarWardenDB and BarWardenDB.visual or ns.DEFAULTS.visual
    local display = config or (bar.barData and bar.barData.display) or {}

    -- Resolve style
    local style = display.style or "Full"

    -- Determine dimensions from visual defaults
    local barWidth  = visual.barWidth or 200
    local barHeight = visual.barHeight or 20
    local iconSize  = visual.iconSize or 20
    local fontSize  = visual.fontSize or 11
    local borderSize = visual.borderSize or 1

    -- Style overrides
    if style == "Compact" then
        barHeight = math.max(barHeight * 0.6, 8)
        iconSize  = barHeight
        fontSize  = math.max(fontSize - 2, 7)
    elseif style == "ComboPoint" then
        barHeight = math.max(barHeight * 0.5, 6)
        iconSize  = 0
        fontSize  = 0
    end

    -- Set bar size
    bar:SetWidth(barWidth)
    bar:SetHeight(barHeight)

    -- Resolve texture
    local textureName = display.textureOverride or visual.texture or "Flat"
    if textureName == "Custom" and visual.customTexture and visual.customTexture ~= "" then
        textureName = visual.customTexture
    end
    local texturePath = ResolveTexture(textureName)
    bar:SetStatusBarTexture(texturePath)

    -- Progress direction
    -- SetReverseFill does not exist in WoW 3.3.5a (added in Cataclysm).
    -- RTL is silently ignored; bars always fill left-to-right.
    -- (direction stored in DB for future compat but not applied here)

    -- Bar color
    local r, g, b = GetBarColor(bar, config)
    bar:SetStatusBarColor(r, g, b)

    -- Background
    if bar.background then
        bar.background:SetVertexColor(0, 0, 0, 0.6)
    end

    -- Border
    if bar.border then
        if borderSize > 0 then
            bar.border:Show()
            bar.border:SetVertexColor(0, 0, 0, 0.8)
        else
            bar.border:Hide()
        end
    end

    -- Icon visibility
    local showIcon = visual.showIcon
    if display.showIcon ~= nil then
        showIcon = display.showIcon
    end
    if style == "ComboPoint" then
        showIcon = false
    end

    if bar.icon then
        if showIcon and iconSize > 0 then
            bar.icon:Show()
            bar.icon:SetWidth(iconSize)
            bar.icon:SetHeight(iconSize)
        else
            bar.icon:Hide()
        end
    end

    -- Text visibility and positioning
    local showText = visual.textEnabled ~= false
    if display.showText ~= nil then
        showText = display.showText
    end
    if style == "ComboPoint" then
        showText = false
    end

    local textPosition = visual.textPosition or "INSIDE_LEFT"
    local font = visual.font or "Fonts\\FRIZQT__.TTF"

    if bar.nameText then
        if showText and fontSize > 0 and textPosition ~= "NONE" then
            bar.nameText:Show()
            bar.nameText:SetFont(font, fontSize, "OUTLINE")

            -- Anchor name text based on icon visibility
            bar.nameText:ClearAllPoints()
            local leftOffset = (showIcon and iconSize > 0) and (iconSize + 4) or 4
            bar.nameText:SetPoint("LEFT", bar, "LEFT", leftOffset, 0)
            bar.nameText:SetPoint("RIGHT", bar, "RIGHT", -44, 0)
        else
            bar.nameText:Hide()
        end
    end

    if bar.timeText then
        if showText and fontSize > 0 and textPosition ~= "NONE" then
            bar.timeText:Show()
            bar.timeText:SetFont(font, fontSize, "OUTLINE")
            bar.timeText:ClearAllPoints()
            bar.timeText:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
        else
            bar.timeText:Hide()
        end
    end

    -- Spark visibility
    local showSpark = visual.showSpark ~= false
    if style == "ComboPoint" then
        showSpark = false
    end

    if bar.sparkFrame then
        if showSpark then
            bar.sparkFrame:Show()
        else
            bar.sparkFrame:Hide()
        end
    end
end

-- ----------------------------------------------------------------------------
-- UpdateBarDisplay: Update the bar's visual state (value, text, spark position)
-- Called each frame or when bar data changes.
-- ----------------------------------------------------------------------------
function ns:UpdateBarDisplay(bar)
    if not bar or not bar.barData then return end

    local data = bar.barData
    local visual = BarWardenDB and BarWardenDB.visual or ns.DEFAULTS.visual
    local display = data.display or {}

    -- Calculate progress (0-1)
    local duration = data.duration or 0
    local remaining = data.remaining or 0
    local progress = 0
    if duration > 0 then
        progress = remaining / duration
        if progress < 0 then progress = 0 end
        if progress > 1 then progress = 1 end
    end

    bar:SetMinMaxValues(0, 1)
    bar:SetValue(progress)

    -- Update bar color (may change with track mode)
    local r, g, b = GetBarColor(bar)
    bar:SetStatusBarColor(r, g, b)

    -- Update icon texture
    if bar.icon and bar.icon:IsShown() and bar.iconTexture then
        local icon = data.icon
        if icon then
            bar.iconTexture:SetTexture(icon)
        end
    end

    -- Update text
    local textFormat = display.textFormat or visual.textFormat or "NAME_DURATION"
    local spellName = data.spellName or data.name or ""

    if bar.nameText and bar.nameText:IsShown() then
        if textFormat == "NAME_ONLY" or textFormat == "NAME_DURATION" or textFormat == "NAME_STACKS" then
            bar.nameText:SetText(spellName)
        elseif textFormat == "DURATION" then
            bar.nameText:SetText(ns:FormatTime(remaining))
        elseif textFormat == "STACKS" then
            bar.nameText:SetText(data.stacks and tostring(data.stacks) or "")
        elseif textFormat == "CUSTOM" then
            local fmt = display.customTextFormat or visual.customTextFormat or "%n %d"
            local text = fmt:gsub("%%n", spellName):gsub("%%d", ns:FormatTime(remaining))
            if data.stacks then
                text = text:gsub("%%s", tostring(data.stacks))
            else
                text = text:gsub("%%s", "")
            end
            bar.nameText:SetText(text)
        elseif textFormat == "NONE" then
            bar.nameText:SetText("")
        else
            bar.nameText:SetText(spellName)
        end
    end

    if bar.timeText and bar.timeText:IsShown() then
        if textFormat == "NAME_DURATION" or textFormat == "DURATION" then
            bar.timeText:SetText(ns:FormatTime(remaining))
        elseif textFormat == "NAME_STACKS" or textFormat == "STACKS" then
            bar.timeText:SetText(data.stacks and tostring(data.stacks) or "")
        else
            bar.timeText:SetText("")
        end
    end

    -- Update spark position
    if bar.sparkFrame and bar.sparkFrame:IsShown() then
        local barWidth = bar:GetWidth()
        local direction = display.progressDirection or "LTR"
        local sparkX
        if direction == "RTL" then
            sparkX = barWidth * (1 - progress)
        else
            sparkX = barWidth * progress
        end
        bar.sparkFrame:ClearAllPoints()
        bar.sparkFrame:SetPoint("CENTER", bar, "LEFT", sparkX, 0)
    end

    -- Alpha handling
    local activeAlpha = visual.activeAlpha or 1.0
    local inactiveAlpha = visual.inactiveAlpha or 0.3
    if remaining > 0 then
        bar:SetAlpha(activeAlpha)
    else
        bar:SetAlpha(inactiveAlpha)
    end
end
