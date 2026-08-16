-- Bar.lua - Bar frame construction and visual config.
-- Author:  Serv
-- Source:  https://github.com/powerfulqa/BarWarden
-- License: GNU GPL v3 (see LICENSE); attribution preservation is required.

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

-- X-Perl's bar textures (GNU GPL v3, see LICENSE and NOTICE.md). Keyed by
-- the same names SharedMedia.lua registers with LSM, so a saved texture
-- choice resolves identically whether or not LSM is present - without this,
-- a unit frame would silently fall back to Flat on an LSM-less client and
-- the Frames tab's default would look broken through no fault of the user.
local XP = "Interface\\AddOns\\BarWarden\\Textures\\XPerl\\"
TEXTURES["XP Perl v2"] = XP .. "XPerl_StatusBar.blp"
for i = 2, 10 do
    TEXTURES["XP Perl " .. i] = XP .. "XPerl_StatusBar" .. i .. ".blp"
end

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

-- Memoises spellId -> resolved name (or `false` for an id GetSpellInfo does
-- not know) so a bar configured purely by ID doesn't pay for a fresh
-- GetSpellInfo call on every activation/deactivation, which is called on
-- the 4 Hz scan loop; the id -> name mapping is stable for the session,
-- so this needs invalidation on a spell edit, not an expiry. Wiped by
-- ns:InvalidateTrackedNames (BarEngine.lua) alongside the tracked-name
-- cache, since both go stale on the same "a bar's spell can change" edits
-- (ns:RefreshBarSettings and the spell/name edit boxes in Options_Bars.lua).
local displayNameCache = {}

function ns:InvalidateBarDisplayNameCache()
    wipe(displayNameCache)
end

-- Resolve the id to look a display name up under, or nil if this bar has
-- none. Mirrors getSpell (Trackers.lua) and ns:GetTrackedAuraNames: a bare
-- numeric barData.spellName is treated as an id there too (the editor
-- routes a typed-in numeric straight to spellId, but an imported or
-- hand-edited profile can still carry one in spellName), so this has to
-- agree rather than show the digits as if they were a real name.
local function ResolveDisplayNameId(barData)
    if barData.spellId then return barData.spellId end
    if type(barData.spellName) == "string" then
        return tonumber(barData.spellName)
    end
    return nil
end

function ns.GetBarDisplayName(barData)
    if not barData then return "" end
    if barData.name and barData.name ~= "" then
        return barData.name
    end

    local spellId = ResolveDisplayNameId(barData)
    if not spellId then return "" end

    local cached = displayNameCache[spellId]
    if cached == nil then
        -- GetSpellInfo returns nil for an id the client's spell table does
        -- not know (a custom private-server id, for example); fall back to
        -- the same blank this function always returned rather than error
        -- or display "nil".
        cached = GetSpellInfo(spellId) or false
        displayNameCache[spellId] = cached
    end
    return cached or ""
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

-- Smoothly interpolates between COLOR_HIGH/MED/LOW based on remaining seconds,
-- unless Bar Alerts has taken over (ns:GetBarAlertColor, Conditions.lua): an
-- explicit "flash this exact colour right now" is a more specific instruction
-- than the ambient gradient, and checking it first also means a bar gets its
-- alert colour even with Colour by Time switched off, which is the common
-- case for this feature - a bar that only wants the one alert cue near the
-- end, not a colour that drifts for its entire active life.
-- Returns (r, g, b) or nil if neither is active.
function ns.GetTimeBasedColor(remaining, display, visual, duration)
    if not display then return nil end

    local ar, ag, ab = ns:GetBarAlertColor(display, remaining, duration)
    if ar then return ar, ag, ab end

    if not display.colorByTime then return nil end

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

-- Exposed so a unit frame can draw its bar-background texture with the same
-- resolution rules (own table, then LSM, then raw path) the bar fill itself
-- uses. Without a shared resolver the background would need a second copy of
-- that fallback chain, and the two would drift the first time a texture is
-- added to one list and not the other.
function ns:ResolveTextureName(name)
    return ResolveTexture(name)
end

-- Resolve the group config for a bar (nil-safe). Used for group-level visual
-- overrides that fall back to the global default when unset.
local function GetBarGroup(bar)
    local idx = bar.frameIndex
    if not idx then return nil end
    return ns.db and ns.db.frames and ns.db.frames[idx]
end

