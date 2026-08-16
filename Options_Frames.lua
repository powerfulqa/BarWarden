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
-- resource groups on the Bars / Groups tab.
--
-- Every frame's settings are GENERATED from one builder rather than written
-- out per frame. There are around twenty controls each; three hand-copied
-- blocks would drift the first time one was edited and the others were not,
-- which is exactly how unit frames came to be missing from profile export
-- (see ns:CaptureProfileData, DB.lua). Add a setting once, in
-- AppendFrameSchema, and every frame gets it.
--
-- The one deliberate asymmetry is the resource tick list, which only the
-- player frame has. A target frame shows what the target actually has, the
-- way the default UI does. docs/CODE_REVIEW.md item 25 has the reasoning;
-- do not "complete" the target by giving it the player's controls.
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

-- Size 0 is the stored "inherit" value and the slider's minimum, so dragging
-- fully left restores the Visuals size rather than producing an unreadable
-- 1px font. Kept short because ns:CreateSlider uses this same function for
-- the minimum-value label under the left end of the track, where a long
-- string runs out from under the slider.
local function SizeLabel(value)
    if not value or value < 1 then return "Auto" end
    return tostring(math.floor(value))
end

-- Append one frame's whole settings block to `schema`.
--
-- `key` is the unit-frame key ("player", "target", ...) and doubles as the
-- widget-id namespace, so each frame's conditional widgets can be found
-- without three frames' worth of ids colliding on one panel.
--
-- `opts.resourceTickList` adds the per-resource tickboxes and the
-- rune-combining option. Player only, on purpose - see the file header.
local function AppendFrameSchema(schema, panel, key, label, opts)
    opts = opts or {}
    local P  = "unitFrames." .. key .. "."
    local id = function(suffix) return key .. suffix end

    -- Fires the shared show/hide pass whenever a setting that gates another
    -- widget changes. onChange rather than set: BuildSetCallback composes
    -- db + onChange, whereas supplying `set` REPLACES the DB write (ns:DBSet
    -- is a factory that returns a setter, so calling it directly writes
    -- nothing at all - a bug this panel has already shipped once).
    local function reapply()
        if panel.ApplyConditionals then panel:ApplyConditionals() end
    end

    local entries = {
        { type = "header", text = label, large = true,
          id = id("Header"), spacing = 28, offsetX = ns.OFFSET_HEADER },

        { type = "toggle", label = "Show " .. label,
          tooltip = "Shows a portrait unit frame for " .. opts.whose .. ".",
          db = P .. "enabled", refresh = "RebuildUnitFrames",
          offsetX = ns.OFFSET_TOGGLE, spacing = 16 },

        { type = "slider", label = "Scale", min = 0.5, max = 3.0, step = 0.1,
          width = 200,
          tooltip = "Resizes the frame without moving it.",
          get = function() return ns:DBGet(P .. "scale", 1.0) end,
          set = function(_, value) ns:SetUnitFrameScale(key, value) end,
          offsetX = ns.OFFSET_SLIDER, spacing = 16 },

        { type = "dropdown", id = id("TextureDD"), label = "Bar Look",
          db = P .. "barTexture", refresh = "RebuildUnitFrames",
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
          db = P .. "barHeight", refresh = "RebuildUnitFrames",
          offsetX = ns.OFFSET_SLIDER, spacing = 16 },

        { type = "slider", label = "Strip Height", min = 0, max = 30, step = 1,
          width = 200, format = SizeLabel,
          tooltip = "How tall the rune and combo point strips are. They are "
                 .. "kept shorter than the main bars so health and power "
                 .. "stand out. Slide fully left to size them automatically.",
          db = P .. "secondaryBarHeight", refresh = "RebuildUnitFrames",
          offsetX = ns.OFFSET_SLIDER, spacing = 16 },

        { type = "header", text = "Opacity", spacing = 24, offsetX = ns.OFFSET_HEADER },

        { type = "slider", label = "Panel", min = 0, max = 1, step = 0.05,
          width = 200, format = PercentLabel,
          tooltip = "The dark background the frame sits on, including behind "
                 .. "the bars.",
          db = P .. "frameOpacity", refresh = "RebuildUnitFrames",
          offsetX = ns.OFFSET_SLIDER, spacing = 16 },

        { type = "slider", label = "Portrait", min = 0, max = 1, step = 0.05,
          width = 200, format = PercentLabel,
          tooltip = "The box behind the portrait. A 3D model shows the world "
                 .. "through it once this is lowered.",
          db = P .. "portraitOpacity", refresh = "RebuildUnitFrames",
          offsetX = ns.OFFSET_SLIDER, spacing = 16 },

        { type = "slider", label = "Bars", min = 0, max = 1, step = 0.05,
          width = 200, format = PercentLabel,
          tooltip = "The bars themselves, and any numbers sitting on them.",
          db = P .. "barOpacity", refresh = "RebuildUnitFrames",
          offsetX = ns.OFFSET_SLIDER, spacing = 16 },

        { type = "slider", label = "Border", min = 0, max = 1, step = 0.05,
          width = 200, format = PercentLabel,
          tooltip = "The edge around the frame and the portrait.",
          db = P .. "borderOpacity", refresh = "RebuildUnitFrames",
          offsetX = ns.OFFSET_SLIDER, spacing = 16 },

        { type = "header", text = "Elements", spacing = 24, offsetX = ns.OFFSET_HEADER },

        { type = "toggle", label = "Show Portrait",
          tooltip = "Shows the portrait on the left.",
          db = P .. "showPortrait", refresh = "RebuildUnitFrames",
          onChange = reapply,
          offsetX = ns.OFFSET_TOGGLE, spacing = 16 },

        { type = "dropdown", id = id("PortraitStyleDD"), label = "Portrait Style",
          db = P .. "portraitStyle", refresh = "RebuildUnitFrames",
          items = {
              { text = "Picture",  value = "2D" },
              { text = "3D Model", value = "3D" },
          },
          width = 191,
          tooltip = "A 3D model shows the character live. It falls back to "
                 .. "the picture for anyone out of sight.",
          offsetX = ns.OFFSET_DROPDOWN, spacing = 16 },

        { type = "toggle", label = "Show Name",
          tooltip = "Shows the name across the top of the frame.",
          db = P .. "showName", refresh = "RebuildUnitFrames",
          offsetX = ns.OFFSET_TOGGLE, spacing = 16 },

        { type = "toggle", label = "Show Level",
          tooltip = "Adds the level next to the name.",
          db = P .. "showLevel", refresh = "RebuildUnitFrames",
          offsetX = ns.OFFSET_TOGGLE },

        { type = "toggle", label = "Show Values",
          tooltip = "Shows the amount and percent for each bar.",
          db = P .. "showValues", refresh = "RebuildUnitFrames",
          onChange = reapply,
          offsetX = ns.OFFSET_TOGGLE },

        { type = "dropdown", id = id("ValuePlacementDD"), label = "Values Position",
          db = P .. "valuePlacement", refresh = "RebuildUnitFrames",
          items = {
              { text = "Beside the bars", value = "COLUMN" },
              { text = "On the bars",     value = "ONBAR"  },
          },
          width = 191,
          tooltip = "Whether the numbers sit in a column beside the bars or "
                 .. "on the bars themselves.",
          offsetX = ns.OFFSET_DROPDOWN, spacing = 16 },
    }

    for _, entry in ipairs(entries) do
        schema[#schema + 1] = entry
    end

    -- Resource tick list. Player only: a target frame shows what the target
    -- has, so a tick list there would be settings that either do nothing or
    -- offer bars the target cannot have.
    if opts.resourceTickList then
        schema[#schema + 1] = { type = "header", text = "Resources Shown",
                                spacing = 24, offsetX = ns.OFFSET_HEADER }
        schema[#schema + 1] = { type = "note",
                                text = "Untick anything you do not want on the frame.",
                                offsetX = ns.OFFSET_HEADER, spacing = 10 }

        -- Generated from ns.RESOURCE_FAMILIES (Trackers.lua) rather than
        -- written out, so a family added there appears here automatically.
        --
        -- get/set closures rather than a `db =` path: hiddenResources holds
        -- user-chosen keys, and ns:DBSet validates paths against ns.DEFAULTS
        -- where the table is deliberately empty. The stored sense is inverted
        -- (it records what is HIDDEN) so the tickbox reads the natural way
        -- round: ticked means shown.
        for _, family in ipairs(ns.RESOURCE_FAMILIES) do
            local familyKey = family.key
            schema[#schema + 1] = {
                type = "toggle", label = family.label,
                -- Power types read differently from the rest: ticking one
                -- keeps it on the frame even when it is not the pool you are
                -- currently using, which is the whole point on a character
                -- with more than one. It still never appears if the pool is
                -- not real.
                tooltip = family.power
                    and ("Keeps " .. family.label:lower() .. " on the frame, if "
                         .. "your character has it.")
                    or ("Shows " .. family.label:lower() .. " on the frame."),
                get = function()
                    local hidden = ns:DBGet(P .. "hiddenResources", nil)
                    return not (hidden and hidden[familyKey])
                end,
                set = function(_, value)
                    local cfg = ns.db and ns.db.unitFrames and ns.db.unitFrames[key]
                    if not cfg then return end
                    cfg.hiddenResources = cfg.hiddenResources or {}
                    -- nil rather than false when shown, so the table stays a
                    -- set of genuinely-hidden keys and never accumulates a row
                    -- per family the owner merely looked at.
                    cfg.hiddenResources[familyKey] = (not value) or nil
                    ns:RebuildUnitFrames()
                    -- Unticking Runes takes the rune-combining option with it.
                    if familyKey == "runes" then reapply() end
                end,
                offsetX = ns.OFFSET_TOGGLE,
            }
        end

        schema[#schema + 1] = {
            type = "toggle", id = id("PairRunesToggle"),
            label = "Combine Runes by Type",
            tooltip = "Shows three rune bars (blood, frost, unholy) instead of "
                   .. "six separate ones.",
            db = P .. "pairRunes", refresh = "RebuildUnitFrames",
            offsetX = ns.OFFSET_TOGGLE, spacing = 16,
        }
    end

    local textEntries = {
        { type = "dropdown", id = id("NameFontDD"), label = "Name Font",
          db = P .. "nameFont", refresh = "RebuildUnitFrames",
          items = ufFontItems, width = 191,
          tooltip = "The font used for the name across the top.",
          offsetX = ns.OFFSET_DROPDOWN, spacing = 24 },

        { type = "slider", label = "Name Size", min = 0, max = 24, step = 1,
          width = 200, format = SizeLabel,
          tooltip = "Size of the name text. Slide fully left to match Visuals.",
          db = P .. "nameFontSize", refresh = "RebuildUnitFrames",
          offsetX = ns.OFFSET_SLIDER, spacing = 16 },

        { type = "dropdown", id = id("ValueFontDD"), label = "Values Font",
          db = P .. "valueFont", refresh = "RebuildUnitFrames",
          items = ufFontItems, width = 191,
          tooltip = "The font used for the numbers.",
          offsetX = ns.OFFSET_DROPDOWN, spacing = ns.GAP_DROPDOWN_UNDER_SLIDER },

        { type = "slider", label = "Values Size", min = 0, max = 24, step = 1,
          width = 200, format = SizeLabel,
          tooltip = "Size of the numbers. Slide fully left to match Visuals.",
          db = P .. "valueFontSize", refresh = "RebuildUnitFrames",
          offsetX = ns.OFFSET_SLIDER, spacing = 16 },
    }
    for _, entry in ipairs(textEntries) do
        schema[#schema + 1] = entry
    end
end

-- Which frames the tab offers, in panel order, and what each one is called
-- in its own settings. `whose` completes "Shows a portrait unit frame for
-- ___." so the tooltips read naturally rather than being three copies of a
-- generic sentence.
local FRAME_SECTIONS = {
    { key = "player",       label = "Player Frame",
      whose = "your own character", resourceTickList = true },
    { key = "target",       label = "Target Frame",
      whose = "whatever you have targeted" },
    { key = "targettarget", label = "Target's Target Frame",
      whose = "whoever your target is targeting" },
}

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
    desc:SetText("A unit frame shows health, power, and class resources in the "
              .. "usual arrangement: portrait, name and level, and bars. Drag "
              .. "one to move it. This is separate from Resource Groups on Bar "
              .. "Control - use whichever reads better.")

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

    local SCHEMA = {}
    for _, section in ipairs(FRAME_SECTIONS) do
        AppendFrameSchema(SCHEMA, frame, section.key, section.label, section)
    end

    frame.Refresh, frame.Reflow = ns:BuildSettings(content, SCHEMA, widgets,
                                     { firstX = 16, firstY = -10 })

    -- Widgets that only make sense under another setting. BuildSettings has
    -- no declarative "hidden" concept: PositionEntry simply skips any widget
    -- that is not shown and chains the next one off the last visible widget,
    -- so a panel drives this itself by Show/Hide followed by a reflow.
    --
    -- One function covering every frame, rather than per-frame copies, so a
    -- rule cannot end up applied to the player and forgotten for the target.
    function frame:ApplyConditionals()
        for _, section in ipairs(FRAME_SECTIONS) do
            local key = section.key
            local P   = "unitFrames." .. key .. "."

            local styleDD = widgets[key .. "PortraitStyleDD"]
            if styleDD then
                if ns:DBGet(P .. "showPortrait", true) == false then
                    styleDD:Hide()
                else
                    styleDD:Show()
                end
            end

            local placementDD = widgets[key .. "ValuePlacementDD"]
            if placementDD then
                if ns:DBGet(P .. "showValues", true) == false then
                    placementDD:Hide()
                else
                    placementDD:Show()
                end
            end

            local pairRunes = widgets[key .. "PairRunesToggle"]
            if pairRunes then
                local hiddenRes = ns:DBGet(P .. "hiddenResources", nil)
                if hiddenRes and hiddenRes.runes then
                    pairRunes:Hide()
                else
                    pairRunes:Show()
                end
            end
        end
        if frame.Reflow then frame.Reflow() end
    end

    if widgets.playerHeader and ns.CreateHelpIcon then
        ns:CreateHelpIcon(content, widgets.playerHeader, "LEFT", "RIGHT", 6, 0,
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
