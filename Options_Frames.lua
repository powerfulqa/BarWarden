-- Options_Frames.lua - Frames tab: unit frame settings (declarative schema).
-- Author:  Serv
-- Source:  https://github.com/powerfulqa/BarWarden
-- License: GNU GPL v3 (see LICENSE); attribution preservation is required.

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

-- Bar skins offered for a unit frame. Same guard-the-call pattern as
-- Options_Visuals.lua: SharedMedia.lua returns early when LibSharedMedia is
-- absent, so ns:LSMDropdownItems does not merely return nil then, it does
-- not exist - calling it unguarded takes the whole panel down at file scope.
-- "Custom" is deliberately NOT offered here: a raw texture path belongs on
-- the Visuals tab where the path box that goes with it lives.
local BUILTIN_UF_TEXTURE_ITEMS = {
    { text = "XP Perl v2", value = "XP Perl v2" },
    { text = "Flat",       value = "Flat"       },
    { text = "Smooth",     value = "Smooth"     },
    { text = "Gloss",      value = "Gloss"      },
    { text = "Graphite",   value = "Graphite"   },
}
for i = 2, 10 do
    BUILTIN_UF_TEXTURE_ITEMS[#BUILTIN_UF_TEXTURE_ITEMS + 1] =
        { text = "XP Perl " .. i, value = "XP Perl " .. i }
end

local ufTextureItems = (ns.LSMDropdownItems and ns:LSMDropdownItems("statusbar"))
                       or BUILTIN_UF_TEXTURE_ITEMS

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

        { type = "dropdown", id = "ufTextureDD", label = "Bar Look",
          db = "unitFrames.player.barTexture", refresh = "RebuildUnitFrames",
          items = ufTextureItems, width = 191,
          tooltip = "The look of the bars inside the frame. This is separate "
                 .. "from your timer bars, so the frame can look one way and "
                 .. "your bars another.",
          offsetX = ns.OFFSET_DROPDOWN, spacing = 16 },

        { type = "slider", label = "Bar Height", min = 8, max = 40, step = 1,
          width = 200,
          tooltip = "How tall each bar is. Taller bars suit showing the "
                 .. "numbers on the bar.",
          db = "unitFrames.player.barHeight", refresh = "RebuildUnitFrames",
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

        { type = "toggle", label = "Show Values",
          tooltip = "Shows the amount and percent for each bar.",
          db = "unitFrames.player.showValues", refresh = "RebuildUnitFrames",
          set = function(_, value)
              ns:DBSet("unitFrames.player.showValues", value)
              ns:RebuildUnitFrames()
              -- Values Position means nothing with no values to place, so it
              -- appears and disappears with this tick. Same show/hide-then-
              -- reflow pattern the Visuals tab uses for its colour swatch.
              if frame.ApplyConditionals then frame:ApplyConditionals() end
          end,
          offsetX = ns.OFFSET_TOGGLE },

        { type = "dropdown", id = "valuePlacementDD", label = "Values Position",
          db = "unitFrames.player.valuePlacement", refresh = "RebuildUnitFrames",
          items = {
              { text = "Beside the bars", value = "COLUMN" },
              { text = "On the bars",     value = "ONBAR"  },
          },
          width = 191,
          tooltip = "Whether the numbers sit in a column beside the bars or "
                 .. "on the bars themselves.",
          offsetX = ns.OFFSET_DROPDOWN, spacing = 16 },

        { type = "header", text = "Resources Shown", spacing = 24,
          offsetX = ns.OFFSET_HEADER },

        { type = "note",
          text = "Untick anything you do not want on the frame.",
          offsetX = ns.OFFSET_HEADER, spacing = 10 },
    }

    -- One tickbox per resource family, generated from ns.RESOURCE_FAMILIES
    -- (Trackers.lua) rather than written out here, so a family added there
    -- appears here automatically instead of needing both lists edited.
    --
    -- These use get/set closures rather than a `db =` path: hiddenResources
    -- holds user-chosen keys, and ns:DBSet validates paths against
    -- ns.DEFAULTS, where the table is deliberately empty. The stored sense is
    -- inverted (the table records what is HIDDEN) so the tickbox reads the
    -- natural way round: ticked means shown.
    for _, family in ipairs(ns.RESOURCE_FAMILIES) do
        local familyKey = family.key
        SCHEMA[#SCHEMA + 1] = {
            type = "toggle", label = family.label,
            tooltip = "Shows " .. family.label:lower() .. " on the frame.",
            get = function()
                local hidden = ns:DBGet("unitFrames.player.hiddenResources", nil)
                return not (hidden and hidden[familyKey])
            end,
            set = function(_, value)
                local cfg = ns.db and ns.db.unitFrames and ns.db.unitFrames.player
                if not cfg then return end
                cfg.hiddenResources = cfg.hiddenResources or {}
                -- nil rather than false when shown, so the table stays a set
                -- of genuinely-hidden keys and never accumulates a row per
                -- family the owner merely looked at.
                cfg.hiddenResources[familyKey] = (not value) or nil
                ns:RebuildUnitFrames()
                -- Unticking Runes takes the rune-combining option with it.
                if familyKey == "runes" and frame.ApplyConditionals then
                    frame:ApplyConditionals()
                end
            end,
            offsetX = ns.OFFSET_TOGGLE,
        }
    end

    SCHEMA[#SCHEMA + 1] = {
        type = "toggle", id = "pairRunesToggle", label = "Combine Runes by Type",
        tooltip = "Shows three rune bars (blood, frost, unholy) instead of "
               .. "six separate ones.",
        db = "unitFrames.player.pairRunes", refresh = "RebuildUnitFrames",
        offsetX = ns.OFFSET_TOGGLE, spacing = 16,
    }

    frame.Refresh, frame.Reflow = ns:BuildSettings(content, SCHEMA, widgets,
                                     { firstX = 16, firstY = -10 })

    -- Widgets that only make sense under another setting. BuildSettings has
    -- no declarative "hidden" concept: PositionEntry simply skips any widget
    -- that is not shown and chains the next one off the last visible widget,
    -- so a panel drives this itself by Show/Hide followed by a reflow. Kept
    -- as one function on the frame rather than inline in each setter so
    -- every trigger (a setter, OnShow, the initial build) applies the exact
    -- same rules and cannot drift.
    function frame:ApplyConditionals()
        if widgets.valuePlacementDD then
            if ns:DBGet("unitFrames.player.showValues", true) == false then
                widgets.valuePlacementDD:Hide()
            else
                widgets.valuePlacementDD:Show()
            end
        end
        if widgets.pairRunesToggle then
            local hiddenRes = ns:DBGet("unitFrames.player.hiddenResources", nil)
            if hiddenRes and hiddenRes.runes then
                widgets.pairRunesToggle:Hide()
            else
                widgets.pairRunesToggle:Show()
            end
        end
        if frame.Reflow then frame.Reflow() end
    end

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
        -- Before trimHeight: the trim measures the last visible widget, so
        -- hiding one afterwards would leave the scroll child too tall.
        frame:ApplyConditionals()
        trimHeight()
        if ns.After then ns:After(0, trimHeight) end
    end)

    return frame
end

ns:RegisterOptionsTab(FRAMES_TAB_INDEX, CreateFramesTab)
