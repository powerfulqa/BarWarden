local addonName, ns = ...

-- ============================================================================
-- Options_Visuals.lua - Tab 3: Visuals / Texturing
-- ============================================================================

local function CreateVisualsTab(parent)
    local frame = CreateFrame("Frame", "BarWardenVisualsTab", parent)
    frame:SetAllPoints(parent)
    frame:Hide()

    local yOffset = -80

    -- -----------------------------------------------------------------------
    -- Section: Frame Dimensions
    -- -----------------------------------------------------------------------
    local dimHeader = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    dimHeader:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, yOffset)
    dimHeader:SetText("Frame Dimensions")

    local barWidthSlider = ns:CreateSlider(frame, "Bar Width", 50, 400, 5, function(self, value)
        BarWardenDB.visual.barWidth = value
        ns:RefreshAllBars()
    end)
    barWidthSlider:SetPoint("TOPLEFT", dimHeader, "BOTTOMLEFT", 4, -20)
    barWidthSlider:SetWidth(200)

    local barHeightSlider = ns:CreateSlider(frame, "Bar Height", 4, 60, 1, function(self, value)
        BarWardenDB.visual.barHeight = value
        ns:RefreshAllBars()
    end)
    barHeightSlider:SetPoint("TOPLEFT", barWidthSlider, "BOTTOMLEFT", 0, -30)
    barHeightSlider:SetWidth(200)

    local iconSizeSlider = ns:CreateSlider(frame, "Icon Size", 0, 60, 1, function(self, value)
        BarWardenDB.visual.iconSize = value
        ns:RefreshAllBars()
    end)
    iconSizeSlider:SetPoint("TOPLEFT", barHeightSlider, "BOTTOMLEFT", 0, -30)
    iconSizeSlider:SetWidth(200)

    local borderSizeSlider = ns:CreateSlider(frame, "Border Size", 0, 4, 1, function(self, value)
        BarWardenDB.visual.borderSize = value
        ns:RefreshAllBars()
    end)
    borderSizeSlider:SetPoint("TOPLEFT", iconSizeSlider, "BOTTOMLEFT", 0, -30)
    borderSizeSlider:SetWidth(200)

    local barSpacingSlider = ns:CreateSlider(frame, "Bar Spacing", 0, 10, 1, function(self, value)
        BarWardenDB.visual.barSpacing = value
        ns:RefreshAllBars()
    end)
    barSpacingSlider:SetPoint("TOPLEFT", borderSizeSlider, "BOTTOMLEFT", 0, -30)
    barSpacingSlider:SetWidth(200)

    -- -----------------------------------------------------------------------
    -- Section: Style Presets (right column)
    -- -----------------------------------------------------------------------
    local presetHeader = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    presetHeader:SetPoint("TOPLEFT", frame, "TOPLEFT", 280, yOffset)
    presetHeader:SetText("Style Presets")

    local function ApplyPreset(presetName)
        local preset = ns.VISUAL_PRESETS[presetName]
        if not preset then return end
        local v = BarWardenDB.visual
        for key, value in pairs(preset) do
            if type(value) == "table" then
                v[key] = ns:CopyTable(value)
            else
                v[key] = value
            end
        end
        v.preset = presetName
        ns:RefreshAllBars()
        if frame.Refresh then frame:Refresh() end
    end

    local rogueBtn = ns:CreateButton(frame, "Rogue Style", 140, function()
        ApplyPreset("Rogue")
    end)
    rogueBtn:SetPoint("TOPLEFT", presetHeader, "BOTTOMLEFT", 0, -10)

    local ntkBtn = ns:CreateButton(frame, "NeedToKnow-like", 140, function()
        ApplyPreset("NeedToKnow")
    end)
    ntkBtn:SetPoint("TOPLEFT", rogueBtn, "BOTTOMLEFT", 0, -6)

    local minBtn = ns:CreateButton(frame, "Minimalist", 140, function()
        ApplyPreset("Minimalist")
    end)
    minBtn:SetPoint("TOPLEFT", ntkBtn, "BOTTOMLEFT", 0, -6)

    -- -----------------------------------------------------------------------
    -- Section: Texture
    -- -----------------------------------------------------------------------
    local texHeader = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    texHeader:SetPoint("TOPLEFT", presetHeader, "BOTTOMLEFT", 0, -120)
    texHeader:SetText("Texture")

    local textureItems = {
        { text = "Flat",    value = "Flat" },
        { text = "Glow",    value = "Glow" },
        { text = "Metal",   value = "Metal" },
        { text = "Leather", value = "Leather" },
        { text = "Custom",  value = "Custom" },
    }

    local customTexBox
    local fallbackWarning

    local textureDD = ns:CreateDropdown(frame, "Bar Texture", textureItems, function(dd, value, index)
        BarWardenDB.visual.texture = value
        if customTexBox then
            if value == "Custom" then
                customTexBox:Show()
                if fallbackWarning then fallbackWarning:Show() end
            else
                customTexBox:Hide()
                if fallbackWarning then fallbackWarning:Hide() end
            end
        end
        ns:RefreshAllBars()
    end)
    textureDD:SetPoint("TOPLEFT", texHeader, "BOTTOMLEFT", -16, -8)

    customTexBox = ns:CreateEditBox(frame, "Custom Texture Filename", 150, function(self, text)
        BarWardenDB.visual.customTexture = text
        ns:RefreshAllBars()
    end)
    customTexBox:SetPoint("TOPLEFT", textureDD, "BOTTOMLEFT", 20, -8)
    customTexBox:Hide()

    fallbackWarning = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    fallbackWarning:SetPoint("TOPLEFT", customTexBox, "BOTTOMLEFT", 0, -4)
    fallbackWarning:SetText("|cffff8800Warning: If file not found, Flat texture will be used.|r")
    fallbackWarning:Hide()

    -- -----------------------------------------------------------------------
    -- Section: Bar Color
    -- -----------------------------------------------------------------------
    local colorHeader = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    colorHeader:SetPoint("TOPLEFT", barSpacingSlider, "BOTTOMLEFT", -4, -30)
    colorHeader:SetText("Bar Color")

    local colorModeItems = {
        { text = "Class Color",      value = "CLASS" },
        { text = "Track Mode Color", value = "TRACK_MODE" },
        { text = "Custom Color",     value = "CUSTOM" },
    }

    local colorSwatch

    local colorModeDD = ns:CreateDropdown(frame, "Color Mode", colorModeItems, function(dd, value, index)
        BarWardenDB.visual.colorMode = value
        if colorSwatch then
            if value == "CUSTOM" then
                colorSwatch:Show()
            else
                colorSwatch:Hide()
            end
        end
        ns:RefreshAllBars()
    end)
    colorModeDD:SetPoint("TOPLEFT", colorHeader, "BOTTOMLEFT", -16, -8)

    colorSwatch = ns:CreateColorSwatch(frame, "Default Bar Color",
        nil,
        function(self, color)
            BarWardenDB.visual.defaultColor.r = color.r
            BarWardenDB.visual.defaultColor.g = color.g
            BarWardenDB.visual.defaultColor.b = color.b
            ns:RefreshAllBars()
        end)
    colorSwatch:SetPoint("TOPLEFT", colorModeDD, "BOTTOMLEFT", 20, -8)

    local perBarOverrideCB = ns:CreateCheckbox(frame, "Allow Per-Bar Color Override",
        "When enabled, individual bars can override the global color setting.",
        function(self, checked)
            BarWardenDB.visual.perBarColorOverride = checked
        end)
    perBarOverrideCB:SetPoint("TOPLEFT", colorSwatch, "BOTTOMLEFT", -4, -12)

    -- -----------------------------------------------------------------------
    -- Section: Text Options
    -- -----------------------------------------------------------------------
    local textHeader = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    textHeader:SetPoint("TOPLEFT", perBarOverrideCB, "BOTTOMLEFT", 0, -20)
    textHeader:SetText("Text Options")

    local textEnabledCB = ns:CreateCheckbox(frame, "Show Bar Text",
        "Toggle text display on bars.",
        function(self, checked)
            BarWardenDB.visual.textEnabled = checked
            ns:RefreshAllBars()
        end)
    textEnabledCB:SetPoint("TOPLEFT", textHeader, "BOTTOMLEFT", 0, -8)

    local textPosItems = {
        { text = "Top",          value = "TOP" },
        { text = "Bottom",       value = "BOTTOM" },
        { text = "Inside Left",  value = "INSIDE_LEFT" },
        { text = "Inside Right", value = "INSIDE_RIGHT" },
        { text = "None",         value = "NONE" },
    }

    local textPosDD = ns:CreateDropdown(frame, "Text Position", textPosItems, function(dd, value)
        BarWardenDB.visual.textPosition = value
        ns:RefreshAllBars()
    end)
    textPosDD:SetPoint("TOPLEFT", textEnabledCB, "BOTTOMLEFT", -4, -24)

    local fontItems = {
        { text = "Friz Quadrata",   value = "Fonts\\FRIZQT__.TTF" },
        { text = "Arial Narrow",    value = "Fonts\\ARIALN.TTF" },
        { text = "Morpheus",        value = "Fonts\\MORPHEUS.TTF" },
        { text = "Skurri",          value = "Fonts\\skurri.TTF" },
    }

    local fontDD = ns:CreateDropdown(frame, "Font", fontItems, function(dd, value)
        BarWardenDB.visual.font = value
        ns:RefreshAllBars()
    end)
    fontDD:SetPoint("TOPLEFT", textPosDD, "BOTTOMLEFT", 0, -24)

    local fontSizeSlider = ns:CreateSlider(frame, "Font Size", 6, 24, 1, function(self, value)
        BarWardenDB.visual.fontSize = value
        ns:RefreshAllBars()
    end)
    fontSizeSlider:SetPoint("TOPLEFT", fontDD, "BOTTOMLEFT", 20, -24)
    fontSizeSlider:SetWidth(200)

    local textFormatItems = {
        { text = "Name + Duration",  value = "NAME_DURATION" },
        { text = "Name Only",        value = "NAME_ONLY" },
        { text = "Name + Stacks",    value = "NAME_STACKS" },
        { text = "Duration Only",    value = "DURATION" },
        { text = "Stacks Only",      value = "STACKS" },
        { text = "Custom",           value = "CUSTOM" },
        { text = "None",             value = "NONE" },
    }

    local textFormatDD = ns:CreateDropdown(frame, "Text Format", textFormatItems, function(dd, value)
        BarWardenDB.visual.textFormat = value
        ns:RefreshAllBars()
    end)
    textFormatDD:SetPoint("TOPLEFT", fontSizeSlider, "BOTTOMLEFT", -20, -24)

    -- -----------------------------------------------------------------------
    -- Section: Opacity
    -- -----------------------------------------------------------------------
    local opacityHeader = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    opacityHeader:SetPoint("TOPLEFT", fallbackWarning, "BOTTOMLEFT", 0, -30)
    opacityHeader:SetText("Opacity")

    local activeAlphaSlider = ns:CreateSlider(frame, "Active Opacity", 0, 1, 0.05, function(self, value)
        BarWardenDB.visual.activeAlpha = value
        ns:RefreshAllBars()
    end)
    activeAlphaSlider:SetPoint("TOPLEFT", opacityHeader, "BOTTOMLEFT", 4, -20)
    activeAlphaSlider:SetWidth(200)

    local inactiveAlphaSlider = ns:CreateSlider(frame, "Inactive Opacity", 0, 1, 0.05, function(self, value)
        BarWardenDB.visual.inactiveAlpha = value
        ns:RefreshAllBars()
    end)
    inactiveAlphaSlider:SetPoint("TOPLEFT", activeAlphaSlider, "BOTTOMLEFT", 0, -30)
    inactiveAlphaSlider:SetWidth(200)

    local fadeInactiveCB = ns:CreateCheckbox(frame, "Fade When Inactive",
        "Gradually fade bars to inactive opacity when not tracking anything.",
        function(self, checked)
            BarWardenDB.visual.fadeWhenInactive = checked
            ns:RefreshAllBars()
        end)
    fadeInactiveCB:SetPoint("TOPLEFT", inactiveAlphaSlider, "BOTTOMLEFT", -4, -24)

    local fadeSpeedSlider = ns:CreateSlider(frame, "Fade Speed", 0.1, 2.0, 0.1, function(self, value)
        BarWardenDB.visual.fadeSpeed = value
    end)
    fadeSpeedSlider:SetPoint("TOPLEFT", fadeInactiveCB, "BOTTOMLEFT", 4, -24)
    fadeSpeedSlider:SetWidth(200)

    -- -----------------------------------------------------------------------
    -- Refresh function
    -- -----------------------------------------------------------------------
    frame.Refresh = function()
        if not BarWardenDB then return end
        local v = BarWardenDB.visual

        barWidthSlider:SetValue(v.barWidth or 200)
        barHeightSlider:SetValue(v.barHeight or 20)
        iconSizeSlider:SetValue(v.iconSize or 20)
        borderSizeSlider:SetValue(v.borderSize or 1)
        barSpacingSlider:SetValue(v.barSpacing or 2)

        -- Texture dropdown
        for i, item in ipairs(textureItems) do
            if item.value == v.texture then
                UIDropDownMenu_SetSelectedID(textureDD, i)
                UIDropDownMenu_SetText(textureDD, item.text)
                break
            end
        end
        if v.texture == "Custom" then
            customTexBox:Show()
            customTexBox:SetText(v.customTexture or "")
            if fallbackWarning then fallbackWarning:Show() end
        else
            customTexBox:Hide()
            if fallbackWarning then fallbackWarning:Hide() end
        end

        -- Color mode dropdown
        for i, item in ipairs(colorModeItems) do
            if item.value == v.colorMode then
                UIDropDownMenu_SetSelectedID(colorModeDD, i)
                UIDropDownMenu_SetText(colorModeDD, item.text)
                break
            end
        end
        if v.colorMode == "CUSTOM" then
            colorSwatch:Show()
        else
            colorSwatch:Hide()
        end
        local c = v.defaultColor or { r = 0.2, g = 0.6, b = 1.0 }
        colorSwatch.color.r = c.r
        colorSwatch.color.g = c.g
        colorSwatch.color.b = c.b
        colorSwatch.swatch:SetTexture(c.r, c.g, c.b, 1)

        perBarOverrideCB:SetChecked(v.perBarColorOverride)

        -- Text options
        textEnabledCB:SetChecked(v.textEnabled)

        for i, item in ipairs(textPosItems) do
            if item.value == v.textPosition then
                UIDropDownMenu_SetSelectedID(textPosDD, i)
                UIDropDownMenu_SetText(textPosDD, item.text)
                break
            end
        end

        for i, item in ipairs(fontItems) do
            if item.value == v.font then
                UIDropDownMenu_SetSelectedID(fontDD, i)
                UIDropDownMenu_SetText(fontDD, item.text)
                break
            end
        end

        fontSizeSlider:SetValue(v.fontSize or 11)

        for i, item in ipairs(textFormatItems) do
            if item.value == v.textFormat then
                UIDropDownMenu_SetSelectedID(textFormatDD, i)
                UIDropDownMenu_SetText(textFormatDD, item.text)
                break
            end
        end

        -- Opacity
        activeAlphaSlider:SetValue(v.activeAlpha or 1.0)
        inactiveAlphaSlider:SetValue(v.inactiveAlpha or 0.3)
        fadeInactiveCB:SetChecked(v.fadeWhenInactive)
        fadeSpeedSlider:SetValue(v.fadeSpeed or 0.3)
    end

    return frame
end

-- Register tab when options panel is created
local orig = ns.CreateOptionsPanel
ns.CreateOptionsPanel = function(self)
    local panel = orig(self)
    local tab = CreateVisualsTab(panel)
    ns.optionsTabs[3] = tab
    return panel
end
