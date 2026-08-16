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

-- Breathing room above and below the name inside the header band. Outlined
-- text needs a little more than its nominal point size or the outline itself
-- clips against the band edges.
local UF_HEADER_TEXT_PADDING = 4

-- The same allowance for the numbers inside a bar row.
local UF_ROW_TEXT_PADDING = 4

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

-- X-Perl's own backdrop tint, from its option defaults: the frame fill is
-- BLACK and the border a mid grey (XPerl_FrameOptions.lua sets
-- colour.frame = {0,0,0,1} and colour.border = {0.5,0.5,0.5,1}).
--
-- This file originally drew the backdrop white, reasoning that tinting it
-- would mute the artwork. That was simply wrong about how X-Perl uses its
-- own tile: XPerl_FrameBack is a light texture that is MEANT to be tinted
-- dark, and leaving it white is why the frame read as washed-out grey and
-- why a 3D portrait appeared to sit on a grey background - the model is
-- transparent around the character, so the untinted tile showed through it.
local UF_BORDER_COLOR = { r = 0.5, g = 0.5, b = 0.5 }

-- Read one opacity setting, clamped to 0-1, defaulting to fully opaque for
-- anything unset or non-numeric (a hand-edited or imported profile). Every
-- part of the frame gets its own, so the panel, the portrait, the bars and
-- the border can each be faded independently.
function ns:GetUnitFrameOpacity(cfg, key)
    local alpha = cfg and cfg[key]
    if type(alpha) ~= "number" then return 1.0 end
    if alpha < 0 then return 0 end
    if alpha > 1 then return 1 end
    return alpha
end

-- Apply the backdrop tint to a frame or its portrait box. The colour is not
-- a setting, only the opacity: anything other than black stops looking like
-- the addon this artwork came from.
local function ApplyUnitFrameBackdropColor(f, cfg, opacityKey)
    f:SetBackdropColor(0, 0, 0, ns:GetUnitFrameOpacity(cfg, opacityKey))
    f:SetBackdropBorderColor(UF_BORDER_COLOR.r, UF_BORDER_COLOR.g, UF_BORDER_COLOR.b,
                             ns:GetUnitFrameOpacity(cfg, "borderOpacity"))
end

-- How much of each edge of a unit portrait to crop away. Blizzard's portrait
-- images carry a transparent margin around a circular subject; this is the
-- long-standing value that trims it without cutting into the face.
local UF_PORTRAIT_CROP = 0.15

-- Default bar texture for a unit frame. Registered by both SharedMedia.lua
-- (for LSM) and Bar.lua (for the LSM-less fallback) under this exact name,
-- so the default resolves either way.
local UF_DEFAULT_TEXTURE = "XP Perl v2"

-- Resolve a font path + size for one of the frame's fontstrings, falling
-- back to the addon-wide Visuals settings for anything the frame leaves
-- unset. Empty string / 0 mean "inherit" rather than being stored as a copy
-- of the current global, so a frame keeps following a later Visuals change.
--
-- Returns nil when there is no usable font at all, which is the caller's
-- signal to leave the fontstring on its template font rather than calling
-- SetFont with a nil path (which errors).
-- The LSM step is not optional and its absence is a silent failure: the font
-- dropdowns are populated from ns:LSMDropdownItems, which yields LSM NAMES
-- ("BW Adventure"), not file paths. SetFont given a name simply does nothing
-- and leaves the fontstring on its template font - which is exactly how this
-- first shipped, making the font AND size controls both look inert (no
-- SetFont call happens at all, so the size never lands either). Bar.lua's
-- ApplyVisualConfig does the same LSMFetch for the same reason.
local function ResolveUnitFrameFont(font, size, sizeBump)
    local visual = ns:GetVisual()
    local path = (font and font ~= "") and font or visual.font
    if not path or path == "" then
        path = "Fonts\\FRIZQT__.TTF"
    elseif ns.LSM then
        path = ns:LSMFetch("font", path) or path
    end
    local resolved = size
    if not resolved or resolved <= 0 then
        resolved = (visual.fontSize or 11) + (sizeBump or 0)
    end
    if resolved < 1 then resolved = 1 end
    return path, resolved
