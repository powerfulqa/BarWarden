-- DragReorder.lua - Drag-to-reorder with ghost bar and drop indicator.
-- Author:  Serv
-- Source:  https://github.com/powerfulqa/BarWarden
-- License: GNU GPL v3 (see LICENSE); attribution preservation is required.

local addonName, ns = ...

-- ============================================================================
-- DragReorder.lua - Drag-to-reorder bars within a frame group
-- ============================================================================

local DRAG_THRESHOLD = 5       -- pixels before drag starts
local HIGHLIGHT_ALPHA = 0.4    -- drop indicator opacity
local GHOST_ALPHA = 0.5        -- ghost bar opacity during drag

-- Shared state for active drag operation
local dragState = {
    active = false,
    bar = nil,
    frameIndex = nil,
    startY = 0,
    ghost = nil,
    indicator = nil,
    dropIndex = nil,
}

-- ----------------------------------------------------------------------------
-- CreateIndicator: Lazy-create the drop-target highlight line
-- ----------------------------------------------------------------------------
local function GetIndicator()
    if dragState.indicator then return dragState.indicator end

    local ind = CreateFrame("Frame", "BarWardenDropIndicator", UIParent)
    ind:SetHeight(3)
    ind:SetFrameStrata("TOOLTIP")

    local tex = ind:CreateTexture(nil, "OVERLAY")
    tex:SetAllPoints()
    tex:SetTexture("Interface\\Buttons\\WHITE8x8")
    tex:SetVertexColor(0.2, 0.8, 1.0, HIGHLIGHT_ALPHA)
    ind.texture = tex

    ind:Hide()
    dragState.indicator = ind
    return ind
end

-- ----------------------------------------------------------------------------
-- CreateGhost: Lazy-create the ghost bar shown while dragging
-- ----------------------------------------------------------------------------
local function GetGhost()
    if dragState.ghost then return dragState.ghost end

    local ghost = CreateFrame("Frame", "BarWardenDragGhost", UIParent)
    ghost:SetFrameStrata("TOOLTIP")
    ghost:SetFrameLevel(100)

    local tex = ghost:CreateTexture(nil, "BACKGROUND")
    tex:SetAllPoints()
    tex:SetTexture("Interface\\Buttons\\WHITE8x8")
    tex:SetVertexColor(0.4, 0.4, 0.4, GHOST_ALPHA)
    ghost.bgTexture = tex

    local label = ghost:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("CENTER")
    ghost.label = label

    ghost:Hide()
    dragState.ghost = ghost
    return ghost
end

-- ----------------------------------------------------------------------------
-- CalcDropIndex: Determine which bar slot the cursor is over
-- ----------------------------------------------------------------------------
-- Is this group laid out bottom-to-top by index? (growDirection == "UP")
local function GroupGrowsUp(groupFrame)
    local fd = BarWardenDB and BarWardenDB.frames and BarWardenDB.frames[groupFrame.frameIndex]
    return fd and fd.growDirection == "UP" or false
end

-- Is this group's Sort Mode "manual"? Anything else (remaining time,
-- alphabetical, as-they-come) re-derives the on-screen bar order on every
-- ns:UpdateGroupLayout, so a drop here would land in an unrelated slot and
-- even a "successful" reorder would have no visible effect - see
-- CODE_REVIEW.md's Resolved section, "drag-reorder was wrong under a
-- sorted group". Checked live by frame index (not cached at
-- ns:EnableDragReorder time) because the Sort Mode dropdown only calls
-- ns:UpdateGroupLayout when changed, not ns:EnableDragReorderAll, so a
-- group can flip sorted while already unlocked.
local function IsManualSort(frameIndex)
    local fd = BarWardenDB and BarWardenDB.frames and BarWardenDB.frames[frameIndex]
    return not fd or not fd.sortMode or fd.sortMode == "manual"
end

-- Shared wording so the in-game ghost drag and the Options Bars-tab list
-- drag (Options_Bars.lua) explain a refused reorder identically.
local SORTED_DRAG_MESSAGE =
    "This group is sorted, so its bar order is set by the Sort Mode. " ..
    "Switch Sort Mode to Manual to drag bars into your own order."

