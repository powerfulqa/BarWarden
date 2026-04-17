local addonName, ns = ...

-- ============================================================================
-- DB.lua - BarWardenDB schema, defaults, visual presets, SavedVariables init
-- ============================================================================

ns.DEFAULTS = {
    -- Schema version: increment when a migration pass is needed
    schemaVersion = 5,

    -- Global settings
    global = {
        enabled = true,
        locked = true,
    },

    -- Minimap icon state owned by LibDBIcon-1.0. The layout (hide / minimapPos)
    -- is what LibDBIcon's Register/Show/Hide/Refresh read + mutate directly,
    -- so keep these field names exactly.
    minimap = {
        hide = false,
        minimapPos = 220,
    },

    -- Visual settings (global defaults)
    visual = {
        texture = "Flat",
        customTexture = "",
        barWidth = 200,
        barHeight = 20,
        iconSize = 20,
        showIcon = true,
        iconPosition = "LEFT",
        barSpacing = 2,
        font = "Fonts\\FRIZQT__.TTF",
        fontSize = 11,
        textEnabled = true,
        textPosition = "INSIDE_LEFT",
        textFormat = "NAME_DURATION",
        durationStyle = "DECIMAL",
        colorMode = "CLASS",
        perBarColorOverride = false,
        defaultColor = { r = 0.2, g = 0.6, b = 1.0 },
        trackModeColors = {
            Cooldown = { r = 0.4, g = 0.6, b = 1.0 },
            Buff     = { r = 0.0, g = 0.8, b = 0.0 },
            Debuff   = { r = 1.0, g = 0.2, b = 0.2 },
            Proc     = { r = 1.0, g = 0.8, b = 0.0 },
            Item     = { r = 0.6, g = 0.2, b = 0.8 },
            Enchant      = { r = 0.2, g = 0.8, b = 0.6 },
            ["Enchant MH"] = { r = 0.2, g = 0.8, b = 0.6 },
            ["Enchant OH"] = { r = 0.2, g = 0.8, b = 0.6 },
            Totem    = { r = 0.8, g = 0.4, b = 0.2 },
            -- Class resources
            ["Combo Points"] = { r = 1.0, g = 0.6, b = 0.2 },
            ["Runic Power"]  = { r = 0.4, g = 0.2, b = 0.8 },
            ["Soul Shards"]  = { r = 0.8, g = 0.2, b = 0.8 },
            ["Runes"]        = { r = 0.7, g = 0.2, b = 0.2 },
        },
        activeAlpha = 1.0,
        inactiveAlpha = 0.3,
        showSpark = true,
        -- Icon crop
        iconCrop = true,
        -- Radial cooldown spiral overlay on bar icons (TellMeWhen-style)
        showCooldownSpiral = true,
        -- Spell tooltip when hovering a bar's icon (off by default)
        showBarTooltip = false,
    },

    -- Frames (groups of bars). Empty by default: the auto-prompt at
    -- PLAYER_LOGIN (Core.lua CheckFirstLoginStarter) offers to load a
    -- curated class starter on first login, replacing the old sample
    -- Hearthstone bar that just added clutter.
    frames = {},

    -- Activity tracker: passive spell/aura/cooldown monitoring (persistent across sessions)
    activity = {},

    -- Active profile name (profiles themselves are stored account-wide in BarWardenAccountDB)
    activeProfile = nil,
}

-- One-time migration to canonicalise legacy field names. Runs only when
-- BarWardenDB.schemaVersion is absent or below CURRENT_SCHEMA. Only writes
-- to nil keys; never overwrites existing user data.
local CURRENT_SCHEMA = 5

