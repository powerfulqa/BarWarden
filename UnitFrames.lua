-- UnitFrames.lua - Unit frame widget: portrait + name/level + health/power
-- bars + a values column, driven by a unit token.
-- Author:  Serv
-- Source:  https://github.com/powerfulqa/BarWarden
-- License: GNU GPL v3 (see LICENSE); attribution preservation is required.

local addonName, ns = ...

-- ============================================================================
-- UnitFrames.lua
--
-- A second, separate way to show the same data a resource group already can
-- (see ns:CollectResources, Trackers.lua): the owner found a resource group
-- reads as "bars in a box" and wanted the conventional arrangement instead -
-- portrait on the left, a name/level header, health and power bars stacked
-- tightly, and a values column on the right with both the raw numbers and a
-- percentage. Resource groups are untouched by this file; both stay as
-- separate, equally-supported options.
--
-- This first slice builds the widget and the player frame only. Everything
-- below is keyed by a unit token (UNIT_TOKENS / UNIT_FRAME_KEYS) rather than
-- hardcoding "player", so target/pet/focus/party frames in a later slice are
-- a new key plus a token mapping, not a new widget.
--
-- Positioning/dragging/rescaling is NOT a second implementation: it reuses
-- ns:ApplySavedFramePosition, ns:OnFrameDragStart, ns:OnFrameDragStop, and
-- ns:RescaleFrame (all FrameManager.lua, extracted from the group-frame code
-- specifically so this file could reuse them - see that file's comment
-- above ns:ApplySavedFramePosition). Bars are borrowed from the shared pool
-- via ns:AcquireBar/ns:ReleaseBar (BarPool.lua), the same as every other bar
-- in the addon; no CreateFrame("StatusBar") appears here, so the rule in
-- CLAUDE.md/ADDON_GUIDE.md needed no change. Resource data comes from
-- ns:CollectResources (Trackers.lua) and is drawn through the existing
-- ns:UpdateResourceBar (BarEngine.lua), so colouring, the rune-pair view, and
-- every other resource-bar behaviour documented there applies here for free.
-- Updates ride the existing 0.25s scan loop (ns:ScanUnitFrames is called
-- from Core.lua's OnUpdate ticker, right alongside ns:ScanAllBars) rather
-- than a second OnUpdate frame.
-- ============================================================================

local floor = math.floor
local max   = math.max

ns.unitFrames = {}  -- [key] = WoW frame object, mirrors ns.groupFrames

-- Unit token each frame key reads. "player" is the only one this slice
-- builds; UNIT_FRAME_KEYS (the scan/rebuild iteration order) is a separate
-- list below so a later slice adds one line to each rather than restructuring
-- either loop.
local UNIT_TOKENS = {
    player = "player",
}
local UNIT_FRAME_KEYS = { "player" }

-- Pre-allocated resource-row slots. ns:CollectResources for the player
-- returns at most health + current power + a handful of class resources
-- (six rune slots is the largest single feed), so this comfortably covers
-- every case with room to spare, matching the headroom a resource
-- auto-tracking group gets from its own (user-configurable) Max Bars.
local MAX_UNIT_FRAME_SLOTS = 10

-- ----------------------------------------------------------------------------
-- Pure layout constants + arithmetic. No frame objects are touched by
-- anything in this section, so it is fully unit-testable (tests/test_unit_frames.lua).
-- ----------------------------------------------------------------------------

local UF_BAR_WIDTH    = 120
local UF_BAR_HEIGHT   = 16
local UF_BAR_SPACING  = 1
local UF_HEADER_HEIGHT = 14
local UF_PADDING       = 4

-- Bounds for the Bar Height setting. The floor is the point below which the
-- value text stops fitting on a bar at all; the ceiling just stops a typo or
-- a hand-edited profile producing a frame taller than the screen.
local UF_MIN_BAR_HEIGHT = 8
local UF_MAX_BAR_HEIGHT = 40

-- Fallback width for the values column, used only until the first scan has
-- real text to measure (see ns:MeasureUnitFrameValuesWidth and the
-- measured-width note above it). Deliberately narrow: the frame widens to
-- fit on the very next tick, and starting narrow-then-growing looks better
-- than starting wide-then-shrinking.
local UF_VALUES_MIN_WIDTH = 40

-- X-Perl's own frame backdrop, reproduced with its geometry exactly as
-- XPerl_BorderStyleTemplate declares it (XPerl_Globals.xml): its
-- XPerl_FrameBack tile, Blizzard's tooltip border, edge 16, tile 32, inset
-- 4. The artwork is GPL v3 and redistributed under that licence - it is the
-- reason this addon is GPL at all (see LICENSE and NOTICE.md).
--
-- This deliberately does NOT reuse ns.GROUP_BACKDROP: a bar group is a
-- container the player positions and should recede, whereas a unit frame is
-- meant to read as a piece of UI in its own right, the way the frames it
-- replaces do. They looked identical before this and that was the single
-- biggest reason the unit frame read as unfinished next to X-Perl.
local UNIT_FRAME_BACKDROP = {
    bgFile   = "Interface\\AddOns\\BarWarden\\Textures\\XPerl\\XPerl_FrameBack",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 32, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

-- Inset from the portrait's own border to the portrait art, matching
-- XPerl_Portrait_Template (a 60x62 bordered frame around a 50x50 portrait).
local UF_PORTRAIT_INSET = 5

-- How much of each edge of a unit portrait to crop away. Blizzard's portrait
-- images carry a transparent margin around a circular subject; this is the
-- long-standing value that trims it without cutting into the face.
local UF_PORTRAIT_CROP = 0.15

-- Default bar texture for a unit frame. Registered by both SharedMedia.lua
-- (for LSM) and Bar.lua (for the LSM-less fallback) under this exact name,
-- so the default resolves either way.
local UF_DEFAULT_TEXTURE = "XP Perl v2"

-- Which optional elements a unit frame currently shows, resolved from its
-- saved config. Nil-safe (a not-yet-built cfg reads as "show everything",
-- matching ns.DEFAULTS.unitFrames.player) so this can be called defensively
-- from anywhere without a live frame or a populated DB.
-- `values` is specifically "a values COLUMN is drawn", because that is the
-- only element that changes the layout arithmetic - values drawn on the bars
-- reserve no width. Placement is resolved here rather than at each use site
-- so the two settings that produce it (Show Values, and where) are read in
-- exactly one place: showValues == false must win over any placement, and
-- splitting that rule across callers is how one of them ends up disagreeing.
function ns:ResolveUnitFrameElements(cfg)
    cfg = cfg or {}
    local showValues = cfg.showValues ~= false
    local onBar = showValues and cfg.valuePlacement == "ONBAR"
    return {
        portrait    = cfg.showPortrait ~= false,
        level       = cfg.showLevel ~= false,
        values      = showValues and not onBar,
        valuesOnBar = onBar,
        barHeight   = cfg.barHeight,
    }
end

-- Pure layout arithmetic for the widget: given which optional elements are
-- shown and how many resource rows this scan collected, compute the frame's
-- overall size and where each piece anchors. ns:LayoutUnitFrame below is the
-- thin impure layer that feeds these numbers into SetPoint/SetSize calls.
--
-- The header (portrait-adjacent name/level text) is not itself an optional
-- element - a unit frame always has a name - only whether the level is
-- appended to it is a toggle (ns:ResolveUnitFrameElements above), so it does
-- not change this arithmetic at all.
-- `measuredValuesWidth` is the width the widest values-column string
-- actually needs, measured from the live fontstrings by
-- ns:MeasureUnitFrameValuesWidth. It is a parameter rather than a constant
-- because a fixed width is what broke this column in the first place: a
-- FontString given an explicit width wraps at spaces on 3.3.5a (there is no
-- SetWordWrap before 4.0), so "2489 / 2489 (100%)" in a 74px column split
-- across two lines and every row collided with the row beneath it. The
-- column is now never given a width at all - it cannot wrap - and the frame
-- widens to fit instead. Nil (no measurement yet) falls back to a narrow
-- starting width.
function ns:ComputeUnitFrameLayout(elements, barCount, measuredValuesWidth)
    elements = elements or {}
    barCount = max(barCount or 0, 1)

    -- Bar height is a setting (X-Perl's bars are chunkier than the 14px this
    -- started at, and a values-on-the-bar frame needs the room), clamped so
    -- a hand-edited or imported profile cannot produce a frame with
    -- zero-height or absurd rows.
    local barHeight = elements.barHeight or UF_BAR_HEIGHT
    if barHeight < UF_MIN_BAR_HEIGHT then barHeight = UF_MIN_BAR_HEIGHT end
    if barHeight > UF_MAX_BAR_HEIGHT then barHeight = UF_MAX_BAR_HEIGHT end

    local barsHeight = barCount * barHeight + (barCount - 1) * UF_BAR_SPACING
    local bodyHeight = UF_HEADER_HEIGHT + barsHeight
    local portraitSize = elements.portrait and bodyHeight or 0

    -- Left edge of the body sits inside the backdrop's own 4px inset, so the
    -- artwork's border never overlaps the portrait or the first bar.
    local bodyX = UF_PADDING
    local barsX = bodyX + ((portraitSize > 0) and (portraitSize + UF_PADDING) or 0)

    local valuesWidth = 0
    if elements.values then
        valuesWidth = max(measuredValuesWidth or 0, UF_VALUES_MIN_WIDTH)
    end
    local valuesX = barsX + UF_BAR_WIDTH + (valuesWidth > 0 and UF_PADDING or 0)

    return {
        width        = valuesX + valuesWidth + UF_PADDING,
        height       = bodyHeight + UF_PADDING * 2,
        portraitSize = portraitSize,
        portraitInset = UF_PORTRAIT_INSET,
        bodyX        = bodyX,
        barsX        = barsX,
        barsTop      = UF_PADDING + UF_HEADER_HEIGHT,
        valuesX      = valuesX,
        valuesWidth  = valuesWidth,
        barWidth     = UF_BAR_WIDTH,
        barHeight    = barHeight,
        barSpacing   = UF_BAR_SPACING,
    }
end

-- Width the values column needs to show every visible row without wrapping,
-- measured from the live fontstrings. GetStringWidth reports a FontString's
-- natural single-line width, which is only meaningful because these
-- fontstrings are never given an explicit width - see the note on
-- ns:ComputeUnitFrameLayout above.
--
-- Called only when a values string actually changed (ScanUnitFrame diffs
-- them already), so a frame whose numbers are steady pays nothing, and a
-- frame whose numbers tick pays a handful of GetStringWidth calls - the same
-- order of cost as the UnitHealth/UnitPower reads that produced them.
function ns:MeasureUnitFrameValuesWidth(valueTexts, count)
    local widest = 0
    for i = 1, count do
        local fs = valueTexts[i]
        if fs and fs:IsShown() then
            local w = fs:GetStringWidth() or 0
            if w > widest then widest = w end
        end
    end
    -- Ceil to a whole pixel: a fractional width would differ from the stored
    -- value on every comparison and re-layout the frame on every single tick.
    return floor(widest + 0.999)
end

-- Values-column text for one resource row: the raw current/max fraction plus
-- a percentage, e.g. "3000 / 4500 (67%)" - both pieces the owner asked for,
-- on one line so a tightly-stacked bar still has room for it. A resource
-- with no real max (should not happen for anything ns:CollectResources
-- returns, which already skips max <= 0, but this is guarded independently
-- so a malformed private-server read degrades to the bare current value
-- instead of dividing by zero) just shows the current number. Percent is
-- clamped to 0-100 so a stale server read just above full doesn't print
-- "104%".
function ns:FormatUnitFrameValue(current, max_)
    current = current or 0
    if not max_ or max_ <= 0 then
        return tostring(current)
    end
    local pct = current / max_
    if pct < 0 then pct = 0 elseif pct > 1 then pct = 1 end
    return string.format("%d / %d (%d%%)", current, max_, floor(pct * 100 + 0.5))
end

-- ----------------------------------------------------------------------------
-- Impure: frame construction, layout application, scanning, teardown.
-- ----------------------------------------------------------------------------

-- Apply a layout computed by ns:ComputeUnitFrameLayout to the live frame:
-- resize it, place the portrait/header, and position every bar + values
-- text. Only called when the number of resource rows actually changes
-- (see ScanUnitFrame below) - a per-scan reformat of unchanged geometry
-- would be exactly the kind of per-frame-path work CLAUDE.md asks this
-- slice to avoid.
local function LayoutUnitFrame(frame, elements, barCount, measuredValuesWidth)
    local layout = ns:ComputeUnitFrameLayout(elements, barCount, measuredValuesWidth)

    frame:SetWidth(layout.width)
    frame:SetHeight(layout.height)

    if frame.portraitFrame then
        if elements.portrait then
            frame.portraitFrame:ClearAllPoints()
            frame.portraitFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", layout.bodyX, -UF_PADDING)
            frame.portraitFrame:SetWidth(layout.portraitSize)
            frame.portraitFrame:SetHeight(layout.portraitSize)
            frame.portraitFrame:Show()
        else
            frame.portraitFrame:Hide()
        end
    end

    -- The header strip spans the bars and the values column together, so the
    -- name and the numbers share one band across the top of the frame.
    if frame.headerStrip then
        frame.headerStrip:ClearAllPoints()
        frame.headerStrip:SetPoint("TOPLEFT", frame, "TOPLEFT", layout.barsX, -UF_PADDING)
        frame.headerStrip:SetWidth(layout.valuesX + layout.valuesWidth - layout.barsX)
        frame.headerStrip:SetHeight(UF_HEADER_HEIGHT)
    end

    frame.nameText:ClearAllPoints()
    frame.nameText:SetPoint("LEFT", frame, "TOPLEFT",
        layout.barsX + 3, -(UF_PADDING + UF_HEADER_HEIGHT / 2))
    frame.nameText:SetPoint("RIGHT", frame, "TOPLEFT",
        layout.valuesX + layout.valuesWidth - 3, -(UF_PADDING + UF_HEADER_HEIGHT / 2))

    for i = 1, MAX_UNIT_FRAME_SLOTS do
        local bar = frame.bars[i]
        local y = -(layout.barsTop + (i - 1) * (layout.barHeight + layout.barSpacing))

        bar:ClearAllPoints()
        bar:SetPoint("TOPLEFT", frame, "TOPLEFT", layout.barsX, y)
        bar:SetWidth(layout.barWidth)
        bar:SetHeight(layout.barHeight)

        -- The unfilled remainder of a bar. Without this a resource sitting at
        -- zero (an out-of-combat rage bar, a spent rune) drew as a bare hole
        -- in the backdrop rather than as an empty bar.
        local bg = frame.barBackdrops[i]
        bg:ClearAllPoints()
        bg:SetPoint("TOPLEFT", frame, "TOPLEFT", layout.barsX, y)
        bg:SetWidth(layout.barWidth)
        bg:SetHeight(layout.barHeight)

        -- Anchored by its RIGHT edge with no width set, so it right-aligns
        -- against the frame edge and never wraps. See ns:ComputeUnitFrameLayout.
        local valueText = frame.valueTexts[i]
        valueText:ClearAllPoints()
        valueText:SetPoint("RIGHT", frame, "TOPLEFT",
            layout.valuesX + layout.valuesWidth, y - layout.barHeight / 2)
    end

    frame.lastLayoutBarCount = barCount
    frame.lastValuesWidth = layout.valuesWidth
    -- The MEASUREMENT this layout was built from, kept separate from the
    -- width actually applied. They differ whenever the measurement falls
    -- under UF_VALUES_MIN_WIDTH, and comparing the next measurement against
    -- the applied width instead would then never match - re-laying the frame
    -- out on every tick that touched a number.
    frame.lastValuesMeasured = measuredValuesWidth or 0
    return layout
end

-- Build the frame for `key` (currently only ever "player"). Bars are
-- acquired from the shared pool exactly like an auto-tracking resource
-- group's slots (see NewAutoBarData, FrameManager.lua): each carries a
-- runtime-only barData, never written to SavedVariables. frameIndex is
-- deliberately left nil (unlike a group's bars) - that integer indexes
-- BarWardenDB.frames (bar GROUPS), a different table this widget has
-- nothing to do with, so leaving it unset is what keeps every frameIndex-
-- gated resolver (GetBarColor's per-group override, GetBarTextFormat's
-- group text format, and so on) a harmless no-op here rather than a
-- collision with an unrelated group.
local function BuildUnitFrame(key)
    local unit = UNIT_TOKENS[key]
    local cfg = ns.db and ns.db.unitFrames and ns.db.unitFrames[key]
    if not unit or not cfg then return nil end

    -- The bar texture this frame draws with, resolved up front because both
    -- the header strip and every bar background need it. Applied to the bars
    -- themselves as a per-bar textureOverride (the highest-precedence level
    -- ns:ApplyVisualConfig resolves) rather than left to the addon-wide
    -- visual.texture: a unit frame should look like a unit frame regardless
    -- of the texture chosen for timer bars. It is still a setting, so anyone
    -- who wants them to match can say so.
    local barTexture = cfg.barTexture or UF_DEFAULT_TEXTURE

    local frame = CreateFrame("Frame", "BarWardenUnitFrame" .. key, UIParent)
    frame.isUnitFrame = true
    frame.unitKey = key

    frame:SetBackdrop(UNIT_FRAME_BACKDROP)
    -- White backdrop colour so XPerl_FrameBack's own artwork shows through
    -- untinted, the way X-Perl draws it. Tinting it (as the bar-group
    -- backdrop does with a black fill) would just mute the texture we went
    -- to the trouble of licensing.
    frame:SetBackdropColor(1, 1, 1, 1)
    frame:SetBackdropBorderColor(1, 1, 1, 1)
    frame:SetWidth(160)
    frame:SetHeight(40)  -- placeholder; the first ScanUnitFrame pass resizes it

    ns:ApplySavedFramePosition(frame, cfg.position,
        { point = "CENTER", relativePoint = "CENTER", x = 0, y = 0 })

    local scale = math.max(ns.MIN_FRAME_SCALE, math.min(ns.MAX_FRAME_SCALE, cfg.scale or 1.0))
    frame:SetScale(scale)

    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", ns.OnFrameDragStart)
    frame:SetScript("OnDragStop", function(self)
        ns:OnFrameDragStop(self, false, function(pos)
            local c = ns.db and ns.db.unitFrames and ns.db.unitFrames[key]
            if c then c.position = pos end
        end)
    end)
    if BarWardenDB and BarWardenDB.global.locked then
        frame:EnableMouse(false)
    end

    -- Portrait. SetPortraitTexture(texture, unit) is the standard 3.3.5a API;
    -- guarded with pcall since a private server is not trusted to implement
    -- it identically (per-3.3.5a-private-server rule).
    --
    -- The portrait gets its own bordered sub-frame rather than being a bare
    -- texture on the parent, matching XPerl_Portrait_Template: X-Perl's
    -- portrait is ringed by the same border as the frame body, and without
    -- that ring the portrait art just bled into the backdrop with no edge.
    local portraitFrame = CreateFrame("Frame", nil, frame)
    portraitFrame:SetBackdrop(UNIT_FRAME_BACKDROP)
    portraitFrame:SetBackdropColor(1, 1, 1, 1)
    portraitFrame:SetBackdropBorderColor(1, 1, 1, 1)
    frame.portraitFrame = portraitFrame

    local portrait = portraitFrame:CreateTexture(nil, "ARTWORK")
    portrait:SetPoint("TOPLEFT", portraitFrame, "TOPLEFT", UF_PORTRAIT_INSET, -UF_PORTRAIT_INSET)
    portrait:SetPoint("BOTTOMRIGHT", portraitFrame, "BOTTOMRIGHT", -UF_PORTRAIT_INSET, UF_PORTRAIT_INSET)
    -- SetPortraitTexture hands back a square image whose subject is a circle
    -- with transparent corners - drawn raw it reads as a small head floating
    -- in a black box, which is exactly how it looked. Cropping past the
    -- transparent margin makes the portrait fill its frame, which is what
    -- X-Perl and every other unit-frame addon does with it.
    portrait:SetTexCoord(UF_PORTRAIT_CROP, 1 - UF_PORTRAIT_CROP,
                         UF_PORTRAIT_CROP, 1 - UF_PORTRAIT_CROP)
    frame.portrait = portrait

    -- Header: name, optionally with a colour-escaped level suffix
    -- (ns:FormatUnitLevelSuffix, FrameManager.lua - already built and tested
    -- for the "Group Name Follows Target" resource-group feature; reused
    -- verbatim rather than re-implemented).
    local visual = ns:GetVisual()

    -- A strip behind the name, so the header reads as part of the frame
    -- rather than as text floating over the backdrop. X-Perl's name sits on
    -- its own panel; this is the same idea with the artwork already loaded.
    local headerStrip = frame:CreateTexture(nil, "BORDER")
    headerStrip:SetTexture(ns.ResolveTextureName and ns:ResolveTextureName(barTexture)
        or "Interface\\Buttons\\WHITE8x8")
    headerStrip:SetVertexColor(0.1, 0.1, 0.1, 0.85)
    frame.headerStrip = headerStrip

    local nameText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameText:SetJustifyH("LEFT")
    if visual.font then
        nameText:SetFont(visual.font, (visual.fontSize or 11) + 1, "OUTLINE")
    end
    frame.nameText = nameText
    frame.lastHeaderText = nil

    frame.bars = {}
    frame.valueTexts = {}
    frame.barBackdrops = {}
    for i = 1, MAX_UNIT_FRAME_SLOTS do
        -- Drawn before the bar is acquired so it sits behind it: the pool
        -- parents bars to this frame at a higher draw layer.
        local bg = frame:CreateTexture(nil, "BACKGROUND")
        bg:SetTexture(ns.ResolveTextureName and ns:ResolveTextureName(barTexture)
            or "Interface\\Buttons\\WHITE8x8")
        bg:SetVertexColor(0.15, 0.15, 0.15, 0.9)
        bg:Hide()
        frame.barBackdrops[i] = bg

        local bar = ns:AcquireBar(frame)
        bar.barData = {
            name = "", enabled = false, trackMode = "Buff", unit = unit,
            -- showIcon = false: a unit frame's bars are plain fills, not
            -- icon rows - identity lives in the header, numbers live in the
            -- values column, so a per-row icon would just be clutter.
            display = { lingerTime = 0, showIcon = false, textureOverride = barTexture },
            conditions = {},
        }
        bar.barIndex   = i
        bar.frameIndex = nil
        bar.isAutoBar  = false
        bar.isResourceBar = false
        bar.barState = ns.BAR_STATE and ns.BAR_STATE.INACTIVE or 0
        if ns.ApplyVisualConfig then ns:ApplyVisualConfig(bar) end
        bar:Hide()
        frame.bars[i] = bar

        -- No SetWidth, ever: an explicit width makes a 3.3.5a FontString
        -- wrap at spaces, which is what stacked two lines of every row on top
        -- of the row below it. Width is reserved by the frame instead
        -- (ns:MeasureUnitFrameValuesWidth).
        local valueText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        valueText:SetJustifyH("RIGHT")
        valueText:SetJustifyV("MIDDLE")
        if visual.font then
            valueText:SetFont(visual.font, visual.fontSize or 11, "OUTLINE")
        end
        -- The values column can overhang the frame edge onto the game world
        -- while the frame is mid-resize, so it carries its own shadow rather
        -- than relying on the backdrop behind it for contrast.
        valueText:SetShadowColor(0, 0, 0, 1)
        valueText:SetShadowOffset(1, -1)
        valueText:Hide()
        frame.valueTexts[i] = valueText
    end

    ns.unitFrames[key] = frame
    return frame
end

local function DestroyUnitFrame(key)
    local frame = ns.unitFrames[key]
    if not frame then return end
    ns:ReleaseFrameBars(frame)
    frame:Hide()
    frame:ClearAllPoints()
    frame:SetParent(UIParent)
    ns.unitFrames[key] = nil
end

-- Refresh one unit frame's bars, header, and values column from
-- ns:CollectResources. Called every 0.25s scan tick (ns:ScanUnitFrames
-- below), same cadence a resource auto-tracking group's slots refresh at.
--
-- Per-frame-path discipline (CLAUDE.md): the header text and each values-
-- column entry are cached and only written when they actually changed,
-- exactly as ns:ScanAutoResourceGroup (BarEngine.lua) already does for a
-- resource group's title. The full per-bar reposition (LayoutUnitFrame) is
-- similarly skipped unless the number of resource rows changed since the
-- last pass. Bar fill/colour/text is NOT diffed here beyond that: it goes
-- through ns:UpdateResourceBar, the same function every resource bar
-- (hand-placed or auto-tracked) already runs through every tick, so this
-- adds no new per-tick cost class beyond what that shared path already pays.
local function ScanUnitFrame(key)
    local frame = ns.unitFrames[key]
    if not frame then return end
    local cfg = ns.db and ns.db.unitFrames and ns.db.unitFrames[key]
    if not cfg or not cfg.enabled then return end
    local unit = UNIT_TOKENS[key]
    if not unit then return end

    local elements = ns:ResolveUnitFrameElements(cfg)
    -- pairRunes collapses six rune rows to three ready-count rows. Reused
    -- from the resource-group feature rather than reimplemented, and defaulted
    -- ON for unit frames (unlike groups, where it stays off so an existing
    -- group's six-bar view is unchanged): six full-width rune bars are the
    -- single biggest reason a frame reads as cluttered, and a frame is a new
    -- surface with no existing look to preserve.
    local entries = ns:CollectResources({
        unit = unit,
        pairRunes = cfg.pairRunes ~= false,
    })
    entries = ns:FilterResourceEntries(entries, cfg.hiddenResources)

    if frame.lastLayoutBarCount ~= #entries then
        LayoutUnitFrame(frame, elements, #entries, frame.lastValuesMeasured)
    end

    -- Header: name (+ level). Diffed against frame.lastHeaderText, a
    -- runtime-only cache field, so an unchanged header never touches the
    -- fontstring - mirrors group.lastTitleName in ns:ScanAutoResourceGroup.
    local exists = UnitExists and UnitExists(unit)
    local unitName = exists and (UnitName(unit) or "") or ""
    local levelSuffix = (elements.level and exists) and ns:FormatUnitLevelSuffix(unit) or ""
    local headerText = (levelSuffix ~= "") and (unitName .. "  " .. levelSuffix) or unitName
    if frame.lastHeaderText ~= headerText then
        frame.lastHeaderText = headerText
        frame.nameText:SetText(headerText)
    end

    -- Portrait: not diffed the way text is - there is no cheap equality
    -- check for "did the texture change" the way there is for a string, and
    -- SetPortraitTexture is a single lightweight client call, no more
    -- expensive than the UnitHealth/UnitPower reads ns:CollectResources just
    -- made above for every row. Skipped entirely while hidden.
    if elements.portrait and SetPortraitTexture then
        pcall(SetPortraitTexture, frame.portrait, unit)
    end

    local valuesChanged = false

    for i = 1, MAX_UNIT_FRAME_SLOTS do
        local bar = frame.bars[i]
        local valueText = frame.valueTexts[i]
        local barBackdrop = frame.barBackdrops[i]
        local e = entries[i]

        if e then
            local bd = bar.barData
            bd.enabled    = true
            bd.name       = e.label
            bd.resourceKey = e.key
            bd.runeType    = e.runeType
            bd.trackMode   = e.trackMode or "Buff"
            ns:UpdateResourceBar(bar, e.current, e.max, e.icon, e.label, e.stacks or e.current)
            -- The resource NAME is never drawn on the bar: the header already
            -- names the unit, and a row labelled "Health" next to a health
            -- bar tells nobody anything. The numbers are a real choice
            -- though, and this is where "on the bar" is honoured -
            -- UpdateResourceBar has just written its own text into timeText,
            -- so this overwrites it with the same string the column would
            -- have shown, keeping the two placements identical in content.
            if bar.nameText then bar.nameText:Hide() end

            local text
            if elements.values or elements.valuesOnBar then
                text = ns:FormatUnitFrameValue(e.current, e.max)
            end

            if bar.timeText then
                if elements.valuesOnBar then
                    if bar.timeText.lastUFText ~= text then
                        bar.timeText.lastUFText = text
                        bar.timeText:SetText(text)
                    end
                    bar.timeText:Show()
                else
                    bar.timeText.lastUFText = nil
                    bar.timeText:Hide()
                end
            end

            bar:Show()
            barBackdrop:Show()

            if elements.values then
                if valueText.lastText ~= text then
                    valueText.lastText = text
                    valueText:SetText(text)
                    valuesChanged = true
                end
                valueText:Show()
            else
                valueText:Hide()
            end
        else
            if bar.barData.enabled then
                bar.barData.enabled = false
                bar.barData.resourceKey = nil
                bar.barData.runeType = nil
                ns:DeactivateBar(bar, true)
            end
            bar:Hide()
            barBackdrop:Hide()
            valueText:Hide()
        end
    end

    -- Re-reserve the values column only when a string actually changed and
    -- the width it needs actually moved. Health ticking 2489 -> 2488 changes
    -- the text but not its width, so the common case costs a measurement and
    -- nothing more. The frame is only ever re-laid-out when the numbers grow
    -- or shrink a digit.
    if valuesChanged and elements.values then
        local needed = ns:MeasureUnitFrameValuesWidth(frame.valueTexts, MAX_UNIT_FRAME_SLOTS)
        if needed ~= frame.lastValuesMeasured then
            LayoutUnitFrame(frame, elements, #entries, needed)
        end
    end
end

-- Rebuild every known unit frame from the live config: destroy it if it
-- exists, then (re)build + do an immediate scan pass when enabled. Called
-- once from ns:OnInitialize and from the Frames tab's own settings (any
-- change there is infrequent, so a full rebuild rather than a targeted
-- per-setting updater is the simplest correct answer for a single frame).
function ns:RebuildUnitFrames()
    for _, key in ipairs(UNIT_FRAME_KEYS) do
        DestroyUnitFrame(key)
        local cfg = ns.db and ns.db.unitFrames and ns.db.unitFrames[key]
        if cfg and cfg.enabled then
            if BuildUnitFrame(key) then
                ScanUnitFrame(key)
            end
        end
    end
end

-- Set a unit frame's scale, preserving its on-screen position - reuses
-- ns:RescaleFrame (FrameManager.lua) exactly like ns:SetFrameScale does for
-- a bar group, rather than a second copy of that offset-conversion maths.
-- growUp is always false: a unit frame never grows (it always shows the
-- same fixed header + bar stack), unlike a bar group whose bar count varies.
function ns:SetUnitFrameScale(key, scale)
    local cfg = ns.db and ns.db.unitFrames and ns.db.unitFrames[key]
    local frame = ns.unitFrames[key]
    local applied

    if frame then
        applied = ns:RescaleFrame(frame, scale, false, function(pos)
            if cfg then cfg.position = pos end
        end)
    else
        applied = math.max(ns.MIN_FRAME_SCALE, math.min(ns.MAX_FRAME_SCALE, scale))
    end

    if cfg then cfg.scale = applied end
end

-- Called from Core.lua's 0.25s OnUpdate ticker, right alongside
-- ns:ScanAllBars - reusing the existing scan loop rather than adding a
-- second one, per CLAUDE.md. Each frame guards its own enabled state, so
-- this is a cheap no-op pass whenever no unit frame is built.
function ns:ScanUnitFrames()
    for _, key in ipairs(UNIT_FRAME_KEYS) do
        if ns.unitFrames[key] then
            ScanUnitFrame(key)
        end
    end
end