function ns:ExplainSortedDragRefusal()
    ns:Print(SORTED_DRAG_MESSAGE)
end

local function CalcDropIndex(groupFrame)
    local cx, cy = GetCursorPosition()
    local scale = groupFrame:GetEffectiveScale()
    cx, cy = cx / scale, cy / scale

    local bars = groupFrame.bars
    if not bars or #bars == 0 then return 1 end

    -- Find the visible bar nearest the cursor in 2D (so multi-column layouts
    -- pick the actual nearest bar, not just the first bar of a row), then decide
    -- insert-before vs -after from which side the cursor is on. Growth direction
    -- flips the vertical sense: DOWN lays bars[1] at the top (higher Y = earlier
    -- index), UP lays bars[1] at the bottom (higher Y = later index).
    local growUp = GroupGrowsUp(groupFrame)
    local nearest, nearestDist, nearestY
    for i, bar in ipairs(bars) do
        if bar:IsShown() then
            local bx, by = bar:GetCenter()
            if bx and by then
                local dx, dy = cx - bx, cy - by
                local d = dx * dx + dy * dy
                if not nearestDist or d < nearestDist then
                    nearestDist, nearest, nearestY = d, i, by
                end
            end
        end
    end
    if not nearest then return #bars + 1 end

    local before = cy > nearestY   -- cursor above the nearest bar's centre
    if growUp then before = not before end
    return before and nearest or (nearest + 1)
end

