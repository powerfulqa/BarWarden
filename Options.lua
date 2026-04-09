local addonName, ns = ...

-- Tab content frames (populated by Options_General, Options_Bars, Options_Visuals, Options_Profiles)
ns.optionsTabs = {}

local TAB_NAMES = {"General", "Bars / Groups", "Visuals", "Profiles", "Statistics"}

local function ShowTab(index)
    for i, frame in pairs(ns.optionsTabs) do
        if frame then
            if i == index then
                frame:Show()
            else
                frame:Hide()
            end
        end
    end
end

function ns:CreateOptionsPanel()
    local panel = CreateFrame("Frame", "BarWardenOptionsPanel", UIParent)
    panel.name = "BarWarden"
    ns.optionsPanel = panel

    -- Title
    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("BarWarden")

    local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    subtitle:SetText("Cooldown, buff, and debuff bar tracking")

    -- Create tab buttons
    local tabs = {}
    for i, tabName in ipairs(TAB_NAMES) do
        local tab = CreateFrame("Button", panel:GetName() .. "Tab" .. i, panel, "CharacterFrameTabButtonTemplate")
        tab:SetText(tabName)
        tab:SetID(i)
        tab:SetScript("OnClick", function(self)
            PanelTemplates_SetTab(panel, self:GetID())
            ShowTab(self:GetID())
            PlaySound("igCharacterInfoTab")
        end)
        if i == 1 then
            tab:SetPoint("TOPLEFT", panel, "BOTTOMLEFT", 5, 2)
        else
            tab:SetPoint("LEFT", tabs[i - 1], "RIGHT", -14, 0)
        end
        tabs[i] = tab
    end
    PanelTemplates_SetNumTabs(panel, #TAB_NAMES)
    panel.tabs = tabs
    PanelTemplates_SetTab(panel, 1)

    -- Panel callbacks
    panel.okay = function()
        if ns.db then
            ns:ApplySettings()
        end
    end

    panel.cancel = function()
        if ns.db then
            ns:RevertSettings()
        end
    end

    panel.default = function()
        if ns.db then
            ns:ResetToDefaults()
        end
    end

    panel.refresh = function()
        if ns.db then
            ns:RefreshOptions()
        end
    end

    InterfaceOptions_AddCategory(panel)
    return panel
end

-- Open options panel (call twice to work around Blizzard bug)
function ns:OpenOptions()
    InterfaceOptionsFrame_OpenToCategory("BarWarden")
    InterfaceOptionsFrame_OpenToCategory("BarWarden")
end

-- Placeholder callbacks for panel actions (overridden by specific tab modules)
function ns:ApplySettings()
end

function ns:RevertSettings()
end

function ns:ResetToDefaults()
end

function ns:RefreshOptions()
    ShowTab(1)
    if ns.optionsPanel then
        PanelTemplates_SetTab(ns.optionsPanel, 1)
    end
    -- Suppress widget callbacks while restoring UI state so that
    -- programmatic SetValue / SetChecked calls don't write back to DB
    -- and overwrite per-group settings with global defaults.
    ns.suppressCallbacks = true
    for _, tab in pairs(ns.optionsTabs) do
        if tab and tab.Refresh then
            tab:Refresh()
        end
    end
    ns.suppressCallbacks = false
end
