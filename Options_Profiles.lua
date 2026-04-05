local addonName, ns = ...

-- ============================================================================
-- Options_Profiles.lua - Tab 4: Profiles
-- ============================================================================

local PROFILE_ROW_HEIGHT = 20
local MAX_PROFILE_ROWS = 5
local selectedProfileName = nil

-- ============================================================================
-- Helper: get sorted profile names
-- ============================================================================
local function GetSortedProfileNames()
    local names = {}
    if ns.db and ns.db.profiles then
        for name in pairs(ns.db.profiles) do
            names[#names + 1] = name
        end
    end
    table.sort(names)
    return names
end

-- ============================================================================
-- Helper: format timestamp
-- ============================================================================
local function FormatTimestamp(ts)
    if not ts or ts == 0 then return "Never" end
    return date("%Y-%m-%d %H:%M", ts)
end

-- ============================================================================
-- Main Tab Creation
-- ============================================================================

local function CreateProfilesTab(parent)
    local frame = CreateFrame("Frame", "BarWardenProfilesTab", parent)
    frame:SetAllPoints(parent)
    frame:Hide()

    -- Title
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -80)
    title:SetText("Profiles")

    local desc = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    desc:SetText("Save and load configuration profiles. Export/import to share between characters.")

    -- ========================================================================
    -- Profile List (FauxScrollFrame)
    -- ========================================================================
    local listFrame = CreateFrame("Frame", "BarWardenProfileList", frame)
    listFrame:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -12)
    listFrame:SetSize(400, MAX_PROFILE_ROWS * PROFILE_ROW_HEIGHT + 4)

    local listBg = listFrame:CreateTexture(nil, "BACKGROUND")
    listBg:SetAllPoints()
    listBg:SetTexture(0, 0, 0, 0.3)

    local scrollFrame = CreateFrame("ScrollFrame", "BarWardenProfileScrollFrame", listFrame, "FauxScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 2, -2)
    scrollFrame:SetPoint("BOTTOMRIGHT", -22, 2)

    local rows = {}
    for i = 1, MAX_PROFILE_ROWS do
        local row = CreateFrame("Button", "BarWardenProfileRow" .. i, listFrame)
        row:SetSize(374, PROFILE_ROW_HEIGHT)
        if i == 1 then
            row:SetPoint("TOPLEFT", listFrame, "TOPLEFT", 2, -2)
        else
            row:SetPoint("TOPLEFT", rows[i - 1], "BOTTOMLEFT", 0, 0)
        end

        local highlight = row:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetTexture(1, 1, 1, 0.1)

        local selected = row:CreateTexture(nil, "BACKGROUND")
        selected:SetAllPoints()
        selected:SetTexture(0.2, 0.4, 0.8, 0.3)
        selected:Hide()
        row.selectedTex = selected

        local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        nameText:SetPoint("LEFT", row, "LEFT", 4, 0)
        nameText:SetWidth(180)
        nameText:SetJustifyH("LEFT")
        row.nameText = nameText

        local descText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        descText:SetPoint("LEFT", nameText, "RIGHT", 8, 0)
        descText:SetWidth(100)
        descText:SetJustifyH("LEFT")
        row.descText = descText

        local timeText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        timeText:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        timeText:SetJustifyH("RIGHT")
        row.timeText = timeText

        row:SetScript("OnClick", function(self)
            selectedProfileName = self.profileName
            frame:RefreshList()
        end)

        rows[i] = row
    end

    -- ========================================================================
    -- Refresh profile list
    -- ========================================================================
    function frame:RefreshList()
        local names = GetSortedProfileNames()
        local offset = FauxScrollFrame_GetOffset(scrollFrame)
        FauxScrollFrame_Update(scrollFrame, #names, MAX_PROFILE_ROWS, PROFILE_ROW_HEIGHT)

        for i = 1, MAX_PROFILE_ROWS do
            local row = rows[i]
            local index = i + offset
            if index <= #names then
                local name = names[index]
                local profile = ns.db.profiles[name]
                row.profileName = name
                row.nameText:SetText(name)
                row.descText:SetText(profile.description or "")
                row.timeText:SetText(FormatTimestamp(profile.lastModified))
                if name == selectedProfileName then
                    row.selectedTex:Show()
                else
                    row.selectedTex:Hide()
                end
                row:Show()
            else
                row.profileName = nil
                row:Hide()
            end
        end

        -- Update active profile indicator
        if ns.db.activeProfile then
            frame.activeLabel:SetText("Active: " .. ns.db.activeProfile)
        else
            frame.activeLabel:SetText("Active: (none)")
        end
    end

    scrollFrame:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, PROFILE_ROW_HEIGHT, function() frame:RefreshList() end)
    end)

    -- Active profile label
    local activeLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    activeLabel:SetPoint("TOPLEFT", listFrame, "BOTTOMLEFT", 0, -8)
    activeLabel:SetText("Active: (none)")
    frame.activeLabel = activeLabel

    -- ========================================================================
    -- Buttons
    -- ========================================================================
    local btnAnchor = listFrame

    local createBtn = ns:CreateButton(frame, "Create", 80, function()
        StaticPopup_Show("BARWARDEN_RENAME", nil, nil, {
            currentName = "New Profile",
            onAccept = function(text)
                if not ns.db.profiles[text] then
                    ns.db.profiles[text] = {
                        description = "",
                        lastModified = time(),
                        data = {
                            frames = ns:CopyTable(ns.db.frames),
                            visual = ns:CopyTable(ns.db.visual),
                        },
                    }
                    selectedProfileName = text
                    frame:RefreshList()
                end
            end,
        })
    end)
    createBtn:SetPoint("TOPLEFT", activeLabel, "BOTTOMLEFT", 0, -8)

    local deleteBtn = ns:CreateButton(frame, "Delete", 80, function()
        if not selectedProfileName then return end
        local name = selectedProfileName
        StaticPopup_Show("BARWARDEN_CONFIRM_DELETE", name, nil, {
            onAccept = function()
                ns.db.profiles[name] = nil
                if ns.db.activeProfile == name then
                    ns.db.activeProfile = nil
                end
                selectedProfileName = nil
                frame:RefreshList()
            end,
        })
    end)
    deleteBtn:SetPoint("LEFT", createBtn, "RIGHT", 4, 0)

    local duplicateBtn = ns:CreateButton(frame, "Duplicate", 80, function()
        if not selectedProfileName or not ns.db.profiles[selectedProfileName] then return end
        local src = ns.db.profiles[selectedProfileName]
        local newName = selectedProfileName .. " (Copy)"
        local i = 2
        while ns.db.profiles[newName] do
            newName = selectedProfileName .. " (Copy " .. i .. ")"
            i = i + 1
        end
        ns.db.profiles[newName] = {
            description = src.description or "",
            lastModified = time(),
            data = ns:CopyTable(src.data),
        }
        selectedProfileName = newName
        frame:RefreshList()
    end)
    duplicateBtn:SetPoint("LEFT", deleteBtn, "RIGHT", 4, 0)

    local renameBtn = ns:CreateButton(frame, "Rename", 80, function()
        if not selectedProfileName then return end
        local oldName = selectedProfileName
        StaticPopup_Show("BARWARDEN_RENAME", nil, nil, {
            currentName = oldName,
            onAccept = function(newName)
                if newName ~= oldName and not ns.db.profiles[newName] then
                    ns.db.profiles[newName] = ns.db.profiles[oldName]
                    ns.db.profiles[oldName] = nil
                    if ns.db.activeProfile == oldName then
                        ns.db.activeProfile = newName
                    end
                    selectedProfileName = newName
                    frame:RefreshList()
                end
            end,
        })
    end)
    renameBtn:SetPoint("LEFT", duplicateBtn, "RIGHT", 4, 0)

    -- Second row of buttons
    local loadBtn = ns:CreateButton(frame, "Load", 80, function()
        if not selectedProfileName or not ns.db.profiles[selectedProfileName] then return end
        local profile = ns.db.profiles[selectedProfileName]
        if profile.data then
            if profile.data.frames then
                ns.db.frames = ns:CopyTable(profile.data.frames)
            end
            if profile.data.visual then
                ns.db.visual = ns:CopyTable(profile.data.visual)
            end
            ns.db.activeProfile = selectedProfileName
            if ns.ApplySettings then
                ns:ApplySettings()
            end
            if ns.RebuildAllFrames then
                ns:RebuildAllFrames()
            end
            frame:RefreshList()
        end
    end)
    loadBtn:SetPoint("TOPLEFT", createBtn, "BOTTOMLEFT", 0, -4)

    local saveBtn = ns:CreateButton(frame, "Save", 80, function()
        if not selectedProfileName or not ns.db.profiles[selectedProfileName] then return end
        local profile = ns.db.profiles[selectedProfileName]
        profile.data = {
            frames = ns:CopyTable(ns.db.frames),
            visual = ns:CopyTable(ns.db.visual),
        }
        profile.lastModified = time()
        frame:RefreshList()
    end)
    saveBtn:SetPoint("LEFT", loadBtn, "RIGHT", 4, 0)

    local exportBtn = ns:CreateButton(frame, "Export", 80, function()
        if not selectedProfileName or not ns.db.profiles[selectedProfileName] then return end
        local profile = ns.db.profiles[selectedProfileName]
        local serialized = ns:Serialize(profile.data or {})
        local encoded = ns.Base64Encode(serialized)
        local exportString = "BarWarden:v1:" .. encoded
        StaticPopup_Show("BARWARDEN_EXPORT", nil, nil, {
            exportString = exportString,
        })
    end)
    exportBtn:SetPoint("LEFT", saveBtn, "RIGHT", 4, 0)

    local importBtn = ns:CreateButton(frame, "Import", 80, function()
        StaticPopup_Show("BARWARDEN_IMPORT", nil, nil, {
            onAccept = function(text)
                if not text or text == "" then return end
                -- Validate prefix
                local prefix = "BarWarden:v1:"
                if text:sub(1, #prefix) ~= prefix then
                    ns:Print("Invalid import string: missing BarWarden:v1: prefix.")
                    return
                end
                -- Decode
                local encoded = text:sub(#prefix + 1)
                local decoded = ns.Base64Decode(encoded)
                if not decoded or decoded == "" then
                    ns:Print("Invalid import string: failed to decode.")
                    return
                end
                -- Deserialize
                local success, data = pcall(function() return ns:Deserialize(decoded) end)
                if not success or type(data) ~= "table" then
                    ns:Print("Invalid import string: failed to deserialize.")
                    return
                end
                -- Validate schema: must have frames and/or visual tables
                if type(data.frames) ~= "table" and type(data.visual) ~= "table" then
                    ns:Print("Invalid import string: missing frames/visual data.")
                    return
                end
                -- Create a new profile from the imported data
                local newName = "Imported"
                local i = 2
                while ns.db.profiles[newName] do
                    newName = "Imported " .. i
                    i = i + 1
                end
                ns.db.profiles[newName] = {
                    description = "Imported profile",
                    lastModified = time(),
                    data = data,
                }
                selectedProfileName = newName
                frame:RefreshList()
                ns:Print("Profile imported as \"" .. newName .. "\".")
            end,
        })
    end)
    importBtn:SetPoint("LEFT", exportBtn, "RIGHT", 4, 0)

    -- ========================================================================
    -- Reset to Defaults button
    -- ========================================================================
    local resetBtn = ns:CreateButton(frame, "Reset to Defaults", 140, function()
        StaticPopup_Show("BARWARDEN_CONFIRM_RESET", nil, nil, {
            onAccept = function()
                ns.db.frames = ns:CopyTable(ns.DEFAULTS.frames)
                ns.db.visual = ns:CopyTable(ns.DEFAULTS.visual)
                ns.db.profiles = {}
                ns.db.activeProfile = nil
                selectedProfileName = nil
                if ns.ApplySettings then
                    ns:ApplySettings()
                end
                if ns.RebuildAllFrames then
                    ns:RebuildAllFrames()
                end
                frame:RefreshList()
            end,
        })
    end)
    resetBtn:SetPoint("TOPLEFT", loadBtn, "BOTTOMLEFT", 0, -12)

    -- Initial refresh when shown
    frame:SetScript("OnShow", function(self)
        self:RefreshList()
    end)

    return frame
end

-- ============================================================================
-- Register tab when options panel is created
-- ============================================================================
local orig = ns.CreateOptionsPanel
ns.CreateOptionsPanel = function(self)
    local panel = orig(self)
    local tab = CreateProfilesTab(panel)
    ns.optionsTabs[4] = tab
    tab:Show()
    return panel
end
