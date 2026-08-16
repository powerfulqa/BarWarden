-- DB.lua - SavedVariables schema, defaults, and migrations.
-- Author:  Serv
-- Source:  https://github.com/powerfulqa/BarWarden
-- License: GNU GPL v3 (see LICENSE); attribution preservation is required.

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
        -- Notify when a newer BarWarden version is seen on a peer (Comms.lua).
        -- Additive key, backfilled by MergeDefaults on existing saves.
        versionAlerts = true,
        -- Hide Blizzard's default player frame (Options_General.lua). A pure
        -- user preference, addon-wide rather than per-group: a resource group
        -- duplicates what that frame already shows, but a second resource
        -- group must not fight the first over hiding it, and the owner asked
        -- for a plain tickbox, not an automatic rule tied to whether a
        -- resource group exists. See ns:ApplyPlayerFrameHidden (Core.lua) for
        -- how this is applied reversibly. Additive key, backfilled by
        -- MergeDefaults on existing saves (no schema bump needed, same as
        -- versionAlerts above).
        hidePlayerFrame = false,
        -- Hide Blizzard's default target frame (Options_General.lua),
        -- mirroring hidePlayerFrame above: also addon-wide, also a plain
        -- user preference independent of whether a target resource group
        -- exists. See ns:ApplyTargetFrameHidden (Core.lua). Additive key,
        -- backfilled by MergeDefaults on existing saves (no schema bump
        -- needed, same as hidePlayerFrame).
        hideTargetFrame = false,
        -- Help-tab section collapse state: sectionKey -> true when collapsed.
        -- Seeded so Getting Started is open and the rest start collapsed.
        -- Additive key, backfilled by MergeDefaults on existing saves (no
        -- schema bump needed; see InitDB). Section keys match HELP_ENTRIES
        -- in Options_Help.lua. MergeDefaults fills nil keys only, so a user's
        -- later expand/collapse choices and any newly added section are
        -- preserved / default-collapsed respectively.
        helpCollapsed = {
            trackingModes   = true,
            autoTracking    = true,
            conditions      = true,
            visuals         = true,
            profiles        = true,
            activity        = true,
            troubleshooting = true,
            unitFrames      = true,
        },
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
        showStacks = true,
        -- Stack badge size/colour. Defaults match the fixed template the
        -- badge used before these settings existed (NumberFontNormalSmall:
        -- Fonts\ARIALN.TTF at 12px, white), so nothing changes until the
        -- owner moves either one.
        stackFontSize = 12,
        stackColor = { r = 1, g = 1, b = 1 },
        colorMode = "CLASS",
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
            -- Character-stat resources
            ["Health"]       = { r = 0.1, g = 0.9, b = 0.1 },
            ["Mana"]         = { r = 0.2, g = 0.4, b = 0.9 },
            ["Energy"]       = { r = 1.0, g = 0.9, b = 0.2 },
            ["Rage"]         = { r = 0.9, g = 0.1, b = 0.1 },
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

    -- Unit frames (UnitFrames.lua): the conventional portrait + name/level +
    -- health/power-bars + values-column widget, as a second, separate way to
    -- show the same data a resource group already can - the owner picks
    -- whichever reads better, and this table is unrelated to `frames` above
    -- (that key was already taken by bar groups). Keyed by unit ("player" for
    -- now; target/tot/pet/focus/party join later, each just another key
    -- here), not a single hardcoded shape, so a later slice only has to add a
    -- key and a unit-token mapping, not a new schema. `enabled` defaults false
    -- so nothing appears on screen for an existing install until the owner
    -- opts in on the new Frames tab; unlike `frames`, this table's contents
    -- ARE safe to MergeDefaults into (a fixed set of per-unit settings, not a
    -- user-authored array), so it is treated exactly like `global`/`visual`/
    -- `minimap` in ns:InitDB below rather than needing frames' own no-merge
    -- carve-out. No `position` key here on purpose: a unit frame with no
    -- saved position yet falls back to a hardcoded screen spot the same way
    -- ns:CreateGroupFrame does for a brand-new group, rather than
    -- MergeDefaults planting a placeholder anchor no drag ever produced.
    unitFrames = {
        player = {
            enabled      = false,
            scale        = 1.0,
            showPortrait = true,
            -- "2D" is Blizzard's flat portrait image, "3D" a live model of
            -- the character. 2D is the default because a model cannot render
            -- a unit the client cannot see, so it is the one that always
            -- works; the 3D path falls back to it automatically.
            portraitStyle = "2D",
            showName     = true,
            showLevel    = true,
            showValues   = true,
            -- Empty font means "use the addon-wide font from Visuals". Size
            -- 0 means the same for size. Storing "inherit" as empty/zero
            -- rather than copying the current global keeps a frame following
            -- a later Visuals change instead of freezing whatever the global
            -- happened to be when the frame was first built.
            nameFont      = "",
            nameFontSize  = 0,
            valueFont     = "",
            valueFontSize = 0,
            -- Where the numbers sit: "COLUMN" beside the bars, "ONBAR" on
            -- them. showValues == false hides them either way.
            valuePlacement = "COLUMN",
            barHeight    = 16,
            -- Height of a rune / combo point strip. Deliberately shorter
            -- than barHeight: giving a rune slot the same weight as health
            -- is what made the frame read as a stack of identical bars
            -- rather than a unit frame. 0 means "work it out from Bar
            -- Height" (see ns:PlanUnitFrameRows).
            secondaryBarHeight = 0,
            -- Opacity, one per part of the frame so each can be faded on its
            -- own. 1.0 is X-Perl's solid black panel. Kept as four keys
            -- rather than one because they genuinely want different values:
            -- a see-through panel still wants a solid portrait box (a 3D
            -- model is transparent around the character, so a faded box
            -- shows the world through its head) and usually a solid border,
            -- or the frame stops reading as a frame at all.
            frameOpacity    = 1.0,
            portraitOpacity = 1.0,
            barOpacity      = 1.0,
            borderOpacity   = 1.0,
            -- Runes as three ready-count rows rather than six. Defaulted ON
            -- here and OFF for resource groups on purpose: a group predates
            -- this and must keep its six-bar view, a frame is new and six
            -- rune rows are the main thing that made it look cluttered.
            pairRunes    = true,
            -- Resource families the owner has switched OFF (see
            -- ns.RESOURCE_FAMILIES / ns:FilterResourceEntries, Trackers.lua).
            -- Stores what is hidden rather than what is shown so that an
            -- empty table means "show everything" - which is what every save
            -- written before this existed already means, hence no migration
            -- and no schema bump. Written through a set closure rather than a
            -- `db =` path because ns:DBSet validates paths against this
            -- schema and the family keys are user data, not schema.
            hiddenResources = {},
            -- Pin the ticked power types so they stay on the frame even when
            -- they are not the pool currently in use. Only the player frame
            -- does this; see the target entry below.
            pinPowerTypes = true,
            -- X-Perl's own default bar skin, so an enabled unit frame looks
            -- like a unit frame out of the box rather than inheriting
            -- whatever texture the player chose for their timer bars.
            barTexture   = "XP Perl v2",
        },

        -- Target and target's target.
        --
        -- These deliberately carry FEWER keys than the player above, and the
        -- difference is the point rather than an oversight: no
        -- hiddenResources, no pairRunes, no pinPowerTypes. A target frame
        -- shows what the target actually has - health plus its current power
        -- type - the way the default UI does. Adding the player's
        -- resource-choice keys here for symmetry would create settings that
        -- either do nothing or offer bars a target cannot have.
        -- docs/CODE_REVIEW.md item 25 has the full reasoning; read it before
        -- "completing" these tables.
        --
        -- Everything cosmetic IS shared, because there is no reason for a
        -- target frame to look different from the player's.
        target = {
            enabled      = false,
            scale        = 1.0,
            showPortrait = true,
            portraitStyle = "2D",
            showName     = true,
            showLevel    = true,
            showValues   = true,
            nameFont      = "",
            nameFontSize  = 0,
            valueFont     = "",
            valueFontSize = 0,
            valuePlacement = "COLUMN",
            barHeight    = 16,
            secondaryBarHeight = 0,
            frameOpacity    = 1.0,
            portraitOpacity = 1.0,
            barOpacity      = 1.0,
            borderOpacity   = 1.0,
            barTexture   = "XP Perl v2",
        },

        targettarget = {
            enabled      = false,
            scale        = 1.0,
            showPortrait = true,
            portraitStyle = "2D",
            showName     = true,
            showLevel    = true,
            showValues   = true,
            nameFont      = "",
            nameFontSize  = 0,
            valueFont     = "",
            valueFontSize = 0,
            valuePlacement = "COLUMN",
            barHeight    = 16,
            secondaryBarHeight = 0,
            frameOpacity    = 1.0,
            portraitOpacity = 1.0,
            barOpacity      = 1.0,
            borderOpacity   = 1.0,
            barTexture   = "XP Perl v2",
        },
    },

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

    -- Snapshot the layout before we mutate it, so a bad upgrade is recoverable.
    ns:BackupFrames("schema " .. savedVersion .. " to " .. CURRENT_SCHEMA)

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

