local addonName, ns = ...

local widgetCount = 0

local function NextName(prefix)
    widgetCount = widgetCount + 1
    return "BarWarden" .. prefix .. widgetCount
end

function ns:CreateCheckbox(parent, label, tooltip, onClick)
    local name = NextName("CB")
    local cb = CreateFrame("CheckButton", name, parent, "InterfaceOptionsCheckButtonTemplate")
    _G[name .. "Text"]:SetText(label)
    cb.tooltipText = tooltip
    cb:HookScript("OnClick", function(self)
        if onClick then onClick(self, self:GetChecked() == 1) end
    end)
    return cb
end

function ns:CreateSlider(parent, label, min, max, step, onChange)
    local name = NextName("SL")
    local slider = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
    _G[name .. "Text"]:SetText(label)
    _G[name .. "Low"]:SetText(tostring(min))
    _G[name .. "High"]:SetText(tostring(max))
    slider:SetMinMaxValues(min, max)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    slider:HookScript("OnValueChanged", function(self, value)
        if onChange then onChange(self, value) end
    end)
    return slider
end

function ns:CreateDropdown(parent, label, items, onSelect)
    local name = NextName("DD")
    local dd = CreateFrame("Frame", name, parent, "UIDropDownMenuTemplate")

    local lbl = dd:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl:SetPoint("BOTTOMLEFT", dd, "TOPLEFT", 16, 3)
    lbl:SetText(label)

    UIDropDownMenu_SetWidth(dd, 150)

    local function Initialize(self, level)
        for i, item in ipairs(items) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = item.text or item
            info.value = item.value or item
            info.func = function(self)
                UIDropDownMenu_SetSelectedID(dd, i)
                if onSelect then onSelect(dd, self.value, i) end
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end

    UIDropDownMenu_Initialize(dd, Initialize)

    return dd
end

function ns:CreateEditBox(parent, label, width, onChange)
    local name = NextName("EB")
    local eb = CreateFrame("EditBox", name, parent, "InputBoxTemplate")
    eb:SetSize(width or 150, 20)
    eb:SetAutoFocus(false)

    local lbl = eb:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl:SetPoint("BOTTOMLEFT", eb, "TOPLEFT", 0, 3)
    lbl:SetText(label)

    eb:HookScript("OnEnterPressed", function(self)
        self:ClearFocus()
        if onChange then onChange(self, self:GetText()) end
    end)
    eb:HookScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    return eb
end

function ns:CreateButton(parent, label, width, onClick)
    local name = NextName("BT")
    local btn = CreateFrame("Button", name, parent, "UIPanelButtonTemplate")
    btn:SetSize(width or 100, 22)
    btn:SetText(label)
    btn:SetScript("OnClick", function(self)
        if onClick then onClick(self) end
    end)
    return btn
end

function ns:CreateColorSwatch(parent, label, initialColor, onChange)
    local name = NextName("CS")
    local frame = CreateFrame("Frame", name, parent)
    frame:SetSize(20, 20)

    local swatch = frame:CreateTexture(nil, "ARTWORK")
    swatch:SetAllPoints()
    local c = initialColor or { r = 1, g = 1, b = 1, a = 1 }
    swatch:SetTexture(c.r, c.g, c.b, c.a or 1)

    local border = frame:CreateTexture(nil, "BORDER")
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetTexture(0.5, 0.5, 0.5, 1)

    local lbl = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl:SetPoint("LEFT", frame, "RIGHT", 5, 0)
    lbl:SetText(label)

    frame:EnableMouse(true)
    frame:SetScript("OnMouseUp", function(self)
        local prev = { r = c.r, g = c.g, b = c.b, a = c.a or 1 }

        local function SetColor()
            local r, g, b = ColorPickerFrame:GetColorRGB()
            -- Opacity is inverted in 3.3.5a: 0 = opaque, 1 = transparent
            local a = 1 - OpacitySliderFrame:GetValue()
            c.r, c.g, c.b, c.a = r, g, b, a
            swatch:SetTexture(r, g, b, a)
            if onChange then onChange(self, c) end
        end

        local function CancelColor()
            c.r, c.g, c.b, c.a = prev.r, prev.g, prev.b, prev.a
            swatch:SetTexture(prev.r, prev.g, prev.b, prev.a)
            if onChange then onChange(self, c) end
        end

        ColorPickerFrame:Hide()
        ColorPickerFrame.hasOpacity = true
        ColorPickerFrame.opacity = 1 - (c.a or 1) -- invert for display
        ColorPickerFrame.previousValues = { c.r, c.g, c.b, 1 - (c.a or 1) }
        ColorPickerFrame.func = SetColor
        ColorPickerFrame.opacityFunc = SetColor
        ColorPickerFrame.cancelFunc = CancelColor
        ColorPickerFrame:SetColorRGB(c.r, c.g, c.b)
        ColorPickerFrame:Show()
    end)

    frame.swatch = swatch
    frame.color = c

    return frame
end
