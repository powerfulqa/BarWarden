local addonName, ns = ...

-- ============================================================================
-- DB.lua - BarWardenDB schema, defaults, visual presets, SavedVariables init
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Visual Preset Definitions
-- ----------------------------------------------------------------------------

ns.VISUAL_PRESETS = {
    ["Rogue"] = {
        barWidth = 160,
        barHeight = 14,
        iconSize = 14,
        showIcon = true,
        borderSize = 1,
        barSpacing = 1,
        fontSize = 9,
        textPosition = "INSIDE_LEFT",
        texture = "Flat",
        showSpark = false,
        defaultColor = { r = 0.9, g = 0.9, b = 0.0 },
    },
    ["NeedToKnow"] = {
        barWidth = 220,
        barHeight = 22,
        iconSize = 22,
        showIcon = true,
        borderSize = 1,
        barSpacing = 2,
        fontSize = 11,
        textPosition = "INSIDE_LEFT",
        texture = "Smooth",
        showSpark = true,
        defaultColor = { r = 0.2, g = 0.6, b = 1.0 },
    },
    ["Minimalist"] = {
        barWidth = 180,
        barHeight = 8,
        iconSize = 0,
        showIcon = false,
        borderSize = 0,
        barSpacing = 1,
        fontSize = 0,
        textPosition = "NONE",
        texture = "Flat",
        showSpark = false,
        defaultColor = { r = 0.8, g = 0.8, b = 0.8 },
    },
}

-- ----------------------------------------------------------------------------
-- Default Database Schema
-- ----------------------------------------------------------------------------

ns.DEFAULTS = {
    -- Schema version: increment when a migration pass is needed
    schemaVersion = 1,

    -- Global settings
    global = {
        enabled = true,
        locked = true,
        showAll = true,
        snapToGrid = false,
        gridSize = 8,
        minimapIcon = true,
        minimapIconPos = 220,
    },

    -- Visual settings (global defaults)
    visual = {
        texture = "Flat",
        customTexture = "",
        preset = "NeedToKnow",
        barWidth = 200,
        barHeight = 20,
        iconSize = 20,
        showIcon = true,
        iconPosition = "LEFT",
        borderSize = 1,
        barSpacing = 2,
        font = "Fonts\\FRIZQT__.TTF",
        fontSize = 11,
        textEnabled = true,
        textPosition = "INSIDE_LEFT",
        textFormat = "NAME_DURATION",
        customTextFormat = "%n %d",
        colorMode = "CLASS",
        defaultColor = { r = 0.2, g = 0.6, b = 1.0 },
        trackModeColors = {
            Cooldown = { r = 0.4, g = 0.6, b = 1.0 },
            Buff     = { r = 0.0, g = 0.8, b = 0.0 },
            Debuff   = { r = 1.0, g = 0.2, b = 0.2 },
            Proc     = { r = 1.0, g = 0.8, b = 0.0 },
            Item     = { r = 0.6, g = 0.2, b = 0.8 },
            Custom   = { r = 0.5, g = 0.5, b = 0.5 },
        },
        activeAlpha = 1.0,
        inactiveAlpha = 0.3,
        fadeWhenInactive = true,
        fadeSpeed = 0.3,
        showSpark = true,
    },

    -- Frames (groups of bars)
    -- Default frame: one sample bar tracking Hearthstone cooldown (item 6948).
    -- Every player has a Hearthstone so this gives immediate visual feedback.
    -- Delete this frame or add more via the Bars/Groups tab in the options panel.
    frames = {
        {
            name = "Sample Cooldowns",
            enabled = true,
            locked = false,
            visible = true,
            position = { point = "CENTER", relativePoint = "CENTER", x = 0, y = -100 },
            width = 200,
            columns = 1,
            bgAlpha = 0.6,
            scale = 1.0,
            bars = {
                {
                    trackMode = "Item",
                    spell = 6948,   -- Hearthstone
                    unit = "player",
                    onlyMine = true,
                    enabled = true,
                    display = {},
                    conditions = {
                        combatOnly = false,
                        outOfCombatOnly = false,
                        requireBuff = nil,
                        healthBelow = nil,
                        inGroup = false,
                        inRaid = false,
                        hideWhenInactive = false,
                        showEmpty = true,
                    },
                },
            },
        },
    },

    -- Profiles
    profiles = {},
    activeProfile = nil,
}

