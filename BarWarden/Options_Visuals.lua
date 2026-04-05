local addonName, ns = ...

-- ============================================================================
-- Options_Visuals.lua - Tab 3: Visuals / Texturing
-- ============================================================================

local function CreateVisualsTab(parent)
    local frame = CreateFrame("Frame", "BarWardenVisualsTab", parent)
    frame:SetAllPoints(parent)
    frame:Hide()

    -- Scroll frame so content doesn't clip at the bottom of the panel.
    -- Start at -60 to sit below the panel title + subtitle (~54px combined).
    local scrollFrame = CreateFrame("ScrollFrame", "BarWardenVisualsScrollFrame", frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT",     frame, "TOPLEFT",     4,   -60)
    scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -28,   4)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetWidth(544)
    content:SetHeight(820)
    scrollFrame:SetScrollChild(content)

    -- All controls are placed on 'content'. yOffset begins near the top.
    local yOffset = -10

    -- -----------------------------------------------------------------------
    -- LEFT COLUMN (x = 16): Dimensions → Bar Color → Text Options → Opacity
    -- -----------------------------------------------------------------------

    -- Section: Frame Dimensions
    local dimHeader = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    dimHeader:SetPoint("TOPLEFT", content, "TOPLEFT", 16, yOffset)
    dimHeader:SetText("Frame Dimensions")

    local barWidthSlider = ns:CreateSlider(content, "Bar Width", 50, 400, 5, function(self, value)
        BarWardenDB.visual.barWidth = value
        if BarWardenDB.frames then
            for _, f in ipairs(BarWardenDB.frames) do
                f.width = value
            end
        end
        ns:RefreshAllBars()
    end)
    barWidthSlider:SetPoint("TOPLEFT", dimHeader, "BOTTOMLEFT", 4, -20)
    barWidthSlider:SetWidth(200)

    local barHeightSlider = ns:CreateSlider(content, "Bar Height", 4, 60, 1, function(self, value)
        BarWardenDB.visual.barHeight = value
        ns:RefreshAllBars()
    end)
    barHeightSlider:SetPoint("TOPLEFT", barWidthSlider, "BOTTOMLEFT", 0, -30)
    barHeightSlider:SetWidth(200)

    local borderSizeSlider = ns:CreateSlider(content, "Border Size", 0, 8, 1, function(self, value)
        BarWardenDB.visual.borderSize = value
        ns:RefreshAllBars()
    end)
    borderSizeSlider:SetPoint("TOPLEFT", barHeightSlider, "BOTTOMLEFT", 0, -30)
    borderSizeSlider:SetWidth(200)

    local barSpacingSlider = ns:CreateSlider(content, "Bar Spacing", 0, 30, 1, function(self, value)
        BarWardenDB.visual.barSpacing = value
        ns:RefreshAllBars()
    end)
    barSpacingSlider:SetPoint("TOPLEFT", borderSizeSlider, "BOTTOMLEFT", 0, -30)
    barSpacingSlider:SetWidth(200)

    -- Section: Icon
    local iconHeader = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    iconHeader:SetPoint("TOPLEFT", barSpacingSlider, "BOTTOMLEFT", -4, -24)
    iconHeader:SetText("Icon")

    local iconSizeSlider = ns:CreateSlider(content, "Icon Size", 0, 60, 1, function(self, value)
        BarWardenDB.visual.iconSize = value
        ns:RefreshAllBars()
    end)
    iconSizeSlider:SetPoint("TOPLEFT", iconHeader, "BOTTOMLEFT", 4, -20)
    iconSizeSlider:SetWidth(200)

    local iconPosItems = {
        { text = "Left",  value = "LEFT" },
        { text = "Right", value = "RIGHT" },
    }
    local iconPosDD = ns:CreateDropdown(content, "Icon Position", iconPosItems, function(dd, value)
        BarWardenDB.visual.iconPosition = value
        ns:RefreshAllBars()
    end)
    iconPosDD:SetPoint("TOPLEFT", iconSizeSlider, "BOTTOMLEFT", -16, -36)

    -- Section: Bar Color (aligned to x=16 to match other section headers)
    local colorHeader = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    colorHeader:SetPoint("TOPLEFT", iconPosDD, "BOTTOMLEFT", 12, -24)
    colorHeader:SetText("Bar Color")

    local colorModeItems = {
        { text = "Class Color",      value = "CLASS" },
        { text = "Track Mode Color", value = "TRACK_MODE" },
        { text = "Custom Color",     value = "CUSTOM" },
    }

    local colorSwatch

    local colorModeDD = ns:CreateDropdown(content, "Color Mode", colorModeItems, function(dd, value, index)
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
    colorModeDD:SetPoint("TOPLEFT", colorHeader, "BOTTOMLEFT", -16, -28)

    colorSwatch = ns:CreateColorSwatch(content, "Default Bar Color",
        nil,
        function(self, color)
            BarWardenDB.visual.defaultColor.r = color.r
            BarWardenDB.visual.defaultColor.g = color.g
            BarWardenDB.visual.defaultColor.b = color.b
            ns:RefreshAllBars()
        end)
    colorSwatch:SetPoint("TOPLEFT", colorModeDD, "BOTTOMLEFT", 20, -8)

    local perBarOverrideCB = ns:CreateCheckbox(content, "Allow Per-Bar Color Override",
        "When enabled, individual bars can override the global color setting.",
        function(self, checked)
            BarWardenDB.visual.perBarColorOverride = checked
        end)
    perBarOverrideCB:SetPoint("TOPLEFT", colorSwatch, "BOTTOMLEFT", -4, -4)

    -- Section: Text Options
    -- Two-column layout: Position + Font on left; Font Size + Text Format on right.
    local textHeader = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    textHeader:SetPoint("TOPLEFT", perBarOverrideCB, "BOTTOMLEFT", 0, -24)
    textHeader:SetText("Text Options")

    local textEnabledCB = ns:CreateCheckbox(content, "Show Bar Text",
        "Toggle text display on bars.",
        function(self, checked)
            BarWardenDB.visual.textEnabled = checked
            ns:RefreshAllBars()
        end)
    textEnabledCB:SetPoint("TOPLEFT", textHeader, "BOTTOMLEFT", 0, -8)

    -- Left sub-column: Text Position + Font
    local textPosItems = {
        { text = "Left",   value = "INSIDE_LEFT" },
        { text = "Center", value = "CENTER" },
        { text = "Right",  value = "INSIDE_RIGHT" },
        { text = "None",   value = "NONE" },
    }

    local textPosDD = ns:CreateDropdown(content, "Text Position", textPosItems, function(dd, value)
        BarWardenDB.visual.textPosition = value
        ns:RefreshAllBars()
    end)
    textPosDD:SetPoint("TOPLEFT", textEnabledCB, "BOTTOMLEFT", -4, -24)

    local BW_FONT = "Interface\\AddOns\\BarWarden\\Fonts\\"
    local fontItems = {
        -- WoW built-in fonts
        { text = "Friz Quadrata",   value = "Fonts\\FRIZQT__.TTF"          },
        { text = "Arial Narrow",    value = "Fonts\\ARIALN.TTF"            },
        { text = "Morpheus",        value = "Fonts\\MORPHEUS.TTF"          },
        { text = "Nimrod MT",       value = "Fonts\\NIM_____.ttf"          },
        { text = "Skurri",          value = "Fonts\\SKURRI.TTF"            },
        -- BarWarden custom fonts
        { text = "Adventure",       value = BW_FONT .. "adventure.ttf"     },
        { text = "Bazooka",         value = BW_FONT .. "bazooka.ttf"       },
        { text = "Cooline",         value = BW_FONT .. "cooline.ttf"       },
        { text = "Diogenes",        value = BW_FONT .. "diogenes.ttf"      },
        { text = "Ginko",           value = BW_FONT .. "ginko.ttf"         },
        { text = "Heroic",          value = BW_FONT .. "heroic.ttf"        },
        { text = "Porky",           value = BW_FONT .. "porky.ttf"         },
        { text = "Talisman",        value = BW_FONT .. "talisman.ttf"      },
        { text = "Transformers",    value = BW_FONT .. "transformers.ttf"   },
        { text = "Yellow Jacket",   value = BW_FONT .. "yellowjacket.ttf"  },
    }

    local fontDD = ns:CreateDropdown(content, "Font", fontItems, function(dd, value)
        BarWardenDB.visual.font = value
        ns:RefreshAllBars()
    end)
    fontDD:SetPoint("TOPLEFT", textPosDD, "BOTTOMLEFT", 0, -24)

    -- Right sub-column: Font Size + Text Format (aligned with textPosDD and fontDD rows)
    local fontSizeSlider = ns:CreateSlider(content, "Font Size", 6, 24, 1, function(self, value)
        BarWardenDB.visual.fontSize = value
        ns:RefreshAllBars()
    end)
    fontSizeSlider:SetPoint("TOPLEFT", textPosDD, "TOPRIGHT", 20, -18)
    fontSizeSlider:SetWidth(190)

    local textFormatItems = {
        { text = "Name + Duration",  value = "NAME_DURATION" },
        { text = "Name Only",        value = "NAME_ONLY" },
        { text = "Duration Only",    value = "DURATION" },
        { text = "Name + Stacks",    value = "NAME_STACKS" },
        { text = "Stacks Only",      value = "STACKS" },
        { text = "None",             value = "NONE" },
    }

    local textFormatDD = ns:CreateDropdown(content, "Text Format", textFormatItems, function(dd, value)
        BarWardenDB.visual.textFormat = value
        ns:RefreshAllBars()
    end)
    textFormatDD:SetPoint("TOPLEFT", fontDD, "TOPRIGHT", 20, 0)

    -- -----------------------------------------------------------------------
    -- RIGHT COLUMN (x = 280): Style Presets → Texture
    -- -----------------------------------------------------------------------

    -- Section: Style Presets
    local presetHeader = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    presetHeader:SetPoint("TOPLEFT", content, "TOPLEFT", 280, yOffset)
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

    local rogueBtn = ns:CreateButton(content, "Rogue", 86, function()
        ApplyPreset("Rogue")
    end)
    rogueBtn:SetPoint("TOPLEFT", presetHeader, "BOTTOMLEFT", 0, -10)

    local ntkBtn = ns:CreateButton(content, "NeedToKnow", 86, function()
        ApplyPreset("NeedToKnow")
    end)
    ntkBtn:SetPoint("LEFT", rogueBtn, "RIGHT", 4, 0)

    local minBtn = ns:CreateButton(content, "Minimalist", 86, function()
        ApplyPreset("Minimalist")
    end)
    minBtn:SetPoint("LEFT", ntkBtn, "RIGHT", 4, 0)

    -- Texture dropdown (no separate header — "Bar Texture" is the dropdown label itself)
    local textureItems = {
        { text = "Flat",      value = "Flat"     },
        { text = "Smooth",    value = "Smooth"   },
        { text = "Gloss",     value = "Gloss"    },
        { text = "Aluminum",  value = "Aluminum" },
        { text = "Armory",    value = "Armory"   },
        { text = "Graphite",  value = "Graphite" },
        { text = "Otravi",    value = "Otravi"   },
        { text = "Striped",   value = "Striped"  },
        { text = "Canvas",    value = "Canvas"   },
        { text = "LiteStep",  value = "LiteStep" },
        { text = "Glow",      value = "Glow"     },
        { text = "Metal",     value = "Metal"    },
        { text = "Leather",   value = "Leather"  },
        { text = "Custom",    value = "Custom"   },
    }

    local customTexBox
    local fallbackWarning

    local textureDD = ns:CreateDropdown(content, "Bar Texture", textureItems, function(dd, value, index)
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
    textureDD:SetPoint("TOPLEFT", rogueBtn, "BOTTOMLEFT", -16, -20)

    customTexBox = ns:CreateEditBox(content, "Custom Texture Filename", 150, function(self, text)
        BarWardenDB.visual.customTexture = text
        ns:RefreshAllBars()
    end)
    customTexBox:SetPoint("TOPLEFT", textureDD, "BOTTOMLEFT", 20, -8)
    customTexBox:Hide()

    fallbackWarning = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    fallbackWarning:SetPoint("TOPLEFT", customTexBox, "BOTTOMLEFT", 0, -4)
    fallbackWarning:SetText("|cffff8800Warning: If file not found, Flat texture will be used.|r")
    fallbackWarning:Hide()

    -- Section: Opacity (right column, below Texture)
    local opacityHeader = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    opacityHeader:SetPoint("TOPLEFT", textureDD, "BOTTOMLEFT", 16, -30)
    opacityHeader:SetText("Opacity")

    local activeAlphaSlider = ns:CreateSlider(content, "Active Opacity", 0, 1, 0.05, function(self, value)
        BarWardenDB.visual.activeAlpha = value
        ns:RefreshAllBars()
    end)
    activeAlphaSlider:SetPoint("TOPLEFT", opacityHeader, "BOTTOMLEFT", 4, -20)
    activeAlphaSlider:SetWidth(200)

    local inactiveAlphaSlider = ns:CreateSlider(content, "Inactive Opacity", 0, 1, 0.05, function(self, value)
        BarWardenDB.visual.inactiveAlpha = value
        ns:RefreshAllBars()
    end)
    inactiveAlphaSlider:SetPoint("TOPLEFT", activeAlphaSlider, "BOTTOMLEFT", 0, -28)
    inactiveAlphaSlider:SetWidth(200)

    local fadeInactiveCB = ns:CreateCheckbox(content, "Fade When Inactive",
        "Gradually fade bars to inactive opacity when not tracking anything.",
        function(self, checked)
            BarWardenDB.visual.fadeWhenInactive = checked
            ns:RefreshAllBars()
        end)
    fadeInactiveCB:SetPoint("TOPLEFT", inactiveAlphaSlider, "BOTTOMLEFT", -4, -22)

    local fadeSpeedSlider = ns:CreateSlider(content, "Fade Speed", 0.1, 2.0, 0.1, function(self, value)
        BarWardenDB.visual.fadeSpeed = value
    end)
    fadeSpeedSlider:SetPoint("TOPLEFT", fadeInactiveCB, "BOTTOMLEFT", 4, -22)
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
        for i, item in ipairs(iconPosItems) do
            if item.value == (v.iconPosition or "LEFT") then
                UIDropDownMenu_SetSelectedID(iconPosDD, i)
                UIDropDownMenu_SetText(iconPosDD, item.text)
                break
            end
        end
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