-- Canonicalise + backfill a frames array, in place. Idempotent, so it is safe
-- to run on every load and on ANY frame source - the live DB, a loaded
-- profile, an imported string, a starter preset - not just the schema-
-- versioned live DB. This closes the v1 gap where profile-load / import
-- bypassed migration and arrived with legacy fields (bars that never tracked).
-- It only renames legacy fields and fills nil sub-tables; it NEVER clears an
-- identity field (spellName / spellId / itemId / trackMode).
function ns:MigrateFrames(frames)
    if type(frames) ~= "table" then return frames end
    for _, f in ipairs(frames) do
        if type(f) == "table" then
            if f.sortMode == nil then f.sortMode = "manual" end
            -- Per-group default backfill. The layout code reads these on every
            -- relayout, so a group saved before a field existed (or imported
            -- from a legacy profile) must still resolve to a coherent anchor.
            -- Fills nils only; an existing position is never overwritten.
            if f.growDirection == nil then f.growDirection = "DOWN" end
            if f.columns == nil or f.columns < 1 then f.columns = 1 end
            -- Rename: autoIconOnly -> iconOnly. Icon Only was an Auto Track-
            -- only tickbox; it is now a general Bar Overrides setting so a
            -- hand-made group can use it too. Same idempotent legacy-field-
            -- rename shape as bar.spell / bar.spellInput / bar.target below -
            -- runs on every load regardless of schemaVersion, so no schema
            -- bump is needed, and only fills iconOnly when it is still nil so
            -- a value already set some other way is never clobbered.
            if f.autoIconOnly ~= nil then
                if f.iconOnly == nil then f.iconOnly = f.autoIconOnly end
                f.autoIconOnly = nil
            end
            if type(f.position) ~= "table" or f.position.point == nil then
                f.position = { point = "TOPLEFT", relativePoint = "BOTTOMLEFT", x = 100, y = 400 }
            end
            f.bars = f.bars or {}
            for _, bar in ipairs(f.bars) do
                if type(bar) == "table" then
                    -- Legacy field renames (idempotent: only act if present).
                    local s = bar.spell
                    if s ~= nil then
                        if type(s) == "number" then
                            if bar.trackMode == "Item" then
                                bar.itemId = bar.itemId or s
                            else
                                bar.spellId = bar.spellId or s
                            end
                        elseif type(s) == "string" and s ~= "" then
                            bar.spellName = bar.spellName or s
                        end
                        bar.spell = nil
                    end
                    if bar.spellInput ~= nil then
                        bar.spellName = bar.spellName or bar.spellInput
                        bar.spellInput = nil
                    end
                    if bar.target ~= nil then
                        bar.unit = bar.unit or bar.target
                        bar.target = nil
                    end
                    -- Per-bar default backfill: guarantee the sub-tables the
                    -- engine reads exist, so adding a new per-bar field can
                    -- never strand a bar saved before that field existed.
                    -- Fills nils only; identity fields untouched.
                    if bar.conditions == nil then bar.conditions = {} end
                    if bar.display == nil then bar.display = {} end
                end
            end
        end
    end
    return frames
