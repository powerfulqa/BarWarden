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
        ns:Print("BarWarden v1.0.0 commands:")
        DEFAULT_CHAT_FRAME:AddMessage("  /bw             Open configuration panel", 1, 1, 1)
        DEFAULT_CHAT_FRAME:AddMessage("  /bw enable      Enable the addon", 1, 1, 1)
        DEFAULT_CHAT_FRAME:AddMessage("  /bw disable     Disable the addon", 1, 1, 1)
        DEFAULT_CHAT_FRAME:AddMessage("  /bw lock        Toggle frame lock", 1, 1, 1)
        DEFAULT_CHAT_FRAME:AddMessage("  /bw show        Toggle frame visibility", 1, 1, 1)
        DEFAULT_CHAT_FRAME:AddMessage("  /bw reset       Reset all frame positions", 1, 1, 1)
        DEFAULT_CHAT_FRAME:AddMessage("  /bw debug       Dump addon state to chat", 1, 1, 1)
        DEFAULT_CHAT_FRAME:AddMessage("  /bw help        Show this message", 1, 1, 1)
    elseif cmd == "debug" then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ccffBarWarden Debug:|r")
        DEFAULT_CHAT_FRAME:AddMessage("  DB loaded: " .. tostring(ns.db ~= nil))
        DEFAULT_CHAT_FRAME:AddMessage("  Enabled: " .. tostring(ns.db and ns.db.global.enabled))
        DEFAULT_CHAT_FRAME:AddMessage("  ShowAll: " .. tostring(ns.db and ns.db.global.showAll))
        DEFAULT_CHAT_FRAME:AddMessage("  Bars in cache: " .. tostring(#(ns.allBars or {})))
        local gCount = 0
        for _ in pairs(ns.groupFrames or {}) do gCount = gCount + 1 end
        DEFAULT_CHAT_FRAME:AddMessage("  Group frames: " .. gCount)
        -- Show first few bar configs to diagnose spell name issues
        for i, bar in ipairs(ns.allBars or {}) do
            if i > 3 then break end
            local bd = bar.barData
            if bd then
                DEFAULT_CHAT_FRAME:AddMessage(string.format("  Bar %d: mode=%s spell=%s enabled=%s",
                    i, tostring(bd.trackMode), tostring(bd.spellName or bd.spell or bd.spellId or "nil"), tostring(bd.enabled)))
            end
        end
    elseif cmd == "enable" then
        ns:SetEnabled(true)
        ns:Print("Addon enabled.")
    elseif cmd == "disable" then
        ns:SetEnabled(false)
        ns:Print("Addon disabled.")
    elseif cmd == "lock" then
        if ns.db and ns.db.global.locked then
            ns:UnlockAllFrames()
            ns:Print("Frames unlocked.")
        else
            ns:LockAllFrames()
            ns:Print("Frames locked.")
        end
    elseif cmd == "show" then
        if ns.db and ns.db.global.showAll then
            ns:HideAllFrames()
            ns:Print("Frames hidden.")
        else
            ns:ShowAllFrames()
            ns:Print("Frames shown.")
        end
    elseif cmd == "reset" then
        ns:RebuildAllFrames()
        ns:Print("Frame positions reset.")
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
