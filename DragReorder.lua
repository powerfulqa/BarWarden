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
local function CalcDropIndex(groupFrame)
    local _, cursorY = GetCursorPosition()
    local scale = groupFrame:GetEffectiveScale()
    cursorY = cursorY / scale

    local bars = groupFrame.bars
    if not bars or #bars == 0 then return 1 end

    for i, bar in ipairs(bars) do
        if bar:IsShown() then
            local _, barTop = bar:GetCenter()
            if barTop and cursorY > barTop then
                return i
            end
        end
    end
    return #bars + 1
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

    local visual = BarWardenDB and BarWardenDB.visual or ns.DEFAULTS.visual
    local barWidth = visual.barWidth or 200
    local frameData = BarWardenDB and BarWardenDB.frames and BarWardenDB.frames[groupFrame.frameIndex]
    if frameData and frameData.width then
        barWidth = frameData.width
    end

    ind:SetWidth(barWidth)
    ind:ClearAllPoints()

    -- Position above the target bar, or below the last bar
    local anchorBar
    if dropIdx <= #bars then
        anchorBar = bars[dropIdx]
    end

    if anchorBar and anchorBar:IsShown() then
        ind:SetPoint("BOTTOMLEFT", anchorBar, "TOPLEFT", 0, 1)
    elseif #bars > 0 and bars[#bars]:IsShown() then
        ind:SetPoint("TOPLEFT", bars[#bars], "BOTTOMLEFT", 0, -1)
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
end

-- ----------------------------------------------------------------------------
-- Bar OnMouseUp: Complete or cancel drag
-- ----------------------------------------------------------------------------
local function Bar_OnMouseUp(self, button)
    if button ~= "LeftButton" then return end

    if dragState.active and dragState.dropIndex then
        SwapBars(dragState.frameIndex, dragState.startBarIndex, dragState.dropIndex)
    end

    -- Cleanup
    dragState.active = false
    dragState.bar = nil
    dragState.startBarIndex = nil

    local ghost = dragState.ghost
    if ghost then ghost:Hide() end

    local ind = dragState.indicator
    if ind then ind:Hide() end
end

-- ----------------------------------------------------------------------------
-- Bar OnUpdate: Track drag movement and update visuals
-- ----------------------------------------------------------------------------
local function Bar_OnUpdate(self, elapsed)
    if dragState.bar ~= self then return end
    if not dragState.frameIndex then return end

    local _, cursorY = GetCursorPosition()

    -- Check drag threshold
    if not dragState.active then
        if math.abs(cursorY - dragState.startY) < DRAG_THRESHOLD then
            return
        end
        dragState.active = true

        -- Show ghost bar
        local ghost = GetGhost()
        ghost:SetWidth(self:GetWidth())
        ghost:SetHeight(self:GetHeight())
        local barData = self.barData
        ghost.label:SetText(barData and barData.spellName or barData and barData.name or "")
        ghost:Show()
    end

    -- Update ghost position to follow cursor
    local ghost = GetGhost()
    local scale = self:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    ghost:ClearAllPoints()
    ghost:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx / scale, cy / scale)

    -- Calculate drop target
    local groupFrame = ns.groupFrames[dragState.frameIndex]
    if groupFrame then
        dragState.dropIndex = CalcDropIndex(groupFrame)
        UpdateIndicatorPosition(groupFrame, dragState.dropIndex)
    end
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
    SwapBars(frameIndex, barIndex, barIndex + 2)
end

-- ----------------------------------------------------------------------------
-- EnableDragReorder: Attach drag scripts to all bars in a group frame
-- ----------------------------------------------------------------------------
function ns:EnableDragReorder(groupFrame)
    if not groupFrame or not groupFrame.bars then return end

    for _, bar in ipairs(groupFrame.bars) do
        bar:EnableMouse(true)
        bar:SetScript("OnMouseDown", Bar_OnMouseDown)
        bar:SetScript("OnMouseUp", Bar_OnMouseUp)
        -- Only set drag OnUpdate on inactive bars; active bars must keep
        -- BarEngine's Bar_OnUpdate for smooth fill. MouseDown/Up still fire.
        if bar.barState ~= ns.BAR_STATE.ACTIVE then
            bar:SetScript("OnUpdate", Bar_OnUpdate)
        end
        bar.dragEnabled = true
    end
end

-- ----------------------------------------------------------------------------
-- DisableDragReorder: Remove drag scripts from all bars in a group frame
-- ----------------------------------------------------------------------------
function ns:DisableDragReorder(groupFrame)
    if not groupFrame or not groupFrame.bars then return end

    for _, bar in ipairs(groupFrame.bars) do
        bar:SetScript("OnMouseDown", nil)
        bar:SetScript("OnMouseUp", nil)
        if bar.dragEnabled then
            -- Only clear OnUpdate on inactive bars; active bars are running
            -- BarEngine's Bar_OnUpdate and must not have it cleared here.
            if bar.barState ~= ns.BAR_STATE.ACTIVE then
                bar:SetScript("OnUpdate", nil)
            end
            bar.dragEnabled = false
        end
    end

    -- Cancel any active drag
    if dragState.active then
        dragState.active = false
        dragState.bar = nil
        if dragState.ghost then dragState.ghost:Hide() end
        if dragState.indicator then dragState.indicator:Hide() end
    end
end