end

-- ----------------------------------------------------------------------------
-- What a profile carries.
--
-- These two functions exist because the answer used to be written out
-- separately at four call sites (create, save, load, and the import
-- validator), and they drifted: unit frames were added as a new top-level
-- table and none of the four learned about them, so every Frames-tab setting
-- - portrait style, fonts, sizes, the four opacity sliders, which resources
-- show - silently failed to travel with an exported profile. The bug was not
-- that someone forgot a line; it was that there were four places to forget.
--
-- Anything added to a profile from here on goes in PROFILE_SECTIONS and is
-- picked up by all of them at once.
-- ----------------------------------------------------------------------------

-- `migrate` runs on load for sections whose shape can predate the current
-- schema; `merge` backfills keys added since the profile was saved, so a
-- profile written before a setting existed does not read it back as nil and
-- re-persist an incomplete table on the next Save.
local PROFILE_SECTIONS = {
    { key = "frames",     migrate = "MigrateFrames" },
    { key = "visual",     merge = true },
    { key = "unitFrames", merge = true },
}

-- Snapshot the live config into a fresh table suitable for storing in a
-- profile or serialising for export.
function ns:CaptureProfileData()
    local data = {}
    if not ns.db then return data end
    for _, section in ipairs(PROFILE_SECTIONS) do
        if type(ns.db[section.key]) == "table" then
            data[section.key] = ns:CopyTable(ns.db[section.key])
        end
    end
    return data
