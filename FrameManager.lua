-- FrameManager.lua - Group frame creation, layout, and positioning.
-- Author:  Serv
-- Source:  https://github.com/powerfulqa/BarWarden
-- License: GNU GPL v3 (see LICENSE); attribution preservation is required.

local addonName, ns = ...

-- ============================================================================
-- FrameManager.lua - Frame (group) creation, layout, positioning, persistence
-- ============================================================================

ns.groupFrames = {}  -- [frameIndex] = WoW frame object

local MAX_FRAMES = 20
local MAX_BARS_PER_FRAME = 30

-- Expose limits so the options UI can enforce them at the Add button level
ns.MAX_FRAMES = MAX_FRAMES
ns.MAX_BARS_PER_FRAME = MAX_BARS_PER_FRAME
local MIN_SCALE = 0.5
local MAX_SCALE = 3.0
-- Exposed so UnitFrames.lua's own scale slider can clamp to the identical
-- range without a second pair of magic numbers to keep in sync.
ns.MIN_FRAME_SCALE = MIN_SCALE
ns.MAX_FRAME_SCALE = MAX_SCALE

-- Pre-allocated sort comparators (avoids closure allocation on every layout)
local sortNow = 0

local function CompareRemaining(a, b)
    local ra = (a.expirationTime and a.barState == ns.BAR_STATE.ACTIVE)
               and (a.expirationTime - sortNow) or 9999
    local rb = (b.expirationTime and b.barState == ns.BAR_STATE.ACTIVE)
               and (b.expirationTime - sortNow) or 9999
    return ra < rb
end

local function CompareAlpha(a, b)
    local na = (a.barData and a.barData.name) or ""
    local nb = (b.barData and b.barData.name) or ""
    return na < nb
end

-- Sort Mode "As They Come": oldest-still-running first, by the appearanceOrder
-- stamp BarEngine.lua sets on the INACTIVE -> ACTIVE transition (ActivateBar /
-- ActivateStaticBar) and clears on deactivate/release. A bar with no stamp
-- (a resource bar, or anything that never went through the activate path)
-- has nothing to compare, so it sorts after every stamped bar.
--
-- Exposed on `ns` (unlike CompareRemaining/CompareAlpha, which stay local)
-- purely so tests/test_frame_manager.lua can reach this one pure function
-- without loading the WoW-frame-creating rest of this file.
local function CompareAppearance(a, b)
    local oa, ob = a.appearanceOrder, b.appearanceOrder
    if oa and ob then return oa < ob end
    if oa and not ob then return true end
    if ob and not oa then return false end
    -- Neither bar has a stamp: table.sort requires a strict weak ordering, so
    -- fall back to a comparison that is at least consistent for the duration
    -- of this sort rather than returning false both ways (which some Lua
    -- sort implementations can loop or corrupt the array on).
    return tostring(a) < tostring(b)
end
ns.CompareAppearance = CompareAppearance

-- Whether a group counts as empty for the purpose of the solid start-up
-- backdrop (see the comment above the call site in UpdateGroupLayout). The
-- two kinds of group are empty in different ways, so this is two explicit
-- branches rather than one shared bar-count check:
--   - An auto-tracking group has no hand-made bars by definition -
--     frameData.bars is just the dormant hand-list BuildBarsForFrame keeps
--     for when auto-track is switched back off, so it is always empty and
--     tells us nothing. The only honest signal is whether any of its slots
--     are currently showing something.
--   - An ordinary group has no slots to check, so it stays keyed off its
--     configured bar count.
-- Exposed on `ns` (like CompareAppearance above) so
-- tests/test_frame_manager.lua can cover the rule without loading the
-- WoW-frame-creating rest of this file.
local function IsGroupEmptyForBackdrop(group, frameData, visibleCount)
    -- EC-TRAP: this branch looks redundant with the #frameData.bars == 0 check
    -- below. Do NOT collapse them: frameData.bars is always the dormant
    -- hand-list for a pure auto group, so that check is permanently true and
    -- an auto group would render its solid start-up backdrop forever no
    -- matter what is on screen. Collapsing them back into one check is the
    -- exact v2.2.1 bug (Background Opacity 0 stuck at solid black on any
    -- populated auto-tracking group).
    if group and group.isAutoGroup then
        return visibleCount == 0
    end
    return (frameData and frameData.bars and #frameData.bars == 0) and true or false
end
ns.IsGroupEmptyForBackdrop = IsGroupEmptyForBackdrop

-- Whether a group has ever been given a real screen anchor, as opposed to
-- still sitting on NewGroup's (Options_Bars.lua) creation placeholder
-- (position = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 0 }).
-- ns:NormalizeGroupAnchor (Utils.lua) is the only thing that writes a corner
-- point, and it only ever writes "TOPLEFT" or "BOTTOMLEFT" - from a drag
-- (SaveFramePosition), a growth-direction flip, a scale change, `/bw reset`,
-- or ns:MigrateFrames's position backfill - so a corner point is a reliable
-- "this group has a real anchor" signal regardless of which of those wrote
-- it. It is not the same as "the user dragged it": the mismatch-repin below
-- also resolves a brand-new group's CENTER placeholder to a corner point on
-- its very first layout pass, before the user has touched anything. That is
-- fine here - by the time that repin has run once, the group has a genuine
-- screen position (even if it is just "the screen centre, corner-relative"),
-- so honouring its own alpha from then on is correct.
local function HasRealAnchor(frameData)
    local point = frameData and frameData.position and frameData.position.point
    return point == "TOPLEFT" or point == "BOTTOMLEFT"
