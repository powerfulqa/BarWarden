-- Bar.lua - Bar frame construction and visual config.
-- Author:  Serv
-- Source:  https://github.com/powerfulqa/BarWarden
-- License: see LICENSE; attribution preservation is required.

local addonName, ns = ...

local max = math.max

-- ============================================================================
-- Bar.lua - Bar frame construction and visual configuration
-- ============================================================================

-- Texture lookup table: all files live in BarWarden/Textures/
local T = "Interface\\AddOns\\BarWarden\\Textures\\"

local TEXTURES = {
    ["Flat"]     = "Interface\\Buttons\\WHITE8x8",
    ["Smooth"]   = T .. "Smooth.tga",
    ["Gloss"]    = T .. "Gloss.tga",
    ["Aluminum"] = T .. "Aluminum.tga",
    ["Armory"]   = T .. "Armory.tga",
    ["Graphite"] = T .. "Graphite.tga",
    ["Otravi"]   = T .. "Otravi.tga",
    ["Striped"]  = T .. "Striped.tga",
    ["Canvas"]   = T .. "Canvas.tga",
    ["LiteStep"] = T .. "LiteStep.tga",
    ["Glow"]     = T .. "Glow.tga",
    ["Metal"]    = T .. "Metal.tga",
    ["Leather"]  = T .. "Leather.tga",
}

-- Resolve the spell/item icon for a bar, or nil if nothing maps.
local function ResolveBarIcon(barData)
    if not barData then return nil end

    local mode = barData.trackMode
    local input = barData.spellName or barData.spellId

    if mode == "Item" then
        local itemId = barData.itemId or input
        if itemId then
            local _, _, _, _, _, _, _, _, _, icon = GetItemInfo(itemId)
            if icon then return icon end
        end
    else
        if input then
            local _, _, icon = GetSpellInfo(input)
            if icon then return icon end
        end
    end

    return nil
end

ns.ResolveBarIcon = ResolveBarIcon

function ns.GetBarDisplayName(barData)
    if not barData then return "" end
    if barData.name and barData.name ~= "" then
        return barData.name
    end
    return ""
end

-- Colour stops for the time-based bar colour gradient:
-- fresh → mid → near-expiry. Lifted to file scope to avoid re-allocating
-- on every OnUpdate tick.
local COLOR_HIGH = { r = 0, g = 0.8, b = 0   }
local COLOR_MED  = { r = 1, g = 0.8, b = 0   }
local COLOR_LOW  = { r = 1, g = 0.2, b = 0.2 }

-- Which fontstrings a given textFormat wants visible. Keeps the visibility
-- logic in ApplyTextConfig a single lookup + two ands, rather than a
-- four-branch if/elseif that the eye has to trace.
local TEXT_FORMAT_VISIBILITY = {
    NAME_DURATION = { name = true,  time = true  },
    DURATION      = { name = false, time = true  },
    NAME_ONLY     = { name = true,  time = false },
    NAME_STACKS   = { name = true,  time = true  },
    STACKS        = { name = false, time = true  },
    NONE          = { name = false, time = false },
}

local function LerpColor(a, b, t)
    return a + (b - a) * t
end

-- Smoothly interpolates between COLOR_HIGH/MED/LOW based on remaining seconds.
-- Returns (r, g, b) or nil if the bar hasn't opted in to colour-by-time.
function ns.GetTimeBasedColor(remaining, display, visual)
    if not display or not display.colorByTime then return nil end

    local highSec = display.colorHighSeconds or 10
    local medSec  = display.colorMedSeconds  or 5

    if remaining >= highSec then
        return COLOR_HIGH.r, COLOR_HIGH.g, COLOR_HIGH.b
    elseif remaining >= medSec then
        local t = (remaining - medSec) / max(highSec - medSec, 0.001)
        return LerpColor(COLOR_MED.r, COLOR_HIGH.r, t),
               LerpColor(COLOR_MED.g, COLOR_HIGH.g, t),
               LerpColor(COLOR_MED.b, COLOR_HIGH.b, t)
    else
        local t = remaining / max(medSec, 0.001)
        return LerpColor(COLOR_LOW.r, COLOR_MED.r, t),
               LerpColor(COLOR_LOW.g, COLOR_MED.g, t),
               LerpColor(COLOR_LOW.b, COLOR_MED.b, t)
    end
end