local function GetBarColor(bar, config)
    -- Per-bar override wins over any group or global mode.
    local display = bar.barData and bar.barData.display
    if display and display.colorOverride then
        local c = display.colorOverride
        return c.r or 1, c.g or 1, c.b or 1
    end

    -- Resource bars (v2.5.0): a per-pinned-resource colour is the next most
    -- specific, ahead of the group's Custom Bar Colour - see the precedence
    -- comment above ns:GetResourcePowerColor (Conditions.lua).
    if bar.isResourceBar then
        local rr, rg, rb = ns:GetPinnedResourceColor(bar)
        if rr then return rr, rg, rb end
    end

    -- Group-level colour override sits between per-bar and global: a group can
    -- give all its bars a colour without touching every bar or the whole addon.
    local group = GetBarGroup(bar)
    if group and group.barColor then
        local c = group.barColor
        return c.r or 1, c.g or 1, c.b or 1
    end

    -- Resource bars fall back to the game's own power-type colour (mana
    -- blue, rage red, and so on) before the addon-wide default below.
    if bar.isResourceBar then
        local pr, pg, pb = ns:GetResourcePowerColor(bar)
        if pr then return pr, pg, pb end
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
            local shown = false
            if mode == "Item" and iid then
                GameTooltip:SetHyperlink("item:" .. iid)
                shown = true
            elseif sid then
                GameTooltip:SetHyperlink("spell:" .. sid)
                shown = true
            elseif sname and sname ~= "" then
                local _, _, _, _, _, _, _, _, _, rid = GetSpellInfo(sname)
                if rid then
                    GameTooltip:SetHyperlink("spell:" .. rid)
                else
                    GameTooltip:AddLine(sname, 1, 1, 1)
                end
                shown = true
            else
                local name = ns.GetBarDisplayName and ns.GetBarDisplayName(bd) or ""
                if name ~= "" then
                    GameTooltip:AddLine(name, 1, 1, 1)
                    shown = true
                end
            end
            if shown then
                -- Auto-tracking groups fill and empty themselves, so alt-click
                -- is the one per-spell escape hatch; say so every time.
                if bar.isAutoBar then
                    GameTooltip:AddLine("Alt-click hides this from the group.", 0.6, 0.6, 0.6)
                end
                -- Re-Show after the extra AddLine so the tooltip resizes to
                -- fit it; SetHyperlink already shows the tooltip on its own,
                -- so this is a harmless repeat there rather than a new call.
                GameTooltip:Show()
            end
        end)
        bar.icon:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        -- Alt-left-click bans this bar's spell from the group, per group. The
        -- icon is the only mouse-enabled part of a bar (bars themselves stay
        -- mouse-disabled so clicks pass through to the world), and isAutoBar
        -- restricts this to auto-tracking slots so a stray alt-click on an
        -- ordinary bar can never ban anything.
        bar.icon:SetScript("OnMouseUp", function(self, button)
            if button ~= "LeftButton" or not IsAltKeyDown() then return end
            if not bar.isAutoBar then return end
            local bd = bar.barData
            if not bd then return end
            local name = bd.name
            if not name or name == "" then return end
            local frameIndex = bar.frameIndex
            if not frameIndex then return end
            local groupData = BarWardenDB and BarWardenDB.frames and BarWardenDB.frames[frameIndex]
            if not groupData then return end

            groupData.autoBanned = groupData.autoBanned or {}
            groupData.autoBanned[string.lower(name)] = { name = name, id = bd.spellId }

            if ns.InvalidateTrackedNames then ns:InvalidateTrackedNames() end
            if ns.ScanAutoGroup then ns:ScanAutoGroup(frameIndex) end
            ns:Print(name .. " hidden from " .. (groupData.name or "this group") .. ".")
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

    -- Stack badge: the count of whatever the bar tracks, in the icon's corner
    -- like the default UI. Parented to the icon frame because a child frame
    -- draws above its parent's OVERLAY layer, so a bar-parented badge would
    -- sit behind the icon. ns:RenderBarStacks reparents it to the bar when
    -- the icon is hidden, and also applies the resolved Stack Text Size /
    -- Stack Text Colour on every render (ns:GetStackFontSize / ns:GetStackColor,
    -- Conditions.lua: bar override, then group, then the Visuals tab
    -- default). The template here only seeds the initial size/colour
    -- (matching the addon-wide default) so an inactive bar built before its
    -- first render still looks right; the font family itself is not the
    -- configured bar font, so the number stays legible whatever font the
    -- bars use.
    local stackParent = bar.icon or bar
    bar.stackText = stackParent:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    bar.stackText:SetJustifyH("RIGHT")
    bar.stackText:Hide()

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

local function ApplyIconConfig(bar, display, visual, showIcon, iconSize, style, iconOnly)
    if style == "ComboPoint" then showIcon = false end

    local iconOnRight = (visual.iconPosition == "RIGHT")

    if not bar.icon then return showIcon, iconOnRight end
    if not (showIcon and iconSize > 0) then
        bar.icon:Hide()
        return false, iconOnRight
    end

    bar.icon:Show()
    bar.icon:ClearAllPoints()
    if iconOnly then
        -- Icon-only groups draw square cells sized entirely by the group's
        -- Width setting (ns:UpdateGroupLayout sets both bar dimensions from
        -- it). Anchoring to fill the bar, rather than a fixed pixel size,
        -- keeps the icon in sync with that cell as it resizes with no
        -- separate code path needed to re-apply a new icon size.
        bar.icon:SetAllPoints(bar)
    else
        bar.icon:SetWidth(iconSize)
        bar.icon:SetHeight(iconSize)
        if iconOnRight then
            bar.icon:SetPoint("RIGHT", bar, "RIGHT", 0, 0)
        else
            bar.icon:SetPoint("LEFT", bar, "LEFT", 0, 0)
        end
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
--   style, fontSize, iconActive (bool from ApplyIconConfig), iconSize,
--   iconOnRight, iconOnly (group.iconOnly)
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
    -- Resolved, not raw: the bar's group may override the global text format,
    -- and the name/time fontstring visibility has to match what will be drawn.
    local textFormat   = (ns.GetBarTextFormat and ns:GetBarTextFormat(bar))
                         or visual.textFormat or "NAME_DURATION"
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
    -- Icon Only groups show nothing but the icon, whatever the resolved text
    -- format says. This overrides the format-driven visibility above rather
    -- than short-circuiting earlier, so a bar returning to a normal group
    -- always falls back to a value this function computed fresh, never a
    -- stale leftover from when it was icon-only.
    if layout.iconOnly then
        showNameText = false
        showTimeText = false
    end

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

    -- Texture and colour. Resolution order: per-bar override, then group
    -- override, then the addon-wide default. Any unset level is skipped.
    local group = GetBarGroup(bar)
    -- Icon Only groups (any group, see Options_Bars.lua's Bar Overrides
    -- block) show just the spell icon: no fill, no background, no border, no
    -- spark, no text. Resolved fresh on every call (not stored on the bar),
    -- so a bar rebuilt into a different group - through the shared pool, via
    -- ns:BuildBarsForFrame - always ends up in the state ITS group asks for,
    -- with nothing left over from whatever group used it before.
    local iconOnly = group and group.iconOnly
    local textureName = display.textureOverride
        or (group and group.barTexture)
        or visual.texture or "Flat"
    if textureName == "Custom" and visual.customTexture and visual.customTexture ~= "" then
        textureName = visual.customTexture
    end
    bar:SetStatusBarTexture(ResolveTexture(textureName))

    local r, g, b = GetBarColor(bar, config)
    bar:SetStatusBarColor(r, g, b)

    -- Fill: hide by zeroing the status bar texture's own alpha rather than
    -- the vertex colour (SetStatusBarColor above has no alpha channel in
    -- 3.3.5a), so GetBarColor's resolved colour is untouched underneath.
    local fillTexture = bar:GetStatusBarTexture()
    if fillTexture then
        fillTexture:SetAlpha(iconOnly and 0 or 1)
    end

    if bar.background then
        bar.background:SetVertexColor(0, 0, 0, iconOnly and 0 or (display.barAlpha or 0.6))
    end
    if bar.border then
        bar.border:SetVertexColor(0, 0, 0, iconOnly and 0 or 0.8)
    end

    -- Per-bar display.showIcon is authoritative; a resource bar's group can
    -- override the global default next (Options_Bars.lua's Show Icon
    -- tickbox, resources feed only - an auto slot has no per-bar display of
    -- its own to set showIcon on, so this is the only override that ever
    -- actually reaches a resource bar in practice); fall back to global.
    local showIcon
    if display.showIcon ~= nil then
        showIcon = display.showIcon
    elseif bar.isResourceBar and group and group.autoResourceShowIcon ~= nil then
        showIcon = group.autoResourceShowIcon
    else
        showIcon = visual.showIcon ~= false
    end

    -- Delegate to helpers
    local iconActive, iconOnRight = ApplyIconConfig(bar, display, visual, showIcon, iconSize, style, iconOnly)
    ApplyTextConfig(bar, display, visual, {
        style       = style,
        fontSize    = fontSize,
        iconActive  = iconActive,
        iconSize    = iconSize,
        iconOnRight = iconOnRight,
        iconOnly    = iconOnly,
    })

    -- Spark
    local showSpark = visual.showSpark ~= false
    if style == "ComboPoint" or iconOnly then showSpark = false end
    if bar.sparkFrame then
        if showSpark then bar.sparkFrame:Show() else bar.sparkFrame:Hide() end
    end

    -- Cooldown spiral: ApplyVisualConfig only ENFORCES the toggle (hides it
    -- when the user turned it off). The per-bar show/hide + SetCooldown call
    -- lives in BarEngine's ActivateBar / DeactivateBar / UpdateResourceBar.
    if bar.cooldownFrame and visual.showCooldownSpiral == false then
        bar.cooldownFrame:Hide()
    end

    -- Stack badge last: it re-anchors against the icon, so it must run after
    -- ApplyIconConfig has settled the icon's visibility and size.
    if ns.RenderBarStacks then ns:RenderBarStacks(bar) end
end

