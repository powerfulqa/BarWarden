-- Options_Visuals.lua - Visuals settings tab.
-- Author:  Serv
-- Source:  https://github.com/powerfulqa/BarWarden
-- License: see LICENSE; attribution preservation is required.

local addonName, ns = ...

-- ============================================================================
-- Options_Visuals.lua - Tab 3: Visuals / Texturing (declarative schema).
--
-- Widget construction is delegated to ns:BuildSettings (Options_Builder.lua).
-- Each entry in SCHEMA below describes one control; the builder handles
-- creation, anchoring, state coupling, and the auto-Refresh pass.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Static item tables (dropdown option lists)
-- ----------------------------------------------------------------------------

local colorModeItems = {
    { text = "Class Color",      value = "CLASS" },
    { text = "Track Mode Color", value = "TRACK_MODE" },
    { text = "Custom Color",     value = "CUSTOM" },
}

local textPosItems = {
    { text = "Left",  value = "INSIDE_LEFT"  },
    { text = "Right", value = "INSIDE_RIGHT" },
}

-- Hardcoded fallback lists (used when LibSharedMedia is not available)
local BUILTIN_TEXTURE_ITEMS = {
    { text = "Flat",      value = "Flat"     },
    { text = "Smooth",    value = "Smooth"   },
    { text = "Gloss",     value = "Gloss"    },
    { text = "Aluminum",  value = "Aluminum" },
    { text = "Armory",    value = "Armory"   },
    { text = "Graphite",  value = "Graphite" },
    { text = "Otravi",    value = "Otravi"   },
    { text = "Striped",   value = "Striped"  },
    { text = "Canvas",    value = "Canvas"   },
    { text = "LiteStep",  value = "LiteStep" },
    { text = "Glow",      value = "Glow"     },
    { text = "Metal",     value = "Metal"    },
    { text = "Leather",   value = "Leather"  },
    { text = "Custom",    value = "Custom"   },
}

local BW_FONT = "Interface\\AddOns\\BarWarden\\Fonts\\"
local BUILTIN_FONT_ITEMS = {
    { text = "Friz Quadrata", value = "Fonts\\FRIZQT__.TTF"        },
    { text = "Arial Narrow",  value = "Fonts\\ARIALN.TTF"          },
    { text = "Morpheus",      value = "Fonts\\MORPHEUS.TTF"        },
    { text = "Nimrod MT",     value = "Fonts\\NIM_____.ttf"        },
    { text = "Skurri",        value = "Fonts\\SKURRI.TTF"          },
    { text = "Adventure",     value = BW_FONT .. "adventure.ttf"   },
    { text = "Bazooka",       value = BW_FONT .. "bazooka.ttf"     },
    { text = "Cooline",       value = BW_FONT .. "cooline.ttf"     },
    { text = "Diogenes",      value = BW_FONT .. "diogenes.ttf"    },
    { text = "Ginko",         value = BW_FONT .. "ginko.ttf"       },
    { text = "Heroic",        value = BW_FONT .. "heroic.ttf"      },
    { text = "Porky",         value = BW_FONT .. "porky.ttf"       },
    { text = "Talisman",      value = BW_FONT .. "talisman.ttf"    },
    { text = "Transformers",  value = BW_FONT .. "transformers.ttf"},
    { text = "Yellow Jacket", value = BW_FONT .. "yellowjacket.ttf"},
}

