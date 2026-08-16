-- UnitFrames.lua - Unit frame widget: portrait + name/level + health/power
-- bars + a values column, driven by a unit token.
-- Author:  Serv
-- Source:  https://github.com/powerfulqa/BarWarden
-- License: see LICENSE; attribution preservation is required.

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
local UF_BAR_HEIGHT   = 14
local UF_BAR_SPACING  = 1
local UF_HEADER_HEIGHT = 14
local UF_VALUES_WIDTH  = 74
local UF_PADDING       = 4

-- Which optional elements a unit frame currently shows, resolved from its
-- saved config. Nil-safe (a not-yet-built cfg reads as "show everything",
-- matching ns.DEFAULTS.unitFrames.player) so this can be called defensively
-- from anywhere without a live frame or a populated DB.
function ns:ResolveUnitFrameElements(cfg)
    cfg = cfg or {}
    return {
        portrait = cfg.showPortrait ~= false,
        level    = cfg.showLevel ~= false,
        values   = cfg.showValues ~= false,
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
function ns:ComputeUnitFrameLayout(elements, barCount)
    elements = elements or {}
    barCount = max(barCount or 0, 1)

    local barsHeight = barCount * UF_BAR_HEIGHT + (barCount - 1) * UF_BAR_SPACING
    local bodyHeight = UF_HEADER_HEIGHT + barsHeight
    local portraitSize = elements.portrait and bodyHeight or 0

    local barsX = (portraitSize > 0) and (portraitSize + UF_PADDING) or 0
    local valuesWidth = elements.values and UF_VALUES_WIDTH or 0
    local valuesX = barsX + UF_BAR_WIDTH + (valuesWidth > 0 and UF_PADDING or 0)

    return {
        width        = valuesX + valuesWidth + UF_PADDING,
        height       = bodyHeight + UF_PADDING,
        portraitSize = portraitSize,
        barsX        = barsX,
        barsTop      = UF_HEADER_HEIGHT,
        valuesX      = valuesX,
        valuesWidth  = valuesWidth,
        barWidth     = UF_BAR_WIDTH,
        barHeight    = UF_BAR_HEIGHT,
        barSpacing   = UF_BAR_SPACING,
    }
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
local function LayoutUnitFrame(frame, elements, barCount)
    local layout = ns:ComputeUnitFrameLayout(elements, barCount)

    frame:SetWidth(layout.width)
    frame:SetHeight(layout.height)

    if frame.portrait then
        if elements.portrait then
            frame.portrait:SetSize(layout.portraitSize, layout.portraitSize)
            frame.portrait:Show()
        else
            frame.portrait:Hide()
        end
    end

    frame.nameText:ClearAllPoints()
    frame.nameText:SetPoint("TOPLEFT", frame, "TOPLEFT", layout.barsX + 2, -2)

    for i = 1, MAX_UNIT_FRAME_SLOTS do
        local bar = frame.bars[i]
        local y = -(layout.barsTop + (i - 1) * (layout.barHeight + layout.barSpacing))

        bar:ClearAllPoints()
        bar:SetPoint("TOPLEFT", frame, "TOPLEFT", layout.barsX, y)
        bar:SetWidth(layout.barWidth)
        bar:SetHeight(layout.barHeight)

        local valueText = frame.valueTexts[i]
        valueText:ClearAllPoints()
        valueText:SetPoint("TOPLEFT", frame, "TOPLEFT", layout.valuesX, y)
        valueText:SetWidth(layout.valuesWidth)
    end

    frame.lastLayoutBarCount = barCount
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

    local frame = CreateFrame("Frame", "BarWardenUnitFrame" .. key, UIParent)
    frame.isUnitFrame = true
    frame.unitKey = key

    frame:SetBackdrop(ns.GROUP_BACKDROP)
    frame:SetBackdropColor(0, 0, 0, 0.6)
    frame:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)
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
    local portrait = frame:CreateTexture(nil, "ARTWORK")
    portrait:SetPoint("TOPLEFT", frame, "TOPLEFT", 2, -2)
    frame.portrait = portrait

    -- Header: name, optionally with a colour-escaped level suffix
    -- (ns:FormatUnitLevelSuffix, FrameManager.lua - already built and tested
    -- for the "Group Name Follows Target" resource-group feature; reused
    -- verbatim rather than re-implemented).
    local visual = ns:GetVisual()
    local nameText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameText:SetJustifyH("LEFT")
    if visual.font then
        nameText:SetFont(visual.font, (visual.fontSize or 11) + 1, "OUTLINE")
    end
    frame.nameText = nameText
    frame.lastHeaderText = nil

    frame.bars = {}
    frame.valueTexts = {}
    for i = 1, MAX_UNIT_FRAME_SLOTS do
        local bar = ns:AcquireBar(frame)
        bar.barData = {
            name = "", enabled = false, trackMode = "Buff", unit = unit,
            -- showIcon = false: a unit frame's bars are plain fills, not
            -- icon rows - identity lives in the header, numbers live in the
            -- values column, so a per-row icon would just be clutter.
            display = { lingerTime = 0, showIcon = false },
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

        local valueText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        valueText:SetJustifyH("RIGHT")
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
    local entries = ns:CollectResources({ unit = unit })

    if frame.lastLayoutBarCount ~= #entries then
        LayoutUnitFrame(frame, elements, #entries)
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

    for i = 1, MAX_UNIT_FRAME_SLOTS do
        local bar = frame.bars[i]
        local valueText = frame.valueTexts[i]
        local e = entries[i]

        if e then
            local bd = bar.barData
            bd.enabled    = true
            bd.name       = e.label
            bd.resourceKey = e.key
            bd.runeType    = e.runeType
            bd.trackMode   = e.trackMode or "Buff"
            ns:UpdateResourceBar(bar, e.current, e.max, e.icon, e.label, e.stacks or e.current)
            -- The bar itself carries no inline text: the header already
            -- names the unit, and the values column already carries the
            -- numbers, so repeating either on every row would just be
            -- clutter - the whole point of this widget over "bars in a box".
            if bar.nameText then bar.nameText:Hide() end
            if bar.timeText then bar.timeText:Hide() end
            bar:Show()

            if elements.values then
                local text = ns:FormatUnitFrameValue(e.current, e.max)
                if valueText.lastText ~= text then
                    valueText.lastText = text
                    valueText:SetText(text)
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
            valueText:Hide()
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
