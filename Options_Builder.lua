-- Options_Builder.lua - Declarative options schema walker (ns:BuildSettings).
-- Author:  Serv
-- Source:  https://github.com/powerfulqa/BarWarden
-- License: see LICENSE; attribution preservation is required.

local addonName, ns = ...

-- ============================================================================
-- Options_Builder.lua - Declarative options-tab walker.
--
-- ns:BuildSettings(parent, schema, widgetRefs?, opts?) walks `schema`, builds
-- one widget per entry under `parent`, anchors each below the previous, and
-- returns a Refresh closure that re-reads DB values into the live widgets.
--
-- opts table (all optional):
--   firstX / firstY   : x/y offset of the first widget from parent's TOPLEFT
--                        (defaults 16, -80; correct for a tab that renders
--                        directly under the panel title).
--
-- Any entry may carry:
--   spacing = <px>           : vertical gap to previous widget (default 8).
--   offsetX = <px>           : ABSOLUTE x offset from the parent's left edge
--                               (added to firstX; default 0). NOT a nudge
--                               from the previous widget - each entry's x is
--                               independent of every other entry, so adding
--                               or removing a row above it never shifts it.
--                               Every widget template pads its own visible
--                               content differently (a dropdown's box sits
--                               ~16px right of its frame, a checkbox's
--                               tickbox a few px), so use the matching
--                               ns.OFFSET_* constant below for the entry's
--                               type rather than a bespoke number, unless the
--                               entry is a deliberate sub-item indented under
--                               the setting above it.
--   anchorTo = "<id>"        : override "anchor to previous" and anchor this
--                               widget relative to another already-rendered
--                               entry's widget. Does NOT affect the chain
--                               pointer; the next entry without anchorTo
--                               anchors to THIS entry normally.
--
-- Inspired by Ace3's AceConfig pattern, but homegrown and minimal, with no
-- library dependency. Used by Options_General.lua (v1.4.0) and
-- Options_Visuals.lua.
--
-- Supported entry types:
--
--   { type = "header",  text = <string>, spacing = <px>, large = <bool?> }
--                       -- large: GameFontNormalLarge instead of GameFontNormal,
--                       -- for a header that needs to read as a section break.
--   { type = "note",    text = <string|function>, style = "normal"|"disabled",
--                       id = <string?>, spacing = <px?> }
--   { type = "spacer",  height = <px> }
--
--   { type = "toggle",  label = <string>, tooltip = <string>,
--                       db = <path>, refresh = <NsMethod?>,     -- DBSet style, OR
--                       get = <function>, set = <function>,     -- closure escape hatch
--                       id = <string?>, onChange = <fn?>, spacing = <px?> }
--
--   { type = "slider",  label = <string>, tooltip = <string?>,
--                       db = <path>, refresh = <NsMethod?>,     -- OR get/set pair
--                       min = <num>, max = <num>, step = <num>,
--                       width = <px?>, id = <string?>, onChange = <fn?>,
--                       spacing = <px?> }
--
--   { type = "dropdown", label = <string>,
--                        db = <path>, refresh = <NsMethod?>,    -- OR get/set pair
--                        items = <{ {text=..., value=...}, ... }>,
--                        id = <string?>, onChange = <fn?>, spacing = <px?> }
--
--   { type = "editbox", label = <string>, tooltip = <string?>,
--                       db = <path>, refresh = <NsMethod?>,     -- OR get/set pair
--                       width = <px?>, id = <string?>, onChange = <fn?>,
--                       spacing = <px?> }
--
--   { type = "color",   label = <string>,
--                       db = <path>, refresh = <NsMethod?>,     -- OR get/set pair
--                       -- db path resolves to a { r, g, b, a? } sub-table.
--                       id = <string?>, onChange = <fn?>, spacing = <px?> }
--
-- `onChange(value)` (optional on any DB-backed entry): fires after a user
-- write AND after each Refresh pass. Use it (together with `id` + a caller-
-- supplied `widgetRefs` table) to show/hide coupled widgets.
-- ============================================================================

-- Layout defaults
local FIRST_X       = 16   -- x offset of the first widget from the parent's TOPLEFT
local FIRST_Y       = -80  -- y offset (negative = down) of the first widget
local DEFAULT_GAP   = 8    -- vertical gap between consecutive widgets

