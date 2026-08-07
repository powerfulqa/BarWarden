-- Core.lua - Lifecycle, ADDON_LOADED, slash commands, provenance.
-- Author:  Serv
-- Source:  https://github.com/powerfulqa/BarWarden
-- License: see LICENSE; attribution preservation is required.

local addonName, ns = ...

-- ============================================================================
-- Core.lua - Addon initialization, slash commands, global enable/disable
-- ============================================================================

-- Read version once from the TOC so it is defined in a single place.
-- Stamped by the release workflow alongside the TOC, and verified against the
-- tag before packaging. The TOC stays the packaging source of truth, but
-- GetAddOnMetadata reads the client's addon index, which WoW only rebuilds when
-- the game is launched - so after dropping in a new build and /reload-ing, it
-- reports the PREVIOUS version until a full restart. A Lua constant is re-read
-- on every /reload, so what the addon reports is right straight away. The TOC
-- lookup stays as the fallback for an unstamped working copy.
local ADDON_VERSION = "2.2.3"

ns.version = (ADDON_VERSION ~= "" and ADDON_VERSION)
             or GetAddOnMetadata(addonName, "Version")
             or "unknown"

-- ============================================================================
-- Provenance: stamp author + source URL into globals so /run introspection
-- and addon-management tools can identify the origin of any forked or
-- repackaged copy. The double-underscore-prefix-with-addon-name form follows
-- a convention shared with EbonClearance for cross-addon consistency.
-- ns.author / ns.url are exposed as the single source of truth for any
-- in-addon UI (the options panel byline, bug reports, etc).
-- ============================================================================
ns.author = "Serv"
ns.url    = "https://github.com/powerfulqa/BarWarden"
_G["BARWARDEN_IDENT"]      = "BarWarden"
_G["BARWARDEN_AUTHOR"]     = ns.author
_G["BARWARDEN_ORIGIN"]     = ns.url
_G["__BarWarden_origin"]   = ns.url
_G["__BarWarden_author"]   = ns.author

-- Build watermark: precomputed fingerprint of "BarWarden@<version>". Exposed
-- as a global so /run inspection and external auditors can read it. If this
-- exact 6-char hex value (computed for our version) ever appears in another
-- addon's source, that addon is a verbatim copy of BarWarden.
if ns.Fingerprint then
    _G["__BarWarden_watermark"] = ns:Fingerprint("BarWarden@" .. ns.version)
end

local coreFrame = CreateFrame("Frame", "BarWardenCoreFrame", UIParent)

-- Periodic scan: reliable fallback for cooldowns already active on login/reload
-- or when game events are missed (e.g. returning from AFK, zoning).
-- Runs for the whole session; the body bails cheaply when there is nothing to
-- scan. (An earlier comment claimed it hid itself when no bars were configured
-- - it never did, so the coreFrame:Show() calls elsewhere are belt-and-braces.)
local SCAN_INTERVAL = 0.25
local scanTimer = 0
coreFrame:SetScript("OnUpdate", function(self, elapsed)
    if not ns.db or not ns.db.global.enabled then return end
    scanTimer = scanTimer + elapsed
    if scanTimer >= SCAN_INTERVAL then
        scanTimer = 0
        -- Activity tracker: detect cooldown expiry (lightweight, only tracked CDs)
        ns:CheckCooldownExpiry()
        -- Bar engine scan (skip if no bars configured)
        local bars = ns.allBars
        if bars and #bars > 0 and ns.ScanAllBars then
            ns:ScanAllBars()
        end
    end
end)

function ns:Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage(ns.COLORS.prefix .. "BarWarden:|r " .. tostring(msg))
end

