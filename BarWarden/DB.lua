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
        texture = "Flat",
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
    frames = {},

    -- Profiles
    profiles = {},
    activeProfile = nil,
}

-- ----------------------------------------------------------------------------
-- InitDB: Initialize or migrate SavedVariables
-- ----------------------------------------------------------------------------

function ns:InitDB()
    if not BarWardenDB then
        BarWardenDB = ns:CopyTable(ns.DEFAULTS)
    else
        -- Deep-merge: add any new default keys missing from saved data
        ns:MergeDefaults(BarWardenDB, ns.DEFAULTS)
    end
    ns.db = BarWardenDB
end
