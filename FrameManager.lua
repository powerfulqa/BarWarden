-- FrameManager.lua - Group frame creation, layout, and positioning.
-- Author:  Serv
-- Source:  https://github.com/powerfulqa/BarWarden
-- License: see LICENSE; attribution preservation is required.

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
local MAX_SCALE = 2.0

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

-- Backdrop table for group frames
local GROUP_BACKDROP = {
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
}


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

local function SaveFramePosition(frame)
    if not frame.frameIndex then return end
    local db = BarWardenDB and BarWardenDB.frames
    if not db or not db[frame.frameIndex] then return end

    -- Save against the edge the frame grows from, so a height change (bars
    -- appearing/disappearing with Hide When Inactive) never moves it: DOWN
    -- pins the top, UP pins the bottom. Saving everything as TOPLEFT used to
    -- pin a grow-up group by the wrong edge.
    local growUp = (db[frame.frameIndex].growDirection == "UP")
    local pos = RepinGroup(frame, growUp)
    if pos then
        db[frame.frameIndex].position = pos
    end
end

-- ----------------------------------------------------------------------------
-- OnDragStart / OnDragStop: Drag support for unlocked frames
-- ----------------------------------------------------------------------------
local function OnDragStart(self)
    if BarWardenDB and BarWardenDB.global.locked then return end
    self:StartMoving()
    self.isMoving = true
end

local function OnDragStop(self)
    if not self.isMoving then return end
    self:StopMovingOrSizing()
    self.isMoving = false
    SaveFramePosition(self)
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

    -- Position: load saved anchor. SaveFramePosition converts to TOPLEFT on
    -- next drag so future loads will use TOPLEFT, but we must respect the
    -- saved anchor for existing positions to display correctly.
    local pos = groupData.position
    if pos and pos.point then
        frame:SetPoint(pos.point, UIParent, pos.relativePoint or pos.point, pos.x or 0, pos.y or 0)
    else
        frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 100, -200)
    end

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

    -- Re-anchor ONLY when the pinned corner has to change (a new group still on
    -- its CENTER anchor, or the growth direction was flipped). DOWN pins
    -- TOPLEFT so bars grow downward; UP pins BOTTOMLEFT so bars grow upward.
    --
    -- A pure size change needs no re-anchor at all: the frame is already held
    -- by a corner, so the SetHeight/SetWidth below grows it away from that
    -- fixed corner. Re-deriving and re-saving the position on every relayout is
    -- what made scaled groups drift toward the corner, because relayout runs on
    -- every bar activate/deactivate.
    local pinPoint = growUp and "BOTTOMLEFT" or "TOPLEFT"
    if group:GetPoint(1) ~= pinPoint then
        -- Read the edges BEFORE resizing so the corner we keep is the one the
        -- user currently sees.
        local pos = RepinGroup(group, growUp)
        if pos and group.frameIndex then
            local db = BarWardenDB and BarWardenDB.frames and BarWardenDB.frames[group.frameIndex]
            if db then db.position = pos end
        end
    end

    group:SetHeight(totalHeight)
    group:SetWidth(totalWidth)

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
    scale = math.max(MIN_SCALE, math.min(MAX_SCALE, scale))
    local frame = ns.groupFrames[frameIndex]
    if frame then
        frame:SetScale(scale)
    end
    if BarWardenDB and BarWardenDB.frames and BarWardenDB.frames[frameIndex] then
        BarWardenDB.frames[frameIndex].scale = scale
    end
end

-- ----------------------------------------------------------------------------
-- SetGroupColumns: Set column count for a group and relayout immediately
-- ----------------------------------------------------------------------------
function ns:SetGroupColumns(frameIndex, columns)
    columns = math.max(1, math.min(4, columns))
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
end

function ns:UnlockAllFrames()
    for _, frame in pairs(ns.groupFrames) do
        frame:EnableMouse(true)
        if ns.EnableDragReorder then
            ns:EnableDragReorder(frame)
        end
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

    -- Deactivate then release all bars back to pool.
    -- skipGlow=true prevents glow-on-ready from firing during teardown.
    -- CancelBarGlow clears any pre-existing glow so the pool doesn't
    -- recycle a bar that the glow timer is still animating.
    if frame.bars then
        for i = #frame.bars, 1, -1 do
            ns:DeactivateBar(frame.bars[i], true)
            ns:CancelBarGlow(frame.bars[i])
            ns:ReleaseBar(frame.bars[i])
            frame.bars[i] = nil
        end
    end

    frame:Hide()
    frame:ClearAllPoints()
    frame:SetParent(UIParent)
    ns.groupFrames[frameIndex] = nil
end

-- ----------------------------------------------------------------------------
-- CreateFrameFromDB: Create a new frame entry in BarWardenDB and build it
-- ----------------------------------------------------------------------------
function ns:CreateFrame(name)
    if not BarWardenDB or not BarWardenDB.frames then return nil end
    if #BarWardenDB.frames >= MAX_FRAMES then return nil end

    local newFrame = {
        name = name or ("Group " .. (#BarWardenDB.frames + 1)),
        enabled = true,
        locked = true,
        visible = true,
        position = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 0 },
        width = BarWardenDB.visual.barWidth or 200,
        columns = 1,
        bgAlpha = 0.6,
        borderAlpha = 0.8,
        scale = 1.0,
        bars = {},
    }

    table.insert(BarWardenDB.frames, newFrame)
    local idx = #BarWardenDB.frames
    local frame = ns:CreateGroupFrame(newFrame, idx)
    ns:UpdateGroupLayout(frame)
    return idx
end

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
    -- skipGlow=true prevents glow-on-ready from firing during rebuild.
    if frame.bars then
        for i = #frame.bars, 1, -1 do
            ns:DeactivateBar(frame.bars[i], true)
            ns:CancelBarGlow(frame.bars[i])
            ns:ReleaseBar(frame.bars[i])
            frame.bars[i] = nil
        end
    end
    frame.bars = {}

    -- Acquire and configure bars
    for i, barData in ipairs(frameData.bars) do
        if i > MAX_BARS_PER_FRAME then break end
        local bar = ns:AcquireBar(frame)
        bar.barData = barData
        bar.barIndex = i
        bar.frameIndex = frameIndex
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
        if barData.enabled == false then
            bar:Hide()
        elseif ns:ResolveHideWhenInactive(bar) then
            bar:Hide()
        else
            local visual = BarWardenDB and BarWardenDB.visual or (ns.DEFAULTS and ns.DEFAULTS.visual) or {}
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
        local frame = ns:CreateGroupFrame(frameData, idx)
        if frame then
            ns:BuildBarsForFrame(idx)
            ns:UpdateGroupLayout(frame)
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
