local addonName, ns = ...

-- ============================================================================
-- Core.lua - Addon initialization, slash commands, global enable/disable
-- ============================================================================

-- Read version once from the TOC so it is defined in a single place.
ns.version = GetAddOnMetadata(addonName, "Version") or "unknown"

local coreFrame = CreateFrame("Frame", "BarWardenCoreFrame", UIParent)

-- Periodic scan: reliable fallback for cooldowns already active on login/reload
-- or when game events are missed (e.g. returning from AFK, zoning).
local SCAN_INTERVAL = 0.25
local scanTimer = 0
coreFrame:SetScript("OnUpdate", function(self, elapsed)
    if not ns.db or not ns.db.global.enabled then return end
    scanTimer = scanTimer + elapsed
    if scanTimer >= SCAN_INTERVAL then
        scanTimer = 0
        if ns.ScanAllBars then
            ns:ScanAllBars()
        end
    end
end)

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
                local visual = BarWardenDB and BarWardenDB.visual or ns.DEFAULTS.visual
                if bar.barState == ns.BAR_STATE.ACTIVE then
                    bar:SetAlpha(visual.activeAlpha or 1.0)
                else
                    bar:SetAlpha(visual.inactiveAlpha or 0.3)
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

    -- Initialize session statistics (resets every login/reload)
    ns.sessionStats = {}
    ns.sessionStartTime = time()

    ns:InitDB()
    ns:CreateOptionsPanel()
    ns:RebuildAllFrames()
    ns:RefreshAllBars()
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

    if ns.UpdateMinimapButtonState then
        ns:UpdateMinimapButtonState()
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
        ns:Print("BarWarden v" .. ns.version .. " commands:")
        DEFAULT_CHAT_FRAME:AddMessage("  /bw             Open configuration panel", 1, 1, 1)
        DEFAULT_CHAT_FRAME:AddMessage("  /bw enable      Enable the addon", 1, 1, 1)
        DEFAULT_CHAT_FRAME:AddMessage("  /bw disable     Disable the addon", 1, 1, 1)
        DEFAULT_CHAT_FRAME:AddMessage("  /bw lock        Toggle frame lock", 1, 1, 1)
        DEFAULT_CHAT_FRAME:AddMessage("  /bw reset       Reset all frame positions", 1, 1, 1)
        DEFAULT_CHAT_FRAME:AddMessage("  /bw debug       Dump addon state to chat", 1, 1, 1)
        DEFAULT_CHAT_FRAME:AddMessage("  /bw scan        Live-test spell/item lookups for all bars", 1, 1, 1)
        DEFAULT_CHAT_FRAME:AddMessage("  /bw trackers    Show live tracker state for all bars", 1, 1, 1)
        DEFAULT_CHAT_FRAME:AddMessage("  /bw stats       Show bar activation and uptime statistics", 1, 1, 1)
        DEFAULT_CHAT_FRAME:AddMessage("  /bw bugreport   Open copyable diagnostic report", 1, 1, 1)
        DEFAULT_CHAT_FRAME:AddMessage("  /bw test        Toggle test mode (fake 30s timers)", 1, 1, 1)
        DEFAULT_CHAT_FRAME:AddMessage("  /bw help        Show this message", 1, 1, 1)
    elseif cmd == "debug" then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ccffBarWarden Debug:|r")
        DEFAULT_CHAT_FRAME:AddMessage("  DB loaded: " .. tostring(ns.db ~= nil))
        DEFAULT_CHAT_FRAME:AddMessage("  Enabled: " .. tostring(ns.db and ns.db.global.enabled))
        DEFAULT_CHAT_FRAME:AddMessage("  ShowAll: " .. tostring(ns.db and ns.db.global.showAll))
        DEFAULT_CHAT_FRAME:AddMessage("  Schema version: " .. tostring(ns.db and ns.db.schemaVersion or "nil"))
        DEFAULT_CHAT_FRAME:AddMessage("  Bars in cache: " .. tostring(#(ns.allBars or {})))
        local gCount = 0
        for _ in pairs(ns.groupFrames or {}) do gCount = gCount + 1 end
        DEFAULT_CHAT_FRAME:AddMessage("  Group frames: " .. gCount)
        for i, bar in ipairs(ns.allBars or {}) do
            local bd = bar.barData
            if bd then
                DEFAULT_CHAT_FRAME:AddMessage(string.format("  Bar %d: mode=%s spell=%s state=%s",
                    i, tostring(bd.trackMode), tostring(bd.spellName or bd.spellId or bd.itemId or "nil"),
                    tostring(bar.barState)))
            end
        end
    elseif cmd == "scan" then
        -- Live diagnostic: test GetSpellInfo and GetSpellCooldown for each bar
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ccffBarWarden Scan:|r")
        local bars = ns.allBars or {}
        if #bars == 0 then
            DEFAULT_CHAT_FRAME:AddMessage("  No bars in cache. Try /reload then /bw scan.")
            return
        end
        for i, bar in ipairs(bars) do
            local bd = bar.barData
            if not bd then
                DEFAULT_CHAT_FRAME:AddMessage(string.format("  Bar %d: no barData", i))
            else
                local spellInput = bd.spellId or bd.spellName or bd.spellInput or bd.spell
                local mode = bd.trackMode or "?"
                if mode == "Cooldown" then
                    local resolvedId = nil
                    local siName = nil
                    if spellInput then
                        siName, _, _, _, _, _, resolvedId = GetSpellInfo(spellInput)
                    end
                    -- Mirror ResolveSpell: treat id=0 as invalid, fall back to name string
                    local cdInput = (resolvedId and resolvedId ~= 0) and resolvedId or spellInput
                    local cdStart, cdDur, cdEnabled = nil, nil, nil
                    if cdInput then
                        cdStart, cdDur, cdEnabled = GetSpellCooldown(cdInput)
                    end
                    DEFAULT_CHAT_FRAME:AddMessage(string.format(
                        "  Bar %d [CD] input=%s siName=%s id=%s cdInput=%s | start=%.1f dur=%.1f en=%s",
                        i, tostring(spellInput), tostring(siName), tostring(resolvedId), tostring(cdInput),
                        cdStart or 0, cdDur or 0, tostring(cdEnabled)))
                elseif mode == "Item" then
                    local itemId = bd.itemId or spellInput
                    local cdStart, cdDur, cdEnabled = nil, nil, nil
                    if itemId then
                        cdStart, cdDur, cdEnabled = GetItemCooldown(itemId)
                    end
                    DEFAULT_CHAT_FRAME:AddMessage(string.format(
                        "  Bar %d [Item] id=%s | start=%.1f dur=%.1f en=%s",
                        i, tostring(itemId), cdStart or 0, cdDur or 0, tostring(cdEnabled)))
                else
                    DEFAULT_CHAT_FRAME:AddMessage(string.format(
                        "  Bar %d [%s] spell=%s", i, mode, tostring(spellInput)))
                end
            end
        end
    elseif cmd == "trackers" then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ccffBarWarden Trackers:|r")
        local bars = ns.allBars or {}
        if #bars == 0 then
            DEFAULT_CHAT_FRAME:AddMessage("  No bars in cache. Try /reload then /bw trackers.")
            return
        end
        for i, bar in ipairs(bars) do
            local bd = bar.barData
            if bd then
                local isActive, remaining, duration = ns:CheckTracker(bd)
                DEFAULT_CHAT_FRAME:AddMessage(string.format(
                    "  Bar %d [%s] %s | active=%s remaining=%.1f duration=%.1f",
                    i,
                    tostring(bd.trackMode or "?"),
                    tostring(bd.spellName or bd.spellId or bd.itemId or "?"),
                    tostring(isActive),
                    remaining or 0,
                    duration or 0))
            end
        end
    elseif cmd == "bugreport" then
        if ns.ShowBugReport then
            ns:ShowBugReport()
        else
            ns:Print("Bug report module not loaded.")
        end
    elseif cmd == "stats" then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ccffBarWarden Statistics:|r")
        local sessionDuration = time() - (ns.sessionStartTime or time())
        DEFAULT_CHAT_FRAME:AddMessage(string.format("  Session duration: %dm %ds",
            math.floor(sessionDuration / 60), sessionDuration % 60))
        local hasStats = false
        -- Merge keys from both session and persistent stats
        local allKeys = {}
        for key in pairs(ns.sessionStats or {}) do allKeys[key] = true end
        for key in pairs(ns.db and ns.db.stats or {}) do allKeys[key] = true end
        for key in pairs(allKeys) do
            hasStats = true
            local session = ns.sessionStats and ns.sessionStats[key] or { activations = 0, uptime = 0 }
            local allTime = ns.db and ns.db.stats and ns.db.stats[key] or { activations = 0, uptime = 0 }
            DEFAULT_CHAT_FRAME:AddMessage(string.format(
                "  %s: %d activations / %.0fs uptime (session) | %d / %.0fs (all-time)",
                key, session.activations, session.uptime, allTime.activations, allTime.uptime))
        end
        if not hasStats then
            DEFAULT_CHAT_FRAME:AddMessage("  No statistics recorded yet.")
        end
    elseif cmd == "enable" then
        ns:SetEnabled(true)
        ns:Print("Addon enabled.")
    elseif cmd == "disable" then
        ns:SetEnabled(false)
        ns:Print("Addon disabled.")
    elseif cmd == "lock" then
        if ns.db and ns.db.global.locked then
            ns.db.global.locked = false
            ns:UnlockAllFrames()
            ns:Print("Frames unlocked.")
        else
            if ns.db then ns.db.global.locked = true end
            ns:LockAllFrames()
            ns:Print("Frames locked.")
        end
    elseif cmd == "reset" then
        ns:RebuildAllFrames()
        ns:Print("Frame positions reset.")
    elseif cmd == "test" then
        if ns.testMode then
            ns:DeactivateTestMode()
        else
            ns:ActivateTestMode()
        end
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