-- ----------------------------------------------------------------------------
-- InitDB: Initialize or migrate SavedVariables
-- ----------------------------------------------------------------------------

-- ----------------------------------------------------------------------------
-- MigrateDB: One-time migration to canonicalize legacy field names.
-- Runs only when BarWardenDB.schemaVersion is absent or below current.
-- Safe: only writes to nil keys, never overwrites non-nil user data.
-- ----------------------------------------------------------------------------
local CURRENT_SCHEMA = 2

local function MigrateDB()
    local savedVersion = BarWardenDB.schemaVersion or 0
    if savedVersion >= CURRENT_SCHEMA then return end

    -- v0 → v1: rename legacy bar config fields to canonical names.
    --   spell (number) → spellId / itemId   spell (string) → spellName
    --   spellInput → spellName   target → unit
    if savedVersion < 1 then
        for _, frameData in ipairs(BarWardenDB.frames or {}) do
            for _, bar in ipairs(frameData.bars or {}) do
                local s = bar.spell
                if s ~= nil then
                    if type(s) == "number" then
                        if bar.trackMode == "Item" then
                            if bar.itemId == nil then bar.itemId = s end
                        else
                            if bar.spellId == nil then bar.spellId = s end
                        end
                    elseif type(s) == "string" and s ~= "" then
                        if bar.spellName == nil then bar.spellName = s end
                    end
                    bar.spell = nil
                end
                if bar.spellInput ~= nil then
                    if bar.spellName == nil then bar.spellName = bar.spellInput end
                    bar.spellInput = nil
                end
                if bar.target ~= nil then
                    if bar.unit == nil then bar.unit = bar.target end
                    bar.target = nil
                end
            end
        end
    end

    -- v1 → v2: fix saves corrupted by MergeDefaults recursing into user frames.
    -- The old InitDB merged the sample default frame (spell=6948 Hearthstone)
    -- into user bars. v1 migration then turned that into spellId=6948 on
    -- Cooldown bars even when the user had set spellName (e.g. "Evasion").
    -- Fix: for non-Item bars, if both spellName and spellId are set, the spellId
    -- was injected by the bug (the UI only sets one or the other). Clear it.
    if savedVersion < 2 then
        for _, frameData in ipairs(BarWardenDB.frames or {}) do
            for _, bar in ipairs(frameData.bars or {}) do
                if bar.trackMode ~= "Item"
                    and bar.spellName and bar.spellName ~= ""
                    and bar.spellId ~= nil then
                    bar.spellId = nil
                end
            end
        end
    end

    BarWardenDB.schemaVersion = CURRENT_SCHEMA
end

function ns:InitDB()
    if not BarWardenDB then
        BarWardenDB = ns:CopyTable(ns.DEFAULTS)
    else
        -- Merge only 'global' and 'visual' — these may have new keys added
        -- across versions and need default values filled in for them.
        -- NEVER recurse into 'frames' or 'profiles': those are user data.
        -- Merging the sample default frame into user frames corrupts bar configs.
        if type(BarWardenDB.global) ~= "table" then
            BarWardenDB.global = ns:CopyTable(ns.DEFAULTS.global)
        else
            ns:MergeDefaults(BarWardenDB.global, ns.DEFAULTS.global)
        end
        if type(BarWardenDB.visual) ~= "table" then
            BarWardenDB.visual = ns:CopyTable(ns.DEFAULTS.visual)
        else
            ns:MergeDefaults(BarWardenDB.visual, ns.DEFAULTS.visual)
        end
        -- Only initialize frames/profiles if completely absent
        if type(BarWardenDB.frames) ~= "table" then
            BarWardenDB.frames = ns:CopyTable(ns.DEFAULTS.frames)
        end
        if type(BarWardenDB.profiles) ~= "table" then
            BarWardenDB.profiles = {}
        end
        MigrateDB()
    end
    ns.db = BarWardenDB
end
