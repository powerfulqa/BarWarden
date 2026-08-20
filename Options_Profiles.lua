-- Options_Profiles.lua - Profiles tab (save / load / import / export).
-- Author:  Serv
-- Source:  https://github.com/powerfulqa/BarWarden
-- License: GNU GPL v3 (see LICENSE); attribution preservation is required.

local addonName, ns = ...

-- ============================================================================
-- Options_Profiles.lua - Tab 4: Profiles
-- ============================================================================

local PROFILE_ROW_HEIGHT = 20
local MAX_PROFILE_ROWS = 6
local selectedProfileName = nil

local function RequireSelectedProfile()
    if not selectedProfileName or not ns.profiles[selectedProfileName] then
        ns:Print("Select a profile first.")
        return nil
    end
    return selectedProfileName
end

-- ============================================================================
-- Helper: get sorted profile names
-- ============================================================================
local function GetSortedProfileNames()
    local names = {}
    if ns.db and ns.profiles then
        for name in pairs(ns.profiles) do
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
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -16)
    title:SetText("Profiles")

    local desc = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    desc:SetJustifyH("LEFT")
    if desc.SetWordWrap then desc:SetWordWrap(true) end
    if ns.ApplyWidth then ns:ApplyWidth(desc, 32) end
    desc:SetText("Save and Load bar layouts. Profiles are account-wide.")

    -- ========================================================================
    -- Profile List (FauxScrollFrame)
    -- ========================================================================
    -- Fixed width matching the button grid below (4 columns x 80 px + gaps, out
    -- to the Rename/Import buttons). The list box does NOT scale with the window
    -- - it stays the same width as the buttons beneath it.
    local PROFILE_LIST_WIDTH = 332
    local listFrame = CreateFrame("Frame", "BarWardenProfileList", frame)
    listFrame:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -12)
    listFrame:SetWidth(PROFILE_LIST_WIDTH)
    listFrame:SetHeight(MAX_PROFILE_ROWS * PROFILE_ROW_HEIGHT + 4)

    local listBg = listFrame:CreateTexture(nil, "BACKGROUND")
    listBg:SetAllPoints()
    listBg:SetTexture(0, 0, 0, 0.3)

    local scrollFrame = CreateFrame("ScrollFrame", "BarWardenProfileScrollFrame", listFrame, "FauxScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 2, -2)
    scrollFrame:SetPoint("BOTTOMRIGHT", -22, 2)

    local rows = {}
    for i = 1, MAX_PROFILE_ROWS do
        -- Rows stretch to the list width (TOPLEFT + TOPRIGHT), so the row grows
        -- with the window instead of being pinned at a fixed 374 px.
        local row = CreateFrame("Button", "BarWardenProfileRow" .. i, listFrame)
        row:SetHeight(PROFILE_ROW_HEIGHT)
        if i == 1 then
            row:SetPoint("TOPLEFT",  listFrame, "TOPLEFT",   2, -2)
            row:SetPoint("TOPRIGHT", listFrame, "TOPRIGHT", -22, -2)
        else
            row:SetPoint("TOPLEFT",  rows[i - 1], "BOTTOMLEFT",  0, 0)
            row:SetPoint("TOPRIGHT", rows[i - 1], "BOTTOMRIGHT", 0, 0)
        end

        local highlight = row:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetTexture(1, 1, 1, 0.1)

        local selected = row:CreateTexture(nil, "BACKGROUND")
        selected:SetAllPoints()
        selected:SetTexture(0.2, 0.4, 0.8, 0.3)
        selected:Hide()
        row.selectedTex = selected

        -- Name auto-sizes to its text (no fixed width) so the description gets
        -- whatever room is left before the date, avoiding the old clipping.
        local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        nameText:SetPoint("LEFT", row, "LEFT", 6, 0)
        nameText:SetJustifyH("LEFT")
        row.nameText = nameText

        -- Time is right-anchored with a fixed width; the description fills the
        -- gap between the name and the time (bounded on both sides) so the two
        -- can never overlap, whatever the window width.
        local timeText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        timeText:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        timeText:SetWidth(110)
        timeText:SetJustifyH("RIGHT")
        row.timeText = timeText

        local descText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        descText:SetPoint("LEFT",  nameText, "RIGHT",  8, 0)
        descText:SetPoint("RIGHT", timeText, "LEFT",  -8, 0)
        descText:SetJustifyH("LEFT")
        descText:SetWordWrap(false)
        row.descText = descText

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
                local profile = ns.profiles[name]
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

    local createBtn = ns:CreateButton(frame, "Create", 80, function()
        StaticPopup_Show("BARWARDEN_RENAME", nil, nil, {
            currentName = "New Profile",
            onAccept = function(text)
                if not ns.profiles[text] then
                    ns.profiles[text] = {
                        description = "",
                        lastModified = time(),
                        data = ns:CaptureProfileData(),
                    }
                    selectedProfileName = text
                    frame:RefreshList()
                end
            end,
        })
    end)
    createBtn:SetPoint("TOPLEFT", activeLabel, "BOTTOMLEFT", 0, -8)

    local deleteBtn = ns:CreateButton(frame, "Delete", 80, function()
        local name = RequireSelectedProfile()
        if not name then return end
        StaticPopup_Show("BARWARDEN_CONFIRM_DELETE", name, nil, {
            onAccept = function()
                ns.profiles[name] = nil
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
        if not RequireSelectedProfile() then return end
        local src = ns.profiles[selectedProfileName]
        local newName = selectedProfileName .. " (Copy)"
        local i = 2
        while ns.profiles[newName] do
            newName = selectedProfileName .. " (Copy " .. i .. ")"
            i = i + 1
        end
        ns.profiles[newName] = {
            description = src.description or "",
            lastModified = time(),
            data = ns:CopyTable(src.data),
        }
        selectedProfileName = newName
        frame:RefreshList()
    end)
    duplicateBtn:SetPoint("LEFT", deleteBtn, "RIGHT", 4, 0)

    local renameBtn = ns:CreateButton(frame, "Rename", 80, function()
        if not RequireSelectedProfile() then return end
        local oldName = selectedProfileName
        StaticPopup_Show("BARWARDEN_RENAME", nil, nil, {
            currentName = oldName,
            onAccept = function(newName)
                if newName ~= oldName and not ns.profiles[newName] then
                    ns.profiles[newName] = ns.profiles[oldName]
                    ns.profiles[oldName] = nil
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
        local name = RequireSelectedProfile()
        if not name then return end
        -- Confirm first: Load replaces the whole live layout, exactly as
        -- destructive as Delete or the starter buttons, and was the one
        -- replace on this tab a single click on the wrong row could fire.
        -- The name is captured at click time, not re-read at accept time:
        -- the popup is not modal, so clicking another row behind it must
        -- not switch the target (the wrong-row class fixed in v2.1.1).
        StaticPopup_Show("BARWARDEN_CONFIRM_LOAD_PROFILE", name, nil, {
            onAccept = function()
                local profile = ns.profiles[name]
                if not (profile and profile.data) then return end
                -- Back up first: loading a profile replaces the current layout.
                if ns.BackupFrames then ns:BackupFrames("load profile") end
                -- Per-section migration and default-backfill live in
                -- ns:ApplyProfileData (DB.lua) so save, load, and import cannot
                -- disagree about what a profile contains - which is exactly how
                -- unit frames came to be missing from every exported profile.
                ns:ApplyProfileData(profile.data)
                ns.db.activeProfile = name
                ns:FireCallback("OnProfileChanged", name)
                frame:RefreshList()
            end,
        })
    end)
    loadBtn:SetPoint("TOPLEFT", createBtn, "BOTTOMLEFT", 0, -4)

    local saveBtn = ns:CreateButton(frame, "Save", 80, function()
        if not RequireSelectedProfile() then return end
        local profile = ns.profiles[selectedProfileName]
        profile.data = ns:CaptureProfileData()
        profile.lastModified = time()
        frame:RefreshList()
    end)
    saveBtn:SetPoint("LEFT", loadBtn, "RIGHT", 4, 0)

    local exportBtn = ns:CreateButton(frame, "Export", 80, function()
        if not RequireSelectedProfile() then return end
        local profile = ns.profiles[selectedProfileName]
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
                -- Must carry at least one section we recognise. Asked of
                -- ns:ProfileDataHasContent rather than naming frames/visual
                -- here, so a profile carrying only unit frames is accepted
                -- instead of being rejected as empty.
                if not ns:ProfileDataHasContent(data) then
                    ns:Print("Invalid import string: no settings found in it.")
                    return
                end
                -- Canonicalise imported frames now (they may predate the current
                -- schema), so the stored profile is clean and tracks on load.
                if type(data.frames) == "table" and ns.MigrateFrames then
                    ns:MigrateFrames(data.frames)
                end
                -- Create a new profile from the imported data
                local newName = "Imported"
                local i = 2
                while ns.profiles[newName] do
                    newName = "Imported " .. i
                    i = i + 1
                end
                ns.profiles[newName] = {
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
    local resetBtn = ns:CreateButton(frame, "Reset to Defaults", 164, function()
        StaticPopup_Show("BARWARDEN_CONFIRM_RESET", nil, nil, {
            onAccept = function()
                -- Snapshot the current layout first so `/bw restore` can undo a
                -- reset (matches Load / Import / starter, which all back up).
                if ns.BackupFrames then ns:BackupFrames("reset") end
                ns.db.frames = ns:CopyTable(ns.DEFAULTS.frames)
                ns.db.visual = ns:CopyTable(ns.DEFAULTS.visual)
                -- Deliberately DO NOT wipe ns.profiles: this resets the live
                -- layout to defaults, it is not a "delete my saved profiles"
                -- action, and profiles are not in the backup ring so wiping them
                -- would be irrecoverable.
                ns.db.activeProfile = nil
                selectedProfileName = nil
                -- GetVisual caches a reference to the old visual table; the line
                -- above replaced the pointer, so drop the cache or bars keep the
                -- pre-reset look until /reload.
                if ns.InvalidateVisualCache then ns:InvalidateVisualCache() end
                ns:FireCallback("OnProfileChanged", nil)
                frame:RefreshList()
            end,
        })
    end)
    resetBtn:SetPoint("TOPLEFT", loadBtn, "BOTTOMLEFT", 0, -12)

    -- ========================================================================
    -- Class Starter buttons: Load (replace) + Add (append). Both consult
    -- ClassPresets.lua and show a confirm dialog with a preset summary.
    -- ========================================================================
    local starterBtn = ns:CreateButton(frame, "Load Class Starter", 164, function()
        local _, classToken = UnitClass("player")
        if not classToken or not (ns.ClassPresets and ns.ClassPresets[classToken]) then
            ns:Print("No starter profile available for your class.")
            return
        end
        local summary, _, _, label = ns:GetClassPresetSummary(classToken)
        summary = summary or ""
        label = label or UnitClass("player") or classToken
        StaticPopup_Show("BARWARDEN_CONFIRM_STARTER", label, summary, {
            onAccept = function()
                if ns.LoadClassStarter then
                    ns:LoadClassStarter(classToken)
                    selectedProfileName = nil
                    frame:RefreshList()
                end
            end,
        })
    end)
    starterBtn:SetPoint("LEFT", resetBtn, "RIGHT", 4, 0)

    local appendBtn = ns:CreateButton(frame, "Add Class Starter", 164, function()
        local _, classToken = UnitClass("player")
        if not classToken or not (ns.ClassPresets and ns.ClassPresets[classToken]) then
            ns:Print("No starter profile available for your class.")
            return
        end
        local summary, _, _, label = ns:GetClassPresetSummary(classToken)
        summary = summary or ""
        label = label or UnitClass("player") or classToken
        StaticPopup_Show("BARWARDEN_CONFIRM_STARTER_APPEND", label, summary, {
            onAccept = function()
                if ns.AppendClassStarter then
                    ns:AppendClassStarter(classToken)
                    selectedProfileName = nil
                    frame:RefreshList()
                end
            end,
        })
    end)
    -- Align under Load Starter (right half of the button grid).
    appendBtn:SetPoint("TOPLEFT", starterBtn, "BOTTOMLEFT", 0, -4)

    ns:CreateHelpIcon(frame, starterBtn, "LEFT", "RIGHT", 6, 0, "class-starters")

    -- Initial refresh when shown
    frame:SetScript("OnShow", function(self)
        self:RefreshList()
    end)

    return frame
end

ns:RegisterOptionsTab(4, CreateProfilesTab)