-- ----------------------------------------------------------------------------
-- Canonical per-type absolute offsetX values. Derived from each widget
-- template's own padding, then checked by eye against the live Bars tab
-- (which is the only panel exercising every one of header / dropdown /
-- toggle / slider / colour in one place; it has no editbox, so that one is
-- derived from the header column rather than eyeballed in-panel). Each
-- widget template pads its own visible content differently
-- (a dropdown's box sits ~16px right of its frame origin, a checkbox's
-- tickbox only a few px), so each type needs its own frame-origin offset to
-- make the VISIBLE LEFT EDGES line up in the same column. Exposed on `ns`
-- (rather than kept file-local) so every Options_*.lua schema can reference
-- the same numbers instead of re-deriving or copy-pasting them.
-- ----------------------------------------------------------------------------
ns.OFFSET_HEADER   = 2     -- plain fontstring, no template padding
ns.OFFSET_DROPDOWN = -14   -- UIDropDownMenuTemplate box sits ~16px right of frame origin
ns.OFFSET_TOGGLE   = -4    -- CheckButton tickbox is inset a few px from frame origin
ns.OFFSET_SLIDER   = 8     -- OptionsSliderTemplate label/track padding
-- InputBoxTemplate's left edge texture actually sits ~5px left of the frame
-- origin (it is NOT flush), so offsetX = 2 in a firstX = 0 panel puts the box
-- border a few px inside the scroll clip edge. The value is chosen to align
-- the editbox's LABEL with the header column, not to clear the border - a
-- deliberate trade-off, not an oversight.
ns.OFFSET_EDITBOX  = 2     -- aligns editbox label with header column
ns.OFFSET_COLOR    = 2     -- bare swatch frame, no built-in inset; matches header

-- ----------------------------------------------------------------------------
-- Callback plumbing
--
-- Every DB-backed entry builds a user-change callback that:
--   1. Writes the value to the DB (via ns:DBSet or entry.set)
--   2. Fires entry.onChange(value) if present, so coupled widgets resync.
-- ----------------------------------------------------------------------------

local function BuildSetCallback(entry)
    if entry.set then
        if entry.onChange then
            return function(self, value, ...)
                entry.set(self, value, ...)
                entry.onChange(value)
            end
        end
        return entry.set
    end
    if entry.db then
        local dbSet = ns:DBSet(entry.db, entry.refresh)
        if entry.onChange then
            return function(self, value, ...)
                dbSet(self, value, ...)
                entry.onChange(value)
            end
        end
        return dbSet
    end
    error("Options_Builder: entry must have either `set` or `db`", 3)
end

-- ----------------------------------------------------------------------------
-- BUILDERS: per-type widget construction. Each returns the live widget so
-- the walker can anchor the next entry below it.
-- ----------------------------------------------------------------------------

local BUILDERS = {}

BUILDERS.header = function(parent, entry)
    -- entry.large picks the bigger font for a header that needs to read as a
    -- section break rather than just another label; default keeps every
    -- existing header (built before this option existed) unchanged.
    local font = entry.large and "GameFontNormalLarge" or "GameFontNormal"
    local fs = parent:CreateFontString(nil, "ARTWORK", font)
    fs:SetText(entry.text or "")
    return fs
end

BUILDERS.note = function(parent, entry)
    local font = (entry.style == "disabled") and "GameFontDisableSmall"
                                              or "GameFontHighlightSmall"
    local fs = parent:CreateFontString(nil, "ARTWORK", font)
    fs:SetJustifyH("LEFT")
    if fs.SetWordWrap then fs:SetWordWrap(true) end
    -- Reactive width: notes are the wrapping text that used to clip at other
    -- panel widths. ns:ApplyWidth sets the width from the live panel width and
    -- registers it so it re-wraps on Interface-Options resize (PanelInfra).
    if ns.ApplyWidth then
        ns:ApplyWidth(fs, 44)
    end
    local text = entry.text
    if type(text) == "function" then text = text() end
    fs:SetText(text or "")
    return fs
end

BUILDERS.spacer = function(parent, entry)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(1, entry.height or 1)
    return f
end

BUILDERS.toggle = function(parent, entry)
    return ns:CreateCheckbox(parent, entry.label or "", entry.tooltip,
                             BuildSetCallback(entry))
end

BUILDERS.slider = function(parent, entry)
    local s = ns:CreateSlider(parent, entry.label or "",
                              entry.min or 0, entry.max or 1, entry.step or 1,
                              BuildSetCallback(entry),
                              entry.tooltip)
    if entry.width then s:SetWidth(entry.width) end
    return s
end

