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
--   offsetX = <px>           : extra x offset on the anchor (default 0).
--                               Useful for dropdowns (invisible left padding)
--                               or for fine-tuning alignment between
--                               different widget types.
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
--   { type = "header",  text = <string>, spacing = <px> }
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
    local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    fs:SetText(entry.text or "")
    return fs
end

BUILDERS.note = function(parent, entry)
    local font = (entry.style == "disabled") and "GameFontDisableSmall"
                                              or "GameFontHighlightSmall"
    local fs = parent:CreateFontString(nil, "ARTWORK", font)
    fs:SetJustifyH("LEFT")
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
    return ns:CreateDropdown(parent, entry.label or "", entry.items, wrapped)
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
        --   1. First widget pins to parent TOPLEFT at (firstX, firstY).
        --   2. `anchorTo = "<id>"` anchors relative to another rendered
        --      widget by id (using widgetRefs lookup). The chain pointer
        --      (prev) still updates to THIS widget for subsequent entries.
        --   3. Otherwise, anchor below `prev` with per-entry spacing/offsetX.
        local offsetX = entry.offsetX or 0
        local gap = entry.spacing or DEFAULT_GAP
        local anchorWidget
        if entry.anchorTo and widgetRefs then
            anchorWidget = widgetRefs[entry.anchorTo]
        end

        if anchorWidget then
            widget:SetPoint("TOPLEFT", anchorWidget, "BOTTOMLEFT", offsetX, -gap)
        elseif not prev then
            widget:SetPoint("TOPLEFT", parent, "TOPLEFT", firstX + offsetX, firstY)
        else
            widget:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", offsetX, -gap)
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
                if value ~= nil then
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
