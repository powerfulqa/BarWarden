-- Dialogs.lua - StaticPopup dialog definitions.
-- Author:  Serv
-- Source:  https://github.com/powerfulqa/BarWarden
-- License: see LICENSE; attribution preservation is required.

local addonName, ns = ...

-- All BarWarden dialogs use preferredIndex = 4 (STATICPOPUP_NUMDIALOGS)
-- to occupy the highest popup slot and minimise taint propagation to
-- Blizzard's protected StaticPopup code.  OnHide handlers that modify
-- Blizzard frames are avoided entirely; they extend the taint chain
-- and can block protected functions like CancelLogout().

-- Confirm Delete (group or bar)
StaticPopupDialogs["BARWARDEN_CONFIRM_DELETE"] = {
    text = "Are you sure you want to delete \"%s\"?",
    button1 = "Yes",
    button2 = "No",
    OnAccept = function(self)
        if self.data and self.data.onAccept then
            self.data.onAccept()
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 4,
}

-- Rename (groups/profiles)
StaticPopupDialogs["BARWARDEN_RENAME"] = {
    text = "Enter new name:",
    button1 = "OK",
    button2 = "Cancel",
    hasEditBox = true,
    editBoxWidth = 200,
    OnShow = function(self)
        if self.data and self.data.currentName then
            self.editBox:SetText(self.data.currentName)
            self.editBox:HighlightText()
        end
        self.editBox:SetFocus()
    end,
    OnAccept = function(self)
        local text = self.editBox:GetText()
        if text and text ~= "" and self.data and self.data.onAccept then
            self.data.onAccept(text)
        end
    end,
    EditBoxOnEnterPressed = function(self)
        local parent = self:GetParent()
        local text = parent.editBox:GetText()
        if text and text ~= "" and parent.data and parent.data.onAccept then
            parent.data.onAccept(text)
        end
        parent:Hide()
    end,
    EditBoxOnEscapePressed = function(self)
        self:GetParent():Hide()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 4,
}

-- Import (text input for pasting export strings)
StaticPopupDialogs["BARWARDEN_IMPORT"] = {
    text = "Paste import string below:",
    button1 = "Import",
    button2 = "Cancel",
    hasEditBox = true,
    editBoxWidth = 300,
    OnShow = function(self)
        self.editBox:SetText("")
        self.editBox:SetFocus()
        self.editBox:SetMaxLetters(0)
    end,
    OnAccept = function(self)
        local text = self.editBox:GetText()
        if text and text ~= "" and self.data and self.data.onAccept then
            self.data.onAccept(text)
        end
    end,
    EditBoxOnEscapePressed = function(self)
        self:GetParent():Hide()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 4,
}

-- Export (read-only text display with select-all)
StaticPopupDialogs["BARWARDEN_EXPORT"] = {
    text = "Copy the export string below (Ctrl+A to select all):",
    button1 = "Close",
    hasEditBox = true,
    editBoxWidth = 300,
    OnShow = function(self)
        if self.data and self.data.exportString then
            self.editBox:SetText(self.data.exportString)
        end
        self.editBox:SetMaxLetters(0)
        self.editBox:HighlightText()
        self.editBox:SetFocus()
    end,
    EditBoxOnEscapePressed = function(self)
        self:GetParent():Hide()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 4,
}

-- Confirm Reset all statistics
StaticPopupDialogs["BARWARDEN_CONFIRM_STATS_RESET"] = {
    text = "Are you sure you want to reset all statistics? This cannot be undone.",
    button1 = "Yes",
    button2 = "No",
    OnAccept = function(self)
        if self.data and self.data.onAccept then
            self.data.onAccept()
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 4,
}

-- Confirm Reset to defaults
StaticPopupDialogs["BARWARDEN_CONFIRM_RESET"] = {
    text = "Are you sure you want to reset all settings to defaults? This cannot be undone.",
    button1 = "Yes",
    button2 = "No",
    OnAccept = function(self)
        if self.data and self.data.onAccept then
            self.data.onAccept()
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 4,
}

-- Welcome starter: first-login prompt for brand-new characters with no bars.
-- Friendly tone, no mention of replacing anything.
StaticPopupDialogs["BARWARDEN_WELCOME_STARTER"] = {
    text = "Welcome to BarWarden!\n\nWould you like to load a %s starter profile?\n\n%s\n\nYou can customise these bars or start fresh from the Bars / Groups tab at any time.",
    button1 = "Yes, load it",
    button2 = "No thanks",
    OnAccept = function(self)
        if self.data and self.data.onAccept then
            self.data.onAccept()
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 4,
}