BUILDERS.dropdown = function(parent, entry)
    if not entry.items then
        error("Options_Builder: dropdown entry requires `items`", 2)
    end
    -- ns:CreateDropdown callback signature is (dd, value, index); wrap
    -- BuildSetCallback's (self, value) to match.
    local cb = BuildSetCallback(entry)
    local wrapped = function(dd, value, index) cb(dd, value, index) end
    local dd = ns:CreateDropdown(parent, entry.label or "", entry.items, wrapped, entry.tooltip)
    if entry.width then UIDropDownMenu_SetWidth(dd, entry.width) end
    return dd
end

BUILDERS.editbox = function(parent, entry)
    return ns:CreateEditBox(parent, entry.label or "", entry.width or 150,
                            BuildSetCallback(entry),
                            entry.tooltip)
end

BUILDERS.color = function(parent, entry)
    -- Resolve the initial colour from DB (or entry.get) before creating the
    -- swatch, so the swatch texture is correct on first render.
    local initial
    if entry.get then
        initial = entry.get()
    elseif entry.db then
        initial = ns:DBGet(entry.db)
    end
    initial = initial or { r = 1, g = 1, b = 1 }

    -- ns:CreateColorSwatch's onChange signature is (self, color) where
    -- color = { r, g, b, a }. Translate to the generic (self, value) shape
    -- the BuildSetCallback plumbing expects. For DB-backed entries, the
    -- default set writes r/g/b/a into the sub-table without clobbering
    -- fields that aren't present (e.g. `a` is preserved if it pre-existed
    -- and the new color lacks it).
    local callback
    if entry.set then
        callback = entry.set
    elseif entry.db then
        callback = function(_, color)
            local target = ns:DBGet(entry.db)
            if target then
                target.r = color.r
                target.g = color.g
                target.b = color.b
                if color.a ~= nil then target.a = color.a end
            end
            if entry.refresh and ns[entry.refresh] then
                ns[entry.refresh](ns)
            end
        end
    else
        error("Options_Builder: color entry must have either `set` or `db`", 2)
    end
    if entry.onChange then
        local inner = callback
        callback = function(self, color)
            inner(self, color)
            entry.onChange(color)
        end
    end

    return ns:CreateColorSwatch(parent, entry.label or "", initial, callback)
end

-- ----------------------------------------------------------------------------
-- APPLIERS: per-type "write current DB value into the live widget" logic
-- used by the auto-Refresh function. Signature is (widget, value, entry);
-- existing APPLIERS that ignore `entry` stay backwards-compatible.
-- ----------------------------------------------------------------------------

local APPLIERS = {}

APPLIERS.toggle = function(widget, value)
    widget:SetChecked(value and true or false)
end

APPLIERS.slider = function(widget, value)
    if type(value) == "number" then widget:SetValue(value) end
end

APPLIERS.dropdown = function(widget, value, entry)
    local items = entry and entry.items
    if not items then return end
    for i, item in ipairs(items) do
        if item.value == value then
            UIDropDownMenu_SetSelectedID(widget, i)
            UIDropDownMenu_SetText(widget, item.text)
            return
        end
    end
end

APPLIERS.editbox = function(widget, value)
    widget:SetText(value or "")
end

APPLIERS.color = function(widget, value)
    if type(value) ~= "table" then return end
    if widget.color then
        widget.color.r = value.r
        widget.color.g = value.g
        widget.color.b = value.b
        if value.a ~= nil then widget.color.a = value.a end
    end
    if widget.swatch then
        widget.swatch:SetTexture(value.r or 1, value.g or 1, value.b or 1, 1)
    end
end

-- ----------------------------------------------------------------------------
-- Value resolution (entry -> current value). Mirrors Widgets.lua DBSet/DBGet
-- semantics but lives here to keep Options_Builder self-contained.
-- ----------------------------------------------------------------------------

local function ResolveValue(entry)
    if entry.get then
        return entry.get()
    elseif entry.db then
        return ns:DBGet(entry.db)
    end
end

-- ----------------------------------------------------------------------------
-- Public: BuildSettings
-- ----------------------------------------------------------------------------

