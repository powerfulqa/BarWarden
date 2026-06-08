-- Options_General.lua - General settings tab.
-- Author:  Serv
-- Source:  https://github.com/powerfulqa/BarWarden
-- License: see LICENSE; attribution preservation is required.

local addonName, ns = ...

-- ============================================================================
-- Options_General.lua - Tab 1: General settings (declarative schema) plus a
-- runnable slash-command list.
--
-- The toggles are built by ns:BuildSettings (Options_Builder.lua). Below the
-- "Slash Commands" header, each command is listed with a Run button that
-- invokes the same handler /bw routes through, so the panel button and the
-- typed command are identical. Mirrors EbonClearance's MainPanel command list.
-- The tab content lives in a scroll frame so the command list never clips.
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

    -- Slash Commands section header. The runnable list is rendered below it
    -- (see CreateGeneralTab); id exposes it as the anchor for that list.
    { type = "header", text = "Slash Commands", spacing = 24, id = "slashHeader" },
}

-- Runnable slash commands. `run` is the subcommand passed to the /bw handler;
-- a row without `run` is informational (no button). Keep in sync with
-- SLASH_COMMANDS in Core.lua and the slash table in README.md.
local SLASH_ROWS = {
    { label = "|cffffd200/bw|r  Open the settings panel |cff888888(you are here)|r" },
    { run = "enable",    label = "|cffffd200/bw enable|r  Turn the addon on" },
    { run = "disable",   label = "|cffffd200/bw disable|r  Turn the addon off" },
    { run = "lock",      label = "|cffffd200/bw lock|r  Toggle frame lock (drag groups when unlocked)" },
    { run = "reset",     label = "|cffffd200/bw reset|r  Rebuild all frames and reset positions" },
    { run = "test",      label = "|cffffd200/bw test|r  Toggle test mode (fake 30s timers)" },
    { run = "scan",      label = "|cffffd200/bw scan|r  Test spell lookups and print the results" },
    { run = "trackers",  label = "|cffffd200/bw trackers|r  Show live tracker state in chat" },
    { run = "stats",     label = "|cffffd200/bw stats|r  Print activity stats to chat" },
    { run = "debug",     label = "|cffffd200/bw debug|r  Print addon state to chat" },
    { run = "bugreport", label = "|cffffd200/bw bugreport|r  Open a copyable diagnostic report" },
    { run = "help",      label = "|cffffd200/bw help|r  List every command in chat" },
}

local LABEL_COL_X  = 54   -- Run-button column width (44) + gap; labels start here
local ROW_RIGHT_PAD = 24

local function CreateGeneralTab(parent)
    local frame = CreateFrame("Frame", "BarWardenGeneralTab", parent)
    frame:SetAllPoints(parent)
    frame:Hide()

    -- Scroll frame so the slash-command list never clips at the bottom of
    -- the panel (matches the Visuals / Help / Stats tabs).
    local scrollFrame = CreateFrame("ScrollFrame", "BarWardenGeneralScrollFrame",
                                    frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT",     frame, "TOPLEFT",      4, -78)
    scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -28,   4)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetWidth(544)
    content:SetHeight(1)
    scrollFrame:SetScrollChild(content)

    local widgetRefs = {}
    frame.Refresh = ns:BuildSettings(content, SCHEMA, widgetRefs,
                                     { firstX = 16, firstY = -10 })

    -- Render the runnable command rows below the Slash Commands header. Each
    -- label is its own FontString; the Run button sits in a fixed left column
    -- so all labels align and a wrapped label never pushes its button down.
    local prev = widgetRefs.slashHeader
    local lastRow = prev
    for i, row in ipairs(SLASH_ROWS) do
        local xOff = (i == 1) and LABEL_COL_X or 0

        local fs = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", xOff, -8)
        fs:SetJustifyH("LEFT")
        if fs.SetWordWrap then fs:SetWordWrap(true) end
        fs:SetWidth(544 - LABEL_COL_X - ROW_RIGHT_PAD)
        fs:SetText(row.label)

        if row.run then
            local runCmd = row.run
            local btn = ns:CreateButton(content, "Run", 44, function()
                local handler = SlashCmdList and SlashCmdList["BARWARDEN"]
                if handler then handler(runCmd) end
                if PlaySound then PlaySound("igMainMenuOptionCheckBoxOn") end
            end)
            btn:SetSize(44, 20)
            btn:SetPoint("LEFT", fs, "LEFT", -LABEL_COL_X, 0)
        end

        prev = fs
        lastRow = fs
    end

    -- Version footer below the list (back at the left margin).
    local footer = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    footer:SetPoint("TOPLEFT", lastRow, "BOTTOMLEFT", -LABEL_COL_X, -16)
    footer:SetText("BarWarden v" .. (ns.version or "?")
                .. " | WoW 3.3.5a (Interface 30300)")

    -- On show: adapt content width to the viewport and trim its height to the
    -- footer so the scrollbar engages only when there is overflow.
    frame:SetScript("OnShow", function()
        local w = scrollFrame:GetWidth()
        if w and w > 100 then content:SetWidth(w) end
        local footBottom = footer:GetBottom()
        local contentTop = content:GetTop()
        if footBottom and contentTop and contentTop > footBottom then
            content:SetHeight(contentTop - footBottom + 20)  -- 20 px margin
        end
        if frame.Refresh then frame:Refresh() end
    end)

    return frame
end

ns:RegisterOptionsTab(1, CreateGeneralTab)
