-- Options_General.lua - General settings tab.
-- Author:  Serv
-- Source:  https://github.com/powerfulqa/BarWarden
-- License: see LICENSE; attribution preservation is required.

local addonName, ns = ...

-- ============================================================================
-- Options_General.lua - General settings (declarative schema) plus a runnable
-- slash-command list. In v2 these are NOT a separate category: they are folded
-- onto the main "BarWarden" overview page. This file just exposes the content
-- builder (ns:BuildGeneralInto); Options.lua owns the frame + scroll + fit.
--
-- The toggles are built by ns:BuildSettings (Options_Builder.lua). Below the
-- "Slash Commands" header, each command is listed with a Run button that
-- invokes the same handler /bw routes through, so the panel button and the
-- typed command are identical. Mirrors EbonClearance's MainPanel command list.
-- ============================================================================

local SCHEMA = {
    -- Enable toggle: stateful, calls ns:SetEnabled and conditionally
    -- ns:RebuildAllFrames, so it uses the get/set escape hatch instead
    -- of a DBSet path.
    {
        type    = "toggle",
        label   = "Enable BarWarden",
        tooltip = "Turns BarWarden on or off. When off, all bars are hidden.",
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

    -- Version-update nudge toggle (Comms.lua).
    {
        type    = "toggle",
        label   = "Notify me about updates",
        tooltip = "Tells you in chat when a newer BarWarden version is seen on "
               .. "someone in your group or guild.",
        get     = function() return ns.db and ns.db.global and ns.db.global.versionAlerts end,
        set     = function(_, checked)
            if ns.db and ns.db.global then ns.db.global.versionAlerts = checked end
        end,
    },

    -- Slash Commands section header. The runnable list is rendered below it
    -- (see BuildGeneralInto); id exposes it as the anchor for that list.
    { type = "header", text = "Slash Commands", spacing = 24, id = "slashHeader" },
}

-- Runnable slash commands. `run` is the subcommand passed to the /bw handler;
-- a row without `run` is informational (no button). Keep in sync with
-- SLASH_COMMANDS in Core.lua and the slash table in README.md.
local SLASH_ROWS = {
    { label = "|cffffff00/bw|r  Open the settings panel |cff888888(you are here)|r" },
    { run = "enable",    label = "|cffffff00/bw enable|r  Turn the addon on" },
    { run = "disable",   label = "|cffffff00/bw disable|r  Turn the addon off" },
    { run = "lock",      label = "|cffffff00/bw lock|r  Toggle frame lock (drag groups when unlocked)" },
    { run = "reset",     label = "|cffffff00/bw reset|r  Rebuild all frames and reset positions" },
    { run = "test",      label = "|cffffff00/bw test|r  Toggle test mode (fake 30s timers)" },
    { run = "scan",      label = "|cffffff00/bw scan|r  Test spell lookups and print the results" },
    { run = "trackers",  label = "|cffffff00/bw trackers|r  Show live tracker state in chat" },
    { run = "stats",     label = "|cffffff00/bw stats|r  Print activity stats to chat" },
    { run = "debug",     label = "|cffffff00/bw debug|r  Print addon state to chat" },
    { run = "bugreport", label = "|cffffff00/bw bugreport|r  Open a copyable diagnostic report" },
    { run = "help",      label = "|cffffff00/bw help|r  List every command in chat" },
}

local LABEL_COL_X  = 54   -- Run-button column width (44) + gap; labels start here
local ROW_RIGHT_PAD = 24

-- Build the General settings (toggles + runnable slash list) into `content`,
-- a scroll child the caller (Options.lua's overview page) supplies. Returns the
-- BuildSettings refresh fn. Stashes a reflow helper and the footer on `content`
-- so the caller can re-wrap the labels and trim the scroll height on resize.
function ns:BuildGeneralInto(content)
    local widgetRefs = {}
    local refresh = ns:BuildSettings(content, SCHEMA, widgetRefs,
                                     { firstX = 16, firstY = -10 })

    -- Render the runnable command rows below the Slash Commands header. Each
    -- label is its own FontString; the Run button sits in a fixed left column
    -- so all labels align and a wrapped label never pushes its button down.
    local rows = {}
    local prev = widgetRefs.slashHeader
    local lastRow = prev
    for i, row in ipairs(SLASH_ROWS) do
        local xOff = (i == 1) and LABEL_COL_X or 0

        local fs = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", xOff, -8)
        fs:SetJustifyH("LEFT")
        if fs.SetWordWrap then fs:SetWordWrap(true) end
        fs:SetText(row.label)
        rows[#rows + 1] = fs

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

    -- Reactive: re-wrap every slash label to the live content width. The caller
    -- calls this from the scroll frame's OnSizeChanged so labels never clip.
    content._reflowSlashRows = function(w)
        local rowW = (w or content:GetWidth() or 544) - LABEL_COL_X - ROW_RIGHT_PAD
        if rowW < 120 then rowW = 120 end
        for _, fs in ipairs(rows) do fs:SetWidth(rowW) end
    end
    content._reflowSlashRows()
    content._generalFooter = footer

    return refresh
end
