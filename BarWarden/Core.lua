local addonName, ns = ...

-- ============================================================================
-- Core.lua - Addon initialization, slash commands, global enable/disable
-- ============================================================================

local coreFrame = CreateFrame("Frame", "BarWardenCoreFrame", UIParent)

-- ----------------------------------------------------------------------------
-- Print: Chat message helper
-- ----------------------------------------------------------------------------

function ns:Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ccffBarWarden:|r " .. tostring(msg))
end

-- ----------------------------------------------------------------------------
-- RefreshAllBars: Re-apply visual config to all existing bars and relayout
-- ----------------------------------------------------------------------------

function ns:RefreshAllBars()
    for _, group in pairs(ns.groupFrames or {}) do
        if group.bars then
            for _, bar in ipairs(group.bars) do
                if ns.ApplyVisualConfig then
                    ns:ApplyVisualConfig(bar)
                end
            end
        end
        if ns.UpdateGroupLayout then
            ns:UpdateGroupLayout(group)
        end
    end
end

-- ----------------------------------------------------------------------------
-- ApplySettings: Apply current DB settings to live frames
-- ----------------------------------------------------------------------------

function ns:ApplySettings()
    ns:RefreshAllBars()
    if ns.UpdateMinimapButtonVisibility then
        ns:UpdateMinimapButtonVisibility()
    end
end

-- ----------------------------------------------------------------------------
-- ADDON_LOADED: Initialize DB, options, frames, minimap, events
-- ----------------------------------------------------------------------------

local function OnAddonLoaded(event, loadedName)
    if loadedName ~= addonName then return end

    ns:InitDB()
    ns:CreateOptionsPanel()
    ns:RebuildAllFrames()
    ns:InitMinimapButton()

    -- Register gameplay events if addon is enabled
    if ns.db and ns.db.global.enabled then
        ns:EnableEvents()
    end

    coreFrame:UnregisterEvent("ADDON_LOADED")
end

-- ----------------------------------------------------------------------------
-- PLAYER_LOGIN: Final setup after all addons loaded
-- ----------------------------------------------------------------------------

local function OnPlayerLogin(event)
    if ns.db and ns.db.global.enabled then
        ns:EnableEvents()
    end
end

-- ----------------------------------------------------------------------------
-- PLAYER_LOGOUT: Cleanup before disconnect
-- ----------------------------------------------------------------------------

local function OnPlayerLogout(event)
    ns:DisableEvents()
end

-- ----------------------------------------------------------------------------
-- Event Registration
-- ----------------------------------------------------------------------------

coreFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        OnAddonLoaded(event, ...)
    elseif event == "PLAYER_LOGIN" then
        OnPlayerLogin(event)
    elseif event == "PLAYER_LOGOUT" then
        OnPlayerLogout(event)
    end
end)

coreFrame:RegisterEvent("ADDON_LOADED")
coreFrame:RegisterEvent("PLAYER_LOGIN")
coreFrame:RegisterEvent("PLAYER_LOGOUT")

-- ----------------------------------------------------------------------------
-- Global Enable / Disable
-- ----------------------------------------------------------------------------

function ns:SetEnabled(enabled)
    if ns.db then
        ns.db.global.enabled = enabled
    end

    if enabled then
        ns:EnableEvents()
        -- Show all group frames
        for _, frame in pairs(ns.groupFrames or {}) do
            if frame and frame.Show then
                frame:Show()
            end
        end
    else
        ns:DisableEvents()
        -- Hide all group frames
        for _, frame in pairs(ns.groupFrames or {}) do
            if frame and frame.Hide then
                frame:Hide()
            end
        end
    end
end

-- ----------------------------------------------------------------------------
-- Slash Commands: /bw and /barwarden
-- ----------------------------------------------------------------------------

local function SlashHandler(msg)
    local cmd = strtrim(msg):lower()

    if cmd == "help" then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ccffBarWarden|r commands:")
        DEFAULT_CHAT_FRAME:AddMessage("  /bw - Open configuration panel")
        DEFAULT_CHAT_FRAME:AddMessage("  /bw help - Show this help")
        DEFAULT_CHAT_FRAME:AddMessage("  /bw debug - Dump addon state")
        DEFAULT_CHAT_FRAME:AddMessage("  /bw enable - Enable the addon")
        DEFAULT_CHAT_FRAME:AddMessage("  /bw disable - Disable the addon")
    elseif cmd == "debug" then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ccffBarWarden Debug:|r")
        DEFAULT_CHAT_FRAME:AddMessage("  Enabled: " .. tostring(ns.db and ns.db.global.enabled))
        DEFAULT_CHAT_FRAME:AddMessage("  Frames: " .. tostring(ns.groupFrames and #ns.groupFrames or 0))
        DEFAULT_CHAT_FRAME:AddMessage("  DB loaded: " .. tostring(ns.db ~= nil))
    elseif cmd == "enable" then
        ns:SetEnabled(true)
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ccffBarWarden|r enabled.")
    elseif cmd == "disable" then
        ns:SetEnabled(false)
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ccffBarWarden|r disabled.")
    else
        -- No args or unknown: open config panel
        -- Call twice to work around Blizzard bug (Edge Case #10)
        InterfaceOptionsFrame_OpenToCategory("BarWarden")
        InterfaceOptionsFrame_OpenToCategory("BarWarden")
    end
end

SLASH_BARWARDEN1 = "/bw"
SLASH_BARWARDEN2 = "/barwarden"
SlashCmdList["BARWARDEN"] = SlashHandler
