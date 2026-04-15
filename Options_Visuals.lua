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

local textureItems = {
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

local textPosItems = {
    { text = "Left",  value = "INSIDE_LEFT"  },
    { text = "Right", value = "INSIDE_RIGHT" },
}

local BW_FONT = "Interface\\AddOns\\BarWarden\\Fonts\\"
local fontItems = {
    -- WoW built-in fonts
    { text = "Friz Quadrata", value = "Fonts\\FRIZQT__.TTF"        },
    { text = "Arial Narrow",  value = "Fonts\\ARIALN.TTF"          },
    { text = "Morpheus",      value = "Fonts\\MORPHEUS.TTF"        },
    { text = "Nimrod MT",     value = "Fonts\\NIM_____.ttf"        },
    { text = "Skurri",        value = "Fonts\\SKURRI.TTF"          },
    -- BarWarden custom fonts
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

    -- Scroll frame so content doesn't clip at the bottom of the panel.
    -- Start at -60 to sit below the panel title + subtitle (~54 px).
    local scrollFrame = CreateFrame("ScrollFrame", "BarWardenVisualsScrollFrame",
                                    frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT",     frame, "TOPLEFT",     4,   -60)
    scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -28,   4)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetWidth(544)
    content:SetHeight(1200)
    scrollFrame:SetScrollChild(content)

    -- Widget refs populated by BuildSettings. Schema onChange closures close
    -- over this table so they can show/hide coupled widgets by id.
    local widgets = {}

    local SCHEMA = {
        -- -------------------- introductory note --------------------
        { type = "note", style = "disabled",
          text = "These settings apply to all bars globally. Per-bar options are in the Bars / Groups tab.",
          -- First widget; offsetX=0 against firstX=16 => (16, -10).
        },

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
          spacing = 16, offsetX = 4 },
        { type = "slider", label = "Bar Spacing",
          db = "visual.barSpacing", refresh = "RefreshAllBars",
          min = 0, max = 30, step = 1, width = 200,
          spacing = 16,
          tooltip = "Vertical pixels of padding between stacked bars "
                 .. "within a group. 0 = bars touch each other." },

        -- -------------------- Section: Bar Visuals --------------------
        { type = "header", text = "Bar Visuals",
          spacing = 24, offsetX = -4 },

        { type = "dropdown", id = "colorModeDD", label = "Color Mode",
          db = "visual.colorMode", refresh = "RefreshAllBars",
          items = colorModeItems,
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

        { type = "toggle", label = "Allow Per-Bar Color Override",
          tooltip = "When enabled, individual bars can override the global color setting.",
          db = "visual.perBarColorOverride",
          spacing = 12, offsetX = -4 },

        { type = "dropdown", id = "textureDD", label = "Bar Texture",
          db = "visual.texture", refresh = "RefreshAllBars",
          items = textureItems,
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
          width = 150,
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
          items = textPosItems,
          spacing = 24, offsetX = -16 },

        { type = "dropdown", label = "Font",
          db = "visual.font", refresh = "RefreshAllBars",
          items = fontItems,
          spacing = 16 },

        { type = "slider", label = "Font Size",
          db = "visual.fontSize", refresh = "RefreshAllBars",
          min = 6, max = 24, step = 1, width = 200,
          spacing = 16, offsetX = 16 },

        { type = "dropdown", label = "Text Format",
          db = "visual.textFormat", refresh = "RefreshAllBars",
          items = textFormatItems,
          spacing = 24, offsetX = -16 },

        { type = "dropdown", label = "Duration Style",
          db = "visual.durationStyle", refresh = "RefreshAllBars",
          items = durationStyleItems,
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
          items = iconPosItems,
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

        -- -------------------- Section: Bar Opacity --------------------
        { type = "header", text = "Bar Opacity",
          spacing = 24 },

        { type = "slider", label = "Active Opacity",
          db = "visual.activeAlpha", refresh = "RefreshAllBars",
          min = 0, max = 1, step = 0.05, width = 200,
          spacing = 16, offsetX = 4 },

        { type = "slider", label = "Inactive Opacity",
          db = "visual.inactiveAlpha", refresh = "RefreshAllBars",
          min = 0, max = 1, step = 0.05, width = 200,
          spacing = 16 },

        { type = "toggle", label = "Fade When Inactive",
          tooltip = "Gradually fade bars to inactive opacity when not tracking anything.",
          db = "visual.fadeWhenInactive", refresh = "RefreshAllBars",
          spacing = 12, offsetX = -4 },

        -- Fade Speed deliberately has NO refresh method; fade speed only
        -- matters during the next opacity transition, not immediately.
        { type = "slider", id = "fadeSpeed", label = "Fade Speed",
          db = "visual.fadeSpeed",
          min = 0.1, max = 2.0, step = 0.1, width = 200,
          spacing = 16, offsetX = 4,
          tooltip = "How quickly bars fade between Active Opacity and "
                 .. "Inactive Opacity when entering or leaving an active "
                 .. "state. Lower = slower, more pronounced fade; higher "
                 .. "= snappier transition. Only matters when Fade When "
                 .. "Inactive is ticked." },
    }

    frame.Refresh = ns:BuildSettings(content, SCHEMA, widgets,
                                     { firstX = 16, firstY = -10 })

    -- Re-skin section headers to GameFontNormalLarge (the default builder
    -- uses GameFontNormal). Iterate content's FontString regions and match
    -- by text, since headers don't have schema ids and the text is unique.
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

    -- Preserve the v1.4.0 OnShow behaviour: adapt width to scroll viewport,
    -- trim content height to the last widget's bottom, then refresh. The
    -- builder's Refresh closure already brackets itself with
    -- ns.suppressCallbacks, so we don't need the outer bracket here.
    frame:SetScript("OnShow", function()
        local w = scrollFrame:GetWidth()
        if w and w > 100 then
            content:SetWidth(w)
        end
        local last = widgets.fadeSpeed
        if last then
            local lastBottom = last:GetBottom()
            local contentTop = content:GetTop()
            if lastBottom and contentTop and contentTop > lastBottom then
                content:SetHeight(contentTop - lastBottom + 20)  -- 20 px margin
            end
        end
        if frame.Refresh then frame:Refresh() end
    end)

    return frame
end

-- Register tab when options panel is created.
local orig = ns.CreateOptionsPanel
ns.CreateOptionsPanel = function(self)
    local panel = orig(self)
    local tab = CreateVisualsTab(panel)
    ns.optionsTabs[3] = tab
    return panel
end