-- Re-apply visual config to every bar and relayout every group.
--
-- Also applies per-bar `conditions.hideWhenInactive` on the spot: the bar
-- engine only consults that flag during active→inactive state transitions,
-- so without re-applying it here a user toggle wouldn't take effect on a
-- bar that's currently sitting inactive+visible (or inactive+hidden) until
-- its state churned. RefreshAllBars is called from every user-driven
-- settings change, so this is the right place to honour the current flag.
function ns:RefreshAllBars()
    for _, group in pairs(ns.groupFrames or {}) do
        if group.bars then
            for _, bar in ipairs(group.bars) do
                if ns.ApplyVisualConfig then
                    ns:ApplyVisualConfig(bar)
                end
                local visual = ns:GetVisual()
                if not ns:IsBarEnabled(bar) then
                    -- Switched off in the editor: never draw it, and do not let
                    -- it hold a layout slot.
                    bar:Hide()
                elseif bar.barState == ns.BAR_STATE.ACTIVE then
                    bar:SetAlpha(visual.activeAlpha or 1.0)
                    bar:Show()
                else
                    if ns:ResolveHideWhenInactive(bar) and not ns:IsBarGlowing(bar) then
                        bar:Hide()
                    else
                        bar:Show()
                        bar:SetAlpha(visual.inactiveAlpha or 0.3)
                    end
                end
            end
        end
        if ns.UpdateGroupLayout then
            ns:UpdateGroupLayout(group)
        end
    end
end

function ns:ApplySettings()
    -- Profile load/reset can replace BarWardenDB.visual wholesale, so drop
    -- the cached reference before any refresh reads it.
    ns:InvalidateVisualCache()
    ns:RefreshAllBars()
    -- Restart the scan timer in case it idled due to an empty bar cache
    coreFrame:Show()
    if ns.UpdateMinimapButtonVisibility then
        ns:UpdateMinimapButtonVisibility()
    end
end

-- Unified refresh used by every per-bar editor callback so the UI stays
-- uniformly reactive: re-applies visual config (including hideWhenInactive),
-- then forces a tracker-data scan so condition changes (combat-only, in-raid,
-- health-below, require-buff, etc.) take effect without waiting for the
-- next scan tick.
function ns:RefreshBarSettings()
    -- Guard the cross-file call the same way this function's other callers
    -- already do (see RebuildAllFrames above), rather than assuming
    -- BarEngine.lua is present.
    if ns.InvalidateTrackedNames then ns:InvalidateTrackedNames() end
    ns:RefreshAllBars()
    ns:ScanAllBars()
end

-- ----------------------------------------------------------------------------
-- Lifecycle (Ace3-style: Initialize once, Enable/Disable any number of times).
-- ----------------------------------------------------------------------------

