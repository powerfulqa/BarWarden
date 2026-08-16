-- Options_Frames.lua - Frames tab: unit frame settings (declarative schema).
-- Author:  Serv
-- Source:  https://github.com/powerfulqa/BarWarden
-- License: see LICENSE; attribution preservation is required.

local addonName, ns = ...

-- ============================================================================
-- Options_Frames.lua - Tab 7: Frames
--
-- Settings for the unit frame widget (UnitFrames.lua): a second, separate
-- way to show health/power/class-resource data alongside the existing
-- resource groups on the Bars / Groups tab. This first slice covers the
-- player frame only - enable, scale, and which optional elements it shows.
-- ============================================================================

local FRAMES_TAB_INDEX = 7

local function CreateFramesTab(parent)
    local frame = CreateFrame("Frame", "BarWardenFramesTab", parent)
    frame:SetAllPoints(parent)
    frame:Hide()

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -16)
    title:SetText("Frames")

    local desc = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    desc:SetJustifyH("LEFT")
    if desc.SetWordWrap then desc:SetWordWrap(true) end
    if ns.ApplyWidth then ns:ApplyWidth(desc, 32) end
    desc:SetText("A unit frame shows your health, power, and class resources "
              .. "in the usual arrangement: portrait, name and level, bars, "
              .. "and a numbers column. This is separate from Resource Groups "
              .. "on Bar Control - use whichever reads better.")

    local scrollFrame = CreateFrame("ScrollFrame", "BarWardenFramesScrollFrame",
                                    frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT",     desc,  "BOTTOMLEFT",  -12,  -6)
    scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -28,   4)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetWidth(544)
    content:SetHeight(1)
    scrollFrame:SetScrollChild(content)
    scrollFrame:SetScript("OnSizeChanged", function(_, w)
        if w and w > 0 then content:SetWidth(math.min(w, ns.SETTINGS_MAX_WIDTH or 300)) end
    end)

    local widgets = {}

    local SCHEMA = {
        { type = "header", text = "Player Frame", large = true,
          id = "playerFrameHeader", offsetX = ns.OFFSET_HEADER },

        { type = "toggle", label = "Show Player Frame",
          tooltip = "Shows a portrait unit frame for your own character.",
          db = "unitFrames.player.enabled", refresh = "RebuildUnitFrames",
          offsetX = ns.OFFSET_TOGGLE, spacing = 16 },

        { type = "slider", label = "Scale", min = 0.5, max = 3.0, step = 0.1,
          width = 200,
          tooltip = "Resizes the frame without moving it.",
          get = function() return ns:DBGet("unitFrames.player.scale", 1.0) end,
          set = function(_, value) ns:SetUnitFrameScale("player", value) end,
          offsetX = ns.OFFSET_SLIDER, spacing = 16 },

        { type = "header", text = "Elements", spacing = 24, offsetX = ns.OFFSET_HEADER },

        { type = "toggle", label = "Show Portrait",
          tooltip = "Shows your character's portrait on the left.",
          db = "unitFrames.player.showPortrait", refresh = "RebuildUnitFrames",
          offsetX = ns.OFFSET_TOGGLE, spacing = 16 },

        { type = "toggle", label = "Show Level",
          tooltip = "Adds your level next to your name.",
          db = "unitFrames.player.showLevel", refresh = "RebuildUnitFrames",
          offsetX = ns.OFFSET_TOGGLE },

        { type = "toggle", label = "Show Values Column",
          tooltip = "Shows the amount and percent next to each bar.",
          db = "unitFrames.player.showValues", refresh = "RebuildUnitFrames",
          offsetX = ns.OFFSET_TOGGLE },
    }

    frame.Refresh, frame.Reflow = ns:BuildSettings(content, SCHEMA, widgets,
                                     { firstX = 16, firstY = -10 })

    if widgets.playerFrameHeader and ns.CreateHelpIcon then
        ns:CreateHelpIcon(content, widgets.playerFrameHeader, "LEFT", "RIGHT", 6, 0,
            "unit-frames-overview")
    end

    -- Trim the scroll child to the last widget so there is no empty scroll
    -- area below it, same pattern as Options_Visuals.lua's trimHeight.
    local function trimHeight()
        local bottom = frame.Reflow and frame.Reflow()
        local contentTop = content:GetTop()
        if bottom and contentTop and contentTop > bottom then
            content:SetHeight(contentTop - bottom + 20)
        end
    end

    frame:SetScript("OnShow", function()
        local w = scrollFrame:GetWidth()
        if w and w > 100 then content:SetWidth(math.min(w, ns.SETTINGS_MAX_WIDTH or 300)) end
        if frame.Refresh then frame:Refresh() end
        trimHeight()
        if ns.After then ns:After(0, trimHeight) end
    end)

    return frame
end

ns:RegisterOptionsTab(FRAMES_TAB_INDEX, CreateFramesTab)