end

-- Restore a profile's data over the live config. Only sections actually
-- present are touched, so loading a profile saved before unit frames existed
-- leaves the current unit frames alone rather than wiping them.
--
-- Does NOT back up first: every caller has its own view of whether a backup
-- is warranted (and what reason to record), and they all take one already.
function ns:ApplyProfileData(data)
    if type(data) ~= "table" or not ns.db then return end
    for _, section in ipairs(PROFILE_SECTIONS) do
        local incoming = data[section.key]
        if type(incoming) == "table" then
            ns.db[section.key] = ns:CopyTable(incoming)
            if section.migrate and ns[section.migrate] then
                ns[section.migrate](ns, ns.db[section.key])
            end
            if section.merge and ns.MergeDefaults and ns.DEFAULTS[section.key] then
                ns:MergeDefaults(ns.db[section.key], ns.DEFAULTS[section.key])
            end
        end
    end
end

-- Does this decoded import string carry anything we recognise? Used by the
-- import validator so it accepts a profile carrying only unit frames rather
-- than insisting on frames/visual specifically.
function ns:ProfileDataHasContent(data)
    if type(data) ~= "table" then return false end
    for _, section in ipairs(PROFILE_SECTIONS) do
        if type(data[section.key]) == "table" then return true end
    end
    return false
end

-- Pre-migration safety net: snapshot the current frames into a small ring of
-- timestamped backups before anything mutates them, so a bad upgrade or a
-- destructive load is recoverable via ns:RestoreLastBackup(). Kept to the
-- last few; skips empty layouts (nothing worth saving).
local MAX_BACKUPS = 3
function ns:BackupFrames(reason)
    if not BarWardenDB or type(BarWardenDB.frames) ~= "table" then return end
    if #BarWardenDB.frames == 0 then return end
    BarWardenDB.backups = BarWardenDB.backups or {}
    table.insert(BarWardenDB.backups, 1, {
        t = (time and time()) or 0,
        reason = reason or "migration",
        frames = ns:CopyTable(BarWardenDB.frames),
    })
    while #BarWardenDB.backups > MAX_BACKUPS do
        table.remove(BarWardenDB.backups)
    end
end

