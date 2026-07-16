-- PanelInfra.lua - panel-width registry + reactivity layer.
-- Author:  Serv
-- Source:  https://github.com/powerfulqa/BarWarden
-- License: see LICENSE; attribution preservation is required.
--
-- The v2 UI foundation. Every Interface Options sub-panel builds widgets
-- through these helpers and relies on the reactive layout registry to track
-- the Interface Options container resizing (a UI-scale change, or a
-- differently-sized options frame). Mirrors EbonClearance's PanelInfra: the
-- pre-v2 BarWarden UI snapshotted a fixed width once in each panel's OnShow
-- and never reflowed, so content clipped at other widths. Here, widgets whose
-- width tracks the panel register themselves, scroll-wrapped panels register
-- their (content, last-widget) pair, and one OnSizeChanged hook re-applies
-- every width and re-fits scroll content. No widget rebuilds - pure reflow.

local addonName, ns = ...

local PANEL_WIDTH = 440 -- default fallback; refreshed dynamically from the container
local MARGIN = 40

-- Maximum width settings controls (edit boxes, sliders, dropdowns) stretch to.
-- Matches the Bar Control button row (the Paste button's right edge is the
-- marker), which fits at the smallest window width. Capping here stops controls
-- from stretching absurdly wide on a large window, and gives Bar Control,
-- Groups, and Visuals one shared width for visual parity. If the Bar list
-- button widths change, revisit this value.
ns.SETTINGS_MAX_WIDTH = 300

local function UpdatePanelWidth()
    local container = InterfaceOptionsFramePanelContainer
    if container and container.GetWidth then
        local w = container:GetWidth()
        if w and w > 100 then
            PANEL_WIDTH = w - MARGIN
        end
    end
end

-- Live getter (not a frozen value): PANEL_WIDTH mutates in UpdatePanelWidth,
-- so callers that need it for build-time SetSize must read it every call.
function ns.GetPanelWidth()
    return PANEL_WIDTH
end

-- Reactive layout registry. widgets = width-tracking widgets; scrollFits =
-- (content, last-widget) pairs whose scroll height must re-fit on resize.
local widthRegistry = { widgets = {}, scrollFits = {} }

function ns:RegisterWidth(widget, xOffset)
    if not widget then return end
    local list = widthRegistry.widgets
    list[#list + 1] = { w = widget, x = xOffset or 0 }
end

function ns:RegisterScrollFit(content, last, padding)
    if not content or not last then return end
    local list = widthRegistry.scrollFits
    list[#list + 1] = { c = content, l = last, p = padding }
end

-- SetWidth + register in one call. Use at every site that would otherwise
-- snapshot the panel width into a widget, so the widget tracks resizes.
function ns:ApplyWidth(widget, x)
    if not widget or not widget.SetWidth then return end
    widget:SetWidth(PANEL_WIDTH - (x or 0))
    ns:RegisterWidth(widget, x or 0)
end

local function fitPair(f)
    if not f.c or not f.l or not f.l.GetBottom or not f.c.GetTop then return end
    local top = f.c:GetTop()
    local bottom = f.l:GetBottom()
    if top and bottom and top > bottom then
        f.c:SetHeight(top - bottom + (f.p or 24))
    end
end

function ns:RefreshLayouts()
    UpdatePanelWidth()
    local widgets = widthRegistry.widgets
    for i = 1, #widgets do
        local d = widgets[i]
        if d.w and d.w.SetWidth then
            d.w:SetWidth(math.max(PANEL_WIDTH - d.x, 100))
        end
    end
    -- Re-applied widths change wrapped FontString heights; re-fit each scroll
    -- content in two passes (the second covers heights not settled at the first).
    local fits = widthRegistry.scrollFits
    ns:After(0.1, function() for i = 1, #fits do fitPair(fits[i]) end end)
    ns:After(0.5, function() for i = 1, #fits do fitPair(fits[i]) end end)
end

-- Auto-hide a UIPanelScrollFrameTemplate's scroll bar when content fits.
function ns:HookScrollbarAutoHide(scrollFrame)
    if not scrollFrame or not scrollFrame.GetName then return end
    local scrollName = scrollFrame:GetName()
    if not scrollName then return end
    local sb = _G[scrollName .. "ScrollBar"]
    if not sb then return end
    local function update()
        local yRange = scrollFrame.GetVerticalScrollRange and scrollFrame:GetVerticalScrollRange() or 0
        if yRange <= 0 then sb:Hide() else sb:Show() end
    end
    scrollFrame:HookScript("OnScrollRangeChanged", update)
    ns:After(0.1, update)
end

-- Wrap a panel's body in a vertical scroll frame; return the content frame to
-- use as the widget parent. Call ns:FitScrollContent after placing widgets.
function ns:WrapPanelInScrollFrame(panel)
    local scrollName = (panel:GetName() or "BarWardenPanel") .. "Scroll"
    local scroll = CreateFrame("ScrollFrame", scrollName, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", -26, 6)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetWidth(math.max(PANEL_WIDTH - 26, 100))
    content:SetHeight(1)
    scroll:SetScrollChild(content)
    ns:RegisterWidth(content, 26)

    local sb = _G[scrollName .. "ScrollBar"]
    if sb then
        sb:ClearAllPoints()
        sb:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", -6, -20)
        sb:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", -6, 16)
    end

    ns:HookScrollbarAutoHide(scroll)
    return content
end

-- Resize a scroll-wrapped content frame to fit its bottom-most widget. Two
-- passes; also registers the pair so resize reflows re-fit it.
function ns:FitScrollContent(content, lastWidget, padding)
    if not content or not lastWidget then return end
    local pad = padding or 24
    local function compute()
        if not lastWidget.GetBottom or not content.GetTop then return end
        local top = content:GetTop()
        local bottom = lastWidget:GetBottom()
        if top and bottom and top > bottom then
            content:SetHeight(top - bottom + pad)
        end
    end
    ns:After(0.1, compute)
    ns:After(0.5, compute)
    ns:RegisterScrollFit(content, lastWidget, pad)
end

-- Panel OnShow preamble: refresh width, guard first-build, then refresh-or-
-- build. `build(self, content)` runs once; `refresh(self)` runs every later
-- OnShow. `wrapScroll` scroll-wraps and passes the content frame to build.
function ns:InitPanel(panel, refresh, build, wrapScroll)
    UpdatePanelWidth()
    if panel.inited then
        if refresh then refresh(panel) end
        return
    end
    panel.inited = true
    local content = panel
    if wrapScroll then
        content = ns:WrapPanelInScrollFrame(panel)
    end
    if build then build(panel, content) end
end

-- Hook the container's resize once so every registered widget reflows. The
-- container exists at load on 3.3.5a; guard just in case.
local container = InterfaceOptionsFramePanelContainer
if container and container.HookScript then
    container:HookScript("OnSizeChanged", function() ns:RefreshLayouts() end)
end