-- First-login prompt for the parallel BarWarden V2 build: a v1 install was
-- detected, offer to import its layout. %d is the bar count found in v1.
StaticPopupDialogs["BARWARDEN_IMPORT_V1"] = {
    text = "Found your existing BarWarden layout (%d bars).\n\nImport it into this version? Your other BarWarden is not changed, and your current layout here is backed up first.",
    button1 = "Import it",
    button2 = "No thanks",
    OnAccept = function(self)
        if self.data and self.data.onAccept then
            self.data.onAccept()
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 4,
}

-- Confirm Load Class Starter (replaces current groups/bars with a preset).
-- Used from the Profiles tab when the player already has bars configured.
-- First %s is the class name, second %s is the preset summary.
StaticPopupDialogs["BARWARDEN_CONFIRM_STARTER"] = {
    text = "Load the %s starter profile?\n\n%s\n\nThis will REPLACE your current groups and bars on this character. Save a profile first if you want to keep them.",
    button1 = "Load",
    button2 = "Cancel",
    OnAccept = function(self)
        if self.data and self.data.onAccept then
            self.data.onAccept()
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 4,
}

-- Confirm Append Class Starter (appends preset groups onto current layout).
-- Same %s format as above.
StaticPopupDialogs["BARWARDEN_CONFIRM_STARTER_APPEND"] = {
    text = "Add the %s starter profile to your current layout?\n\n%s\n\nThis ADDS new groups; your existing bars are preserved.",
    button1 = "Add",
    button2 = "Cancel",
    OnAccept = function(self)
        if self.data and self.data.onAccept then
            self.data.onAccept()
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 4,
}

-- A confirmation/entry popup shown from a settings panel can appear BEHIND the
-- Interface Options window (press a button and the dialog is hidden under the
-- menu). Every BarWarden popup, while shown, is lifted to sit above the options
-- window: match its frame strata and raise the frame level well past it (so it
-- wins even if BlizzMove or the client bumped the options window's strata). The
-- shared popup frame's strata/level are restored on hide so other addons'
-- popups are unaffected. The "^BARWARDEN" match covers the V2-test rename too.
function ns:EnsurePopupsTopmost()
    for key, dialog in pairs(StaticPopupDialogs) do
        if type(key) == "string" and key:find("^BARWARDEN") and not dialog._bwTopmost then
            dialog._bwTopmost = true
            local prevShow, prevHide = dialog.OnShow, dialog.OnHide
            dialog.OnShow = function(self, ...)
                self._bwStrata = self:GetFrameStrata()
                self._bwLevel = self:GetFrameLevel()
                local io = InterfaceOptionsFrame
                if io and io:IsShown() then
                    self:SetFrameStrata(io:GetFrameStrata())
                    self:SetFrameLevel(io:GetFrameLevel() + 50)
                else
                    self:SetFrameStrata("FULLSCREEN_DIALOG")
                end
                self:SetToplevel(true)
                if prevShow then return prevShow(self, ...) end
            end
            dialog.OnHide = function(self, ...)
                if self._bwStrata then self:SetFrameStrata(self._bwStrata); self._bwStrata = nil end
                if self._bwLevel then self:SetFrameLevel(self._bwLevel); self._bwLevel = nil end
                if prevHide then return prevHide(self, ...) end
            end
        end
    end
end

-- Cover the dialogs defined here immediately; Core re-runs it after every file
-- has loaded so late definitions (e.g. Comms) are caught too.
ns:EnsurePopupsTopmost()

-- Lift a shared Blizzard frame (e.g. ColorPickerFrame) above the Interface
-- Options window while it is shown, restoring its original strata/level on hide.
-- Same technique as the popups: match the options window's strata and sit well
-- above it by level, so it wins even if BlizzMove bumped the options window. The
-- OnHide restore is hooked once so the shared frame is unaffected elsewhere.
function ns:RaiseFrameAboveOptions(frame)
    if not frame then return end
    if not frame._bwRaiseHooked then
        frame._bwRaiseHooked = true
        frame:HookScript("OnHide", function(self)
            if self._bwOrigStrata then self:SetFrameStrata(self._bwOrigStrata); self._bwOrigStrata = nil end
            if self._bwOrigLevel then self:SetFrameLevel(self._bwOrigLevel); self._bwOrigLevel = nil end
        end)
    end
    if not frame._bwOrigStrata then
        frame._bwOrigStrata = frame:GetFrameStrata()
        frame._bwOrigLevel = frame:GetFrameLevel()
    end
    local io = InterfaceOptionsFrame
    if io and io:IsShown() then
        frame:SetFrameStrata(io:GetFrameStrata())
        frame:SetFrameLevel(io:GetFrameLevel() + 50)
    else
        frame:SetFrameStrata("FULLSCREEN_DIALOG")
    end
    if frame.SetToplevel then frame:SetToplevel(true) end
end
