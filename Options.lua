-- Options.lua - Interface Options shell: one category per panel.
-- Author:  Serv
-- Source:  https://github.com/powerfulqa/BarWarden
-- License: GNU GPL v3 (see LICENSE); attribution preservation is required.
--
-- v2 navigation: instead of one cramped window with hand-rolled tab buttons,
-- BarWarden registers a parent "BarWarden" category plus one child category
-- per section (Bar Control, Visuals, Profiles, Activity, Help), nested via
-- Blizzard's `.parent` field. The General settings (and the runnable slash
-- list) are folded onto the parent overview page rather than a category of
-- their own. Each section gets a full panel with room to breathe, and the
-- native Interface Options tree does the navigation.
--
-- Existing panel builders keep working unchanged: each still calls
-- ns:RegisterOptionsTab(index, builderFn) and returns a content frame; here we
-- give that builder its own child category instead of a tab. Per-panel reactive
-- reflow comes from PanelInfra (the builders wrap their content on OnShow).

local addonName, ns = ...

-- Single source of truth for the parent category label. The v2-test deploy
-- script rewrites this one line to "BarWarden V2" so a parallel install shows
-- as its own separate tree without touching the live addon.
local PARENT_NAME = "BarWarden"
ns.PARENT_NAME = PARENT_NAME

ns.optionsTabs = {}   -- index -> child category frame
ns.tabBuilders = {}   -- index -> builder fn, set by ns:RegisterOptionsTab

-- Section titles shown in the Interface Options tree, by registration index.
-- Index 1 (General) is intentionally absent: those settings live on the parent
-- overview page now, so no builder registers at index 1.
local TAB_NAMES = {
    [2] = "Bar Control",
    [3] = "Visuals",
    [4] = "Profiles",
    [5] = "Activity",
    [6] = "Help",
    [7] = "Frames",
}
ns.TAB_NAMES = TAB_NAMES  -- exposed so the Help "Back" button can name the origin

function ns:RegisterOptionsTab(index, builderFn)
    ns.tabBuilders[index] = builderFn
end

local function BuildParentPanel()
    local panel = CreateFrame("Frame", "BarWardenOptionsPanel", UIParent)
    panel.name = PARENT_NAME
    ns.optionsPanel = panel

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText(PARENT_NAME .. " v" .. (ns.version or "?"))

    -- Author + source byline (subdued olive), matching EbonClearance so the
    -- two addons read as one family. ns.author / ns.url are the single source
    -- of truth, stamped in Core.lua.
    local byline = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    byline:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    byline:SetText("|cff888866by " .. (ns.author or "?") .. "  \194\183  "
                .. (ns.url or "?") .. "|r")

    local sub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", byline, "BOTTOMLEFT", 0, -14)
    sub:SetJustifyH("LEFT")
    if sub.SetWordWrap then sub:SetWordWrap(true) end
    -- Explicit reactive width: a two-point (TOPLEFT+RIGHT) anchor does NOT give
    -- a FontString a reliable wrap width on 3.3.5a (it clips to one line).
    if ns.ApplyWidth then ns:ApplyWidth(sub, 32) end
    sub:SetText("Cooldown, buff, and debuff bar tracking. Set the addon-wide "
             .. "options below, then pick a section on the left to build bars, "
             .. "style them, or manage profiles.")

    -- General settings + the runnable slash list are folded onto this overview
    -- page (no separate "General" category). A scroll frame below the intro
    -- hosts them so the command list never clips, and reflows on resize.
    local scroll = CreateFrame("ScrollFrame", "BarWardenOverviewScrollFrame",
                               panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",     sub,   "BOTTOMLEFT",   0, -14)
    scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -28,  16)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetWidth(544)
    content:SetHeight(1)
    scroll:SetScrollChild(content)

    local refresh
    if ns.BuildGeneralInto then refresh = ns:BuildGeneralInto(content) end

    -- Fit: match the scroll child to the viewport width, re-wrap the slash
    -- labels, and trim the child height to the footer so the scrollbar engages
    -- only on overflow.
    local function fit()
        local w = scroll:GetWidth()
        if w and w > 100 then content:SetWidth(w) end
        if content._reflowSlashRows then content._reflowSlashRows(content:GetWidth()) end
        local footer = content._generalFooter
        local footBottom = footer and footer:GetBottom()
        local contentTop = content:GetTop()
        if footBottom and contentTop and contentTop > footBottom then
            content:SetHeight(contentTop - footBottom + 20)
        end
    end
    scroll:SetScript("OnSizeChanged", function() fit() end)

    panel.content = content
    panel.Refresh = refresh
    panel:SetScript("OnShow", function()
        fit()
        if refresh then refresh() end
    end)

    InterfaceOptions_AddCategory(panel)
    return panel
end

-- Called once from ns:OnInitialize. Builds the parent category, then one child
-- category per registered section builder (in index order).
function ns:CreateOptionsPanel()
    BuildParentPanel()

    local indices = {}
    for i in pairs(ns.tabBuilders) do indices[#indices + 1] = i end
    table.sort(indices)

    for _, index in ipairs(indices) do
        local builder = ns.tabBuilders[index]
        local child = CreateFrame("Frame", "BarWardenPanel" .. index, UIParent)
        child.name = TAB_NAMES[index] or ("Section " .. index)
        child.parent = PARENT_NAME
        -- The builder creates a content frame parented to `child` (SetAllPoints)
        -- and returns it; that becomes this category's body.
        local content = builder(child)
        if content then
            child.content = content
            if content.Show then content:Show() end
            -- Record which section is on screen whenever it is shown, so a [?]
            -- deep-link into Help can offer a "Back to <section>" button.
            local idx = index
            if content.HookScript then
                content:HookScript("OnShow", function()
                    ns.currentOptionsTab = idx
                    -- Showing any non-Help section clears a stored deep-link
                    -- origin, so the Back button never shows a stale target when
                    -- Help is next opened directly from the tree.
                    if TAB_NAMES[idx] ~= "Help" then ns.helpReturnTab = nil end
                end)
            end
        end
        ns.optionsTabs[index] = child
        InterfaceOptions_AddCategory(child)
    end
end

-- Open the addon's options. Double-call is the 3.3.5a quirk: the first call
-- only scrolls the category list, the second opens it. Everything that opens
-- the options routes here so the category name lives in one place.
function ns:OpenOptions()
    local target = ns.optionsPanel or PARENT_NAME
    -- EC-TRAP: the duplicated line is NOT a copy-paste bug. Do NOT dedupe it.
    -- See CLAUDE.md (Interface options panel).
    InterfaceOptionsFrame_OpenToCategory(target)
    InterfaceOptionsFrame_OpenToCategory(target)
end

-- Deep-link to a specific section (used by the Help [?] icons via index).
function ns:SelectOptionsTab(index)
    local child = ns.optionsTabs[index]
    if not child then return end
    InterfaceOptionsFrame_OpenToCategory(child)
    InterfaceOptionsFrame_OpenToCategory(child)
end

-- Panel action hooks used to live here as no-op stubs. They are gone: the real
-- ns:ApplySettings is in Core.lua (this file loads first, so the stub was
-- shadowing it only by luck of TOC order), Reset to Defaults is a self-contained
-- button in Options_Profiles.lua, and nothing ever called RevertSettings.

function ns:RefreshOptions()
    ns.suppressCallbacks = true
    if ns.optionsPanel and ns.optionsPanel.Refresh then ns.optionsPanel.Refresh() end
    for _, child in pairs(ns.optionsTabs) do
        local content = child and child.content
        if content and content.Refresh then content:Refresh() end
    end
    ns.suppressCallbacks = false
end
