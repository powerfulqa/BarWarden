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

-- Fonts, with an explicit "same as Visuals" row at the top. Empty string is
-- the stored inherit value (see ns.DEFAULTS.unitFrames.player.nameFont), so
-- a frame keeps following a later Visuals change instead of freezing a copy
-- of whatever the global font was when the frame was built.
local BUILTIN_UF_FONT_ITEMS = {
    { text = "Friz Quadrata", value = "Fonts\\FRIZQT__.TTF" },
    { text = "Arial Narrow",  value = "Fonts\\ARIALN.TTF"   },
    { text = "Morpheus",      value = "Fonts\\MORPHEUS.TTF" },
    { text = "Skurri",        value = "Fonts\\SKURRI.TTF"   },
}

local ufFontItems = (ns.LSMDropdownItems and ns:LSMDropdownItems("font"))
                    or BUILTIN_UF_FONT_ITEMS
table.insert(ufFontItems, 1, { text = "Same as Visuals", value = "" })

-- Shared by every opacity slider. ns:CreateSlider uses the same function for
-- the minimum and maximum labels under the track, so this has to read
-- sensibly as "0%" and "100%" as well as for the live value.
local function PercentLabel(v)
    return string.format("%d%%", (v or 0) * 100)
end

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
          -- A dropdown directly under a slider needs the wider gap: both
          -- draw outside their own frames and the normal 16 printed this
          -- label straight through the slider's minimum value.
          offsetX = ns.OFFSET_DROPDOWN, spacing = ns.GAP_DROPDOWN_UNDER_SLIDER },

        { type = "slider", label = "Bar Height", min = 8, max = 40, step = 1,
          width = 200,
          tooltip = "How tall each bar is. Taller bars suit showing the "
                 .. "numbers on the bar.",
          db = "unitFrames.player.barHeight", refresh = "RebuildUnitFrames",
          offsetX = ns.OFFSET_SLIDER, spacing = 16 },

        { type = "header", text = "Opacity", spacing = 24, offsetX = ns.OFFSET_HEADER },

        { type = "note",
          text = "Each part of the frame fades on its own.",
          offsetX = ns.OFFSET_HEADER, spacing = 10 },

        { type = "slider", label = "Panel", min = 0, max = 1, step = 0.05,
          width = 200, format = PercentLabel,
          tooltip = "The dark background the frame sits on, including behind "
                 .. "the bars.",
          db = "unitFrames.player.frameOpacity", refresh = "RebuildUnitFrames",
          offsetX = ns.OFFSET_SLIDER, spacing = 16 },

        { type = "slider", label = "Portrait", min = 0, max = 1, step = 0.05,
          width = 200, format = PercentLabel,
          tooltip = "The box behind the portrait. A 3D model shows the world "
                 .. "through it once this is lowered.",
          db = "unitFrames.player.portraitOpacity", refresh = "RebuildUnitFrames",
          offsetX = ns.OFFSET_SLIDER, spacing = 16 },

        { type = "slider", label = "Bars", min = 0, max = 1, step = 0.05,
          width = 200, format = PercentLabel,
          tooltip = "The bars themselves, and any numbers sitting on them.",
          db = "unitFrames.player.barOpacity", refresh = "RebuildUnitFrames",
          offsetX = ns.OFFSET_SLIDER, spacing = 16 },

        { type = "slider", label = "Border", min = 0, max = 1, step = 0.05,
          width = 200, format = PercentLabel,
          tooltip = "The edge around the frame and the portrait.",
          db = "unitFrames.player.borderOpacity", refresh = "RebuildUnitFrames",
          offsetX = ns.OFFSET_SLIDER, spacing = 16 },

        { type = "header", text = "Elements", spacing = 24, offsetX = ns.OFFSET_HEADER },

        { type = "toggle", label = "Show Portrait",
          tooltip = "Shows your character's portrait on the left.",
          db = "unitFrames.player.showPortrait", refresh = "RebuildUnitFrames",
          -- onChange, not set: BuildSetCallback composes db + onChange, and
          -- an entry that supplies `set` replaces the DB write entirely
          -- rather than adding to it (ns:DBSet is a factory that RETURNS a
          -- setter, so calling it directly writes nothing).
          onChange = function()
              if frame.ApplyConditionals then frame:ApplyConditionals() end
          end,
          offsetX = ns.OFFSET_TOGGLE, spacing = 16 },

        { type = "dropdown", id = "portraitStyleDD", label = "Portrait Style",
          db = "unitFrames.player.portraitStyle", refresh = "RebuildUnitFrames",
          items = {
              { text = "Picture",  value = "2D" },
              { text = "3D Model", value = "3D" },
          },
          width = 191,
          tooltip = "A 3D model shows your character live. It falls back to "
                 .. "the picture for anyone out of sight.",
          offsetX = ns.OFFSET_DROPDOWN, spacing = 16 },

        { type = "toggle", label = "Show Name",
          tooltip = "Shows the name across the top of the frame.",
          db = "unitFrames.player.showName", refresh = "RebuildUnitFrames",
          offsetX = ns.OFFSET_TOGGLE, spacing = 16 },

        { type = "toggle", label = "Show Level",
          tooltip = "Adds the level next to the name.",
          db = "unitFrames.player.showLevel", refresh = "RebuildUnitFrames",
          offsetX = ns.OFFSET_TOGGLE },

        { type = "toggle", label = "Show Values",
          tooltip = "Shows the amount and percent for each bar.",
          db = "unitFrames.player.showValues", refresh = "RebuildUnitFrames",
          -- Values Position means nothing with no values to place, so it
          -- appears and disappears with this tick. Same show/hide-then-reflow
          -- pattern the Visuals tab uses for its colour swatch. See the note
          -- on Show Portrait above for why this is onChange and not set.
          onChange = function()
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
            -- Power types read differently from the rest: ticking one keeps
            -- it on the frame even when it is not the pool you are currently
            -- using, which is the whole point on a character that has more
            -- than one. It still never appears if the pool is not real.
            tooltip = family.power
                and ("Keeps " .. family.label:lower() .. " on the frame, if "
                     .. "your character has it.")
                or ("Shows " .. family.label:lower() .. " on the frame."),
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

    -- Text section. Size 0 is the stored "inherit" value, and the slider's
    -- minimum, so dragging it to the far left restores the Visuals size
    -- rather than producing an unreadable 1px font. The format callback
    -- spells that out on the slider itself.
    -- Kept short because ns:CreateSlider uses this same function for the
    -- minimum-value label printed under the left end of the track, where a
    -- long string would run out under the slider.
    local function SizeLabel(value)
        if not value or value < 1 then return "Auto" end
        return tostring(math.floor(value))
    end

    local TEXT_SCHEMA = {
        { type = "dropdown", id = "nameFontDD", label = "Name Font",
          spacing = 24,
          db = "unitFrames.player.nameFont", refresh = "RebuildUnitFrames",
          items = ufFontItems, width = 191,
          tooltip = "The font used for the name across the top.",
          offsetX = ns.OFFSET_DROPDOWN, spacing = 16 },

        { type = "slider", label = "Name Size", min = 0, max = 24, step = 1,
          width = 200, format = SizeLabel,
          tooltip = "Size of the name text. Slide fully left to match Visuals.",
          db = "unitFrames.player.nameFontSize", refresh = "RebuildUnitFrames",
          offsetX = ns.OFFSET_SLIDER, spacing = 16 },

        { type = "dropdown", id = "valueFontDD", label = "Values Font",
          db = "unitFrames.player.valueFont", refresh = "RebuildUnitFrames",
          items = ufFontItems, width = 191,
          tooltip = "The font used for the numbers.",
          offsetX = ns.OFFSET_DROPDOWN, spacing = ns.GAP_DROPDOWN_UNDER_SLIDER },

        { type = "slider", label = "Values Size", min = 0, max = 24, step = 1,
          width = 200, format = SizeLabel,
          tooltip = "Size of the numbers. Slide fully left to match Visuals.",
          db = "unitFrames.player.valueFontSize", refresh = "RebuildUnitFrames",
          offsetX = ns.OFFSET_SLIDER, spacing = 16 },
    }
    for _, entry in ipairs(TEXT_SCHEMA) do
        SCHEMA[#SCHEMA + 1] = entry
    end

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
        if widgets.portraitStyleDD then
            if ns:DBGet("unitFrames.player.showPortrait", true) == false then
                widgets.portraitStyleDD:Hide()
            else
                widgets.portraitStyleDD:Show()
            end
        end
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