-- Restore the most recent frames backup. Returns true if one was restored.
function ns:RestoreLastBackup()
    if not BarWardenDB or type(BarWardenDB.backups) ~= "table" then return false end
    local b = BarWardenDB.backups[1]
    if not b or type(b.frames) ~= "table" then return false end
    -- Snapshot what we are about to replace. Restoring is destructive like
    -- every other path that swaps `frames` wholesale, so it has to be undoable
    -- too: without this, restoring by mistake threw away the current layout
    -- with nothing left to go back to.
    ns:BackupFrames("before restore")
    BarWardenDB.frames = ns:CopyTable(b.frames)
    return true
end

-- ----------------------------------------------------------------------------
-- Import from a sibling "BarWarden v1" install
--
-- The parallel BarWarden V2 test build runs alongside the live v1 addon in the
-- same client, so v2 can read v1's in-memory SavedVariables and offer a
-- one-click layout import - no export/paste needed.
--
-- V1_DB_NAME is written split ("BarWarden" .. "DB") ON PURPOSE: the v2-test
-- deploy script rewrites the contiguous token BarWardenDB -> BarWardenV2DB, but
-- must NOT rewrite this, so it keeps pointing at v1's data. In the normal
-- single-addon release, this name equals our own DB global, so GetV1Layout
-- finds "the same table" and returns nil (nothing separate to import).
-- ----------------------------------------------------------------------------
local V1_DB_NAME = "BarWarden" .. "DB"

-- Return v1's saved layout (a migrated copy of its frames + visual) if a
-- SEPARATE v1 install is loaded, else nil (including the release case where
-- v1's DB is our DB).
function ns:GetV1Layout()
    local v1 = _G[V1_DB_NAME]
    if type(v1) ~= "table" then return nil end
    if v1 == BarWardenDB then return nil end          -- same addon: nothing separate
    if type(v1.frames) ~= "table" or #v1.frames == 0 then return nil end
    local layout = { frames = ns:CopyTable(v1.frames) }
    if type(v1.visual) == "table" then layout.visual = ns:CopyTable(v1.visual) end
    ns:MigrateFrames(layout.frames)
    return layout
end

-- Copy v1's layout into this addon's DB (backs up the current layout first).
-- Returns the number of bars imported, or nil if there was nothing to import.
function ns:ImportFromV1()
    local layout = ns:GetV1Layout()
    if not layout then return nil end
    ns:BackupFrames("before import from v1")
    BarWardenDB.frames = layout.frames
    if layout.visual then
        BarWardenDB.visual = layout.visual
        ns:MergeDefaults(BarWardenDB.visual, ns.DEFAULTS.visual)
    end
    ns.db = BarWardenDB
    local bars = 0
    for _, f in ipairs(BarWardenDB.frames) do bars = bars + #(f.bars or {}) end
    if ns.FireCallback then ns:FireCallback("OnProfileChanged", nil) end
    return bars
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
        -- Unit frames: a brand-new sub-table with no legacy predecessor to
        -- migrate FROM (unlike the minimap block above, which converts old
        -- global.minimapIcon* keys), so a plain create-or-MergeDefaults here
        -- is the whole story. No CURRENT_SCHEMA bump needed for the same
        -- reason global.hidePlayerFrame/versionAlerts/helpCollapsed above
        -- needed none: MergeDefaults backfills every existing save the
        -- moment this code ships, so there is nothing left for a versioned
        -- migration pass to do.
        if type(BarWardenDB.unitFrames) ~= "table" then
            BarWardenDB.unitFrames = ns:CopyTable(ns.DEFAULTS.unitFrames)
        else
            ns:MergeDefaults(BarWardenDB.unitFrames, ns.DEFAULTS.unitFrames)
        end
    end
    ns.db = BarWardenDB

    -- Canonicalise + backfill the live frames every load (idempotent). This
    -- guarantees old bars gain any newly-added per-bar sub-table, and is the
    -- same entry point profile-load / import / starter route through, so no
    -- frame source can arrive un-migrated.
    ns:MigrateFrames(BarWardenDB.frames)

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
