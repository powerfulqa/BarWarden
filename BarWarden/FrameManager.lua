local addonName, ns = ...

-- ============================================================================
-- FrameManager.lua - Frame (group) creation, layout, positioning, persistence
-- ============================================================================

ns.groupFrames = {}  -- [frameIndex] = WoW frame object

local MAX_FRAMES = 20
local MAX_BARS_PER_FRAME = 30
local MIN_SCALE = 0.5
local MAX_SCALE = 2.0

-- Backdrop table for group frames
local GROUP_BACKDROP = {
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
}

-- ----------------------------------------------------------------------------
-- SnapToGrid: Snap a value to the nearest grid increment
-- ----------------------------------------------------------------------------
local function SnapToGrid(value, gridSize)
    if not gridSize or gridSize <= 0 then return value end
    return math.floor(value / gridSize + 0.5) * gridSize
end

-- ----------------------------------------------------------------------------
-- SaveFramePosition: Persist frame position to BarWardenDB
-- ----------------------------------------------------------------------------
local function SaveFramePosition(frame)
    if not frame.frameIndex then return end
    local db = BarWardenDB and BarWardenDB.frames
    if not db or not db[frame.frameIndex] then return end

    local point, relativeTo, relativePoint, x, y = frame:GetPoint(1)
    if not point then return end

    local snap = BarWardenDB.global.snapToGrid
    local gridSize = BarWardenDB.global.gridSize or 8
    if snap then
        x = SnapToGrid(x, gridSize)
        y = SnapToGrid(y, gridSize)
    end

    db[frame.frameIndex].position = {
        point = point,
        relativePoint = relativePoint or point,
        x = x,
        y = y,
    }
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

    -- Apply snap-to-grid
    if BarWardenDB and BarWardenDB.global.snapToGrid then
        local point, relativeTo, relativePoint, x, y = self:GetPoint(1)
        if point then
            local gridSize = BarWardenDB.global.gridSize or 8
            x = SnapToGrid(x, gridSize)
            y = SnapToGrid(y, gridSize)
            self:ClearAllPoints()
            self:SetPoint(point, UIParent, relativePoint, x, y)
        end
    end

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
    frame:SetBackdropColor(0, 0, 0, 0.6)
    frame:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)

    -- Size from visual settings
    local visual = BarWardenDB and BarWardenDB.visual or ns.DEFAULTS.visual
    local barWidth = groupData.width or visual.barWidth or 200
    frame:SetWidth(barWidth + 8)  -- padding for border
    frame:SetHeight(30)  -- minimum height, updated by layout

    -- Position
    local pos = groupData.position
    if pos and pos.point then
        frame:SetPoint(pos.point, UIParent, pos.relativePoint or pos.point, pos.x or 0, pos.y or 0)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
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

    -- Visibility
    if groupData.visible == false or (BarWardenDB and not BarWardenDB.global.showAll) then
        frame:Hide()
    else
        frame:Show()
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

    local visual = BarWardenDB and BarWardenDB.visual or ns.DEFAULTS.visual
    local spacing = visual.barSpacing or 2
    local barHeight = visual.barHeight or 20
    local barWidth = visual.barWidth or 200
    local titleOffset = 16  -- space for title bar

    -- Get frame data for width override
    local frameData = BarWardenDB and BarWardenDB.frames and BarWardenDB.frames[group.frameIndex]
    if frameData and frameData.width then
        barWidth = frameData.width
    end

    local yOffset = -titleOffset
    local visibleCount = 0

    for i, bar in ipairs(group.bars) do
        if bar:IsShown() then
            bar:ClearAllPoints()
            bar:SetPoint("TOPLEFT", group, "TOPLEFT", 4, yOffset)
            bar:SetWidth(barWidth)
            bar:SetHeight(barHeight)
            yOffset = yOffset - barHeight - spacing
            visibleCount = visibleCount + 1
        end
    end

    -- Update frame height
    local totalHeight = titleOffset + (visibleCount * (barHeight + spacing)) + 4
    if visibleCount == 0 then
        totalHeight = titleOffset + barHeight + 4  -- minimum height for empty frame
    end
    group:SetHeight(totalHeight)
    group:SetWidth(barWidth + 8)
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
-- LockAllFrames / UnlockAllFrames: Toggle drag support
-- ----------------------------------------------------------------------------
function ns:LockAllFrames()
    for _, frame in pairs(ns.groupFrames) do
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

    -- Release all bars back to pool
    if frame.bars then
        for i = #frame.bars, 1, -1 do
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

    -- Release existing bars
    if frame.bars then
        for i = #frame.bars, 1, -1 do
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
        -- Apply visual config and set initial inactive appearance
        if ns.ApplyVisualConfig then
            ns:ApplyVisualConfig(bar)
        end
        -- Set the bar name so it shows on the inactive bar
        if bar.nameText then
            local displayName = barData.spellName or barData.name or
                (type(barData.spell) == "string" and barData.spell or nil) or ""
            bar.nameText:SetText(displayName)
        end
        if barData.enabled == false then
            bar:Hide()
        else
            local visual = BarWardenDB and BarWardenDB.visual or (ns.DEFAULTS and ns.DEFAULTS.visual) or {}
            bar:SetAlpha(visual.inactiveAlpha or 0.3)
        end
        table.insert(frame.bars, bar)
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

    -- Apply visibility
    if not BarWardenDB.global.showAll then
        ns:HideAllFrames()
    end

    -- Rebuild the flat bar list used by the scan engine
    if ns.RebuildAllBarsCache then
        ns:RebuildAllBarsCache()
    end
end
