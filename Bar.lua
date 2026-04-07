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
-- ResolveBarIcon: Look up the spell/item icon from bar configuration.
-- Returns the icon texture path or nil if nothing can be resolved.
-- ----------------------------------------------------------------------------
local function ResolveBarIcon(barData)
    if not barData then return nil end

    local mode = barData.trackMode
    local input = barData.spellName or barData.spellId or barData.spell

    if mode == "Item" then
        local itemId = barData.itemId or input
        if itemId then
            local _, _, _, _, _, _, _, _, _, icon = GetItemInfo(itemId)
            if icon then return icon end
        end
    else
        if input then
            local _, _, icon = GetSpellInfo(input)
            if icon then return icon end
        end
    end

    return nil
end

ns.ResolveBarIcon = ResolveBarIcon

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

    -- Ensure text always renders above child frames (e.g. sparkFrame)
    if bar.nameText then bar.nameText:SetDrawLayer("HIGHLIGHT") end
    if bar.timeText then bar.timeText:SetDrawLayer("HIGHLIGHT") end

    -- Spark texture must use additive blending; without it the alpha channel
    -- renders as solid black rather than transparent.
    if bar.spark then bar.spark:SetBlendMode("ADD") end

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

    -- Icon visibility and position
    local forceIcon = display.showIcon == true
    local showIcon = visual.showIcon
    if display.showIcon ~= nil then
        showIcon = display.showIcon
    end
    if style == "ComboPoint" and not forceIcon then
        showIcon = false
    end

    -- When Force Show Icon is on, guarantee a visible icon size
    if forceIcon and iconSize <= 0 then
        iconSize = barHeight
    end

    local iconOnRight = (visual.iconPosition == "RIGHT")

    if bar.icon then
        if showIcon and iconSize > 0 then
            bar.icon:Show()
            bar.icon:SetWidth(iconSize)
            bar.icon:SetHeight(iconSize)
            bar.icon:ClearAllPoints()
            if iconOnRight then
                bar.icon:SetPoint("RIGHT", bar, "RIGHT", 0, 0)
            else
                bar.icon:SetPoint("LEFT", bar, "LEFT", 0, 0)
            end
            -- Ensure the icon texture is set even on inactive bars so
            -- Force Show Icon displays the correct spell/item icon.
            if bar.iconTexture and not bar.iconTexture:GetTexture() then
                local icon = ResolveBarIcon(bar.barData)
                if icon then
                    bar.iconTexture:SetTexture(icon)
                end
            end
        else
            bar.icon:Hide()
        end
    end

    -- Text visibility and positioning
    local forceText = display.showText == true
    local textPosition = visual.textPosition or "INSIDE_LEFT"
    local showText = visual.textEnabled ~= false
    if display.showText ~= nil then
        showText = display.showText
    end
    if style == "ComboPoint" and not forceText then
        showText = false
    end

    -- When Force Show Text is on, guarantee visible text settings
    if forceText then
        if fontSize <= 0 then fontSize = 11 end
        if textPosition == "NONE" then textPosition = "INSIDE_LEFT" end
    end

    local font = visual.font or "Fonts\\FRIZQT__.TTF"

    -- Calculate offsets based on icon position
    local iconActive = showIcon and iconSize > 0
    local leftOffset  = (iconActive and not iconOnRight) and (iconSize + 4) or 4
    local rightOffset = (iconActive and iconOnRight) and -(iconSize + 4) or -4
    -- nameText right edge: leave room for timeText (~40px) plus icon if on right
    local nameRightOffset = rightOffset - 40

    if bar.nameText then
        if showText and fontSize > 0 and textPosition ~= "NONE" then
            bar.nameText:Show()
            bar.nameText:SetFont(font, fontSize, "OUTLINE")
            bar.nameText:ClearAllPoints()
            bar.nameText:SetPoint("LEFT",  bar, "LEFT",  leftOffset,     0)
            bar.nameText:SetPoint("RIGHT", bar, "RIGHT", nameRightOffset, 0)
        else
            bar.nameText:Hide()
        end
    end

    if bar.timeText then
        if showText and fontSize > 0 and textPosition ~= "NONE" then
            bar.timeText:Show()
            bar.timeText:SetFont(font, fontSize, "OUTLINE")
            bar.timeText:ClearAllPoints()
            bar.timeText:SetPoint("RIGHT", bar, "RIGHT", rightOffset, 0)
        else
            bar.timeText:Hide()
        end
    end

    -- Spark visibility and sizing
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