-- ----------------------------------------------------------------------------
-- UpdateIndicatorPosition: Move the drop indicator to the target slot
-- ----------------------------------------------------------------------------
local function UpdateIndicatorPosition(groupFrame, dropIdx)
    local ind = GetIndicator()
    local bars = groupFrame.bars
    if not bars then
        ind:Hide()
        return
    end

    local visual = ns:GetVisual()
    local barWidth = visual.barWidth or 200
    local frameData = BarWardenDB and BarWardenDB.frames and BarWardenDB.frames[groupFrame.frameIndex]
    if frameData and frameData.width then
        barWidth = frameData.width
    end

    ind:SetWidth(barWidth)
    ind:ClearAllPoints()

    -- The drop line sits at the boundary just "before" bars[dropIdx]. In a
    -- DOWN group that boundary is the target bar's TOP edge; in an UP group the
    -- earlier-index side is below, so it's the BOTTOM edge. Past the last index
    -- the line sits on the far edge of the last bar.
    local growUp = GroupGrowsUp(groupFrame)
    local anchorBar = (dropIdx <= #bars) and bars[dropIdx] or nil

    if anchorBar and anchorBar:IsShown() then
        if growUp then
            ind:SetPoint("TOPLEFT", anchorBar, "BOTTOMLEFT", 0, -1)
        else
            ind:SetPoint("BOTTOMLEFT", anchorBar, "TOPLEFT", 0, 1)
        end
    elseif #bars > 0 and bars[#bars]:IsShown() then
        if growUp then
            ind:SetPoint("BOTTOMLEFT", bars[#bars], "TOPLEFT", 0, 1)
        else
            ind:SetPoint("TOPLEFT", bars[#bars], "BOTTOMLEFT", 0, -1)
        end
    else
        ind:Hide()
        return
    end

    ind:Show()
end

-- ----------------------------------------------------------------------------
-- SwapBars: Swap bar positions in BarWardenDB and rebuild layout
-- ----------------------------------------------------------------------------
local function SwapBars(frameIndex, fromIndex, toIndex)
    if fromIndex == toIndex or fromIndex == toIndex - 1 then return end

    local frameData = BarWardenDB and BarWardenDB.frames and BarWardenDB.frames[frameIndex]
    if not frameData or not frameData.bars then return end

    local bars = frameData.bars
    if fromIndex < 1 or fromIndex > #bars then return end

    -- Remove the bar from its old position
    local barData = table.remove(bars, fromIndex)

    -- Adjust target index after removal
    local insertIdx = toIndex
    if toIndex > fromIndex then
        insertIdx = insertIdx - 1
    end
    insertIdx = math.max(1, math.min(insertIdx, #bars + 1))

    table.insert(bars, insertIdx, barData)

    -- Rebuild bars for this frame
    local groupFrame = ns.groupFrames[frameIndex]
    if groupFrame then
        ns:BuildBarsForFrame(frameIndex)
        ns:UpdateGroupLayout(groupFrame)
    end
end

-- ----------------------------------------------------------------------------
-- Drag tracker: shared OnUpdate that follows the cursor while a drag is in
-- progress. Lives on its own frame so that Bar_OnUpdate (BarEngine's
-- countdown handler) is never clobbered. An active countdown bar stays
-- smooth while being drag-reordered.
-- ----------------------------------------------------------------------------
local dragUpdater = CreateFrame("Frame", "BarWardenDragUpdater", UIParent)
dragUpdater:Hide()

-- Forward-declared: the OnUpdate closure below needs to call ClearDrag on a
-- refused sorted-group drag, but ClearDrag itself hides dragUpdater and is
-- defined afterwards for readability (kept next to Bar_OnMouseUp, its other
-- caller). Declaring the local here lets the closure capture the right
-- upvalue instead of resolving a stray global.
local ClearDrag

dragUpdater:SetScript("OnUpdate", function()
    local bar = dragState.bar
    if not bar or not dragState.frameIndex then return end

    local _, cursorY = GetCursorPosition()

    -- Threshold gate: don't kick off the ghost until the user has actually
    -- moved far enough to mean "drag", not "click".
    if not dragState.active then
        if math.abs(cursorY - dragState.startY) < DRAG_THRESHOLD then
            return
        end

        -- The threshold just crossed: this is a genuine drag attempt, not a
        -- click. Refuse it here, once, rather than run the ghost through
        -- motions that can never stick against a sorted group (see
        -- IsManualSort above). ClearDrag hides dragUpdater, so this can't
        -- repeat on later OnUpdate ticks for the same mouse-down.
        if not IsManualSort(dragState.frameIndex) then
            ns:ExplainSortedDragRefusal()
            ClearDrag()
            return
        end

        dragState.active = true

        local ghost = GetGhost()
        ghost:SetWidth(bar:GetWidth())
        ghost:SetHeight(bar:GetHeight())
        local barData = bar.barData
        ghost.label:SetText(barData and barData.spellName or barData and barData.name or "")
        ghost:Show()
    end

    local ghost = GetGhost()
    local scale = bar:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    ghost:ClearAllPoints()
    ghost:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx / scale, cy / scale)

    local groupFrame = ns.groupFrames[dragState.frameIndex]
    if groupFrame then
        dragState.dropIndex = CalcDropIndex(groupFrame)
        UpdateIndicatorPosition(groupFrame, dragState.dropIndex)
    end
end)

-- Reset drag state and hide all drag visuals. Called from OnMouseUp and
-- from DisableDragReorder on lock / teardown. Assigned (not `local
-- function`) because it was forward-declared above so the OnUpdate
-- closure's early-out can call it.
ClearDrag = function()
    dragState.active = false
    dragState.bar = nil
    dragState.frameIndex = nil
    dragState.startBarIndex = nil
    dragState.dropIndex = nil

    dragUpdater:Hide()
    if dragState.ghost then dragState.ghost:Hide() end
    if dragState.indicator then dragState.indicator:Hide() end
end

-- ----------------------------------------------------------------------------
-- Bar OnMouseDown: Begin tracking potential drag
-- ----------------------------------------------------------------------------
local function Bar_OnMouseDown(self, button)
    if button ~= "LeftButton" then return end
    if BarWardenDB and BarWardenDB.global.locked then return end
    if not self.frameIndex or not self.barIndex then return end

    local _, cursorY = GetCursorPosition()
    dragState.startY = cursorY
    dragState.bar = self
    dragState.frameIndex = self.frameIndex
    dragState.startBarIndex = self.barIndex
    dragState.active = false
    dragState.dropIndex = nil

    -- Spin up the shared tracker; its first tick will check the threshold.
    dragUpdater:Show()
end

-- ----------------------------------------------------------------------------
-- Bar OnMouseUp: Complete or cancel drag
-- ----------------------------------------------------------------------------
local function Bar_OnMouseUp(self, button)
    if button ~= "LeftButton" then return end

    if dragState.active and dragState.dropIndex then
        SwapBars(dragState.frameIndex, dragState.startBarIndex, dragState.dropIndex)
    end

    ClearDrag()
end

-- ----------------------------------------------------------------------------
-- MoveBarUp / MoveBarDown: Accessibility fallback via buttons
-- ----------------------------------------------------------------------------
function ns:MoveBarUp(frameIndex, barIndex)
    if barIndex <= 1 then return end
    SwapBars(frameIndex, barIndex, barIndex - 1)
end

function ns:MoveBarDown(frameIndex, barIndex)
    local frameData = BarWardenDB and BarWardenDB.frames and BarWardenDB.frames[frameIndex]
    if not frameData or not frameData.bars then return end
    if barIndex >= #frameData.bars then return end
    -- toIndex is barIndex + 2 because SwapBars removes the bar first (shifting
    -- indices down by one) then inserts at (toIndex - 1). The net effect is a
    -- swap with the bar immediately below: remove@barIndex → insert@(barIndex+1).
    SwapBars(frameIndex, barIndex, barIndex + 2)
end

-- ----------------------------------------------------------------------------
-- EnableDragReorder / DisableDragReorder: per-group toggle.
--
-- Drag tracking uses a dedicated update frame (see dragUpdater above) rather
-- than the bar's own OnUpdate, so enabling drag does not disturb BarEngine's
-- countdown handler on active bars. That means a cooldown that is currently
-- ticking down can still be drag-reordered while unlocked.
-- ----------------------------------------------------------------------------
function ns:EnableDragReorder(groupFrame)
    if not groupFrame or not groupFrame.bars then return end
    -- An auto-tracking group's slots are ordered by the auras themselves, and
    -- its `bars` array in the DB is the user's hand-made list, kept dormant.
    -- A dropped ghost would reorder bars they cannot see.
    if groupFrame.isAutoGroup then return end

    -- A sorted (non-Manual) group gets the same refusal, but it is not a
    -- third early-return here: Sort Mode can change while a group is
    -- already unlocked (its dropdown only calls ns:UpdateGroupLayout, not
    -- this function), so baking the check in at wiring time would go stale.
    -- Bars stay wired; IsManualSort/ExplainSortedDragRefusal above gate the
    -- actual drag attempt live, in the dragUpdater OnUpdate threshold check.
    -- Every auto group the owner runs also uses a sort, but that never
    -- reaches this second guard: the isAutoGroup return above already left
    -- its bars unwired, so there is nothing for a sorted-group drag attempt
    -- to fire on and no risk of the two guards double-printing.
    for _, bar in ipairs(groupFrame.bars) do
        bar:EnableMouse(true)
        bar:SetScript("OnMouseDown", Bar_OnMouseDown)
        bar:SetScript("OnMouseUp",   Bar_OnMouseUp)
        bar.dragEnabled = true
    end
end

function ns:DisableDragReorder(groupFrame)
    if not groupFrame or not groupFrame.bars then return end

    for _, bar in ipairs(groupFrame.bars) do
        bar:SetScript("OnMouseDown", nil)
        bar:SetScript("OnMouseUp",   nil)
        -- Hand the mouse back. Bars are created mouse-disabled so clicks pass
        -- through to the world; leaving it enabled after a lock meant a locked
        -- group silently ate every click landing on a bar.
        bar:EnableMouse(false)
        bar.dragEnabled = false
    end

    -- Cancel any in-flight drag rooted in this group so the ghost/indicator
    -- don't linger after a lock toggle.
    if dragState.bar and dragState.bar:GetParent() == groupFrame then
        ClearDrag()
    end
end

-- Convenience: apply to every live group frame. Called from the global
-- lock/unlock transitions in FrameManager.lua and from the
-- `global.locked` toggle in Options_General.lua, so the drag wiring
-- tracks frame-lock state without each call site repeating the loop.
function ns:EnableDragReorderAll()
    for _, gf in pairs(ns.groupFrames or {}) do
        ns:EnableDragReorder(gf)
    end
end

function ns:DisableDragReorderAll()
    for _, gf in pairs(ns.groupFrames or {}) do
        ns:DisableDragReorder(gf)
    end
end