local function MigrateDB()
    local savedVersion = BarWardenDB.schemaVersion or 0
    if savedVersion >= CURRENT_SCHEMA then return end

    -- v0 → v1: rename legacy bar config fields to canonical names.
    --   spell (number) → spellId / itemId   spell (string) → spellName
    --   spellInput → spellName   target → unit
    if savedVersion < 1 then
        for _, frameData in ipairs(BarWardenDB.frames or {}) do
            for _, bar in ipairs(frameData.bars or {}) do
                -- Migrate spell field
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
                -- Migrate spellInput field
                if bar.spellInput ~= nil then
                    if bar.spellName == nil then bar.spellName = bar.spellInput end
                    bar.spellInput = nil
                end
                -- Migrate target → unit
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
    --
    -- WARNING: this is a one-shot heuristic specific to the pre-v2 bug. If a
    -- future schema ever makes dual spellName+spellId a legitimate state, this
    -- block must be revisited; running it under that schema would silently
    -- delete user data. The guard is `savedVersion < 2` so new installs never
    -- hit it, but keep this in mind before bumping CURRENT_SCHEMA.
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

    -- v2 → v3: ensure sortMode exists on all frames (new field).
    -- Per-bar display fields are additive nils so no migration needed for those.
    if savedVersion < 3 then
        for _, frameData in ipairs(BarWardenDB.frames or {}) do
            if frameData.sortMode == nil then
                frameData.sortMode = "manual"
            end
        end
    end

    -- v3 → v4: add activity tracker table for passive spell monitoring.
    if savedVersion < 4 then
        if not BarWardenDB.activity then
            BarWardenDB.activity = {}
        end
    end

    -- v4 → v5: housekeeping pass for keys that pre-v1.10.2 persisted but
    -- no code ever reads, plus the switch from the hand-rolled minimap
    -- button to LibDBIcon (which owns its own db sub-table).
    --   * bar `_tokenCache` / `_tokenCacheKey` : the parsed-token cache used
    --     to live on the bar config but is now module-local in Trackers.lua.
    --   * visual `fadeWhenInactive` / `fadeSpeed` : exposed in the Visuals
    --     tab and seeded in defaults, but BarEngine always did a hard
    --     SetAlpha, so the toggles never animated anything. UI removed.
    --   * global `minimapIcon` / `minimapIconPos` : replaced by the
    --     LibDBIcon-shaped `minimap = { hide, minimapPos }` sub-table.
    --     We invert `minimapIcon` (show-on) into `hide` (hide-on).
    if savedVersion < 5 then
        for _, frameData in ipairs(BarWardenDB.frames or {}) do
            for _, bar in ipairs(frameData.bars or {}) do
                bar._tokenCache = nil
                bar._tokenCacheKey = nil
            end
        end
        if type(BarWardenDB.visual) == "table" then
            BarWardenDB.visual.fadeWhenInactive = nil
            BarWardenDB.visual.fadeSpeed = nil
        end
        if type(BarWardenDB.global) == "table" then
            if not BarWardenDB.minimap then
                BarWardenDB.minimap = {
                    hide = BarWardenDB.global.minimapIcon == false,
                    minimapPos = BarWardenDB.global.minimapIconPos or 220,
                }
            end
            BarWardenDB.global.minimapIcon = nil
            BarWardenDB.global.minimapIconPos = nil
        end
    end

    BarWardenDB.schemaVersion = CURRENT_SCHEMA
end

function ns:InitDB()
    -- Wiping the visual-table cache here covers the cold-start case where
    -- ns:GetVisual() was called before BarWardenDB existed and cached the
    -- DEFAULTS pointer. After this function returns, callers get the live
    -- SavedVariables table instead.
    ns:InvalidateVisualCache()

    if not BarWardenDB then
        BarWardenDB = ns:CopyTable(ns.DEFAULTS)
    else
        -- Merge only config tables (global, visual) so new settings added in
        -- future versions are picked up.  Do NOT merge into "frames": that is
        -- user data (an array) and MergeDefaults would corrupt it by injecting
        -- the sample-frame defaults into the user's first group/bar.
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
        -- Ensure frames array exists (but never merge into it)
        if type(BarWardenDB.frames) ~= "table" then
            BarWardenDB.frames = ns:CopyTable(ns.DEFAULTS.frames)
        end
        -- Do NOT default schemaVersion here. A pre-schema save (missing
        -- field) must be treated as version 0 so MigrateDB's `or 0` fallback
        -- kicks in and the v0 -> v1 legacy-field rename actually runs.
        -- Stamping CURRENT_SCHEMA here would skip every migration for
        -- users upgrading from a pre-schemaVersion release. MigrateDB
        -- writes the final schemaVersion when it finishes.
        MigrateDB()
        -- Minimap state lives in its own sub-table because LibDBIcon-1.0
        -- expects to own the `hide` + `minimapPos` keys directly. Runs
        -- AFTER MigrateDB so the v4 → v5 migration gets a chance to seed
        -- the table from legacy `global.minimapIcon*` before defaults
        -- backfill anything missing.
        if type(BarWardenDB.minimap) ~= "table" then
            BarWardenDB.minimap = ns:CopyTable(ns.DEFAULTS.minimap)
        else
            ns:MergeDefaults(BarWardenDB.minimap, ns.DEFAULTS.minimap)
        end
    end
    ns.db = BarWardenDB

    -- Remove legacy stats table (replaced by ActivityTracker)
    BarWardenDB.stats = nil

    -- Ensure activity table exists for passive activity tracking
    if not BarWardenDB.activity then
        BarWardenDB.activity = {}
    end

    -- Account-wide profile storage (shared across all characters)
    if not BarWardenAccountDB then
        BarWardenAccountDB = {
            profiles = {
                ["Default"] = {
                    description = "Default starter profile",
                    lastModified = time(),
                    data = {
                        frames = ns:CopyTable(ns.DEFAULTS.frames),
                        visual = ns:CopyTable(ns.DEFAULTS.visual),
                    },
                },
            },
        }
    end
    if not BarWardenAccountDB.profiles then
        BarWardenAccountDB.profiles = {}
    end

    -- One-time migration: move any per-character profiles into the account store.
    -- Check with next() because an empty table {} is truthy in Lua but has nothing
    -- to migrate, so we still clear the key so it isn't re-checked every login.
    if type(BarWardenDB.profiles) == "table" then
        for name, profile in pairs(BarWardenDB.profiles) do
            if not BarWardenAccountDB.profiles[name] then
                BarWardenAccountDB.profiles[name] = profile
            end
        end
        BarWardenDB.profiles = nil
    end

    -- Point ns.profiles at the account-wide table for all profile operations
    ns.profiles = BarWardenAccountDB.profiles
end