function ns:BuildSettings(parent, schema, widgetRefs, opts)
    local firstX = (opts and opts.firstX) or FIRST_X
    local firstY = (opts and opts.firstY) or FIRST_Y

    local rendered = {}    -- list of { widget, entry } for the Refresh closure
    local prev             -- chain tip: the previous in-flow widget
    local widgetX = {}      -- widget -> its resolved x-from-parent's-left-edge,
                            -- so a later entry chaining off it (as `prev`, or
                            -- via `anchorTo`) can compute a single-anchor delta
                            -- without re-deriving an absolute frame position

    for i, entry in ipairs(schema) do
        local builder = BUILDERS[entry.type]
        if not builder then
            error(string.format(
                "ns:BuildSettings: unknown entry type %q at schema[%d]",
                tostring(entry.type), i), 2)
        end

        local widget = builder(parent, entry)
        if not widget then
            error(string.format(
                "ns:BuildSettings: builder for type %q returned nil at schema[%d]",
                entry.type, i), 2)
        end

        -- Optional widget-reference table: entries with an `id` are exposed
        -- back to the caller for cross-widget coordination (e.g. onChange
        -- closures showing/hiding other widgets, or `anchorTo` referencing
        -- an earlier widget).
        if widgetRefs and entry.id then
            widgetRefs[entry.id] = widget
        end

        -- Anchor resolution:
        --   1. First widget pins to parent TOPLEFT at (firstX + offsetX, firstY).
        --   2. `anchorTo = "<id>"` anchors relative to another rendered
        --      widget by id (using widgetRefs lookup), offsetX/gap staying a
        --      relative nudge from THAT widget - this is a deliberate branch
        --      off the main chain (see Options_Visuals.lua's textureDD/
        --      customTexBox), not a positioning bug, so it keeps the old
        --      relative semantics. The chain pointer (prev) still updates to
        --      THIS widget for subsequent entries.
        --   3. Otherwise, chain y below `prev` (so variable-height widgets
        --      like wrapped notes still flow correctly) but pin x to parent's
        --      left edge, so offsetX stays absolute and independent of every
        --      other entry. A single TOPLEFT-to-BOTTOMLEFT anchor gets there
        --      by computing the x delta from `prev`'s already-known resolved
        --      x (widgetX[prev]) to the target absolute x: anchoring at
        --      ((firstX + offsetX) - widgetX[prev]) lands this widget's left
        --      edge at exactly firstX + offsetX from the parent's left edge,
        --      same result as the old TOP/LEFT anchor pair, without pinning
        --      two different corner points (one of which carries an implicit
        --      centring component on the other axis) on the same frame.
        local offsetX = entry.offsetX or 0
        local gap = entry.spacing or DEFAULT_GAP
        local anchorWidget
        if entry.anchorTo and widgetRefs then
            anchorWidget = widgetRefs[entry.anchorTo]
        end

        local resolvedX
        if anchorWidget then
            widget:SetPoint("TOPLEFT", anchorWidget, "BOTTOMLEFT", offsetX, -gap)
            resolvedX = (widgetX[anchorWidget] or 0) + offsetX
        elseif not prev then
            widget:SetPoint("TOPLEFT", parent, "TOPLEFT", firstX + offsetX, firstY)
            resolvedX = firstX + offsetX
        else
            local prevX = widgetX[prev] or firstX
            widget:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", (firstX + offsetX) - prevX, -gap)
            resolvedX = firstX + offsetX
        end
        widgetX[widget] = resolvedX

        -- Full-width entries (editboxes, sliders) also pin their RIGHT edge to
        -- the parent, so they stretch to the panel width instead of a fixed
        -- `width`. Dropdowns cannot stretch this way (their box width is a
        -- template property), so they are left alone.
        if entry.stretch then
            widget:SetPoint("RIGHT", parent, "RIGHT", -(entry.stretchPad or 6), 0)
        end

        rendered[#rendered + 1] = { widget = widget, entry = entry }
        prev = widget
    end

    -- Refresh closure: walks the rendered list, applies current DB values
    -- back into widgets, and fires onChange hooks so coupled widgets resync.
    -- Brackets itself with ns.suppressCallbacks so SetValue/SetChecked calls
    -- inside appliers don't loop back into user-write callbacks.
    return function()
        if not BarWardenDB then return end
        ns.suppressCallbacks = true
        for _, r in ipairs(rendered) do
            local applier = APPLIERS[r.entry.type]
            if applier then
                local value = ResolveValue(r.entry)
                -- Toggles must be applied even when the value is nil: an unset
                -- flag means "off". Skipping them left the widget showing the
                -- PREVIOUS selection's state, so picking a second group or bar
                -- displayed the first one's settings. Other widget types keep
                -- their last value rather than being blanked.
                if value ~= nil or r.entry.type == "toggle" then
                    applier(r.widget, value, r.entry)
                end
                if r.entry.onChange then
                    r.entry.onChange(value)
                end
            end
        end
        ns.suppressCallbacks = false
    end
end
