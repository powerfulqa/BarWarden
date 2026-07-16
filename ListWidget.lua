-- ListWidget.lua - reusable, domain-agnostic list widget.
-- Author:  Serv
-- Source:  https://github.com/powerfulqa/BarWarden
-- License: see LICENSE; attribution preservation is required.
--
-- Brings EbonClearance's list mechanics across (pooled rows anchored
-- TOPLEFT/TOPRIGHT so they reflow, a scroll area with an auto-hiding
-- scrollbar, debounced search, an empty-state line) but as a data-provider
-- widget instead of EC's item-ID-specific CreateListUI: the caller supplies
-- a `provider()` that returns the ordered items and a `renderRow(row, item)`
-- that paints one, so the same widget drives the group list, the bar list,
-- the Activity list, and the Profiles list. Reactivity comes from PanelInfra.
--
-- ns:CreateListWidget(parent, opts) -> box (with box.Refresh, box.GetSelected)
-- opts:
--   x, y            placement TOPLEFT in parent (default 0, 0)
--   width           optional fixed width; default reactive (panel width - x)
--   height          box height (default 260)
--   rowHeight       row height (default 22)
--   title           optional header text above the list
--   provider()      -> ordered array of items (item shape is caller-defined)
--   renderRow(row, item, index)  paint a pooled row; row has .text, .icon,
--                                .highlight and whatever buildRow added
--   buildRow(row)   optional: create extra per-row sub-widgets once
--   onSelect(item, index)        optional row-click handler
--   selectedKey                  optional: opts.keyOf(item) == this -> highlighted
--   keyOf(item)                  optional identity for selection highlight
--   searchable      bool; builds a Search box (debounced) filtered by match()
--   match(item, needle) -> bool  required if searchable
--   addLabel        optional; builds an add row (label + input + Add), onAdd(text)
--   emptyText       shown when the list is empty
--   noMatchText     shown when a search hides everything
--   reorderable     bool; drag a row to reorder, calls onMove(from, to)
--   onMove(from, to)             required if reorderable

local addonName, ns = ...

local function styleInput(eb)
    if eb.SetTextInsets then eb:SetTextInsets(6, 0, 0, 0) end
end