end
ns.HasRealAnchor = HasRealAnchor

-- Runtime-only bar data for one auto-tracking slot. ScanAutoGroup overwrites
-- the name and id each pass, so this is never written to SavedVariables: the
-- group's real `bars` array stays untouched in the DB and comes back the
-- moment auto-tracking is switched off.
--
-- `enabled` doubles as the occupied flag. An empty slot is a disabled bar,
-- which the existing DeactivateBar path already knows to hide, so no new
-- hide route is needed.
local function NewAutoBarData()
    return {
        name       = "",
        enabled    = false,
        trackMode  = "Buff",
        unit       = "player",
        display    = { lingerTime = 0 },
        conditions = {},
    }
end

-- Backdrop table for group frames: a plain white texture tinted by
-- SetBackdropColor, plus Blizzard's own tooltip border.
--
-- Unit frames deliberately do NOT use this. They started out sharing it, on
-- the reasoning that a unit frame's backdrop need not look different from a
-- bar group's; seeing both on screen at once disproved that. A bar group is
-- a container the player positions and which should recede, while a unit
-- frame is meant to read as a piece of UI in its own right. UnitFrames.lua
-- now carries its own UNIT_FRAME_BACKDROP built on X-Perl's artwork. Still
-- exposed on `ns` because other callers use it; this note exists so the
-- divergence reads as a decision rather than as an oversight to tidy up.
local GROUP_BACKDROP = {
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
}
ns.GROUP_BACKDROP = GROUP_BACKDROP


-- ----------------------------------------------------------------------------
-- SaveFramePosition: Persist frame position to BarWardenDB
-- ----------------------------------------------------------------------------
-- Re-anchor `group` to the fixed edge for its growth direction, keeping it
-- exactly where it currently sits, and return the anchor table (nil if the
-- frame has no geometry yet). ns:NormalizeGroupAnchor documents why the edges
-- are used verbatim with no scale conversion.
local function RepinGroup(group, growUp)
    local left, top, bottom = group:GetLeft(), group:GetTop(), group:GetBottom()
    if not left then return nil end

    local pos = ns:NormalizeGroupAnchor(growUp, left, top, bottom)
    group:ClearAllPoints()
    group:SetPoint(pos.point, UIParent, pos.relativePoint, pos.x, pos.y)
    return pos
end

-- ----------------------------------------------------------------------------
-- Shared movable-frame positioning.
--
-- A unit frame (UnitFrames.lua) needs the identical "apply a saved anchor,
-- drag while unlocked, repin and persist on drop, rescale without drifting"
-- behaviour a bar group frame already has - the owner asked for this to be
-- reused rather than given a second positioning system. The three pieces
-- below are the ones that generalise cleanly: the anchor-apply-or-fallback
-- (ns:ApplySavedFramePosition), the drag-stop repin+persist body
-- (ns:OnFrameDragStop, replacing the old SaveFramePosition), and the
-- position-preserving rescale (ns:RescaleFrame, replacing the inline maths
-- ns:SetFrameScale used to do just for itself). OnDragStart needed no
-- generalising at all: it already has zero group-specific state, so it is
-- exposed as-is (ns.OnFrameDragStart) rather than duplicated.
-- ----------------------------------------------------------------------------

-- Apply `pos` (a saved { point, relativePoint, x, y } anchor) to `frame`, or
-- `fallback` (same shape) when there is nothing saved yet - e.g. a group's
-- CENTER creation placeholder, or a unit frame's first-ever build.
function ns:ApplySavedFramePosition(frame, pos, fallback)
    if pos and pos.point then
        frame:SetPoint(pos.point, UIParent, pos.relativePoint or pos.point, pos.x or 0, pos.y or 0)
        return
    end
    fallback = fallback or { point = "TOPLEFT", relativePoint = "TOPLEFT", x = 100, y = -200 }
    frame:SetPoint(fallback.point, UIParent, fallback.relativePoint or fallback.point,
                    fallback.x or 0, fallback.y or 0)
end

-- ----------------------------------------------------------------------------
-- OnDragStart / OnDragStop: Drag support for unlocked frames
-- ----------------------------------------------------------------------------
local function OnDragStart(self)
    if BarWardenDB and BarWardenDB.global.locked then return end
    self:StartMoving()
    self.isMoving = true
end
ns.OnFrameDragStart = OnDragStart

-- Generic drag-stop body: stop moving, repin to the fixed edge for `growUp`,
-- and hand the recomputed anchor to `savePosition` so the caller can persist
-- it wherever its own config lives (BarWardenDB.frames[i] for a group,
-- BarWardenDB.unitFrames[key] for a unit frame).
function ns:OnFrameDragStop(frame, growUp, savePosition)
    if not frame.isMoving then return end
    frame:StopMovingOrSizing()
    frame.isMoving = false
    local pos = RepinGroup(frame, growUp)
    if pos and savePosition then savePosition(pos) end
end

local function OnDragStop(self)
    if not self.frameIndex then return end
    local db = BarWardenDB and BarWardenDB.frames
    if not db or not db[self.frameIndex] then return end
    -- Save against the edge the frame grows from, so a height change (bars
    -- appearing/disappearing with Hide When Inactive) never moves it: DOWN
    -- pins the top, UP pins the bottom. Read fresh on every drop (not
    -- captured once) so a growth-direction flip mid-session is honoured on
    -- the very next drag without recreating the frame.
    local growUp = (db[self.frameIndex].growDirection == "UP")
    ns:OnFrameDragStop(self, growUp, function(pos)
        db[self.frameIndex].position = pos
    end)
end

