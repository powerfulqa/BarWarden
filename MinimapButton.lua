-- MinimapButton.lua - Minimap button and drag positioning.
-- Author:  Serv
-- Source:  https://github.com/powerfulqa/BarWarden
-- License: see LICENSE; attribution preservation is required.

local addonName, ns = ...

-- ============================================================================
-- MinimapButton.lua - LibDataBroker launcher + LibDBIcon-managed minimap icon.
--
-- BarWarden exposes itself as a standard LDB launcher, so addon families like
-- Bazooka, Chocolate Bar, and SexyMap (which all consume LDB) can pick up the
-- button without any per-addon plumbing. LibDBIcon handles the minimap-side
-- display: creation, drag-to-reposition, show/hide, and the wrap-around edge
-- cases. BarWarden only supplies the data object + a small refresh helper.
-- ============================================================================

local LDB      = LibStub and LibStub("LibDataBroker-1.1", true)
local LibDBIcon = LibStub and LibStub("LibDBIcon-1.0", true)

-- The LDB object name doubles as the key LibDBIcon tracks registrations by.
-- Keep it stable across sessions; a rename would orphan the existing button.
local DATA_OBJECT_NAME = "BarWarden"
local ICON_ENABLED     = "Interface\\Icons\\Spell_Nature_EnchantArmor"

local dataObject    -- LDB data object (created lazily on InitMinimapButton)

-- --------------------------------------------------------------------------
-- LDB data-object callbacks.
--
-- Any LDB display (minimap button, Bazooka plugin, WeakAuras status panel)
-- receives these via the shared LDB registry; we don't have to know which
-- consumer is rendering us.
-- --------------------------------------------------------------------------

local function OnClick(_, button)
    if button == "RightButton" then
        local enabled = ns.db and ns.db.global and ns.db.global.enabled
        ns:SetEnabled(not enabled)
    else
        -- 3.3.5a double-call quirk: first call only scrolls the category list.
        InterfaceOptionsFrame_OpenToCategory("BarWarden")
        InterfaceOptionsFrame_OpenToCategory("BarWarden")
    end
end

local function OnTooltipShow(tt)
    if not tt or not tt.AddLine then return end
    local C = ns.COLORS
    local enabled = ns.db and ns.db.global and ns.db.global.enabled

    tt:AddLine("BarWarden")
    tt:AddLine(C.muted .. "v" .. (ns.version or "?") .. "|r")
    tt:AddLine("Status: " .. (enabled and (C.good .. "Enabled|r")
                                       or (C.bad .. "Disabled|r")))

    -- Live counts so the tooltip is a quick at-a-glance status, like EC's.
    local barCount = #(ns.allBars or {})
    local groupCount = 0
    for _ in pairs(ns.groupFrames or {}) do groupCount = groupCount + 1 end
    tt:AddLine(string.format("Tracking %s%d|r bars in %s%d|r groups",
        C.emphasis, barCount, C.emphasis, groupCount))

    tt:AddLine(" ")
    tt:AddLine("Left-click to open options", 0.8, 0.8, 0.8)
    tt:AddLine("Right-click to enable/disable", 0.8, 0.8, 0.8)
    tt:AddLine("Drag to reposition", 0.8, 0.8, 0.8)
end

-- --------------------------------------------------------------------------
-- Public API
-- --------------------------------------------------------------------------

function ns:InitMinimapButton()
    -- Libraries are bundled in Libs/, so absence means a broken install.
    -- Fail quietly rather than erroring so the rest of the addon still loads.
    -- EC-TRAP: this early-return is graceful degradation, not a dead guard. Do NOT
    -- remove it or hard-require the libs. See CLAUDE.md (libs are intentional).
    if not LDB or not LibDBIcon then return end
    if dataObject then return end

    dataObject = LDB:NewDataObject(DATA_OBJECT_NAME, {
        type          = "launcher",
        text          = "BarWarden",
        icon          = ICON_ENABLED,
        OnClick       = OnClick,
        OnTooltipShow = OnTooltipShow,
    })

    -- Ensure the db sub-table exists even if the migration path didn't run
    -- (e.g. a dev wipe of BarWardenDB between test reloads).
    ns.db.minimap = ns.db.minimap or { hide = false, minimapPos = 220 }

    LibDBIcon:Register(DATA_OBJECT_NAME, dataObject, ns.db.minimap)
    ns:UpdateMinimapButtonState()
end

-- Toggle button visibility. Called from the "Show Minimap Icon" toggle in
-- Options_General.lua after it flips `ns.db.minimap.hide`.
function ns:UpdateMinimapButtonVisibility()
    if not LibDBIcon then return end
    if ns.db and ns.db.minimap and ns.db.minimap.hide then
        LibDBIcon:Hide(DATA_OBJECT_NAME)
    else
        LibDBIcon:Show(DATA_OBJECT_NAME)
    end
end

-- Desaturate the icon when the addon is globally disabled so users can see
-- the state at a glance. SetDesaturated can taint on some 3.3.5a builds;
-- fall back to a vertex-colour dim if it refuses.
function ns:UpdateMinimapButtonState()
    if not LibDBIcon then return end
    -- GetMinimapButton is only present on newer LibDBIcon revisions; the
    -- bundled copy exposes the `objects` table instead. Prefer the method
    -- where available, fall back to the table where not.
    local btn
    if LibDBIcon.GetMinimapButton then
        btn = LibDBIcon:GetMinimapButton(DATA_OBJECT_NAME)
    elseif LibDBIcon.objects then
        btn = LibDBIcon.objects[DATA_OBJECT_NAME]
    end
    if not btn or not btn.icon then return end

    local enabled = ns.db and ns.db.global and ns.db.global.enabled
    local ok, desatOk = pcall(btn.icon.SetDesaturated, btn.icon, not enabled)
    if not ok or not desatOk then
        if enabled then
            btn.icon:SetVertexColor(1, 1, 1)
        else
            btn.icon:SetVertexColor(0.5, 0.5, 0.5)
        end
    end
end

-- Exposed so /bw debug and tests can assert the minimap button is live.
function ns:GetMinimapButton()
    if not LibDBIcon then return nil end
    if LibDBIcon.objects then return LibDBIcon.objects[DATA_OBJECT_NAME] end
    return nil
end