local function ResolveTexture(name)
    if not name or name == "" then
        return TEXTURES["Flat"]
    end
    -- Check the hardcoded table first (fast path for BarWarden's own names)
    if TEXTURES[name] then return TEXTURES[name] end
    -- Try LibSharedMedia if available (resolves names from other addons)
    if ns.LSM then
        local path = ns:LSMFetch("statusbar", name)
        if path then return path end
    end
    -- Fall back to treating the name as a raw texture path
    return name
end

local function GetBarColor(bar, config)
    -- Per-bar override wins over any global mode.
    local display = bar.barData and bar.barData.display
    if display and display.colorOverride then
        local c = display.colorOverride
        return c.r or 1, c.g or 1, c.b or 1
    end

    local visual = ns:GetVisual()
    local colorMode = visual.colorMode or "CLASS"

    if colorMode == "CLASS" then
        return ns:GetPlayerClassColor()
    elseif colorMode == "TRACK_MODE" then
        local trackMode = bar.barData and bar.barData.trackMode or "Cooldown"
        local colors = visual.trackModeColors
        if colors and colors[trackMode] then
            local c = colors[trackMode]
            return c.r or 1, c.g or 1, c.b or 1
        end
        local dc = visual.defaultColor
        return dc.r or 0.2, dc.g or 0.6, dc.b or 1.0
    else -- "CUSTOM"
        local dc = visual.defaultColor
        return dc.r or 0.2, dc.g or 0.6, dc.b or 1.0
    end
end

local barCount = 0

function ns:CreateBarFrame(parent)
    barCount = barCount + 1
    local name = "BarWardenBar" .. barCount
    local bar = CreateFrame("StatusBar", name, parent or UIParent, "BarWardenBarTemplate")

    bar.background = _G[name .. "Background"]
    bar.border     = _G[name .. "Border"]
    bar.icon       = _G[name .. "Icon"]

    -- In 3.3.5a, child textures/FontStrings declared inside a StatusBar
    -- template aren't always registered as globals. Fall back to creating
    -- them in Lua so icon/name/time references are never nil.
    bar.iconTexture = _G[name .. "IconIconTexture"]
    if bar.icon and not bar.iconTexture then
        bar.iconTexture = bar.icon:CreateTexture(nil, "ARTWORK")
        bar.iconTexture:SetAllPoints()
    end

    -- Cooldown spiral overlay on the icon (radial sweep driven by
    -- SetCooldown(start, duration) in ActivateBar). Hidden until a CD
    -- activates, hidden for resource bars, and hidden entirely when
    -- visual.showCooldownSpiral is false.
    if bar.icon then
        bar.cooldownFrame = CreateFrame("Cooldown", nil, bar.icon)
        bar.cooldownFrame:SetAllPoints(bar.icon)
        bar.cooldownFrame:Hide()

        -- Spell tooltip on icon hover. Only the icon frame is mouse-enabled
        -- (not the bar body) so clicks pass through to the game world.
        -- Gated on visual.showBarTooltip (default off).
        bar.icon:EnableMouse(true)
        bar.icon:SetScript("OnEnter", function(self)
            local visual = ns:GetVisual()
            if not visual.showBarTooltip then return end
            local bd = bar.barData
            if not bd then return end
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            local mode = bd.trackMode
            local sid = bd.spellId
            local sname = bd.spellName
            local iid = bd.itemId
            if mode == "Item" and iid then
                GameTooltip:SetHyperlink("item:" .. iid)
            elseif sid then
                GameTooltip:SetHyperlink("spell:" .. sid)
            elseif sname and sname ~= "" then
                local _, _, _, _, _, _, _, _, _, rid = GetSpellInfo(sname)
                if rid then
                    GameTooltip:SetHyperlink("spell:" .. rid)
                else
                    GameTooltip:AddLine(sname, 1, 1, 1)
                    GameTooltip:Show()
                end
            else
                local name = ns.GetBarDisplayName and ns.GetBarDisplayName(bd) or ""
                if name ~= "" then
                    GameTooltip:AddLine(name, 1, 1, 1)
                    GameTooltip:Show()
                end
            end
        end)
        bar.icon:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
    end

    -- Spark must be created before name/time so that, within the OVERLAY
    -- layer, WoW's creation-order rule draws the text on top of it.
    bar.sparkFrame = bar:CreateTexture(nil, "OVERLAY")
    bar.sparkFrame:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
    bar.sparkFrame:SetBlendMode("ADD")
    bar.sparkFrame:SetWidth(16)
    bar.sparkFrame:SetHeight(32)
    bar.sparkFrame:SetPoint("CENTER", bar, "LEFT", 0, 0)
    bar.sparkFrame:Hide()

    bar.nameText = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.nameText:SetJustifyH("LEFT")
    bar.nameText:SetPoint("LEFT",  bar, "LEFT",  24,  0)
    bar.nameText:SetPoint("RIGHT", bar, "RIGHT", -40, 0)

    bar.timeText = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.timeText:SetJustifyH("RIGHT")
    bar.timeText:SetPoint("RIGHT", bar, "RIGHT", -4, 0)

    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    bar:SetStatusBarTexture(TEXTURES["Flat"])
    bar:GetStatusBarTexture():SetHorizTile(false)
    bar:GetStatusBarTexture():SetVertTile(false)

    bar.barData = nil

    return bar
end

-- ----------------------------------------------------------------------------
-- ApplyVisualConfig helpers, split by concern for readability.
-- Each helper receives the bar, the display-override table, the global
-- visual table, and the resolved style/dimension values it needs.
-- ----------------------------------------------------------------------------

local function ApplyIconConfig(bar, display, visual, showIcon, iconSize, style)
    if style == "ComboPoint" then showIcon = false end

    local iconOnRight = (visual.iconPosition == "RIGHT")

    if not bar.icon then return showIcon, iconOnRight end
    if not (showIcon and iconSize > 0) then
        bar.icon:Hide()
        return false, iconOnRight
    end

    bar.icon:Show()
    bar.icon:SetWidth(iconSize)
    bar.icon:SetHeight(iconSize)
    bar.icon:ClearAllPoints()
    if iconOnRight then
        bar.icon:SetPoint("RIGHT", bar, "RIGHT", 0, 0)
    else
        bar.icon:SetPoint("LEFT", bar, "LEFT", 0, 0)
    end

    -- Resolve + apply the icon texture. When resolution fails, behaviour
    -- depends on whether the user typed an explicit spell/item input:
    -- clear on explicit typo, keep engine-set icon (e.g. Enchant) otherwise.
    if bar.iconTexture then
        local barData = bar.barData
        local hasExplicitInput = barData and (
            (barData.spellName and barData.spellName ~= "") or
            barData.spellId or barData.itemId)
        local icon = ResolveBarIcon(barData)
        if icon then
            bar.iconTexture:SetTexture(icon)
        elseif hasExplicitInput then
            bar.iconTexture:SetTexture(nil)
        end
        -- Icon crop: trim border pixels to prevent stretching
        local cropEnabled
        if display.iconCrop ~= nil then
            cropEnabled = display.iconCrop
        else
            cropEnabled = (visual.iconCrop ~= false)
        end
        if cropEnabled then
            bar.iconTexture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        else
            bar.iconTexture:SetTexCoord(0, 1, 0, 1)
        end
    end

    return true, iconOnRight
end

-- layout fields:
--   style, fontSize, iconActive (bool from ApplyIconConfig), iconSize, iconOnRight
local function ApplyTextConfig(bar, display, visual, layout)
    local style    = layout.style
    local fontSize = layout.fontSize

    local showText
    if display.showName ~= nil then
        showText = display.showName
    else
        showText = visual.textEnabled ~= false
    end
    if style == "ComboPoint" then showText = false end

    local textPosition = visual.textPosition or "INSIDE_LEFT"
    local textFormat   = visual.textFormat   or "NAME_DURATION"
    local font         = visual.font         or "Fonts\\FRIZQT__.TTF"
    -- Resolve LSM font name to path if available
    if ns.LSM then
        local resolved = ns:LSMFetch("font", font)
        if resolved then font = resolved end
    end

    -- Per-bar showName guarantees valid text settings
    if display.showName then
        if fontSize <= 0 then fontSize = 11 end
        if textPosition == "NONE" then textPosition = "INSIDE_LEFT" end
    end

    local baseVisible = showText and fontSize > 0 and textPosition ~= "NONE"
    local vis = TEXT_FORMAT_VISIBILITY[textFormat] or TEXT_FORMAT_VISIBILITY.NAME_DURATION
    local showNameText = baseVisible and vis.name
    local showTimeText = baseVisible and vis.time

    local iconActive      = layout.iconActive
    local iconSize        = layout.iconSize
    local iconOnRight     = layout.iconOnRight
    local leftOffset      = (iconActive and not iconOnRight) and (iconSize + 4) or 4
    local rightOffset     = (iconActive and iconOnRight) and -(iconSize + 4) or -4
    local nameRightOffset = rightOffset - 40

    if bar.nameText then
        if showNameText then
            bar.nameText:Show()
            bar.nameText:SetFont(font, fontSize, "OUTLINE")
            bar.nameText:ClearAllPoints()
            if textPosition == "INSIDE_RIGHT" then
                bar.nameText:SetJustifyH("RIGHT")
                bar.nameText:SetPoint("LEFT",  bar, "LEFT",  leftOffset + 40, 0)
                bar.nameText:SetPoint("RIGHT", bar, "RIGHT", rightOffset,     0)
            else
                bar.nameText:SetJustifyH("LEFT")
                bar.nameText:SetPoint("LEFT",  bar, "LEFT",  leftOffset,      0)
                bar.nameText:SetPoint("RIGHT", bar, "RIGHT", nameRightOffset, 0)
            end
            bar.nameText:SetText(ns.GetBarDisplayName(bar.barData))
        else
            bar.nameText:Hide()
        end
    end

    if bar.timeText then
        if showTimeText then
            bar.timeText:Show()
            bar.timeText:SetFont(font, fontSize, "OUTLINE")
            bar.timeText:ClearAllPoints()
            if textPosition == "INSIDE_RIGHT" then
                bar.timeText:SetJustifyH("LEFT")
                bar.timeText:SetPoint("LEFT", bar, "LEFT", leftOffset, 0)
            else
                bar.timeText:SetJustifyH("RIGHT")
                bar.timeText:SetPoint("RIGHT", bar, "RIGHT", rightOffset, 0)
            end
        else
            bar.timeText:Hide()
        end
    end
end

-- Apply all current visual settings to `bar`. Safe to call repeatedly;
-- always reads from ns:GetVisual() and the bar's own display overrides.
function ns:ApplyVisualConfig(bar, config)
    if not bar then return end

    local visual = ns:GetVisual()
    local display = config or (bar.barData and bar.barData.display) or {}

    -- Resolve style and dimensions
    local style    = display.style or "Full"
    local iconSize = visual.iconSize or 20
    local fontSize = visual.fontSize or 11
    if style == "Compact" then
        local barHeight = visual.barHeight or 20
        iconSize = max(barHeight * 0.6, 8)
        fontSize = max(fontSize - 2, 7)
    elseif style == "ComboPoint" then
        iconSize = 0
        fontSize = 0
    end

    -- Texture and colour
    local textureName = display.textureOverride or visual.texture or "Flat"
    if textureName == "Custom" and visual.customTexture and visual.customTexture ~= "" then
        textureName = visual.customTexture
    end
    bar:SetStatusBarTexture(ResolveTexture(textureName))

    local r, g, b = GetBarColor(bar, config)
    bar:SetStatusBarColor(r, g, b)

    if bar.background then
        bar.background:SetVertexColor(0, 0, 0, display.barAlpha or 0.6)
    end
    if bar.border then
        bar.border:SetVertexColor(0, 0, 0, 0.8)
    end

    -- Per-bar display.showIcon is authoritative; fall back to global
    local showIcon
    if display.showIcon ~= nil then
        showIcon = display.showIcon
    else
        showIcon = visual.showIcon ~= false
    end

    -- Delegate to helpers
    local iconActive, iconOnRight = ApplyIconConfig(bar, display, visual, showIcon, iconSize, style)
    ApplyTextConfig(bar, display, visual, {
        style       = style,
        fontSize    = fontSize,
        iconActive  = iconActive,
        iconSize    = iconSize,
        iconOnRight = iconOnRight,
    })

    -- Spark
    local showSpark = visual.showSpark ~= false
    if style == "ComboPoint" then showSpark = false end
    if bar.sparkFrame then
        if showSpark then bar.sparkFrame:Show() else bar.sparkFrame:Hide() end
    end

    -- Cooldown spiral: ApplyVisualConfig only ENFORCES the toggle (hides it
    -- when the user turned it off). The per-bar show/hide + SetCooldown call
    -- lives in BarEngine's ActivateBar / DeactivateBar / UpdateResourceBar.
    if bar.cooldownFrame and visual.showCooldownSpiral == false then
        bar.cooldownFrame:Hide()
    end
end