-- Called once at ADDON_LOADED. Sets up the DB, options panel, frames, and
-- minimap. Does NOT register gameplay events; that is OnEnable's job.
function ns:OnInitialize()
    -- Activity tracker session data (in-memory, resets each login/reload)
    ns.activitySession = {}
    ns.sessionStartTime = time()

    ns:InitDB()
    ns:CreateOptionsPanel()
    ns:RebuildAllFrames()
    ns:RefreshAllBars()
    ns:InitMinimapButton()
    -- All files have loaded by now: make sure every popup we trigger is lifted
    -- above the options window (catches late definitions such as Comms's).
    if ns.EnsurePopupsTopmost then ns:EnsurePopupsTopmost() end

    -- Profile load/reset fires "OnProfileChanged"; subscribe the standard
    -- post-change work so call sites can fire-and-forget.
    ns:RegisterCallback("OnProfileChanged", function()
        -- A profile Load/Reset swaps BarWardenDB.visual to a new table; GetVisual
        -- caches a reference to the old one, so drop the cache before rebuilding
        -- or bars render with the previous profile's look until /reload.
        if ns.InvalidateVisualCache then ns:InvalidateVisualCache() end
        ns:RebuildAllFrames()
        ns:ApplySettings()
    end)
end

-- Called whenever the addon should become active: at ADDON_LOADED if
-- globally enabled, on PLAYER_LOGIN, and from /bw enable. Idempotent.
function ns:OnEnable()
    ns:EnableEvents()
    -- Re-show the scan timer (it hides itself when no bars exist)
    coreFrame:Show()
    ns:StartActivityTracking()
    for _, frame in pairs(ns.groupFrames or {}) do
        if frame and frame.Show then frame:Show() end
    end
    -- Version-probe the guild shortly after enabling (delayed so the guild
    -- roster has loaded). Gated + throttled inside Comms.
    if ns.Comms and ns.After then
        ns:After(5, function() ns.Comms.FireVersionProbe("GUILD") end)
    end
end

-- Called whenever the addon should go quiet: from /bw disable and
-- PLAYER_LOGOUT. Idempotent.
function ns:OnDisable()
    ns:StopActivityTracking()
    ns:DisableEvents()
    for _, frame in pairs(ns.groupFrames or {}) do
        if frame and frame.Hide then frame:Hide() end
    end
end

local function OnAddonLoaded(event, loadedName)
    if loadedName ~= addonName then return end

    ns:OnInitialize()
    if ns.db and ns.db.global.enabled then
        ns:OnEnable()
    end

    coreFrame:UnregisterEvent("ADDON_LOADED")
end

-- Auto-prompt: if the character still has the default sample layout and a
-- class starter preset exists, offer to load it. Fires once per character
-- at PLAYER_LOGIN (UI is fully loaded, safe for StaticPopup). The
-- starterPrompted flag persists in SavedVariables so the user is never
-- asked twice even if they decline.
local function CheckFirstLoginStarter()
    if not ns.db or ns.db.starterPrompted then return end
    if not ns.ClassPresets then return end

    local className, classToken = UnitClass("player")
    if not classToken or not ns.ClassPresets[classToken] then return end

    -- Never auto-prompt over an existing layout. Counting bars (not just
    -- groups) means an upgrader with even one configured bar is left alone,
    -- so the starter load can never wipe their bars (the v1 data-loss bug).
    -- Mark them prompted so this never re-evaluates.
    local frames = ns.db.frames
    if ns:HasExistingLayout(frames) then
        ns.db.starterPrompted = true
        return
    end

    ns.db.starterPrompted = true
    local summary, _, _, label
    if ns.GetClassPresetSummary then
        summary, _, _, label = ns:GetClassPresetSummary(classToken)
    end
    summary = summary or ""
    label = label or className or classToken
    -- The layout is empty here, so append == load; use the non-destructive
    -- append path anyway as belt-and-suspenders against any guard edge case.
    StaticPopup_Show("BARWARDEN_WELCOME_STARTER", label, summary, {
        onAccept = function()
            if ns.AppendClassStarter then
                ns:AppendClassStarter(classToken)
            elseif ns.LoadClassStarter then
                ns:LoadClassStarter(classToken)
            end
        end,
    })
end

-- Parallel BarWarden V2 build: if a separate v1 install is loaded and this
-- build's own layout is still empty, offer to import the v1 layout once. In
-- the normal single-addon release ns:GetV1Layout returns nil, so this no-ops.
local function CheckV1Import()
    if not ns.db or ns.db.v1ImportPrompted then return false end
    if not ns.GetV1Layout or ns:HasExistingLayout(ns.db.frames) then return false end
    local layout = ns:GetV1Layout()
    if not layout then return false end
    ns.db.v1ImportPrompted = true
    local bars = 0
    for _, f in ipairs(layout.frames) do bars = bars + #(f.bars or {}) end
    StaticPopup_Show("BARWARDEN_IMPORT_V1", bars, nil, {
        onAccept = function()
            local n = ns:ImportFromV1()
            if n then
                if ns.RebuildAllFrames then ns:RebuildAllFrames() end
                ns:Print(string.format("Imported %d bars from your other BarWarden.", n))
            end
        end,
    })
    return true
end

local function OnPlayerLogin()
    if ns.db and ns.db.global.enabled then
        ns:OnEnable()
    end
    -- Offer a v1 import first (parallel build); otherwise the starter prompt.
    if not CheckV1Import() then
        CheckFirstLoginStarter()
    end
end

local function OnPlayerLogout()
    ns:OnDisable()
end

coreFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        OnAddonLoaded(event, ...)
    elseif event == "PLAYER_LOGIN" then
        OnPlayerLogin()
    elseif event == "PLAYER_LOGOUT" then
        OnPlayerLogout()
    end
end)