-- Use LibSharedMedia dropdown items when available, falling back to the
-- hardcoded lists. LSM items include textures/fonts from ALL addons on
-- the client, giving users a unified selection.
local textureItems = ns:LSMDropdownItems("statusbar") or BUILTIN_TEXTURE_ITEMS
-- Append "Custom" to the LSM texture list so users can still enter a raw path
if ns.LSM and textureItems ~= BUILTIN_TEXTURE_ITEMS then
    textureItems[#textureItems + 1] = { text = "Custom", value = "Custom" }
end
local fontItems = ns:LSMDropdownItems("font") or BUILTIN_FONT_ITEMS

local textFormatItems = {
    { text = "Name + Duration", value = "NAME_DURATION" },
    { text = "Name Only",       value = "NAME_ONLY"     },
    { text = "Duration Only",   value = "DURATION"      },
    { text = "Name + Stacks",   value = "NAME_STACKS"   },
    { text = "Stacks Only",     value = "STACKS"        },
    { text = "None",            value = "NONE"          },
}

local durationStyleItems = {
    { text = "12.3 (seconds.ms)",       value = "DECIMAL" },
    { text = "12 (seconds only)",       value = "SECONDS" },
    { text = "1:05 (min:sec)",          value = "MINSEC"  },
    { text = "1m 5s (short text)",      value = "SHORT"   },
    { text = "Auto (adapts to length)", value = "AUTO"    },
}

local iconPosItems = {
    { text = "Left",  value = "LEFT"  },
    { text = "Right", value = "RIGHT" },
}

-- ----------------------------------------------------------------------------
-- Overridable header font. The original tab used GameFontNormalLarge for
-- section headers; Options_Builder's default header builder uses
-- GameFontNormal. We re-skin headers at Refresh time via the onChange hook
-- below so the schema stays declarative.
-- ----------------------------------------------------------------------------

local function ApplyLargeHeader(widget)
    if widget and widget.SetFontObject then
        widget:SetFontObject("GameFontNormalLarge")
    end
end

local function CreateVisualsTab(parent)
    local frame = CreateFrame("Frame", "BarWardenVisualsTab", parent)
    frame:SetAllPoints(parent)
    frame:Hide()

    -- Title + description: matches the layout of Bars, Profiles, and Stats tabs.
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -16)
    title:SetText("Visuals")

    local desc = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    desc:SetJustifyH("LEFT")
    if desc.SetWordWrap then desc:SetWordWrap(true) end
    -- Reactive width so the text wraps to the live panel width (a two-point
    -- TOPLEFT+RIGHT anchor does not wrap reliably on 3.3.5a).
    if ns.ApplyWidth then ns:ApplyWidth(desc, 32) end
    desc:SetText("The default look for all bars. Groups and individual bars can "
              .. "override the texture and colour on their own tabs.")

    -- Scroll frame so content doesn't clip at the bottom of the panel.
    local scrollFrame = CreateFrame("ScrollFrame", "BarWardenVisualsScrollFrame",
                                    frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT",     desc, "BOTTOMLEFT",  -12,  -6)
    scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -28,   4)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetWidth(544)
    content:SetHeight(1200)
    scrollFrame:SetScrollChild(content)
    -- Reflow the scroll child to the viewport on live resize (not just OnShow),
    -- capped at the shared settings width so controls do not stretch absurdly
    -- wide on a large window (parity with Bar Control / Groups).
    scrollFrame:SetScript("OnSizeChanged", function(_, w)
        if w and w > 0 then content:SetWidth(math.min(w, ns.SETTINGS_MAX_WIDTH or 300)) end
    end)

    -- Widget refs populated by BuildSettings. Schema onChange closures close
    -- over this table so they can show/hide coupled widgets by id.
    local widgets = {}

    local SCHEMA = {
        -- Spacing convention:
        --   24 = section break (above each header after the first)
        --   16 = within-section widget gap
        --   12 = sub-widget gap (related toggles/colors)
        --   8  = branch widget (off-chain)
        --   4  = warning text under its owner

        -- -------------------- Section: Bar Dimensions --------------------
        { type = "header", text = "Bar Dimensions", spacing = 16 },
        { type = "slider", label = "Bar Height",
          db = "visual.barHeight", refresh = "RefreshAllBars",
          min = 4, max = 60, step = 1, width = 200,
          tooltip = "How tall each timer bar is, in pixels.",
          spacing = 16, offsetX = 4 },
        { type = "slider", label = "Bar Spacing",
          db = "visual.barSpacing", refresh = "RefreshAllBars",
          min = 0, max = 30, step = 1, width = 200,
          spacing = 16,
          tooltip = "Vertical pixels of padding between stacked bars "
                 .. "within a group. 0 = bars touch each other." },

        -- -------------------- Section: Bar Visuals --------------------
        { type = "header", text = "Bar Visuals",
          spacing = 24, offsetX = -4, id = "barVisualsHeader" },

        { type = "dropdown", id = "colorModeDD", label = "Color Mode",
          db = "visual.colorMode", refresh = "RefreshAllBars",
          items = colorModeItems, width = 191,
          tooltip = "How bars are coloured by default: your class colour, a "
                 .. "colour per track mode, or one custom colour. Groups and "
                 .. "individual bars can override this.",
          spacing = 24, offsetX = -16,
          onChange = function(value)
              if widgets.colorSwatch then
                  if value == "CUSTOM" then widgets.colorSwatch:Show()
                  else                      widgets.colorSwatch:Hide() end
              end
          end },

        { type = "color", id = "colorSwatch", label = "Default Bar Color",
          db = "visual.defaultColor", refresh = "RefreshAllBars",
          spacing = 12, offsetX = 20 },

        -- Per-bar and per-group colour overrides are always available (in the
        -- bar editor and on the Groups tab). The old global "allow override"
        -- gate did nothing and was removed in v2.

        { type = "dropdown", id = "textureDD", label = "Bar Texture",
          db = "visual.texture", refresh = "RefreshAllBars",
          items = textureItems, width = 191,
          spacing = 16, offsetX = -16,
          onChange = function(value)
              local show = (value == "Custom")
              if widgets.customTexBox then
                  if show then widgets.customTexBox:Show()
                  else         widgets.customTexBox:Hide() end
              end
              if widgets.fallbackWarning then
                  if show then widgets.fallbackWarning:Show()
                  else         widgets.fallbackWarning:Hide() end
              end
          end },

        -- Branch off textureDD: customTexBox + fallbackWarning stack below
        -- textureDD but OUT of the main chain. textHeader below returns to
        -- the main chain by re-anchoring to textureDD.
        { type = "editbox", id = "customTexBox", label = "Custom Texture Filename",
          db = "visual.customTexture", refresh = "RefreshAllBars",
          width = 190,
          anchorTo = "textureDD", spacing = 8, offsetX = 20,
          tooltip = "Path to a Blizzard-format bar texture file (TGA or "
                 .. "BLP). Use forward slashes or double backslashes, e.g. "
                 .. "'Interface\\\\AddOns\\\\MyAddon\\\\MyBar.tga'. "
                 .. "If the file is missing, BarWarden falls back to the "
                 .. "Flat texture. Press Enter to apply." },

        { type = "note", id = "fallbackWarning",
          text = "|cffff8800Warning: If file not found, Flat texture will be used.|r",
          spacing = 4 },

        -- -------------------- Section: Text Options --------------------
        { type = "header", text = "Text Options",
          anchorTo = "textureDD", spacing = 24, offsetX = 16 },

        { type = "dropdown", label = "Text Position",
          db = "visual.textPosition", refresh = "RefreshAllBars",
          items = textPosItems, width = 191,
          spacing = 24, offsetX = -16 },

        { type = "dropdown", label = "Font",
          db = "visual.font", refresh = "RefreshAllBars",
          items = fontItems, width = 191,
          spacing = 16 },

        { type = "slider", label = "Font Size",
          db = "visual.fontSize", refresh = "RefreshAllBars",
          min = 6, max = 24, step = 1, width = 200,
          tooltip = "Text size for the name and timer shown on each bar.",
          spacing = 16, offsetX = 16 },

        { type = "dropdown", label = "Text Format",
          db = "visual.textFormat", refresh = "RefreshAllBars",
          items = textFormatItems, width = 191,
          spacing = 24, offsetX = -16 },

        { type = "dropdown", label = "Duration Style",
          db = "visual.durationStyle", refresh = "RefreshAllBars",
          items = durationStyleItems, width = 191,
          spacing = 16 },

        -- -------------------- Section: Icon --------------------
        { type = "header", text = "Icon",
          spacing = 24, offsetX = 16 },

        { type = "slider", label = "Icon Size",
          db = "visual.iconSize", refresh = "RefreshAllBars",
          min = 0, max = 60, step = 1, width = 200,
          spacing = 16, offsetX = 4,
          tooltip = "Size (in pixels) of the spell icon shown on each bar. "
                 .. "Set to 0 to hide icons globally. Individual bars can "
                 .. "override this via Show Icon in the per-bar editor." },

        { type = "dropdown", label = "Icon Position",
          db = "visual.iconPosition", refresh = "RefreshAllBars",
          items = iconPosItems, width = 191,
          spacing = 24, offsetX = -16 },

        { type = "toggle", label = "Crop Icons",
          tooltip = "Trim icon border pixels to prevent stretching on non-square bars.",
          db = "visual.iconCrop", refresh = "RefreshAllBars",
          spacing = 12, offsetX = 16 },

        { type = "toggle", label = "Cooldown Spiral",
          tooltip = "Overlay a radial sweep on the bar icon that matches the "
                 .. "cooldown or buff duration. Gives a second visual read on "
                 .. "the timer in addition to the bar fill. Has no effect on "
                 .. "resource bars (combo points, runes, etc.).",
          db = "visual.showCooldownSpiral", refresh = "RefreshAllBars",
          spacing = 12 },

        { type = "toggle", id = "iconTooltip", label = "Icon Tooltip",
          tooltip = "Show the spell or item tooltip when hovering the bar's "
                 .. "icon. Useful for identifying what a bar tracks without "
                 .. "opening the settings panel. Only the icon is hover-sensitive; "
                 .. "the bar body still passes clicks through to the game world.",
          db = "visual.showBarTooltip",
          spacing = 8 },

        -- -------------------- Section: Bar Opacity --------------------
        { type = "header", text = "Bar Opacity",
          spacing = 24 },

        { type = "slider", label = "Active Opacity",
          db = "visual.activeAlpha", refresh = "RefreshAllBars",
          min = 0, max = 1, step = 0.05, width = 200,
          tooltip = "Opacity of a bar while its timer is running.",
          spacing = 16, offsetX = 4 },

        { type = "slider", id = "inactiveAlpha", label = "Inactive Opacity",
          db = "visual.inactiveAlpha", refresh = "RefreshAllBars",
          min = 0, max = 1, step = 0.05, width = 200,
          tooltip = "Opacity of a bar when nothing is active, for bars set to "
                 .. "stay visible.",
          spacing = 16 },
    }

    frame.Refresh = ns:BuildSettings(content, SCHEMA, widgets,
                                     { firstX = 16, firstY = -10 })

    if widgets.barVisualsHeader then
        ns:CreateHelpIcon(content, widgets.barVisualsHeader, "LEFT", "RIGHT", 6, 0,
            "visuals-overview")
    end

    -- Re-skin section headers to GameFontNormalLarge (the default builder uses
    -- GameFontNormal). Headers have no schema ids, so match by their (unique)
    -- text.
    local knownHeaders = {
        ["Bar Dimensions"] = true, ["Bar Visuals"] = true,
        ["Text Options"]   = true, ["Icon"]        = true,
        ["Bar Opacity"]    = true,
    }
    for _, region in ipairs({ content:GetRegions() }) do
        if region.GetObjectType and region:GetObjectType() == "FontString"
           and knownHeaders[region:GetText() or ""] then
            ApplyLargeHeader(region)
        end
    end

    -- Hide the branch widgets that default-off until texture is "Custom".
    if widgets.customTexBox then widgets.customTexBox:Hide() end
    if widgets.fallbackWarning then widgets.fallbackWarning:Hide() end

    -- Trim the scroll child to the last widget so there is no empty scroll
    -- area below it. This MUST run after the widgets are laid out, or GetBottom
    -- is not yet valid and the child stays at its tall initial height (the
    -- "dead space at the bottom" bug). We run it on show and again next frame.
    local function trimHeight()
        local last = widgets.inactiveAlpha
        local lastBottom = last and last:GetBottom()
        local contentTop = content:GetTop()
        if lastBottom and contentTop and contentTop > lastBottom then
            content:SetHeight(contentTop - lastBottom + 20)  -- 20 px margin
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

ns:RegisterOptionsTab(3, CreateVisualsTab)