-- Rescale `frame` in place while preserving its on-screen position: anchor
-- offsets are measured in the frame's OWN scaled space, so changing scale
-- alone would move it (2x scale sends x=500 to screen-x 1000). Shared by
-- ns:SetFrameScale below and UnitFrames.lua's own scale slider so there is
-- exactly one "convert the offsets, reapply the anchor" implementation
-- rather than a second one that could drift out of step with the v2.0.2
-- anti-drift fix this same maths already protects (see the EC-TRAP on
-- ns:UpdateGroupLayout below). Returns the clamped scale actually applied.
function ns:RescaleFrame(frame, newScale, growUp, onAnchorChanged)
    newScale = math.max(MIN_SCALE, math.min(MAX_SCALE, newScale))
    if not frame then return newScale end

    local oldScale = frame:GetScale() or 1
    local left, top, bottom = frame:GetLeft(), frame:GetTop(), frame:GetBottom()

    frame:SetScale(newScale)

    if left and oldScale > 0 and newScale > 0 then
        local k = oldScale / newScale
        local pos = ns:NormalizeGroupAnchor(growUp, left * k, top * k, bottom * k)
        frame:ClearAllPoints()
        frame:SetPoint(pos.point, UIParent, pos.relativePoint, pos.x, pos.y)
        if onAnchorChanged then onAnchorChanged(pos) end
    end

    return newScale
end

-- Release every bar a group or unit frame is holding back to the shared
-- pool. Pulled out of DestroyGroupFrame/BuildBarsForFrame (which both used
-- to inline this same three-call loop) so DestroyUnitFrame (UnitFrames.lua)
-- has one place to call rather than a fourth copy of it.
function ns:ReleaseFrameBars(frame)
    if not frame or not frame.bars then return end
    for i = #frame.bars, 1, -1 do
        ns:DeactivateBar(frame.bars[i], true)
        ns:CancelBarGlow(frame.bars[i])
        ns:ReleaseBar(frame.bars[i])
        frame.bars[i] = nil
    end
end

-- Elite/boss units are conventionally marked with a trailing "+" (matching
-- Blizzard's own unit frames/tooltips); rare units are conventionally marked
-- too, so a rare-but-not-elite unit gets "R" and a rare elite gets both,
-- "R+". A plain "normal" unit gets no mark at all.
local CLASSIFICATION_MARKS = {
    elite     = "+",
    worldboss = "+",
    rareelite = "R+",
    rare      = "R",
}

-- A boss-tier level (UnitLevel's -1, "level above what you can determine")
-- has no entry in the quest-difficulty colour table to look up - it is
-- conventionally shown as the highest-danger colour outright, same as the
-- game's own tooltips paint a skull-level enemy red.
local BOSS_LEVEL_COLOR = { r = 1, g = 0, b = 0 }
-- Guard-rail fallback: a private server missing BOTH colour globals (see
-- below) still gets a legible white level rather than an error.
local FALLBACK_LEVEL_COLOR = { r = 1, g = 1, b = 1 }

-- Resolves the (r, g, b) to colour a unit's level by, via the game's own
-- quest-difficulty colouring. 3.3.5a may expose this under either
-- GetQuestDifficultyColor or GetDifficultyColor depending on the server, so
-- both are tried; a private server missing both (or one that errors on an
-- unexpected level) degrades to plain white rather than propagating an
-- error into the title bar.
local function ResolveLevelColor(level)
    if level == -1 then
        return BOSS_LEVEL_COLOR.r, BOSS_LEVEL_COLOR.g, BOSS_LEVEL_COLOR.b
    end

    local colorFn = GetQuestDifficultyColor or GetDifficultyColor
    if not colorFn then
        return FALLBACK_LEVEL_COLOR.r, FALLBACK_LEVEL_COLOR.g, FALLBACK_LEVEL_COLOR.b
    end

    local ok, r, g, b = pcall(colorFn, level)
    if not ok or not r then
        return FALLBACK_LEVEL_COLOR.r, FALLBACK_LEVEL_COLOR.g, FALLBACK_LEVEL_COLOR.b
    end
    return r, g, b
end

-- ns:FormatUnitLevelSuffix(unit): the compact, colour-escaped level text
-- ns:ResolveGroupTitleName appends to a title when "Show Target Level" is
-- ticked - e.g. "|cffffffff80|r" for a normal level-80 unit, or
-- "|cffff000063+|r" for a red-coloured level-63 elite. Empty string when
-- there is nothing sensible to show: no unit, no UnitLevel API at all, or a
-- level of 0 (a unit UnitLevel has no real reading for - never a live
-- level on 3.3.5a, where the lowest character/creature level is 1).
--
-- Deliberately its own function rather than inlined into
-- ResolveGroupTitleName below: it is reused there but is also just string
-- building around a couple of guarded API calls, so it is worth testing on
-- its own.
function ns:FormatUnitLevelSuffix(unit)
    if not unit or not UnitLevel then return "" end

    local ok, level = pcall(UnitLevel, unit)
    -- A sensible reading is a positive level, or exactly -1 (the "too high to
    -- determine" boss marker). Anything else - 0, a stray negative, a
    -- non-number - has nothing worth showing.
    if not ok or type(level) ~= "number" or not (level > 0 or level == -1) then
        return ""
    end

    local levelText = (level == -1) and "??" or tostring(level)

    local classification
    if UnitClassification then
        local okc, c = pcall(UnitClassification, unit)
        if okc then classification = c end
    end
    local mark = CLASSIFICATION_MARKS[classification] or ""

    local r, g, b = ResolveLevelColor(level)
    -- Clamp before scaling to 0-255: a private server's colour function is
    -- not trusted to hand back values inside 0-1, and an out-of-range
    -- %02x would either error or silently print garbage into the title.
    local function toByte(c)
        c = (type(c) == "number") and c or 1
        if c < 0 then c = 0 elseif c > 1 then c = 1 end
        return math.floor(c * 255 + 0.5)
    end
    return string.format("|cff%02x%02x%02x%s%s|r",
        toByte(r), toByte(g), toByte(b), levelText, mark)
end

-- Resolve the title text a group's frame should show for THIS scan (v2.5.0
-- "Group Name Follows Target"): the unit's own name when
-- groupData.autoTitleFollowsUnit is ticked and a unit is actually selected,
-- otherwise the group's own configured name. Nil by default, so an existing
-- group's title is completely unaffected until the owner opts in.
--
-- "No unit selected" (unitName nil or "") falls back to the group's own
-- name rather than going blank: the title stays legible identity for the
-- group even with nothing to follow right now, matching how the group
-- itself stays visible (rather than vanishing outright) while unlocked with
-- an empty auto-tracking feed - see ns:ShouldHideEmptyGroup (Conditions.lua).
--
-- Show Target Level (v2.5.0): when groupData.autoTitleShowsLevel is ALSO
-- ticked, ns:FormatUnitLevelSuffix's result is appended after the name -
-- but only while the title is actually following the unit (unitName was
-- used, not the group-name fallback); a group showing its own configured
-- name has no unit whose level would make sense there. `unit` is the raw
-- unit token (e.g. "target"), separate from `unitName`, since the level
-- needs its own UnitLevel/UnitClassification reads rather than anything
-- derivable from the resolved name string.
--
-- Pure (config + a resolved name string + a unit token in, a string out) so
-- this is testable without a live frame or real Unit* calls: the caller
-- (ns:ScanAutoResourceGroup, BarEngine.lua) is the one that knows the unit
-- token to ask WoW for a name, and whether the RESULT actually changed since
-- the last scan - it decides whether to touch the fontstring at all, which
-- is what keeps this off the per-frame OnUpdate path.
function ns:ResolveGroupTitleName(groupData, unitName, unit)
    local followsUnit = groupData and groupData.autoTitleFollowsUnit
                         and unitName and unitName ~= ""
    if not followsUnit then
        return (groupData and groupData.name) or ""
    end

    if not groupData.autoTitleShowsLevel then
        return unitName
    end

    local suffix = ns:FormatUnitLevelSuffix(unit)
    if suffix == "" then return unitName end
    return unitName .. " " .. suffix
end

-- ----------------------------------------------------------------------------
-- CreateTitleBar: Build the title bar for a group frame
-- ----------------------------------------------------------------------------
local function CreateTitleBar(parent, name)
    local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, -3)
    title:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -4, -3)
    title:SetText(name or "")
    title:SetJustifyH("LEFT")
    parent.titleText = title
    return title
