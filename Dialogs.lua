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
