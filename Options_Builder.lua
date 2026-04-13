local addonName, ns = ...

-- ============================================================================
-- Options_Builder.lua - Declarative options-tab walker.
--
-- ns:BuildSettings(parent, schema) walks `schema`, builds one widget per
-- entry under `parent`, anchors each below the previous, and returns a
-- Refresh function that re-reads DB values into the live widgets.
--
-- Inspired by Ace3's AceConfig pattern, but homegrown and minimal — no
-- library dependency. Intended to replace the imperative widget
-- construction in Options_*.lua tabs incrementally, one tab at a time.
--
-- Supported entry types (initial cut; add more as Options_Visuals /
-- Options_Bars conversions need them):
--
--   { type = "header", text = <string>, spacing = <px> }
--   { type = "note",   text = <string|function>, style = "normal"|"disabled", spacing = <px> }
--   { type = "spacer", height = <px> }
--   { type = "toggle", label = <string>, tooltip = <string>,
--                      db = "<dotted.path>", refresh = "<NsMethod>",   -- DBSet style
--                      OR  get = function() return bool end,
--                          set = function(self, checked) ... end,      -- closure escape hatch
--                      spacing = <px> }
-- ============================================================================

-- Layout defaults
local FIRST_X       = 16   -- x offset of the first widget from the parent's TOPLEFT
local FIRST_Y       = -80  -- y offset (negative = down) of the first widget
local DEFAULT_GAP   = 8    -- vertical gap between consecutive widgets

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
    -- A zero-content frame the walker can anchor against.
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(1, entry.height or 1)
    return f
end

BUILDERS.toggle = function(parent, entry)
    local callback
    if entry.set then
        callback = entry.set
    elseif entry.db then
        callback = ns:DBSet(entry.db, entry.refresh)
    else
        error("Options_Builder: toggle entry must have either `set` or `db`", 2)
    end
    return ns:CreateCheckbox(parent, entry.label or "", entry.tooltip, callback)
end

-- ----------------------------------------------------------------------------
-- APPLIERS: per-type "write current DB value into the live widget" logic
-- used by the auto-Refresh function. Only widgets that read state need an
-- applier; static elements (header, note, spacer) do not.
-- ----------------------------------------------------------------------------

local APPLIERS = {}

APPLIERS.toggle = function(widget, value)
    widget:SetChecked(value and true or false)
end

-- ----------------------------------------------------------------------------
-- ResolvePath / ReadValue: shared with Widgets.lua's DBSet/DBGet semantics.
-- Duplicated locally to avoid coupling Options_Builder.lua to Widgets.lua's
-- internals; the function is six lines and stable.
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

function ns:BuildSettings(parent, schema)
    local rendered = {}    -- list of { widget, entry } for the Refresh closure
    local prev               -- anchor for the next widget
    local prevGap = 0        -- gap to use when anchoring the next widget

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

        -- Anchor: first widget pins to parent TOPLEFT; subsequent widgets
        -- pin BOTTOMLEFT-of-prev with the per-entry `spacing` (or default).
        if not prev then
            widget:SetPoint("TOPLEFT", parent, "TOPLEFT", FIRST_X, FIRST_Y)
        else
            widget:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -prevGap)
        end

        rendered[#rendered + 1] = { widget = widget, entry = entry }
        prev = widget
        prevGap = entry.spacing or DEFAULT_GAP
    end

    -- Refresh closure: walks the rendered list and applies current DB
    -- values back into widgets. Suppresses widget callbacks during the
    -- pass so SetChecked/SetValue calls don't write back to the DB.
    return function()
        if not BarWardenDB then return end
        ns.suppressCallbacks = true
        for _, r in ipairs(rendered) do
            local applier = APPLIERS[r.entry.type]
            if applier then
                local value = ResolveValue(r.entry)
                if value ~= nil then
                    applier(r.widget, value)
                end
            end
        end
        ns.suppressCallbacks = false
    end
end