end

-- ----------------------------------------------------------------------------
-- CreateGroupFrame: Build a container frame from group data
-- ----------------------------------------------------------------------------
function ns:CreateGroupFrame(groupData, frameIndex)
    if not groupData then return nil end

    local frameName = "BarWardenGroup" .. (frameIndex or 0)
    local frame = CreateFrame("Frame", frameName, UIParent)

    -- Store references
    frame.frameIndex = frameIndex
    frame.bars = {}

    -- Set backdrop
    frame:SetBackdrop(GROUP_BACKDROP)
    local bgAlpha = groupData.bgAlpha ~= nil and groupData.bgAlpha or 0.6
    frame:SetBackdropColor(0, 0, 0, bgAlpha)
    local borderAlpha = groupData.borderAlpha ~= nil and groupData.borderAlpha or 0.8
    frame:SetBackdropBorderColor(0.3, 0.3, 0.3, borderAlpha)

    -- Size from visual settings
    local visual = ns:GetVisual()
    local barWidth = groupData.width or visual.barWidth or 200
    frame:SetWidth(barWidth + 8)  -- padding for border
    frame:SetHeight(30)  -- minimum height, updated by layout

    -- Position: apply the saved anchor as-is. Anchors are normalised on drag
    -- and on a growth-direction change (ns:NormalizeGroupAnchor pins TOPLEFT for
    -- downward growth, BOTTOMLEFT for upward), but this must honour whatever
    -- shape is saved so older layouts still land where the user left them.
    ns:ApplySavedFramePosition(frame, groupData.position)

    -- Scale
    local scale = groupData.scale or 1.0
    scale = math.max(MIN_SCALE, math.min(MAX_SCALE, scale))
    frame:SetScale(scale)

    -- Movable / draggable
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", OnDragStart)
    frame:SetScript("OnDragStop", OnDragStop)

    -- Title bar
    CreateTitleBar(frame, groupData.name)
    if groupData.showTitle == false and frame.titleText then
        frame.titleText:Hide()
    end

    -- Show the group by default. The old guard `(not showAll)` always evaluated
    -- true because showAll was never in DEFAULTS, causing every new group to
    -- start hidden. Groups are only hidden if the per-group `visible` flag is
    -- explicitly false (not currently exposed in the UI, but respected here).
    if groupData.visible ~= false then
        frame:Show()
    else
        frame:Hide()
    end

    -- Lock state
    if BarWardenDB and BarWardenDB.global.locked then
        frame:EnableMouse(false)
    end

    -- Store in tracking table
    if frameIndex then
        ns.groupFrames[frameIndex] = frame
    end

    return frame
end