end

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
    local name = cfg.showName ~= false
    local level = cfg.showLevel ~= false
    return {
        portrait    = cfg.showPortrait ~= false,
        portrait3D  = cfg.portraitStyle == "3D",
        name        = name,
        level       = level,
        -- The header band only exists if something goes in it. With both the
        -- name and the level switched off it collapses entirely rather than
        -- leaving an empty strip across the top of the frame.
        header      = name or level,
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

    -- A bar must be at least as tall as the numbers it carries, exactly as
    -- the header band must fit the name. Without this the Values Size slider
    -- silently capped out around 12 for the same reason Name Size did: the
    -- text drew taller than its row and was clipped, so the slider looked
    -- broken rather than limited. This raises the FLOOR only, so an explicit
    -- Bar Height above it is still honoured.
    local valueSize = elements.valueFontSize
    if valueSize and valueSize + UF_ROW_TEXT_PADDING > barHeight then
        barHeight = valueSize + UF_ROW_TEXT_PADDING
    end

    -- `elements.header` is nil for a caller that predates the name toggle
    -- (and for the tests' minimal element tables), so nil reads as "there is
    -- a header", matching every frame built before it became optional.
    --
    -- The band grows with the name font. It used to be a flat 14px, which
    -- silently capped the Name Size slider: anything past about 12 drew
    -- taller than the band and was clipped, so the slider appeared to stop
    -- working rather than being visibly limited.
    local headerHeight = 0
    if elements.header ~= false then
        headerHeight = UF_HEADER_HEIGHT
        local nameSize = elements.nameFontSize
        if nameSize and nameSize + UF_HEADER_TEXT_PADDING > headerHeight then
            headerHeight = nameSize + UF_HEADER_TEXT_PADDING
        end
    end

    local barsHeight = barCount * barHeight + (barCount - 1) * UF_BAR_SPACING
    local bodyHeight = headerHeight + barsHeight
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
        bodyX        = bodyX,
        barsX        = barsX,
        headerHeight = headerHeight,
        barsTop      = UF_PADDING + headerHeight,
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
    local headerShown = layout.headerHeight > 0
    if frame.headerStrip then
        if headerShown then
            frame.headerStrip:ClearAllPoints()
            frame.headerStrip:SetPoint("TOPLEFT", frame, "TOPLEFT", layout.barsX, -UF_PADDING)
            frame.headerStrip:SetWidth(layout.valuesX + layout.valuesWidth - layout.barsX)
            frame.headerStrip:SetHeight(layout.headerHeight)
            frame.headerStrip:Show()
        else
            frame.headerStrip:Hide()
        end
    end

    if headerShown then
        frame.nameText:ClearAllPoints()
        frame.nameText:SetPoint("LEFT", frame, "TOPLEFT",
            layout.barsX + 3, -(UF_PADDING + layout.headerHeight / 2))
        frame.nameText:SetPoint("RIGHT", frame, "TOPLEFT",
            layout.valuesX + layout.valuesWidth - 3, -(UF_PADDING + layout.headerHeight / 2))
        frame.nameText:Show()
    else
        frame.nameText:Hide()
    end

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
    ApplyUnitFrameBackdropColor(frame, cfg, "frameOpacity")
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
    -- No backdrop of its own. It used to carry the full bordered panel, which
    -- meant the portrait art sat inside two borders (its own and the frame's)
    -- and could not line up with the bars beside it: the art started 5px
    -- inside a box whose own edge was already inset from the panel. Dropping
    -- the border lets the portrait occupy exactly the same vertical span as
    -- the header plus the bar stack, so the two columns align at top and
    -- bottom whether or not the borders are visible.
    --
    -- A plain black fill stays behind it, which is what the Portrait opacity
    -- slider controls: a 3D model is transparent around the character, so
    -- without a backing the game world shows through its head.
    local portraitBG = portraitFrame:CreateTexture(nil, "BACKGROUND")
    portraitBG:SetAllPoints(portraitFrame)
    portraitBG:SetTexture("Interface\\Buttons\\WHITE8x8")
    portraitBG:SetVertexColor(0, 0, 0, ns:GetUnitFrameOpacity(cfg, "portraitOpacity"))
    frame.portraitBG = portraitBG
    frame.portraitFrame = portraitFrame

    local portrait = portraitFrame:CreateTexture(nil, "ARTWORK")
    portrait:SetAllPoints(portraitFrame)
    -- SetPortraitTexture hands back a square image whose subject is a circle
    -- with transparent corners - drawn raw it reads as a small head floating
    -- in a black box, which is exactly how it looked. Cropping past the
    -- transparent margin makes the portrait fill its frame, which is what
    -- X-Perl and every other unit-frame addon does with it.
    portrait:SetTexCoord(UF_PORTRAIT_CROP, 1 - UF_PORTRAIT_CROP,
                         UF_PORTRAIT_CROP, 1 - UF_PORTRAIT_CROP)
    frame.portrait = portrait

    -- Live 3D model, the same approach X-Perl uses (XPerl_Portrait_Template
    -- carries a PlayerModel alongside the flat texture, and XPerlSetPortrait3D
    -- drives it with ClearModel/SetUnit/SetCamera(0) for the head shot).
    -- Created unconditionally but only shown when asked for: building it
    -- lazily would mean a CreateFrame on a settings change, and an unshown
    -- PlayerModel costs nothing.
    --
    -- pcall-guarded because PlayerModel is the one frame type a private
    -- server is most likely to have altered, and a missing SetUnit must
    -- degrade to the flat portrait rather than error on a 4 Hz path.
    local ok, model = pcall(CreateFrame, "PlayerModel", nil, portraitFrame)
    if ok and model then
        model:SetAllPoints(portraitFrame)
        model:Hide()
        frame.portrait3D = model
    end

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
    -- +1 on the inherited size: the name is the frame's title and reads a
    -- step above the numbers unless the owner sets an explicit size.
    local nameFontPath, nameFontSize = ResolveUnitFrameFont(cfg.nameFont, cfg.nameFontSize, 1)
    if nameFontPath then
        nameText:SetFont(nameFontPath, nameFontSize, "OUTLINE")
    end
    -- Fed into the layout so the header band grows with the font instead of
    -- clipping it (see ns:ComputeUnitFrameLayout).
    frame.nameFontSize = nameFontSize
    frame.nameText = nameText
    frame.lastHeaderText = nil

    -- Resolved once for the whole slot loop rather than per slot: every
    -- values fontstring uses the same font, and ResolveUnitFrameFont reads
    -- ns:GetVisual() each call.
    local valueFontPath, valueFontSize = ResolveUnitFrameFont(cfg.valueFont, cfg.valueFontSize, 0)
    -- Stashed on the frame because the on-bar placement has to re-apply them
    -- on every scan (see the note in ScanUnitFrame), not just at build time.
    frame.valueFontPath = valueFontPath
    frame.valueFontSize = valueFontSize

    -- Bars vs panel, and why this changed twice.
    --
    -- This first faded the bar FILLS, then was moved to fade only the
    -- unfilled background behind them, because dimming the fill dims the
    -- data. In practice that made the slider look broken: the background is
    -- only visible on the UNFILLED part of a bar, and a unit frame's bars sit
    -- at 100% almost all the time (full health, full mana, a ready rune), so
    -- there was usually nothing left of it to see. The black a player reads
    -- as "behind the bars" is the panel backdrop, not this.
    --
    -- So the two are now split the way they actually look: "Panel" covers
    -- the frame backdrop AND these bar backgrounds, since they read as one
    -- surface, and "Bars" goes back to the fills. Note that fading a bar
    -- fades its on-bar numbers too - they are regions of the same frame -
    -- which is consistent with what the slider claims to do.
    local barOpacity = ns:GetUnitFrameOpacity(cfg, "barOpacity")
    frame.barOpacity = barOpacity
    local panelOpacity = ns:GetUnitFrameOpacity(cfg, "frameOpacity")

    frame.bars = {}
    frame.valueTexts = {}
    frame.barBackdrops = {}
    for i = 1, MAX_UNIT_FRAME_SLOTS do
        -- Drawn before the bar is acquired so it sits behind it: the pool
        -- parents bars to this frame at a higher draw layer.
        local bg = frame:CreateTexture(nil, "BACKGROUND")
        bg:SetTexture(ns.ResolveTextureName and ns:ResolveTextureName(barTexture)
            or "Interface\\Buttons\\WHITE8x8")
        bg:SetVertexColor(0.15, 0.15, 0.15, 0.9 * panelOpacity)
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
        if valueFontPath then
            valueText:SetFont(valueFontPath, valueFontSize, "OUTLINE")
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
    -- The resolved (not configured) name size: cfg.nameFontSize is 0 for
    -- "inherit", and the header has to size itself to what was actually
    -- applied, which only BuildUnitFrame knows.
    elements.nameFontSize = frame.nameFontSize
    elements.valueFontSize = frame.valueFontSize
    -- pairRunes collapses six rune rows to three ready-count rows. Reused
    -- from the resource-group feature rather than reimplemented, and defaulted
    -- ON for unit frames (unlike groups, where it stays off so an existing
    -- group's six-bar view is unchanged): six full-width rune bars are the
    -- single biggest reason a frame reads as cluttered, and a frame is a new
    -- surface with no existing look to preserve.
    --
    -- `pinned` carries the ticked power types (see ns:BuildUnitFramePins).
    -- Without it, mana/rage/energy only ever appear when one of them is the
    -- unit's CURRENT power type, so on a classless server a character with
    -- all three would still only ever see one - a filter can hide, but it
    -- cannot add. The filter afterwards is what honours the unticked ones.
    local entries = ns:CollectResources({
        unit = unit,
        pairRunes = cfg.pairRunes ~= false,
        pinned = ns:BuildUnitFramePins(cfg.hiddenResources),
    })
    entries = ns:FilterResourceEntries(entries, cfg.hiddenResources)

    if frame.lastLayoutBarCount ~= #entries then
        LayoutUnitFrame(frame, elements, #entries, frame.lastValuesMeasured)
    end

    -- Header: name (+ level). Diffed against frame.lastHeaderText, a
    -- runtime-only cache field, so an unchanged header never touches the
    -- fontstring - mirrors group.lastTitleName in ns:ScanAutoResourceGroup.
    local exists = UnitExists and UnitExists(unit)
    local unitName = (elements.name and exists) and (UnitName(unit) or "") or ""
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
    if elements.portrait then
        -- A 3D model can only render a unit the client can actually see, so
        -- an out-of-range or out-of-view unit falls back to the flat
        -- portrait rather than showing an empty box. This is exactly the
        -- UnitIsVisible gate X-Perl uses for the same reason.
        local want3D = elements.portrait3D and frame.portrait3D
                       and UnitIsVisible and UnitIsVisible(unit)

        if want3D then
            frame.portrait:Hide()
            frame.portrait3D:Show()
            -- Re-seating the model is the expensive part and it visibly
            -- resets the pose, so it happens only when the unit actually
            -- changed - not on every one of the four scans a second. GUID
            -- rather than name, so two mobs sharing a name still re-seat.
            local guid = UnitGUID and UnitGUID(unit)
            if frame.lastPortraitGUID ~= guid then
                frame.lastPortraitGUID = guid
                pcall(function()
                    frame.portrait3D:ClearModel()
                    frame.portrait3D:SetUnit(unit)
                    frame.portrait3D:SetCamera(0)
                end)
            end
        else
            if frame.portrait3D then frame.portrait3D:Hide() end
            frame.portrait:Show()
            -- Cleared so returning to 3D re-seats the model rather than
            -- trusting a GUID stamped while the model was hidden.
            frame.lastPortraitGUID = nil
            if SetPortraitTexture then
                pcall(SetPortraitTexture, frame.portrait, unit)
            end
        end
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
                    -- Re-apply the frame's own Values Font/Size every pass.
                    -- This is NOT redundant with the build-time setup the
                    -- values COLUMN gets: ns:UpdateResourceBar above runs
                    -- ns:ApplyVisualConfig, which re-fonts timeText from the
                    -- addon-wide Visuals settings on every tick, so a font
                    -- applied once at build time would be overwritten four
                    -- times a second. Until this existed, Values Font and
                    -- Values Size did nothing whatsoever in on-bar mode
                    -- while working normally in column mode.
                    if frame.valueFontPath then
                        bar.timeText:SetFont(frame.valueFontPath, frame.valueFontSize, "OUTLINE")
                    end
                    bar.timeText:Show()
                else
                    bar.timeText.lastUFText = nil
                    bar.timeText:Hide()
                end
            end

            -- Applied here, after ns:UpdateResourceBar, because that sets the
            -- bar's alpha from visual.activeAlpha on every scan and would
            -- otherwise overwrite this a quarter of a second later.
            if frame.barOpacity then bar:SetAlpha(frame.barOpacity) end
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
