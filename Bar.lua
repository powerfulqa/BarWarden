local addonName, ns = ...

-- ============================================================================
-- Bar.lua - Bar frame construction and visual configuration
-- ============================================================================

-- Texture lookup table — all files live in BarWarden/Textures/
local T = "Interface\\AddOns\\BarWarden\\Textures\\"

local TEXTURES = {
    ["Flat"]     = "Interface\\Buttons\\WHITE8x8",
    ["Smooth"]   = T .. "Smooth.tga",
    ["Gloss"]    = T .. "Gloss.tga",
    ["Aluminum"] = T .. "Aluminum.tga",
    ["Armory"]   = T .. "Armory.tga",
    ["Graphite"] = T .. "Graphite.tga",
    ["Otravi"]   = T .. "Otravi.tga",
    ["Striped"]  = T .. "Striped.tga",
    ["Canvas"]   = T .. "Canvas.tga",
    ["LiteStep"] = T .. "LiteStep.tga",
    ["Glow"]     = T .. "Glow.tga",
    ["Metal"]    = T .. "Metal.tga",
    ["Leather"]  = T .. "Leather.tga",
}

-- ----------------------------------------------------------------------------
-- ResolveBarIcon: Look up the spell/item icon from bar configuration.
-- Returns the icon texture path or nil if nothing can be resolved.
-- ----------------------------------------------------------------------------
local function ResolveBarIcon(barData)
    if not barData then return nil end

    local mode = barData.trackMode
    local input = barData.spellName or barData.spellId

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
-- GetBarDisplayName: Resolve the text shown on a bar.
-- Always uses the user-entered Bar Name field.
-- ----------------------------------------------------------------------------
function ns.GetBarDisplayName(barData)
    if not barData then return "" end
    if barData.name and barData.name ~= "" then
        return barData.name
    end
    return ""
end

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

    -- Cache child Frame references
    bar.background   = _G[name .. "Background"]
    bar.border       = _G[name .. "Border"]
    bar.icon         = _G[name .. "Icon"]
    -- The icon texture declared in the XML template may not be globally
    -- registered in WoW 3.3.5a (same issue as FontStrings in StatusBars).
    -- Fall back to creating it in Lua if the _G lookup returns nil.
    bar.iconTexture  = _G[name .. "IconIconTexture"]
    if bar.icon and not bar.iconTexture then
        bar.iconTexture = bar.icon:CreateTexture(nil, "ARTWORK")
        bar.iconTexture:SetAllPoints()
    end

    -- Create spark first in OVERLAY so text FontStrings (also OVERLAY, created after)
    -- render on top of it. Within the same draw layer, WoW renders in creation order.
    bar.sparkFrame = bar:CreateTexture(nil, "OVERLAY")
    bar.sparkFrame:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
    bar.sparkFrame:SetBlendMode("ADD")
    bar.sparkFrame:SetWidth(16)
    bar.sparkFrame:SetHeight(32)
    bar.sparkFrame:SetPoint("CENTER", bar, "LEFT", 0, 0)
    bar.sparkFrame:Hide()

    -- Create text FontStrings in OVERLAY after spark so they render on top of it.
    -- FontStrings declared inside a StatusBar <Layer> block in Templates.xml are
    -- NOT registered as globals in WoW 3.3.5a — _G lookups return nil.
    -- Creating them here guarantees bar.nameText / bar.timeText are never nil.
    bar.nameText = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.nameText:SetJustifyH("LEFT")
    bar.nameText:SetPoint("LEFT",  bar, "LEFT",  24,  0)
    bar.nameText:SetPoint("RIGHT", bar, "RIGHT", -40, 0)

    bar.timeText = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.timeText:SetJustifyH("RIGHT")
    bar.timeText:SetPoint("RIGHT", bar, "RIGHT", -4, 0)

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

    -- Background (per-bar opacity via display.barAlpha)
    if bar.background then
        local barAlpha = display.barAlpha or 0.6
        bar.background:SetVertexColor(0, 0, 0, barAlpha)
    end

    -- Border
    if bar.border then
        bar.border:SetVertexColor(0, 0, 0, 0.8)
    end

    -- Icon visibility: per-bar display.showIcon is the authority (true/false).
    -- Falls back to global visual.showIcon only if display.showIcon is nil.
    local showIcon
    if display.showIcon ~= nil then
        showIcon = display.showIcon
    else
        showIcon = visual.showIcon ~= false
    end
    if style == "ComboPoint" then
        showIcon = false
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
            -- Set icon texture on inactive bars so it's visible immediately
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

    -- Text visibility: per-bar display.showName is the authority (true/false).
    -- Falls back to global visual.textEnabled only if display.showName is nil.
    local showText
    if display.showName ~= nil then
        showText = display.showName
    else
        showText = visual.textEnabled ~= false
    end
    if style == "ComboPoint" then
        showText = false
    end

    local textPosition = visual.textPosition or "INSIDE_LEFT"
    local textFormat   = visual.textFormat   or "NAME_DURATION"
    local font         = visual.font         or "Fonts\\FRIZQT__.TTF"

    -- When per-bar showName is on, guarantee valid text settings so the
    -- bar name is always visible regardless of global config
    if display.showName then
        if fontSize <= 0 then fontSize = 11 end
        if textPosition == "NONE" then textPosition = "INSIDE_LEFT" end
    end

    -- Determine which text elements to show based on format
    local showNameText = showText and fontSize > 0 and textPosition ~= "NONE"
    local showTimeText = showText and fontSize > 0 and textPosition ~= "NONE"
    if textFormat == "NAME_ONLY" then
        showTimeText = false
    elseif textFormat == "DURATION" or textFormat == "STACKS" then
        showNameText = false
    elseif textFormat == "NONE" then
        showNameText = false
        showTimeText = false
    end

    -- Icon offset calculation
    local iconActive      = showIcon and iconSize > 0
    local leftOffset      = (iconActive and not iconOnRight) and (iconSize + 4) or 4
    local rightOffset     = (iconActive and iconOnRight) and -(iconSize + 4) or -4
    local nameRightOffset = rightOffset - 40

    if bar.nameText then
        if showNameText then
            bar.nameText:Show()
            bar.nameText:SetFont(font, fontSize, "OUTLINE")
            bar.nameText:ClearAllPoints()
            if textPosition == "INSIDE_RIGHT" then
                bar.nameText:SetJustifyH("RIGHT")
                bar.nameText:SetPoint("LEFT",  bar, "LEFT",  leftOffset + 40, 0)
                bar.nameText:SetPoint("RIGHT", bar, "RIGHT", rightOffset,     0)
            else  -- INSIDE_LEFT (default)
                bar.nameText:SetJustifyH("LEFT")
                bar.nameText:SetPoint("LEFT",  bar, "LEFT",  leftOffset,      0)
                bar.nameText:SetPoint("RIGHT", bar, "RIGHT", nameRightOffset, 0)
            end
        else
            bar.nameText:Hide()
        end
    end

    if bar.timeText then
        if showTimeText then
            bar.timeText:Show()
            bar.timeText:SetFont(font, fontSize, "OUTLINE")
            bar.timeText:ClearAllPoints()
            if textPosition == "INSIDE_RIGHT" then
                bar.timeText:SetJustifyH("LEFT")
                bar.timeText:SetPoint("LEFT", bar, "LEFT", leftOffset, 0)
            else  -- INSIDE_LEFT (default)
                bar.timeText:SetJustifyH("RIGHT")
                bar.timeText:SetPoint("RIGHT", bar, "RIGHT", rightOffset, 0)
            end
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