coreFrame:RegisterEvent("ADDON_LOADED")
coreFrame:RegisterEvent("PLAYER_LOGIN")
coreFrame:RegisterEvent("PLAYER_LOGOUT")

function ns:SetEnabled(enabled)
    if ns.db then
        ns.db.global.enabled = enabled
    end

    if ns.UpdateMinimapButtonState then
        ns:UpdateMinimapButtonState()
    end

    if enabled then
        -- RebuildAllFrames bails while disabled, so logging in disabled leaves
        -- no group frames at all. Rebuild here rather than in each caller: the
        -- slash command used to skip it and re-enabling showed nothing until a
        -- /reload.
        ns:RebuildAllFrames()
        ns:OnEnable()
    else
        ns:OnDisable()
    end
end

-- /bw and /barwarden: dispatch table replaces the long if/elseif chain.
local SLASH_COMMANDS = {}

SLASH_COMMANDS.help = function()
    ns:Print("BarWarden v" .. ns.version .. " commands:")
    local lines = {
        "  /bw             Open configuration panel",
        "  /bw enable      Enable the addon",
        "  /bw disable     Disable the addon",
        "  /bw lock        Toggle frame lock",
        "  /bw reset       Reset all frame positions",
        "  /bw debug       Dump addon state to chat",
        "  /bw scan        Live-test spell/item lookups for all bars",
        "  /bw trackers    Show live tracker state for all bars",
        "  /bw stats       Show bar activation and uptime statistics",
        "  /bw bugreport   Open copyable diagnostic report",
        "  /bw test        Toggle test mode (fake 30s timers)",
        "  /bw restore     Put back your previous layout",
        "  /bw importv1    Import bars from a separate BarWarden install",
        "  /bw commtest    Check version messaging with other players",
        "  /bw help        Show this message",
    }
    for _, line in ipairs(lines) do
        DEFAULT_CHAT_FRAME:AddMessage(line, 1, 1, 1)
    end
end

SLASH_COMMANDS.debug = function()
    DEFAULT_CHAT_FRAME:AddMessage("|cff7fbfffBarWarden Debug:|r")
    DEFAULT_CHAT_FRAME:AddMessage("  DB loaded: " .. tostring(ns.db ~= nil))
    DEFAULT_CHAT_FRAME:AddMessage("  Enabled: " .. tostring(ns.db and ns.db.global.enabled))
    DEFAULT_CHAT_FRAME:AddMessage("  Locked: " .. tostring(ns.db and ns.db.global.locked))
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
end

SLASH_COMMANDS.scan = function()
    DEFAULT_CHAT_FRAME:AddMessage("|cff7fbfffBarWarden Scan:|r")
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
end

SLASH_COMMANDS.trackers = function()
    DEFAULT_CHAT_FRAME:AddMessage("|cff7fbfffBarWarden Trackers:|r")
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
end

SLASH_COMMANDS.bugreport = function()
    if ns.ShowBugReport then
        ns:ShowBugReport()
    else
        ns:Print("Bug report module not loaded.")
    end
end

SLASH_COMMANDS.commtest = function()
    if ns.Comms and ns.Comms.RunSelfTest then
        ns.Comms.RunSelfTest()
    else
        ns:Print("Comms module not loaded.")
    end
end

SLASH_COMMANDS.restore = function()
    if ns.RestoreLastBackup and ns:RestoreLastBackup() then
        if ns.RebuildAllFrames then ns:RebuildAllFrames() end
        ns:Print("Restored your previous layout from the last backup.")
    else
        ns:Print("No layout backup found to restore.")
    end