function ns:CreateListWidget(parent, opts)
    opts = opts or {}
    local x = opts.x or 0
    local y = opts.y or 0
    local rowHeight = opts.rowHeight or 22
    local C = ns.COLORS

    local box = CreateFrame("Frame", nil, parent)
    box:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    if opts.width then
        box:SetWidth(opts.width)
    else
        ns:ApplyWidth(box, x)   -- reactive: reflows on panel resize
    end
    box:SetHeight(opts.height or 260)

    -- Vertical offset accumulator for the header controls; the scroll area
    -- starts below whatever we build here.
    local headerBottom = 0

    if opts.title then
        local t = box:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        t:SetPoint("TOPLEFT", 0, 0)
        t:SetText(opts.title)
        headerBottom = -22
    end

    -- Add row (label + input + Add button).
    local addInput
    if opts.addLabel then
        local lbl = box:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        lbl:SetPoint("TOPLEFT", 0, headerBottom - 4)
        lbl:SetText(opts.addLabel)

        local addBtn = CreateFrame("Button", nil, box, "UIPanelButtonTemplate")
        addBtn:SetSize(56, 20)
        addBtn:SetPoint("TOPRIGHT", box, "TOPRIGHT", 0, headerBottom)
        addBtn:SetText("Add")

        addInput = CreateFrame("EditBox", nil, box, "InputBoxTemplate")
        addInput:SetAutoFocus(false)
        addInput:SetHeight(20)
        addInput:SetPoint("LEFT", lbl, "RIGHT", 8, 0)
        addInput:SetPoint("RIGHT", addBtn, "LEFT", -8, 0)
        styleInput(addInput)

        local function doAdd()
            local text = (addInput:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
            if text == "" then return end
            if opts.onAdd then opts.onAdd(text) end
            addInput:SetText("")
            if box.Refresh then box.Refresh() end
        end
        addBtn:SetScript("OnClick", doAdd)
        addInput:SetScript("OnEnterPressed", function() doAdd(); addInput:ClearFocus() end)
        headerBottom = headerBottom - 26
    end

    -- Search row (debounced).
    local searchBox
    if opts.searchable then
        local lbl = box:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        lbl:SetPoint("TOPLEFT", 0, headerBottom - 4)
        lbl:SetText("Search:")

        searchBox = CreateFrame("EditBox", nil, box, "InputBoxTemplate")
        searchBox:SetAutoFocus(false)
        searchBox:SetHeight(20)
        searchBox:SetPoint("LEFT", lbl, "RIGHT", 8, 0)
        searchBox:SetPoint("RIGHT", box, "TOPRIGHT", -8, 0)
        styleInput(searchBox)
        headerBottom = headerBottom - 26
    end

    -- Scroll area with a dark backdrop, matching the family list look.
    local scrollBg = CreateFrame("Frame", nil, box)
    scrollBg:SetPoint("TOPLEFT", 0, headerBottom - 4)
    scrollBg:SetPoint("BOTTOMRIGHT", 0, 0)
    scrollBg:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    scrollBg:SetBackdropColor(0, 0, 0, 0.6)
    scrollBg:SetBackdropBorderColor(0.4, 0.35, 0.25, 1)

    local scroll = CreateFrame("ScrollFrame", "BarWardenListScroll" .. (opts.name or tostring(box)):gsub("%W", ""),
                               scrollBg, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", -28, 6)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(math.max((box:GetWidth() or 200) - 40, 100), 1)
    scroll:SetScrollChild(content)
    ns:HookScrollbarAutoHide(scroll)

    -- Keep the scroll child's width in step with the (reactive) box.
    box:SetScript("OnSizeChanged", function(_, width)
        if width and width > 0 and content.SetWidth then
            content:SetWidth(width - 40)
        end
    end)

    -- Empty-state line (greyed), wrap width set from the live content width.
    local emptyFS = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    emptyFS:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -8)
    emptyFS:SetJustifyH("LEFT")
    if emptyFS.SetWordWrap then emptyFS:SetWordWrap(true) end
    emptyFS:Hide()

    -- Pooled rows.
    local rowPool = {}
    local activeRows = 0

    local function getRow(index)
        if rowPool[index] then return rowPool[index] end
        local row = CreateFrame("Button", nil, content)
        row:SetHeight(rowHeight)

        local hl = row:CreateTexture(nil, "BACKGROUND")
        hl:SetAllPoints()
        hl:SetTexture(0.30, 0.56, 1.0, 0.25)
        hl:Hide()
        row.highlight = hl

        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(rowHeight - 4, rowHeight - 4)
        icon:SetPoint("LEFT", row, "LEFT", 2, 0)
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        icon:Hide()
        row.icon = icon

        local text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        text:SetPoint("LEFT", row, "LEFT", 4, 0)
        text:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        text:SetJustifyH("LEFT")
        row.text = text

        if opts.buildRow then opts.buildRow(row) end

        if opts.reorderable then
            row:RegisterForDrag("LeftButton")
            row:SetScript("OnDragStart", function(self)
                box._dragFrom = self._index
            end)
            row:SetScript("OnDragStop", function()
                local from = box._dragFrom
                box._dragFrom = nil
                if not from then return end
                -- Target index from cursor Y relative to the rows.
                local _, cy = GetCursorPosition()
                local scale = content:GetEffectiveScale()
                cy = cy / scale
                local top = content:GetTop() or 0
                local to = math.floor((top - cy) / rowHeight) + 1
                if to < 1 then to = 1 end
                if to > activeRows then to = activeRows end
                if to ~= from and opts.onMove then
                    opts.onMove(from, to)
                    box.Refresh()
                end
            end)
        end

        row:SetScript("OnClick", function(self)
            if opts.onSelect and self._item ~= nil then
                opts.onSelect(self._item, self._index)
                box.Refresh()
            end
        end)

        rowPool[index] = row
        return row
    end

    local function hideAllRows()
        for i = 1, activeRows do
            if rowPool[i] then rowPool[i]:Hide() end
        end
        activeRows = 0
    end

    local function currentNeedle()
        if not searchBox then return "" end
        return (searchBox:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", ""):lower()
    end

    function box.Refresh()
        hideAllRows()
        local items = (opts.provider and opts.provider()) or {}
        local needle = currentNeedle()

        local shown = 0
        local rowY = -2
        local total = 0
        for i = 1, #items do
            local item = items[i]
            total = total + 1
            if needle == "" or (opts.match and opts.match(item, needle)) then
                shown = shown + 1
                local row = getRow(shown)
                row._item = item
                row._index = i
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, rowY)
                row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, rowY)
                row.icon:Hide()
                row.text:SetText("")
                if opts.renderRow then opts.renderRow(row, item, i) end
                local selected = false
                if opts.keyOf and opts.selectedKey ~= nil then
                    selected = (opts.keyOf(item) == opts.selectedKey)
                end
                if selected then row.highlight:Show() else row.highlight:Hide() end
                row:Show()
                rowY = rowY - rowHeight
            end
        end
        activeRows = shown

        if shown == 0 then
            emptyFS:SetWidth(math.max(60, (content:GetWidth() or 200) - 8))
            if total == 0 then
                emptyFS:SetText(opts.emptyText or "Nothing here yet.")
            else
                emptyFS:SetText(opts.noMatchText or "No matches.")
            end
            emptyFS:Show()
            content:SetHeight(math.max(44, (emptyFS:GetStringHeight() or 28) + 16))
        else
            emptyFS:Hide()
            content:SetHeight(math.max(1, shown * rowHeight + 6))
        end
    end

    if searchBox then
        local debounce = CreateFrame("Frame")
        debounce:Hide()
        debounce:SetScript("OnUpdate", function(self, dt)
            self.elapsed = (self.elapsed or 0) + dt
            if self.elapsed >= 0.25 then self:Hide(); box.Refresh() end
        end)
        searchBox:SetScript("OnTextChanged", function()
            debounce.elapsed = 0
            debounce:Show()
        end)
    end

    box.scrollFrame = scroll
    box.content = content
    return box
end
