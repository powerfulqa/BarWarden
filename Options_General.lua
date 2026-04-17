local addonName, ns = ...

-- ============================================================================
-- Options_General.lua - Tab 1: General settings (declarative schema).
--
-- Widget construction is delegated to ns:BuildSettings (Options_Builder.lua).
-- Each entry in SCHEMA below describes one row of the panel; the builder
-- handles widget creation, anchoring, and the auto-Refresh pass.
-- ============================================================================

local SCHEMA = {
    -- Enable toggle: stateful, calls ns:SetEnabled and conditionally
    -- ns:RebuildAllFrames, so it uses the get/set escape hatch instead
    -- of a DBSet path.
    {
        type    = "toggle",
        label   = "Enable BarWarden",
        tooltip = "Globally enable or disable BarWarden. When disabled, "
               .. "all frames are hidden and events are unregistered.",
        get     = function() return ns.db and ns.db.global.enabled end,
        set     = function(_, checked)
            ns:SetEnabled(checked)
            if checked then
                ns:RebuildAllFrames()
            end
        end,
    },

    -- Lock toggle: also stateful, two-branch Lock/UnlockAllFrames side
    -- effect, so it stays as a closure rather than a DBSet path.
    {
        type    = "toggle",
        label   = "Lock All Frames",
        tooltip = "When locked, frames cannot be moved or resized.",
        get     = function() return ns.db and ns.db.global.locked end,
        set     = function(_, checked)
            BarWardenDB.global.locked = checked
            if checked then
                ns:LockAllFrames()
            else
                ns:UnlockAllFrames()
            end
        end,
    },

    -- Minimap toggle: `minimap.hide` stores the LibDBIcon-compatible
    -- "hide-when-true" flag, but the UI reads positively ("Show..."), so
    -- get/set invert the value. Stateful enough to warrant closures over
    -- the DBSet path.
    {
        type    = "toggle",
        label   = "Show Minimap Icon",
        tooltip = "Toggle the BarWarden minimap button.",
        get     = function()
            return not (ns.db and ns.db.minimap and ns.db.minimap.hide)
        end,
        set     = function(_, checked)
            if not (ns.db and ns.db.minimap) then return end
            ns.db.minimap.hide = not checked
            ns:UpdateMinimapButtonVisibility()
        end,
    },

    -- Slash Commands section (24px gap above for visual break).
    { type = "header", text = "Slash Commands", spacing = 24 },
    {
        type    = "note",
        text    = "|cffffd200/bw|r or |cffffd200/barwarden|r - Open configuration panel\n"
               .. "|cffffd200/bw lock|r - Toggle frame lock\n"
               .. "|cffffd200/bw reset|r - Reset frame positions",
        spacing = 6,
    },

    -- Version footer (subdued; resolved lazily so ns.version is read at build time).
    {
        type    = "note",
        style   = "disabled",
        text    = function() return "BarWarden v" .. (ns.version or "?")
                                 .. " | WoW 3.3.5a (Interface 30300)" end,
        spacing = 16,
    },
}

local function CreateGeneralTab(parent)
    local frame = CreateFrame("Frame", "BarWardenGeneralTab", parent)
    frame:SetAllPoints(parent)
    frame:Hide()

    frame.Refresh = ns:BuildSettings(frame, SCHEMA)

    return frame
end

ns:RegisterOptionsTab(1, CreateGeneralTab)