end

SLASH_COMMANDS.importv1 = function()
    local n = ns.ImportFromV1 and ns:ImportFromV1()
    if n then
        if ns.RebuildAllFrames then ns:RebuildAllFrames() end
        ns:Print(string.format("Imported %d bars from your other BarWarden.", n))
    else
        ns:Print("No separate BarWarden layout was found to import.")
    end
end

SLASH_COMMANDS.stats = function()
    DEFAULT_CHAT_FRAME:AddMessage("|cff7fbfffBarWarden Activity:|r")
    local sessionDuration = time() - (ns.sessionStartTime or time())
    DEFAULT_CHAT_FRAME:AddMessage(string.format("  Session duration: %dm %ds",
        math.floor(sessionDuration / 60), sessionDuration % 60))
    local hasStats = false
    local allKeys = ns.GetAllActivityKeys and ns:GetAllActivityKeys() or {}
    for key in pairs(allKeys) do
        hasStats = true
        local name, _, category = ns:GetActivityMeta(key)
        local session = ns.activitySession and ns.activitySession[key]
        local persistent = ns.db and ns.db.activity and ns.db.activity[key]
        local sAct = session and session.activations or 0
        local sUp  = session and session.uptime or 0
        local pAct = persistent and persistent.activations or 0
        local pUp  = persistent and persistent.uptime or 0
        DEFAULT_CHAT_FRAME:AddMessage(string.format(
            "  [%s] %s: %d / %.0fs (session) | %d / %.0fs (all-time)",
            category or "?", name or key, sAct, sUp, pAct, pUp))
    end
    if not hasStats then
        DEFAULT_CHAT_FRAME:AddMessage("  No activity recorded yet. Cast some spells!")
    end
end

SLASH_COMMANDS.enable = function()
    ns:SetEnabled(true)
    ns:Print("Addon enabled.")
end

SLASH_COMMANDS.disable = function()
    ns:SetEnabled(false)
    ns:Print("Addon disabled.")
end

SLASH_COMMANDS.lock = function()
    if ns.db and ns.db.global.locked then
        ns.db.global.locked = false
        ns:UnlockAllFrames()
        ns:Print("Frames unlocked.")
    else
        if ns.db then ns.db.global.locked = true end
        ns:LockAllFrames()
        ns:Print("Frames locked.")
    end
end

SLASH_COMMANDS.reset = function()
    -- Actually move the groups. Rebuilding alone re-applied each saved
    -- position verbatim, so the documented recovery action for a group dragged
    -- off-screen did nothing. Cascade them back to a visible spot; a backup is
    -- taken first so the old positions are recoverable with /bw restore.
    local frames = BarWardenDB and BarWardenDB.frames
    if frames and #frames > 0 then
        ns:BackupFrames("reset positions")
        for i, f in ipairs(frames) do
            local step = (i - 1) * 20
            f.position = {
                point = "TOPLEFT", relativePoint = "BOTTOMLEFT",
                x = 100 + step, y = 400 - step,
            }
        end
    end
    ns:RebuildAllFrames()
    ns:Print("Frame positions reset.")
end

SLASH_COMMANDS.test = function()
    if ns.testMode then
        ns:DeactivateTestMode()
    else
        ns:ActivateTestMode()
    end
end

local function SlashHandler(msg)
    local cmd = strtrim(msg):lower()
    local handler = SLASH_COMMANDS[cmd]
    if handler then
        handler()
    else
        -- Open the config panel via the shared opener (the category name lives
        -- in one place in Options.lua; the double-call quirk is handled there).
        if ns.OpenOptions then ns:OpenOptions() end
    end
end

SLASH_BARWARDEN1 = "/bw"
SLASH_BARWARDEN2 = "/barwarden"
SlashCmdList["BARWARDEN"] = SlashHandler
