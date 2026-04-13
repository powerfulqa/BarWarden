local addonName, ns = ...

local widgetCount = 0

-- Guard flag: when true, slider/checkbox OnValueChanged callbacks are
-- suppressed.  Set during programmatic SetValue calls (e.g. Refresh)
-- so that restoring UI state doesn't write back to the DB and overwrite
-- per-group settings with global defaults.
ns.suppressCallbacks = false

local function NextName(prefix)
    widgetCount = widgetCount + 1
    return "BarWarden" .. prefix .. widgetCount
end

-- ----------------------------------------------------------------------------
-- Tooltip helper for widgets whose frame templates don't have built-in
-- tooltip support (sliders, editboxes). Checkboxes use the template-provided
-- `tooltipText` field instead. Uses HookScript so we don't clobber any
-- existing OnEnter/OnLeave handlers the widget already has.
-- ----------------------------------------------------------------------------
local function AttachTooltip(widget, tooltipText)
    if not tooltipText or tooltipText == "" then return end
    widget:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(tooltipText, 1, 1, 1, 1, true)  -- trailing true = wrap
        GameTooltip:Show()
    end)
    widget:HookScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

-- ----------------------------------------------------------------------------
-- DB-path helpers
--
-- Walk a dotted path on a root table, returning (parentTable, lastKey) so
-- the caller can read parent[key] and write parent[key] = v.
-- Returns (nil, nil) if any intermediate segment is missing.
-- ----------------------------------------------------------------------------

local function ResolvePath(root, path)
    local parent, key = root, nil
    for segment in path:gmatch("[^.]+") do
        if key then
            if type(parent[key]) ~= "table" then return nil, nil end
            parent = parent[key]
        end
        key = segment
    end
    return parent, key
end

-- Returns a widget-shaped callback `(self, value)` that writes `value`
-- into BarWardenDB.<path> and optionally calls ns:<refreshMethod>() after.
--
-- Validates strictly at registration time:
--   1. the intermediate path must resolve under BarWardenDB
--   2. the leaf must already exist (i.e. be declared in ns.DEFAULTS)
--   3. the refresh method (if given) must be defined on ns
--
-- This makes ns.DEFAULTS the single source of truth for every option, and
-- surfaces typos at addon load instead of as a silent no-op when the user
-- clicks the control. By the time any Options_*.lua file constructs its
-- tab, ns:OnInitialize has run InitDB (populating defaults) and
-- Core/MinimapButton.lua have defined their refresh methods.
function ns:DBSet(path, refreshMethod)
    local parent, key = ResolvePath(BarWardenDB, path)
    if not parent then
        error(string.format(
            "ns:DBSet: path %q has an unresolved intermediate segment", path), 2)
    end
    if parent[key] == nil then
        error(string.format(
            "ns:DBSet: leaf %q is not declared in ns.DEFAULTS — add it there first",
            path), 2)
    end
    if refreshMethod and not ns[refreshMethod] then
        error(string.format(
            "ns:DBSet: refresh method ns:%s is not defined", refreshMethod), 2)
    end

    return function(_, value)
        local p, k = ResolvePath(BarWardenDB, path)
        if p then p[k] = value end
        if refreshMethod and ns[refreshMethod] then
            ns[refreshMethod](ns)
        end
    end
end

-- Read BarWardenDB.<path>, returning `default` if any segment is missing
-- or the leaf is nil. For use in Refresh handlers.
--
-- Unlike DBSet, DBGet does NOT validate at call time — its whole purpose
-- is to gracefully fall back when a path is absent (e.g. before MergeDefaults
-- has populated a new field on a pre-existing save).
function ns:DBGet(path, default)
    local parent, key = ResolvePath(BarWardenDB, path)
    if parent and parent[key] ~= nil then return parent[key] end
    return default
end

function ns:CreateCheckbox(parent, label, tooltip, onClick)
    local name = NextName("CB")
    local cb = CreateFrame("CheckButton", name, parent, "InterfaceOptionsCheckButtonTemplate")
    _G[name .. "Text"]:SetText(label)
    cb.tooltipText = tooltip
    cb:HookScript("OnClick", function(self)
        if ns.suppressCallbacks then return end
        if onClick then onClick(self, self:GetChecked() == 1) end
    end)
    return cb
end

function ns:CreateSlider(parent, label, min, max, step, onChange, tooltip)
    local name = NextName("SL")
    local slider = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
    local labelText = _G[name .. "Text"]
    labelText:SetText(label)
    _G[name .. "Low"]:SetText(tostring(min))
    _G[name .. "High"]:SetText(tostring(max))
    slider:SetMinMaxValues(min, max)
    slider:SetValueStep(step)
    slider.label = label  -- store for value display updates
    slider:HookScript("OnValueChanged", function(self, value)
        -- Always update the displayed value, even during suppressed refreshes
        if step >= 1 then
            labelText:SetText(label .. ": " .. string.format("%d", value))
        else
            labelText:SetText(label .. ": " .. string.format("%.2f", value))
        end
        if ns.suppressCallbacks then return end
        if onChange then onChange(self, value) end
    end)
    AttachTooltip(slider, tooltip)
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

function ns:CreateEditBox(parent, label, width, onChange, tooltip)
    local name = NextName("EB")
    local eb = CreateFrame("EditBox", name, parent, "InputBoxTemplate")
    eb:SetSize(width or 150, 20)
    eb:SetAutoFocus(false)

    local lbl = eb:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl:SetPoint("BOTTOMLEFT", eb, "TOPLEFT", 0, 3)
    lbl:SetText(label)

    -- `snapshot` records the text at the moment the field gained focus.
    -- Used to detect whether an edit actually changed the value, so Commit
    -- doesn't fire onChange redundantly for unchanged text (avoids churn
    -- on every focus loss).
    local snapshot

    local function Commit(self)
        local text = self:GetText()
        if snapshot == nil or text ~= snapshot then
            snapshot = text
            if onChange then onChange(self, text) end
        end
    end

    eb:HookScript("OnEditFocusGained", function(self)
        snapshot = self:GetText()
    end)
    eb:HookScript("OnEnterPressed", function(self)
        Commit(self)
        self:ClearFocus()    -- fires OnEditFocusLost below; snapshot now
                             -- equals current text so the second Commit no-ops
    end)
    eb:HookScript("OnEditFocusLost", function(self)
        -- Ignore focus loss triggered by Refresh's SetText-driven updates.
        if ns.suppressCallbacks then return end
        Commit(self)
    end)

    -- NOTE: OnEscapePressed intentionally NOT hooked. InputBoxTemplate's
    -- default handler fires `self:ClearFocus()`, which triggers our
    -- OnEditFocusLost → Commit. Net result: Escape commits whatever text
    -- is currently in the field, same as Enter and click-away. Consistent
    -- "any exit commits" UX.
    --
    -- Historical note: v1.5.x tried to make Escape revert via
    -- HookScript("OnEscapePressed", ...) that restored the snapshot before
    -- ClearFocus — but in WoW 3.3.5a, HookScript runs AFTER the template's
    -- default OnEscapePressed, so the template's ClearFocus fires
    -- OnEditFocusLost (committing the in-progress text) before the hook
    -- gets a chance to restore the snapshot. Making Escape revert properly
    -- would require SetScript-overriding the template default.

    AttachTooltip(eb, tooltip)

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