-- ----------------------------------------------------------------------------
-- UpdateGroupLayout: Reposition bars within a group frame top-to-bottom
-- ----------------------------------------------------------------------------
function ns:UpdateGroupLayout(group)
    if not group then return end
    -- EC-TRAP: this early-return looks pointless (every caller already only
    -- ever hands this a real bar-group frame from ns.groupFrames). It is not:
    -- a unit frame (UnitFrames.lua) shares the bar pool and therefore shares
    -- DeactivateBar/UpdateResourceBar's MarkGroupDirty(bar:GetParent()) call
    -- on every activate/deactivate, regardless of what kind of frame the
    -- bar's parent is. A unit frame owns a completely different layout
    -- (portrait, header, values column) and is never in BarWardenDB.frames,
    -- so running the bar-group algorithm against it here would silently
    -- overwrite its own ns:LayoutUnitFrame positions on the very next scan.
    -- Removing this guard reintroduces exactly that: a unit frame's bars
    -- snapping into a top-to-bottom stack ignoring the portrait/values
    -- column the moment any resource bar activates or deactivates.
    if group.isUnitFrame then return end

    local visual = ns:GetVisual()
    local spacing = visual.barSpacing or 2
    local barHeight = visual.barHeight or 20
    local barWidth = visual.barWidth or 200
    local titleOffset = 16  -- space for title bar

    -- Get frame data for width and column override
    local frameData = BarWardenDB and BarWardenDB.frames and BarWardenDB.frames[group.frameIndex]
    if frameData and frameData.width then
        barWidth = frameData.width
    end
    -- Icon Only groups draw square cells: both dimensions come from Width, so
    -- the owner sizes the icon grid with that one slider instead of Width and
    -- Height fighting each other. Everything else about layout (growth
    -- direction, columns, spacing, backdrop) is unchanged below. Available on
    -- any group, not just auto-tracking ones.
    if frameData and frameData.iconOnly then
        barHeight = barWidth
    end
    local columns = (frameData and frameData.columns and frameData.columns > 0) and frameData.columns or 1

    -- Build list of visible bars, optionally sorted
    local sortMode = (frameData and frameData.sortMode) or "manual"
    local visible = {}
    for _, bar in ipairs(group.bars) do
        if bar:IsShown() then
            visible[#visible + 1] = bar
        end
    end

    if sortMode == "remaining" then
        sortNow = GetTime()
        table.sort(visible, CompareRemaining)
    elseif sortMode == "alpha" then
        table.sort(visible, CompareAlpha)
    elseif sortMode == "appearance" then
        table.sort(visible, CompareAppearance)
    end

    -- Growth direction: "DOWN" (default) anchors bars top-to-bottom with the
    -- title at the top. "UP" anchors bars bottom-to-top with the title at the
    -- bottom, so bars grow upward from the anchor point.
    local growUp = (frameData and frameData.growDirection == "UP")

    local visibleCount = 0
    for _, bar in ipairs(visible) do
        local col = visibleCount % columns
        local row = math.floor(visibleCount / columns)
        local xOff = 4 + col * (barWidth + spacing)
        bar:ClearAllPoints()
        if growUp then
            local yOff = titleOffset + row * (barHeight + spacing)
            bar:SetPoint("BOTTOMLEFT", group, "BOTTOMLEFT", xOff, yOff)
        else
            local yOff = -(titleOffset + row * (barHeight + spacing))
            bar:SetPoint("TOPLEFT", group, "TOPLEFT", xOff, yOff)
        end
        bar:SetWidth(barWidth)
        bar:SetHeight(barHeight)
        -- Per-bar scale override. nil (or 1) means "use group default".
        -- Values != 1 may visually overlap neighbouring bars in multi-column
        -- groups; the per-bar editor slider's tooltip warns about this.
        local scaleOverride = bar.barData and bar.barData.display and bar.barData.display.scaleOverride
        bar:SetScale(scaleOverride or 1)
        visibleCount = visibleCount + 1
    end

    -- Update frame size to fit all columns and rows.
    local rowCount = math.ceil(visibleCount / columns)
    if rowCount == 0 then rowCount = 1 end
    local totalHeight = titleOffset + (rowCount * (barHeight + spacing)) + 4
    local totalWidth = columns * barWidth + (columns - 1) * spacing + 8

    -- A group with nothing in it AND no real screen anchor yet is drawn solid
    -- rather than at the configured backdrop alpha, so a brand-new group at
    -- the centre of the screen is obvious and can be dragged into place. It
    -- reverts to the user's own alpha as soon as it holds something, or as
    -- soon as it has a real anchor of its own - so a group the owner has
    -- already placed and deliberately made transparent stays that way even
    -- while empty. See IsGroupEmptyForBackdrop above for what "nothing in it"
    -- means, and HasRealAnchor above for what "no real anchor yet" means.
    local isEmpty = IsGroupEmptyForBackdrop(group, frameData, visibleCount)
    local hasRealAnchor = HasRealAnchor(frameData)
    if group.SetBackdropColor then
        if isEmpty and not hasRealAnchor then
            group:SetBackdropColor(0, 0, 0, 0.85)
        else
            local bgAlpha = (frameData and frameData.bgAlpha) or 0.6
            group:SetBackdropColor(0, 0, 0, bgAlpha)
        end
    end

    -- Re-anchor ONLY when the pinned corner has to change (a new group still on
    -- its CENTER anchor, or the growth direction was flipped). DOWN pins
    -- TOPLEFT so bars grow downward; UP pins BOTTOMLEFT so bars grow upward.
    --
    -- A pure size change needs no re-anchor at all: the frame is already held
    -- by a corner, so the SetHeight/SetWidth below grows it away from that
    -- fixed corner. Re-deriving and re-saving the position on every relayout is
    -- what made scaled groups drift toward the corner, because relayout runs on
    -- every bar activate/deactivate. Decide here, act after the resize; the
    -- EC-TRAP note below the resize explains why that order matters.
    local pinPoint = growUp and "BOTTOMLEFT" or "TOPLEFT"
    local needsRepin = (group:GetPoint(1) ~= pinPoint)

    group:SetHeight(totalHeight)
    group:SetWidth(totalWidth)

    -- EC-TRAP: the repin belongs AFTER the resize above, not before it. Reading
    -- the edges first looked right - keep the corner the user is currently
    -- looking at - and it IS right whenever the size is not changing in the same
    -- pass, which is every relayout of a settled group, so the two orderings
    -- agree there and the wrong one never showed itself. They disagree on the
    -- two paths where the size does change:
    --   - ns:RebuildAllFrames lays out a frame ns:CreateGroupFrame stubbed at
    --     SetHeight(30) a moment earlier, a size nobody has ever seen;
    --   - an auto-tracking group is laid out at whatever its slots happen to
    --     hold, which is nothing at all on the pass straight after a rebuild.
    -- Repinning from that geometry pinned the wrong edge by (final height minus
    -- the size it was read at) and wrote the result straight to SavedVariables,
    -- so a group whose saved corner did not match its growth direction (every
    -- grow-up group after `/bw reset` or a position backfill) jumped that far up
    -- the screen on a rebuild and stayed there, further the taller it was.
    -- Resizing first grows the frame away from the corner it is ALREADY held by,
    -- so the edge we then pin is the one the saved anchor asked for.
    --
    -- The mismatch guard above is what keeps this off the relayout hot path; it
    -- is the v2.0.2 drift fix and must stay. Do not re-derive unconditionally.
    if needsRepin then
        local pos = RepinGroup(group, growUp)
        if pos and group.frameIndex then
            local db = BarWardenDB and BarWardenDB.frames and BarWardenDB.frames[group.frameIndex]
            if db then db.position = pos end
        end
    end

    -- Title bar position: top of frame for DOWN growth, bottom for UP growth.
    if group.titleText then
        group.titleText:ClearAllPoints()
        if growUp then
            group.titleText:SetPoint("BOTTOMLEFT", group, "BOTTOMLEFT", 4, 3)
            group.titleText:SetPoint("BOTTOMRIGHT", group, "BOTTOMRIGHT", -4, 3)
        else
            group.titleText:SetPoint("TOPLEFT", group, "TOPLEFT", 4, -3)
            group.titleText:SetPoint("TOPRIGHT", group, "TOPRIGHT", -4, -3)
        end
    end
end

-- ----------------------------------------------------------------------------
-- SetFrameScale: Set scale on a group frame with clamping
-- ----------------------------------------------------------------------------
function ns:SetFrameScale(frameIndex, scale)
    local frame = ns.groupFrames[frameIndex]
    local frameData = BarWardenDB and BarWardenDB.frames and BarWardenDB.frames[frameIndex]
    local applied

    if frame then
        local growUp = (frameData and frameData.growDirection == "UP")
        applied = ns:RescaleFrame(frame, scale, growUp, function(pos)
            if frameData then frameData.position = pos end
        end)
    else
        applied = math.max(MIN_SCALE, math.min(MAX_SCALE, scale))
    end

    if frameData then
        frameData.scale = applied
    end
end

-- ----------------------------------------------------------------------------
-- SetGroupColumns: Set column count for a group and relayout immediately
-- ----------------------------------------------------------------------------
function ns:SetGroupColumns(frameIndex, columns)
    columns = math.max(1, math.min(10, columns))
    if BarWardenDB and BarWardenDB.frames and BarWardenDB.frames[frameIndex] then
        BarWardenDB.frames[frameIndex].columns = columns
    end
    local frame = ns.groupFrames[frameIndex]
    if frame then ns:UpdateGroupLayout(frame) end
end

-- ----------------------------------------------------------------------------
-- SetGroupBgAlpha: Set background opacity for a group frame
-- ----------------------------------------------------------------------------
function ns:SetGroupBgAlpha(frameIndex, alpha)
    if BarWardenDB and BarWardenDB.frames and BarWardenDB.frames[frameIndex] then
        BarWardenDB.frames[frameIndex].bgAlpha = alpha
    end
    local frame = ns.groupFrames[frameIndex]
    if frame then frame:SetBackdropColor(0, 0, 0, alpha) end
end

-- ----------------------------------------------------------------------------
-- SetGroupBorderAlpha: Set border opacity for a group frame
-- ----------------------------------------------------------------------------
function ns:SetGroupBorderAlpha(frameIndex, alpha)
    if BarWardenDB and BarWardenDB.frames and BarWardenDB.frames[frameIndex] then
        BarWardenDB.frames[frameIndex].borderAlpha = alpha
    end
    local frame = ns.groupFrames[frameIndex]
    if frame then frame:SetBackdropBorderColor(0.3, 0.3, 0.3, alpha) end
end

-- ----------------------------------------------------------------------------
-- LockAllFrames / UnlockAllFrames: Toggle drag support
-- ----------------------------------------------------------------------------
function ns:LockAllFrames()
    for _, frame in pairs(ns.groupFrames) do
        frame:EnableMouse(false)
        if frame.isMoving then
            frame:StopMovingOrSizing()
            frame.isMoving = false
        end
        if ns.DisableDragReorder then
            ns:DisableDragReorder(frame)
        end
    end
    -- Unit frames (UnitFrames.lua) are movable/draggable the same way a group
    -- is, but live in their own tracking table (not ns.groupFrames, since
    -- they are keyed by unit rather than by a BarWardenDB.frames index) - so
    -- the lock toggle has to reach them separately. No drag-reorder to
    -- disable: a unit frame has one bar per resource, not a reorderable list.
    -- Deliberately does NOT touch frame.portraitButton / frame.nameButton.
    -- Those are the click-to-target handles (UnitFrames.lua), and locking is
    -- about not dragging things by accident, not about making a unit frame
    -- inert - a locked frame you cannot click to select the unit would be a
    -- picture of a unit frame. They check the lock state themselves before
    -- starting a drag, so nothing here has to disable them.
    for _, frame in pairs(ns.unitFrames or {}) do
        frame:EnableMouse(false)
        if frame.isMoving then
            frame:StopMovingOrSizing()
            frame.isMoving = false
        end
    end
end

function ns:UnlockAllFrames()
    for _, frame in pairs(ns.groupFrames) do
        frame:EnableMouse(true)
        if ns.EnableDragReorder then
            ns:EnableDragReorder(frame)
        end
    end
    for _, frame in pairs(ns.unitFrames or {}) do
        frame:EnableMouse(true)
    end
end

-- ----------------------------------------------------------------------------
-- ShowAllFrames / HideAllFrames: Visibility toggle
-- ----------------------------------------------------------------------------
function ns:ShowAllFrames()
    for idx, frame in pairs(ns.groupFrames) do
        local data = BarWardenDB and BarWardenDB.frames and BarWardenDB.frames[idx]
        if not data or data.visible ~= false then
            frame:Show()
        end
    end
end

function ns:HideAllFrames()
    for _, frame in pairs(ns.groupFrames) do
        frame:Hide()
    end
end

-- ----------------------------------------------------------------------------
-- ShowFrame / HideFrame: Individual frame visibility
-- ----------------------------------------------------------------------------
function ns:ShowFrame(frameIndex)
    local frame = ns.groupFrames[frameIndex]
    if frame then frame:Show() end
    if BarWardenDB and BarWardenDB.frames and BarWardenDB.frames[frameIndex] then
        BarWardenDB.frames[frameIndex].visible = true
    end
end

function ns:HideFrame(frameIndex)
    local frame = ns.groupFrames[frameIndex]
    if frame then frame:Hide() end
    if BarWardenDB and BarWardenDB.frames and BarWardenDB.frames[frameIndex] then
        BarWardenDB.frames[frameIndex].visible = false
    end
end

-- ----------------------------------------------------------------------------
-- DestroyGroupFrame: Release all bars and hide the frame
-- ----------------------------------------------------------------------------
local function DestroyGroupFrame(frameIndex)
    local frame = ns.groupFrames[frameIndex]
    if not frame then return end

    -- Deactivate then release all bars back to pool. skipGlow=true (inside
    -- ns:ReleaseFrameBars) prevents glow-on-ready from firing during
    -- teardown; CancelBarGlow clears any pre-existing glow so the pool
    -- doesn't recycle a bar the glow timer is still animating.
    ns:ReleaseFrameBars(frame)

    frame:Hide()
    frame:ClearAllPoints()
    frame:SetParent(UIParent)
    ns.groupFrames[frameIndex] = nil
end

-- `ns:CreateFrame` used to live here: a third group-creation template that
-- nothing called and that had drifted out of step with the two that are used
-- (it was missing sortMode / growDirection / groupConditions). The Bars tab
-- builds new groups via NewGroup in Options_Bars.lua; presets use
-- BuildGroupFromPreset in ClassPresets.lua. Removed in v2.1.1 rather than left
-- to mislead - note the name also shadowed the WoW global of the same name.

-- ----------------------------------------------------------------------------
-- DeleteFrame: Remove a frame from BarWardenDB and destroy it
-- ----------------------------------------------------------------------------
function ns:DeleteFrame(frameIndex)
    if not BarWardenDB or not BarWardenDB.frames then return end
    if not BarWardenDB.frames[frameIndex] then return end

    DestroyGroupFrame(frameIndex)
    table.remove(BarWardenDB.frames, frameIndex)

    -- Rebuild remaining frames to fix indices
    ns:RebuildAllFrames()
end

-- ----------------------------------------------------------------------------
-- DuplicateFrame: Copy a frame's data and create a new frame from it
-- ----------------------------------------------------------------------------
function ns:DuplicateFrame(frameIndex)
    if not BarWardenDB or not BarWardenDB.frames then return nil end
    if not BarWardenDB.frames[frameIndex] then return nil end
    if #BarWardenDB.frames >= MAX_FRAMES then return nil end

    local source = BarWardenDB.frames[frameIndex]
    local copy = ns:CopyTable(source)
    copy.name = (copy.name or "Group") .. " (Copy)"
    -- Offset position slightly so it doesn't overlap
    if copy.position then
        copy.position.x = (copy.position.x or 0) + 20
        copy.position.y = (copy.position.y or 0) - 20
    end

    table.insert(BarWardenDB.frames, copy)
    local idx = #BarWardenDB.frames
    local frame = ns:CreateGroupFrame(copy, idx)
    ns:BuildBarsForFrame(idx)
    -- Refresh the flat scan cache or the duplicated group's bars would never be
    -- scanned/activated until the next full RebuildAllFrames.
    if ns.RebuildAllBarsCache then ns:RebuildAllBarsCache() end
    ns:UpdateGroupLayout(frame)
    return idx
end

-- ----------------------------------------------------------------------------
-- BuildBarsForFrame: Acquire bars from pool and attach to a group frame
-- ----------------------------------------------------------------------------
function ns:BuildBarsForFrame(frameIndex)
    local frame = ns.groupFrames[frameIndex]
    if not frame then return end

    local frameData = BarWardenDB and BarWardenDB.frames and BarWardenDB.frames[frameIndex]
    if not frameData or not frameData.bars then return end

    -- Deactivate then release existing bars back to pool.
    -- skipGlow=true (inside ns:ReleaseFrameBars) prevents glow-on-ready from
    -- firing during rebuild.
    ns:ReleaseFrameBars(frame)
    frame.bars = {}

    -- An auto-tracking group holds slots, not configured bars: ScanAutoGroup
    -- fills them from whatever is on the unit. They start disabled, which is
    -- what keeps an unfilled slot hidden and out of the layout.
    frame.isAutoGroup = frameData.autoTrack and true or false
    if frame.isAutoGroup then
        local slots = math.max(1, math.min(frameData.autoMaxBars or 10, MAX_BARS_PER_FRAME))
        for i = 1, slots do
            local bar = ns:AcquireBar(frame)
            bar.barData    = NewAutoBarData()
            bar.barIndex   = i
            bar.frameIndex = frameIndex
            bar.isAutoBar  = true
            bar.barState   = ns.BAR_STATE and ns.BAR_STATE.INACTIVE or 0
            if ns.ApplyVisualConfig then
                ns:ApplyVisualConfig(bar)
            end
            bar:Hide()
            table.insert(frame.bars, bar)
        end
        -- No drag-reorder for slots: their order is the aura order, and a
        -- dropped ghost would have nothing meaningful to write back.
        return
    end

    -- Acquire and configure bars
    for i, barData in ipairs(frameData.bars) do
        if i > MAX_BARS_PER_FRAME then break end
        local bar = ns:AcquireBar(frame)
        bar.barData = barData
        bar.barIndex = i
        bar.frameIndex = frameIndex
        -- Bars come from a shared pool; a slot released by an auto group would
        -- otherwise arrive here still flagged and be skipped by every scan.
        bar.isAutoBar = false
        bar.barState = ns.BAR_STATE and ns.BAR_STATE.INACTIVE or 0
        -- Apply visual config immediately so font, texture, icon position, and
        -- text settings are correct on login, not just when the bar activates.
        if ns.ApplyVisualConfig then
            ns:ApplyVisualConfig(bar)
        end
        -- Set the bar name AFTER ApplyVisualConfig because SetFont can clear
        -- existing text content in WoW 3.3.5a.
        if bar.nameText then
            bar.nameText:SetText(ns.GetBarDisplayName(barData))
        end
        -- Pre-resolve the spell/item icon so it shows on inactive bars
        if bar.iconTexture and ns.ResolveBarIcon then
            local icon = ns.ResolveBarIcon(barData)
            if icon then
                bar.iconTexture:SetTexture(icon)
            end
        end
        if not ns:IsBarEnabled(bar) then
            bar:Hide()
        elseif ns:ResolveHideWhenInactive(bar) then
            bar:Hide()
        else
            local visual = ns:GetVisual()
            bar:SetAlpha(visual.inactiveAlpha or 0.3)
        end
        table.insert(frame.bars, bar)
    end

    -- Freshly-built bars inherit the current drag-reorder state. Without this
    -- a mid-session add/duplicate would hand back bars that don't respond
    -- to the drag ghost while the rest of the group does.
    local locked = BarWardenDB and BarWardenDB.global and BarWardenDB.global.locked
    if not locked and ns.EnableDragReorder then
        ns:EnableDragReorder(frame)
    end
end

-- ----------------------------------------------------------------------------
-- RebuildAllFrames: Destroy all frames and recreate from BarWardenDB state
-- ----------------------------------------------------------------------------
function ns:RebuildAllFrames()
    -- Destroy existing frames
    for idx in pairs(ns.groupFrames) do
        DestroyGroupFrame(idx)
    end
    ns.groupFrames = {}

    if not BarWardenDB or not BarWardenDB.frames then return end
    if not BarWardenDB.global.enabled then return end

    for idx, frameData in ipairs(BarWardenDB.frames) do
        -- A group switched off is not built at all: no frame, no bars taken
        -- from the pool, nothing for the scan loop to walk. Its settings stay
        -- in BarWardenDB.frames untouched, so ticking the box back on brings
        -- it straight back. See ns:IsGroupEnabled (Conditions.lua) for why
        -- this is "not built" rather than "built and hidden".
        if ns:IsGroupEnabled(frameData) then
            local frame = ns:CreateGroupFrame(frameData, idx)
            if frame then
                ns:BuildBarsForFrame(idx)
                ns:UpdateGroupLayout(frame)
            end
        end
    end

    -- Apply lock state
    if BarWardenDB.global.locked then
        ns:LockAllFrames()
    else
        ns:UnlockAllFrames()
    end

    -- Per-group visibility is already handled inside CreateGroupFrame (respects
    -- groupData.visible). The old `showAll` guard here unconditionally hid every
    -- group because showAll was never declared in DEFAULTS (always nil). Removed
    -- so mid-session profile loads (Load Class Starter, profile switches) don't
    -- create-then-immediately-hide all groups.

    -- Rebuild the flat bar list used by the scan engine
    if ns.RebuildAllBarsCache then
        ns:RebuildAllBarsCache()
    end
end
