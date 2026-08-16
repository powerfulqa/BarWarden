-- Trackers.lua - Per-trackMode checkers (aura, cooldown, resource modes).
-- Author:  Serv
-- Source:  https://github.com/powerfulqa/BarWarden
-- License: GNU GPL v3 (see LICENSE); attribution preservation is required.

local addonName, ns = ...

local GetTime = GetTime
local type, tonumber, tostring = type, tonumber, tostring
local ceil = math.ceil

-- ============================================================================
-- Trackers.lua - Canonical tracking mode implementations.
-- Each checker returns (isActive, remaining, duration, icon, name, stacks).
-- Called exclusively via ns:CheckTracker(barConfig) from BarEngine.lua.
-- ============================================================================

local GCD_THRESHOLD = ns.GCD_THRESHOLD
local MAX_AURA_INDEX = ns.MAX_AURA_INDEX

-- Discard slot for multi-return calls. Without a file-scope local, every
-- `a, _, b = GetSpellInfo(...)` in here wrote to the GLOBAL `_` - on a 4 Hz
-- path, and the addon otherwise adds no globals at all.
local _

-- ns.SpellDurations: optional per-spell cooldown-duration override.
-- Keys are numeric spell IDs; values are seconds. When present, CheckCooldown
-- prefers the override over GetSpellCooldown's reported duration. Empty by
-- default. Users can populate this to work around private-server CD patches
-- where GetSpellCooldown returns the wrong value.
--
-- Example (paste into a user-addon or directly append in Trackers.lua):
--   ns.SpellDurations[47568] = 60    -- Empower Rune Weapon forced to 60 s
ns.SpellDurations = ns.SpellDurations or {}

-- stableExpiry prevents bar jitter from fluctuating server expiration times.
-- Key: "unit:spellId_or_name". If the server returns a shorter expiration
-- than what we last saw, we keep the longer cached value.
local stableExpiry = {}

-- Wipe stale entries for a specific unit (e.g. on target/focus change) or
-- the whole table. Called from BarEngine event handlers to prevent unbounded
-- growth when units despawn without a final aura scan.
function ns:ClearStableExpiry(unit)
    if unit then
        local prefix = unit .. ":"
        for key in pairs(stableExpiry) do
            if key:sub(1, #prefix) == prefix then
                stableExpiry[key] = nil
            end
        end
    else
        wipe(stableExpiry)
    end
end

-- Bar configs use canonical fields after DB.lua's v1 migration: spellName
-- (string), spellId (number), itemId (number). Legacy `spell`/`spellInput`
-- are migrated away and no longer referenced here.

local function getSpell(barConfig)
    if barConfig.spellName and barConfig.spellName ~= "" then
        return barConfig.spellName
    end
    if barConfig.spellId then
        return tostring(barConfig.spellId)
    end
    return nil
end

local function getUnit(barConfig, default)
    return barConfig.unit or default
end

-- getSpellTokens: split a (possibly comma-separated) spell string into a
-- list of tokens. Each token is either a number (spell ID) or a string
-- (spell name), depending on how the user wrote it. Tokens starting with
-- `@` are expanded to their entries in ns.AuraGroups (AuraGroups.lua),
-- enabling shortcuts like `@Stunned` or `Rupture, @Bleeding`.
--
-- Caches parsed tokens in a module-local table keyed by the raw spell
-- string. Parsing is deterministic from the string, so string → tokens
-- is a stable mapping and the cache never needs explicit invalidation.
-- The table stays out of SavedVariables (prior versions stashed it on
-- barConfig, which is persisted; DB migration v5 wipes the stale keys).
local tokenCache = {}

local function getSpellTokens(spell)
    if not spell then return nil end
    local cached = tokenCache[spell]
    if cached ~= nil then
        -- `false` sentinel means "parsed, yielded zero tokens" (e.g. unknown
        -- @group). Avoids re-parsing the same dud string every scan.
        if cached == false then return nil end
        return cached
    end
    local tokens = {}
    for rawToken in spell:gmatch("([^,]+)") do
        local t = rawToken:match("^%s*(.-)%s*$")
        if t and t ~= "" then
            if t:sub(1, 1) == "@" then
                local groupName = t:sub(2)
                local group = ns.AuraGroups and ns.AuraGroups[groupName]
                if group then
                    for _, id in ipairs(group) do
                        tokens[#tokens + 1] = id
                    end
                end
            else
                local asNumber = tonumber(t)
                tokens[#tokens + 1] = asNumber or t
            end
        end
    end
    local result = #tokens > 0 and tokens or nil
    tokenCache[spell] = result == nil and false or result
    return result
end

-- smoothExpiry: apply stable-expiry smoothing.
-- Returns the effective expiration time (never moves backward).
local function smoothExpiry(key, expirationTime)
    local cached = stableExpiry[key]
    -- Monotonic by design: keep the cached (longer) expiration against ANY
    -- backward jump, so server drift never makes the bar stutter. The known
    -- trade-off (B7 in docs/CODE_REVIEW.md) is that a genuine re-application
    -- with a SHORTER duration is masked until it drains; fixing that cleanly
    -- would need an absolute-time bar model, out of scope for the frozen engine.
    if cached and expirationTime < cached then
        return cached
    end
    stableExpiry[key] = expirationTime
    return expirationTime
end

-- clearExpiry: remove cached expiry entries for a spell that is no longer
-- active (prevents stale entries from accumulating).
local function clearExpiry(unit, numericId, tokens)
    if numericId then
        stableExpiry[unit .. ":" .. tostring(numericId)] = nil
    elseif tokens then
        for _, token in ipairs(tokens) do
            stableExpiry[unit .. ":" .. token] = nil
        end
    end
end

-- ----------------------------------------------------------------------------
-- ScanAuras: shared aura-scan loop for Buff, Debuff, and Proc trackers.
--
-- auraFunc:    UnitBuff or UnitDebuff
-- unit:        unit token to scan
-- barConfig:   the bar's config table (for token cache + onlyMine)
-- spell:       the raw spell string from getSpell()
-- filterMine:  if true, skip auras not cast by "player"
-- ----------------------------------------------------------------------------

-- Casters treated as "you" for the Only-Mine filter. Auras applied by your pet
-- (hunter/warlock/DK pets) or while you drive a vehicle are yours in every way
-- that matters for tracking, so accept those caster tokens too - they exist on
-- 3.3.5a. (Matches how ClassTimer defines "mine".)
local MINE_CASTERS = { player = true, pet = true, vehicle = true }

local function ScanAuras(auraFunc, unit, barConfig, spell, filterMine)
    local numericId = tonumber(spell)
    local tokens = (not numericId) and getSpellTokens(spell) or nil

    for i = 1, MAX_AURA_INDEX do
        local name, _, icon, count, _, duration, expirationTime, caster, _, _, spellId = auraFunc(unit, i)
        if not name then break end

        local match = false
        local matchedToken
        if numericId then
            match = (spellId == numericId)
        elseif tokens then
            for _, token in ipairs(tokens) do
                if type(token) == "number" then
                    if spellId == token then match = true; matchedToken = token; break end
                else
                    if name == token then match = true; matchedToken = token; break end
                end
            end
        end

        if match then
            if filterMine and not MINE_CASTERS[caster] then
                -- Aura matches but wasn't cast by you/your pet/your vehicle; keep scanning
            else
                local remaining = 0
                local maxVal = 0
                local permanent = false
                if duration and duration > 0 and expirationTime then
                    -- Key by the TRACKED token (or numeric id), so clearExpiry
                    -- clears the same key it was stored under - by name, the old
                    -- code stored under spellId but cleared by name and leaked.
                    local key = unit .. ":" .. tostring(numericId or matchedToken)
                    local stableExp = smoothExpiry(key, expirationTime)
                    remaining = stableExp - GetTime()
                    if remaining < 0 then remaining = 0 end
                    maxVal = duration
                else
                    -- Present but no duration (a permanent buff/debuff). Signal
                    -- the engine to show a static "present" bar rather than
                    -- treating remaining==0 as inactive.
                    permanent = true
                end
                return true, remaining, maxVal, icon, name, count or 0, permanent
            end
        end
    end

    -- No match; clear cached expiry entries
    clearExpiry(unit, numericId, tokens)
    return false, 0, 0, nil, spell, 0, false
end

-- ----------------------------------------------------------------------------
-- Auto-tracking feeds
--
-- A group can fill itself from everything on a unit rather than from bars the
-- user named. Each feed resolves to a unit and an aura channel; the name is
-- what gets stored on the group, so it must stay stable.
-- ----------------------------------------------------------------------------

-- The "resources" feed is unlike the four aura feeds above: it has no spell
-- list to scan at all, so it is driven by ns:CollectResources (bottom of this
-- file, after the resource checkers it calls) rather than ns:CollectAutoAuras.
-- unit = "player" still matters here: ns:ScanAutoGroup passes it through the
-- same unitFilter gate the aura feeds use, so a "target" event never wastes
-- a rescan on a group that only ever reads the player.
ns.AUTO_TRACK_FEEDS = {
    playerBuffs     = { unit = "player",       kind = "buff"     },
    playerDebuffs   = { unit = "player",       kind = "debuff"   },
    targetBuffs     = { unit = "target",       kind = "buff"     },
    targetDebuffs   = { unit = "target",       kind = "debuff"   },
    resources       = { unit = "player",       kind = "resource" },
    targetResources = { unit = "target",       kind = "resource" },
    -- "targettarget" is the standard 3.3.5a unit token for "my target's
    -- target" (Blizzard's own TargetFrameToT reads the same token). Every
    -- Unit* call ns:CollectResources already makes (UnitHealth, UnitPower,
    -- UnitPowerMax, UnitPowerType, UnitExists) accepts it exactly like
    -- "target" - no client-side special-casing needed for a third unit.
    totResources    = { unit = "targettarget", kind = "resource" },
}

local function CompareExpiry(a, b)
    -- Always-on auras pin above the timed ones: they never expire, so they have
    -- no place in a soonest-first order. Ties are broken by name because every
    -- one of them shares the same expiry and table.sort is unstable, which would
    -- otherwise reshuffle the block on every scan.
    if a.permanent ~= b.permanent then return a.permanent end
    if a.permanent then return a.name < b.name end
    return a.expirationTime < b.expirationTime
end

-- Collect the auras on a feed's unit, soonest-expiring first.
--
-- opts = { maxBars, maxDuration, onlyMine, skipNames, keepNames, includePermanent }
--   maxDuration tests the aura's FULL duration, not what is left: a one-hour
--   flask with 30 seconds on it is still a flask, and testing remaining time
--   would surface long buffs at the exact moment they ran out. It only ever
--   tests a timed aura; a permanent one has no duration to be too long.
--   skipNames is a set of lower-cased names supplied by the caller, so this
--   function stays pure and the whole filter chain is testable.
--   keepNames is a set of lower-cased names, like skipNames, that must
--   survive truncation to maxBars even if they are not among the soonest to
--   expire. Without it, truncation is unchanged: whichever names sort last
--   are cut, held or not. Keep Bars In Place relies on this: a bar that is
--   already up must not be evicted by truncation just because it happens to
--   have longer left than something newer, or PlaceAutoAuras would read the
--   held name's absence as a fade and free its slot.
--   includePermanent keeps auras with no duration instead of dropping them
--   (off by default: a bar with no countdown says nothing). Each entry is
--   marked `permanent` so callers know which auras have no timer.
function ns:CollectAutoAuras(feed, opts)
    local def = ns.AUTO_TRACK_FEEDS[feed]
    if not def then return {} end

    opts = opts or {}
    local maxBars          = opts.maxBars or 10
    local maxDuration      = opts.maxDuration or 0
    local skipNames        = opts.skipNames
    local keepNames        = opts.keepNames
    local onlyMine         = opts.onlyMine
    local includePermanent = opts.includePermanent
    local auraFunc         = (def.kind == "buff") and UnitBuff or UnitDebuff

    local found = {}
    for i = 1, MAX_AURA_INDEX do
        local name, _, icon, count, _, duration, expirationTime, caster, _, _, spellId =
            auraFunc(def.unit, i)
        if not name then break end

        -- Mirrors the permanent test in ScanAuras above: no duration means a
        -- permanent effect (class auras, presences). Without includePermanent
        -- that is dropped, exactly as before; with it, it is kept and marked.
        local timed = (duration and duration > 0 and expirationTime) and true or false
        local keep = timed or includePermanent
        -- maxDuration only ever tests a timed aura: `timed` guards it here so
        -- a permanent aura with a nil duration cannot reach `duration > maxDuration`.
        if keep and timed and maxDuration > 0 and duration > maxDuration then keep = false end
        if keep and onlyMine and not MINE_CASTERS[caster] then keep = false end
        if keep and skipNames and skipNames[string.lower(name)] then keep = false end

        if keep then
            found[#found + 1] = {
                name           = name,
                icon           = icon,
                spellId        = spellId,
                count          = count or 0,
                duration       = duration,
                expirationTime = expirationTime,
                permanent      = not timed,
            }
        end
    end

    table.sort(found, CompareExpiry)

    if keepNames and #found > maxBars then
        -- Split the sorted list into held and not-held, each keeping the
        -- relative soonest-expiring order it already had. The held ones go
        -- in first (truncated to the cap themselves, so holding more names
        -- than there are slots still cannot overflow it); whatever room is
        -- left fills from the rest, soonest first. Re-sort at the end so the
        -- documented soonest-expiring-first contract holds for any caller
        -- that is not doing stable placement.
        local kept, rest = {}, {}
        for _, a in ipairs(found) do
            if keepNames[string.lower(a.name)] then
                kept[#kept + 1] = a
            else
                rest[#rest + 1] = a
            end
        end
        for i = #kept, maxBars + 1, -1 do
            kept[i] = nil
        end
        for i = 1, #rest do
            if #kept >= maxBars then break end
            kept[#kept + 1] = rest[i]
        end
        table.sort(kept, CompareExpiry)
        found = kept
    else
        for i = #found, maxBars + 1, -1 do
            found[i] = nil
        end
    end

    return found
end

--- Decide which slot each aura occupies when the group is holding positions.
---
--- held[i] is the name currently in slot i, or nil for a free slot. An aura
--- whose name is already held stays where it is, so a bar does not move while
--- it is up. Whatever is left fills the free slots in the order given, which
--- is soonest-expiring first.
---
--- Returns a sparse array: result[i] is the aura for slot i, or nil if that
--- slot has nothing.
function ns:PlaceAutoAuras(held, auras, slotCount)
    local result = {}
    if not auras or #auras == 0 or not slotCount or slotCount <= 0 then
        return result
    end

    -- Held names claim their slot first, first match wins. `claimed` is keyed
    -- by the aura table itself so two slots that remember the same name (a
    -- target with the same debuff from two casters) cannot both grab one
    -- entry: the second slot finds nothing left and falls through to the
    -- free-slot pass below.
    local claimed = {}
    for i = 1, slotCount do
        local name = held and held[i]
        if name then
            for _, a in ipairs(auras) do
                if not claimed[a] and a.name == name then
                    result[i] = a
                    claimed[a] = true
                    break
                end
            end
        end
    end

    -- Free slots fill ascending, taking auras in the order given (soonest-
    -- expiring first), skipping whatever the pass above already claimed.
    local nextAura = 1
    for i = 1, slotCount do
        if not result[i] then
            while nextAura <= #auras and claimed[auras[nextAura]] do
                nextAura = nextAura + 1
            end
            if nextAura > #auras then break end
            result[i] = auras[nextAura]
            claimed[auras[nextAura]] = true
            nextAura = nextAura + 1
        end
    end

    return result
end

local function addResolvedSpellId(names, spellId)
    local resolvedName = GetSpellInfo(spellId)
    if resolvedName then
        names[string.lower(resolvedName)] = true
    end
end

-- Names of auras that a bar in some other group already tracks, lower-cased,
-- for the auto-track "Skip Spells I Already Track" setting.
--
-- Asks whether a bar EXISTS, not whether it is visible right now. Testing
-- visibility would make auras flicker between groups as conditions changed,
-- which is worse than a rule the player can predict.
--
-- Matching is by resolved spell name, since that is what the aura API
-- returns. A bar can be configured by name or by spell id (getSpell above
-- reads `spellName or spellId`), so both are resolved to a name here: an id
-- goes through GetSpellInfo, and a name is used as-is. A numeric token inside
-- a comma-separated spellName (typed in as an id) is likewise resolved.
-- An aura group reference such as "@Stunned" still does not suppress: it only
-- expands to a list of ids at scan time (getSpellTokens), not here. See
-- CODE_REVIEW.md item 16.
function ns:GetTrackedAuraNames(exceptFrameIndex)
    local names = {}
    local frames = BarWardenDB and BarWardenDB.frames
    if not frames then return names end

    for idx, frameData in ipairs(frames) do
        -- An auto group's own bars are dormant, so they track nothing.
        if idx ~= exceptFrameIndex and not frameData.autoTrack and frameData.bars then
            for _, bd in ipairs(frameData.bars) do
                if ns.AURA_TRACK_MODES[bd.trackMode] and bd.enabled ~= false then
                    if bd.spellId then
                        addResolvedSpellId(names, bd.spellId)
                    end
                    if type(bd.spellName) == "string" and bd.spellName ~= "" then
                        -- A bar accepts a comma-separated list of names/ids.
                        for token in string.gmatch(bd.spellName, "[^,]+") do
                            local trimmed = strtrim(token)
                            if trimmed ~= "" then
                                local asId = tonumber(trimmed)
                                if asId then
                                    addResolvedSpellId(names, asId)
                                else
                                    names[string.lower(trimmed)] = true
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    return names
end

--- Combine the "already tracked elsewhere" names with this group's own banned
--- list into the single skip set CollectAutoAuras consumes.
---
--- trackedNames, when supplied, is whatever ns:GetTrackedAuraNames returned
--- for one group's own exceptFrameIndex - a fresh table per call, not one
--- shared across groups. A fresh table is returned here too, rather than
--- mutating trackedNames in place, so a caller that keeps its own reference
--- to that table never sees a stray ban entry appear in it. Either argument
--- may be nil, and both keys are taken verbatim - both are already
--- lower-cased by their producers. Returns nil (not an empty table) when
--- there is nothing to skip at all, so CollectAutoAuras keeps its cheap "no
--- skipNames" path (skipNames is only ever read behind an
--- `if skipNames and skipNames[...]` check there).
function ns:BuildAutoSkipSet(trackedNames, autoBanned)
    if not trackedNames and not autoBanned then return nil end

    local skip = {}
    if trackedNames then
        for name in pairs(trackedNames) do
            skip[name] = true
        end
    end
    if autoBanned then
        for name in pairs(autoBanned) do
            skip[name] = true
        end
    end
    return skip
end

--- The names one auto group skips: those tracked elsewhere, but only while
--- that setting is on, plus the group's own banned list, always.
---
--- Takes the already-fetched trackedNames (or nil) rather than calling
--- ns:GetTrackedAuraNames itself, so this stays pure and the caller keeps
--- deciding when that lookup is worth paying for. The gate on
--- groupData.autoSkipTracked lives HERE, not in the caller: passing a
--- non-nil trackedNames does not mean it gets used, so a caller cannot
--- forget to check the setting before calling this. groupData.autoBanned is
--- always folded in regardless of the setting. Tolerates a nil groupData
--- (nothing to skip). Returns whatever ns:BuildAutoSkipSet returns: nil when
--- there is nothing to skip at all.
function ns:BuildGroupSkipSet(groupData, trackedNames)
    if not groupData then return nil end
    local tracked = groupData.autoSkipTracked and trackedNames or nil
    return ns:BuildAutoSkipSet(tracked, groupData.autoBanned)
end

-- ----------------------------------------------------------------------------
-- Cooldown Tracker
-- ----------------------------------------------------------------------------

local function CheckCooldown(barConfig)
    local spell = getSpell(barConfig)
    if not spell then
        return false, 0, 0, nil, nil, 0
    end

    local spellID = tonumber(spell)
    local spellName, spellIcon, resolvedID

    if spellID then
        spellName, _, spellIcon = GetSpellInfo(spellID)
        resolvedID = spellID
    else
        -- Single GetSpellInfo call captures both name/icon and the numeric ID
        -- used later for the SpellDurations override lookup; the earlier
        -- `select(10, GetSpellInfo(spellName))` repeat call is now redundant.
        spellName, _, spellIcon, _, _, _, _, _, _, resolvedID = GetSpellInfo(spell)
    end

    if not spellName then
        return false, 0, 0, nil, spell, 0
    end

    local start, duration, enabled = GetSpellCooldown(spellID or spellName)

    if not start or enabled ~= 1 then
        return false, 0, 0, spellIcon, spellName, 0
    end

    -- Apply ns.SpellDurations override, if the user has one for this spell.
    if resolvedID and ns.SpellDurations[resolvedID] then
        duration = ns.SpellDurations[resolvedID]
    end

    -- EC-TRAP: discarding cooldowns <= GCD_THRESHOLD (1.5s) looks like it drops real
    -- short cooldowns, but it filters the global cooldown so bars react only to true
    -- cooldowns. Do NOT remove. Threshold lives in Utils.lua (ns.GCD_THRESHOLD).
    if duration <= GCD_THRESHOLD then
        return false, 0, 0, spellIcon, spellName, 0
    end

    local now = GetTime()
    local remaining = (start + duration) - now

    if remaining <= 0 then
        return false, 0, 0, spellIcon, spellName, 0
    end

    return true, remaining, duration, spellIcon, spellName, 0
end

-- ----------------------------------------------------------------------------
-- Buff Tracker
-- Delegates to ScanAuras with UnitBuff; defaults to "player".
-- ----------------------------------------------------------------------------

local function CheckBuff(barConfig)
    local spell = getSpell(barConfig)
    local unit = getUnit(barConfig, "player")
    if not spell then
        return false, 0, 0, nil, nil, 0
    end
    -- Honour Only Mine. Defaults to false for buffs (unlike debuffs): most
    -- tracked buffs are your own anyway, and filtering by default would hide
    -- raid buffs people watch. Passing a hardcoded false made the checkbox a
    -- silent no-op on Buff and Proc bars.
    return ScanAuras(UnitBuff, unit, barConfig, spell, barConfig.onlyMine == true)
end

-- ----------------------------------------------------------------------------
-- Debuff Tracker
-- Delegates to ScanAuras with UnitDebuff; defaults to "target".
-- onlyMine defaults to true so only the player's debuffs are matched.
-- ----------------------------------------------------------------------------

local function CheckDebuff(barConfig)
    local spell = getSpell(barConfig)
    local unit = getUnit(barConfig, "target")
    if not spell then
        return false, 0, 0, nil, nil, 0
    end
    local onlyMine = barConfig.onlyMine
    if onlyMine == nil then onlyMine = true end
    return ScanAuras(UnitDebuff, unit, barConfig, spell, onlyMine)
end

-- ----------------------------------------------------------------------------
-- Item Tracker (item cooldowns: equipped, bag, inventory)
-- ----------------------------------------------------------------------------

local function CheckItem(barConfig)
    -- itemId takes priority; fall back to spellName/spellId for legacy configs
    local itemRef = barConfig.itemId or getSpell(barConfig)
    if not itemRef then
        return false, 0, 0, nil, nil, 0
    end

    local itemID = tonumber(itemRef)
    local itemName, itemIcon

    if itemID then
        itemName = GetItemInfo(itemID)
        itemIcon = GetItemIcon(itemID)
    else
        itemName = itemRef
        itemIcon = GetItemIcon(itemRef)
    end

    local displayName = itemName or tostring(itemRef)

    local start, duration, enabled
    -- EC-TRAP: GetItemCooldown is the correct bare global on 3.3.5a (retail moved it
    -- to C_Container). Do NOT "modernise" to C_Container.GetItemCooldown. See CLAUDE.md.
    if itemID then
        start, duration, enabled = GetItemCooldown(itemID)
    else
        start, duration, enabled = GetItemCooldown(itemRef)
    end

    -- Items do not share the spell global cooldown, so any active cooldown is
    -- real: gate on duration > 0 (0 = not on cooldown), not the spell GCD, so
    -- short on-use item cooldowns are not hidden. (enabled == 1 = usable item.)
    if start and duration and duration > 0 and enabled == 1 then
        local now = GetTime()
        local remaining = (start + duration) - now
        if remaining > 0 then
            return true, remaining, duration, itemIcon, displayName, 0
        end
    end

    return false, 0, 0, itemIcon, displayName, 0
end

-- ----------------------------------------------------------------------------
-- Enchant Tracker (temporary weapon enchants: poisons, shaman buffs, stones)
-- Uses GetWeaponEnchantInfo() which returns enchant data for MH and OH.
-- The "spell" field selects the slot: "mainhand" or "offhand" (default MH).
-- ----------------------------------------------------------------------------

local function CheckEnchant(barConfig)
    -- Determine slot from trackMode: "Enchant OH" = offhand, anything else = mainhand
    local mode = barConfig.trackMode or ""
    local isOH = (mode == "Enchant OH")

    local hasMainEnchant, mainExpires, mainCharges, hasOffEnchant, offExpires, offCharges = GetWeaponEnchantInfo()

    local hasEnchant, expires, charges
    if isOH then
        hasEnchant, expires, charges = hasOffEnchant, offExpires, offCharges
    else
        hasEnchant, expires, charges = hasMainEnchant, mainExpires, mainCharges
    end

    -- Get the weapon icon from the inventory slot
    local invSlot = isOH and 17 or 16  -- 16=MainHand, 17=OffHand
    local icon = GetInventoryItemTexture("player", invSlot)
    -- Use the bar name for display; fall back to slot label
    local displayName = (barConfig.name and barConfig.name ~= "") and barConfig.name
                        or (isOH and "Offhand Enchant" or "Mainhand Enchant")

    if hasEnchant and expires then
        -- GetWeaponEnchantInfo returns milliseconds remaining
        local remaining = expires / 1000
        if remaining > 0 then
            -- Duration is unknown for enchants; use remaining as duration
            return true, remaining, remaining, icon, displayName, charges or 0
        end
    end

    return false, 0, 0, icon, displayName, 0
end

-- ----------------------------------------------------------------------------
-- Totem Tracker (shaman totems, DK ghouls)
-- Uses GetTotemInfo(slot) where slot is 1-4.
-- The "spell" field can be the totem name or slot number (1-4).
-- If a name is given, all 4 slots are searched for a matching totem.
-- ----------------------------------------------------------------------------

local function CheckTotem(barConfig)
    local spell = getSpell(barConfig)
    if not spell then
        return false, 0, 0, nil, nil, 0
    end

    local slotNum = tonumber(spell)

    if slotNum and slotNum >= 1 and slotNum <= 4 then
        -- Direct slot lookup
        local haveTotem, name, startTime, duration, icon = GetTotemInfo(slotNum)
        if haveTotem and name and name ~= "" and duration > 0 then
            local remaining = (startTime + duration) - GetTime()
            if remaining > 0 then
                return true, remaining, duration, icon, name, 0
            end
        end
        return false, 0, 0, nil, "Totem Slot " .. slotNum, 0
    else
        -- Search all 4 slots for a matching totem name
        for slot = 1, 4 do
            local haveTotem, name, startTime, duration, icon = GetTotemInfo(slot)
            if haveTotem and name and name ~= "" then
                if name:lower():find(spell:lower(), 1, true) then
                    if duration > 0 then
                        local remaining = (startTime + duration) - GetTime()
                        if remaining > 0 then
                            return true, remaining, duration, icon, name, 0
                        end
                    end
                end
            end
        end
        return false, 0, 0, nil, spell, 0
    end
end

-- ----------------------------------------------------------------------------
-- Resource Trackers (class resources: combo points, runic power, soul shards,
-- death knight runes).
--
-- Combo Points / Runic Power / Soul Shards are value-based: the bar fills to
-- show current / max and does not count down with time. The engine dispatches
-- these via UpdateResourceBar (BarEngine.lua) instead of the time-based
-- Bar_OnUpdate; see ns.RESOURCE_TRACK_MODES below.
--
-- Runes ARE time-based (rune cooldown), so they use the standard depleting
-- path unchanged. barConfig.spellId selects the rune slot (1..6).
-- ----------------------------------------------------------------------------

local COMBO_ICON       = "Interface\\Icons\\Ability_Rogue_Eviscerate"
local RUNIC_POWER_ICON = "Interface\\Icons\\Spell_Deathknight_EmpowerRuneblade"
local SHARD_ICON       = "Interface\\Icons\\INV_Misc_Gem_Amethyst_02"
local SOUL_SHARD_ITEM_ID = 6265
local DEFAULT_MAX_SOUL_SHARDS = 10
-- Fallback rune CD for when GetRuneCooldown returns zero or has never been
-- called for a slot. Unholy Presence reduces this in-game but 10s is the
-- baseline and a safe default for the "freshly logged in, never used" case.
local DEFAULT_RUNE_CD = 10

-- GetRuneType returns 1=Blood, 2=Unholy, 3=Frost, 4=Death.
local RUNE_ICONS = {
    [1] = "Interface\\Icons\\Spell_Deathknight_BloodPresence",
    [2] = "Interface\\Icons\\Spell_Deathknight_UnholyPresence",
    [3] = "Interface\\Icons\\Spell_Deathknight_FrostPresence",
    [4] = "Interface\\Icons\\Spell_Deathknight_ClassIcon",
}
local RUNE_NAMES = {
    [1] = "Blood Rune",
    [2] = "Unholy Rune",
    [3] = "Frost Rune",
    [4] = "Death Rune",
}

local function CheckComboPoints(barConfig)
    local cp = GetComboPoints("player", "target") or 0
    -- Always show the bar (even at 0 CP) so the user sees the resource slot.
    return true, cp, 5, COMBO_ICON, "Combo Points", cp
end

local function CheckRunicPower(barConfig)
    -- Power type 6 is SPELL_POWER_RUNIC_POWER on 3.3.5a.
    local power = UnitPower("player", 6) or 0
    local maxPower = UnitPowerMax("player", 6) or 100
    if maxPower <= 0 then maxPower = 100 end
    return true, power, maxPower, RUNIC_POWER_ICON, "Runic Power", power
end

local function CheckSoulShards(barConfig)
    local count = GetItemCount(SOUL_SHARD_ITEM_ID) or 0
    local max = tonumber(barConfig.maxValue) or DEFAULT_MAX_SOUL_SHARDS
    if max <= 0 then max = DEFAULT_MAX_SOUL_SHARDS end
    local icon = GetItemIcon(SOUL_SHARD_ITEM_ID) or SHARD_ICON
    return true, count, max, icon, "Soul Shards", count
end

-- Runes are a resource-style bar (see RESOURCE_TRACK_MODES below) even though
-- the underlying data is a countdown. The bar FILLS as the rune regenerates
-- and stays full when ready, matching the intuition from Blizzard's default
-- DK rune display. Text shows "Ns" countdown while on CD, blank when ready.
--
-- Returns (isActive, current, max, icon, name, stacks, runeType) where:
--   current  = max when ready, 0..max as the rune regenerates
--   max      = the rune's cooldown duration (10 s baseline; server may vary)
--   stacks   = ceil(cdRemaining) in seconds, 0 means ready (used by the text
--              display in UpdateResourceBar)
--   runeType = 1 Blood, 2 Unholy, 3 Frost, 4 Death (GetRuneType's own
--              numbering). Returned so ns:CollectResources can carry it on
--              the entry, letting ns:GetResourcePowerColor (Conditions.lua)
--              colour the bar by rune type instead of falling through to the
--              addon-wide default - see that function's own comment.
local function CheckRunes(barConfig)
    -- Slot lives in spellId (numeric 1..6). spellName falls back for users who
    -- typed it in the text box as a string.
    local slot = tonumber(barConfig.spellId) or tonumber(barConfig.spellName) or 1
    if slot < 1 or slot > 6 then slot = 1 end

    local runeType = GetRuneType and GetRuneType(slot) or 1
    local icon = RUNE_ICONS[runeType] or RUNE_ICONS[1]
    local name = RUNE_NAMES[runeType] or "Rune"

    local start, duration, ready = GetRuneCooldown(slot)

    -- Never-used slot or private-server API glitch: treat as ready at baseline.
    if not duration or duration <= 0 then
        return true, DEFAULT_RUNE_CD, DEFAULT_RUNE_CD, icon, name, 0, runeType
    end

    -- Ready: full bar, no countdown text.
    if ready then
        return true, duration, duration, icon, name, 0, runeType
    end

    -- On cooldown: bar fills from 0 toward max as the rune regenerates.
    local cdRemaining = (start + duration) - GetTime()
    if cdRemaining <= 0 then
        return true, duration, duration, icon, name, 0, runeType
    end

    local current = duration - cdRemaining
    if current < 0 then current = 0 end

    return true, current, duration, icon, name, ceil(cdRemaining), runeType
end

-- Base rune types the paired view groups into rows, in display order (this
-- is also GetRuneType's own numbering for these three; 4 is Death, handled
-- separately below).
local BASE_RUNE_TYPES = { 1, 2, 3 }

local RUNE_PAIR_NAMES = {
    [1] = "Blood Runes",
    [2] = "Unholy Runes",
    [3] = "Frost Runes",
}

-- buildRunePairSlots: assign the six rune slots to the three base-type
-- "pairs" for the Pair Runes by Type view (commit 3), by CURRENT GetRuneType
-- rather than a hardcoded slot->type mapping - the type-to-slot layout is
-- not guaranteed contiguous on 3.3.5a (slots 1/2 are not guaranteed to both
-- be Blood, etc.), so the only honest source is asking the game per slot.
--
-- The complication: any rune can be temporarily converted to a Death rune
-- (GetRuneType returns 4), and a converted slot has no way to report what it
-- "really" is. Rather than spawn a fourth row for Death, or drop a converted
-- rune from the count, a slot reporting type 4 is folded into whichever base
-- bucket (1 Blood, 2 Unholy, 3 Frost) is still short a member, processed in
-- that order using slots in ascending slot-number order. On 3.3.5a the type-
-- to-slot layout for the three base types is itself stable per slot number
-- (each base type occupies a fixed pair of slots that just are not
-- guaranteed to be adjacent pairs like 1-2/3-4/5-6), so backfilling short
-- buckets in ascending type order from slots in ascending slot-number order
-- reconstructs the true pairing for the common single-conversion case; under
-- multiple simultaneous conversions the specific attribution is a best
-- effort, but the ready count and the "three rows of two" shape are always
-- correct regardless, since a converted slot's own cooldown is still read
-- from the physical slot itself (see collectRunePairEntries below), not
-- assumed from whichever pair it lands under.
--
-- Returns { [1] = {slot, slot}, [2] = {...}, [3] = {...} }.
local function buildRunePairSlots()
    local buckets = { [1] = {}, [2] = {}, [3] = {} }
    local overflow = {}
    for slot = 1, 6 do
        local runeType = GetRuneType and GetRuneType(slot) or 1
        if (runeType == 1 or runeType == 2 or runeType == 3) and #buckets[runeType] < 2 then
            table.insert(buckets[runeType], slot)
        else
            overflow[#overflow + 1] = slot
        end
    end
    for _, t in ipairs(BASE_RUNE_TYPES) do
        while #buckets[t] < 2 and #overflow > 0 do
            table.insert(buckets[t], table.remove(overflow, 1))
        end
    end
    return buckets
end

-- collectRunePairEntries: the Pair Runes by Type view - one entry per base
-- type (Blood/Unholy/Frost), each a ready-count value bar ("2/2" when both
-- of that type are up, "1/2" while one recharges). Reuses CheckRunes for
-- each physical slot's ready state rather than re-reading GetRuneCooldown
-- directly, so both views agree on what "ready" means. `trackMode` is left
-- nil (unlike the six-bar view's "Runes"), so UpdateResourceBar renders the
-- plain current/max fraction text instead of the rune-specific "Ns"
-- countdown - a ready-count pair is a value bar, not a countdown.
local function collectRunePairEntries()
    local buckets = buildRunePairSlots()
    local list = {}
    for _, t in ipairs(BASE_RUNE_TYPES) do
        local slots = buckets[t]
        if #slots > 0 then
            local ready = 0
            local icon
            for _, slot in ipairs(slots) do
                local _, _, _, slotIcon, _, stacks = CheckRunes({ spellId = slot })
                icon = icon or slotIcon
                if not stacks or stacks == 0 then ready = ready + 1 end
            end
            list[#list + 1] = {
                key = "runepair" .. t, label = RUNE_PAIR_NAMES[t], current = ready,
                max = #slots, icon = icon or RUNE_ICONS[t], stacks = ready, runeType = t,
            }
        end
    end
    return list
end

-- collectRuneEntries: the DK rune display, in the shape ns:CollectResources'
-- addEntry expects (key/label/current/max/icon/stacks/trackMode/runeType) -
-- either all six slots (default) or the three type pairs above (`paired`,
-- from groupData.autoPairRunes). Pulled out of CollectResources so both the
-- unconditional "always visible" block and the pinned-extras block below can
-- build the exact same list without duplicating the per-slot CheckRunes
-- call - see the pin-ordering fix's own comment for why two call sites need
-- this.
local function collectRuneEntries(paired)
    if paired then
        return collectRunePairEntries()
    end
    local list = {}
    for slot = 1, 6 do
        local _, cur, mx, icon, name, stacks, runeType = CheckRunes({ spellId = slot })
        list[#list + 1] = {
            key = "rune" .. slot, label = name, current = cur, max = mx,
            icon = icon, stacks = stacks, trackMode = "Runes", runeType = runeType,
        }
    end
    return list
end

-- ----------------------------------------------------------------------------
-- Capability probes for the PLAYER's own DK/Warlock-flavoured pools, used by
-- ns:CollectResources below INSTEAD OF UnitClass("player") - see the long
-- comment above that function for the full reasoning.
-- ----------------------------------------------------------------------------

-- EC-TRAP: this reads GetRuneCooldown's raw `duration` across all six slots
-- rather than trusting UnitClass - it looks like the class check that used
-- to gate Runes is simply missing. Do NOT reintroduce
-- `UnitClass("player") == "DEATHKNIGHT"` here: on a classless private server
-- every character can report the same class token while some genuinely have
-- runes and some do not, so the class token is not evidence either way (see
-- the CollectResources comment below). `duration > 0` is: a slot that was
-- never granted real rune data reads back duration 0 (tests/mock_wow.lua's
-- default stub models exactly that "no data" case), while a genuine rune -
-- ready or on cooldown - always carries its real cooldown length. GetRuneType
-- is deliberately NOT probed here: unlike duration, it returns a
-- plausible-looking type (see its own default mock stub) even for a slot
-- that does not exist at all, so it cannot tell "has runes" from "has none".
local function HasRunes()
    for slot = 1, 6 do
        local _, duration = GetRuneCooldown(slot)
        if duration and duration > 0 then return true end
    end
    return false
end

-- Power type 6 (Runic Power): UnitPowerMax("player", 6) > 0 is a direct
-- capability read, the same raw global the current-power-type step further
-- below already calls unmasked. CheckRunicPower is NOT usable as a probe: it
-- deliberately forces a non-zero max as a display fallback for a hand-placed
-- bar (see its own comment above), so calling it would report "has Runic
-- Power" for every character regardless of whether the pool is real.
local function HasRunicPower()
    local maxPower = UnitPowerMax("player", 6)
    return maxPower ~= nil and maxPower > 0
end

-- Health / Mana / Energy / Rage: the plain character-stat resources, added
-- alongside the class resources above. Same value-not-timer reasoning: a
-- health bar does not count down, it just reflects UnitHealth right now.
-- Zero-max is guarded the same way CheckRunicPower guards it (a real client
-- never actually returns 0 for the player's own health/power pool, but the
-- fallback keeps a mocked or otherwise degenerate read from dividing by
-- zero in UpdateResourceBar's current/max fill calculation).
local HEALTH_ICON = "Interface\\Icons\\Spell_Holy_FlashHeal"
local MANA_ICON   = "Interface\\Icons\\INV_Enchant_EssenceManaLarge"
local RAGE_ICON   = "Interface\\Icons\\Ability_Warrior_Rampage"
local ENERGY_ICON = "Interface\\Icons\\Ability_Rogue_Sprint"

-- Health/Mana/Rage/Energy read whichever unit barConfig names, defaulting to
-- "player" via the same getUnit helper Buff/Debuff use above - a hand-placed
-- bar never sets barConfig.unit today, so this is a no-op for it; it exists
-- so ns:CollectResources (below) can ask for a target's reading through the
-- exact same checker instead of a duplicated one.
local function CheckHealth(barConfig)
    local unit = getUnit(barConfig, "player")
    local current = UnitHealth(unit) or 0
    local max = UnitHealthMax(unit) or 0
    if max <= 0 then max = 1 end
    return true, current, max, HEALTH_ICON, "Health", current
end

local function CheckMana(barConfig)
    -- Power type 0 is SPELL_POWER_MANA on 3.3.5a.
    local unit = getUnit(barConfig, "player")
    local power = UnitPower(unit, 0) or 0
    local maxPower = UnitPowerMax(unit, 0) or 0
    if maxPower <= 0 then maxPower = 1 end
    return true, power, maxPower, MANA_ICON, "Mana", power
end

local function CheckRage(barConfig)
    -- Power type 1 is SPELL_POWER_RAGE on 3.3.5a.
    local unit = getUnit(barConfig, "player")
    local power = UnitPower(unit, 1) or 0
    local maxPower = UnitPowerMax(unit, 1) or 0
    if maxPower <= 0 then maxPower = 1 end
    return true, power, maxPower, RAGE_ICON, "Rage", power
end

local function CheckEnergy(barConfig)
    -- Power type 3 is SPELL_POWER_ENERGY on 3.3.5a.
    local unit = getUnit(barConfig, "player")
    local power = UnitPower(unit, 3) or 0
    local maxPower = UnitPowerMax(unit, 3) or 0
    if maxPower <= 0 then maxPower = 1 end
    return true, power, maxPower, ENERGY_ICON, "Energy", power
end

-- Event-driven resource modes. BarEngine's ScanBar checks this set to pick
-- the static (UpdateResourceBar) path instead of time-based ActivateBar.
-- Runes are here even though their data is a cooldown countdown, because we
-- want the bar to FILL (not deplete) as the rune regenerates; the
-- 0.25 s scan loop + RUNE_POWER_UPDATE / RUNE_TYPE_UPDATE events refresh
-- the fill level at a rate that is visibly smooth enough in practice.
ns.RESOURCE_TRACK_MODES = {
    ["Combo Points"] = true,
    ["Runic Power"]  = true,
    ["Soul Shards"]  = true,
    ["Runes"]        = true,
    ["Health"]       = true,
    ["Mana"]         = true,
    ["Energy"]       = true,
    ["Rage"]         = true,
}

function ns:IsResourceTrackMode(mode)
    return ns.RESOURCE_TRACK_MODES[mode] == true
end

-- Dispatch table keyed by barConfig.trackMode.
-- Proc is just Buff restricted to "player"; CheckBuff already defaults unit
-- to "player" via getUnit(barConfig, "player"), so no separate function exists.
ns.TRACKERS = {
    ["Cooldown"]     = CheckCooldown,
    ["Buff"]         = CheckBuff,
    ["Debuff"]       = CheckDebuff,
    ["Proc"]         = CheckBuff,
    ["Item"]         = CheckItem,
    ["Enchant"]      = CheckEnchant,
    ["Enchant MH"]   = CheckEnchant,
    ["Enchant OH"]   = CheckEnchant,
    ["Totem"]        = CheckTotem,
    ["Combo Points"] = CheckComboPoints,
    ["Runic Power"]  = CheckRunicPower,
    ["Soul Shards"]  = CheckSoulShards,
    ["Runes"]        = CheckRunes,
    ["Health"]       = CheckHealth,
    ["Mana"]         = CheckMana,
    ["Energy"]       = CheckEnergy,
    ["Rage"]         = CheckRage,
}

-- Check tracking state for `barConfig` by dispatching on its trackMode.
-- See the file header for the returned tuple shape.
function ns:CheckTracker(barConfig)
    local trackMode = barConfig.trackMode
    if not trackMode then
        return false, 0, 0, nil, nil, 0
    end

    local checker = ns.TRACKERS[trackMode]
    if not checker then
        return false, 0, 0, nil, nil, 0
    end

    return checker(barConfig)
end

-- ----------------------------------------------------------------------------
-- ns:CollectResources - pure collector for the "resources" auto-track feed.
--
-- Unlike ns:CollectAutoAuras, a resource group has no spell list to scan: it
-- always shows Health, then whatever power the character is currently using
-- (UnitPowerType follows a druid live through every form change), then the
-- class resources layered on top of a power pool (combo points, runes,
-- runic power, soul shards), then any pinned extras from opts.pinned.
--
-- Entry shape: { key, label, current, max, icon }
--   key     - stable identifier. Used to de-duplicate (a Death Knight's
--             Runic Power would otherwise arrive twice: once as their
--             current power type, once as a class resource) and gives
--             ns:ScanAutoGroup something to match against if it ever needs
--             to hold a slot across a rescan the way PlaceAutoAuras does.
--   label   - display name; becomes barData.name (feeds ns.GetBarDisplayName).
--   current/max - fed straight to ns:UpdateResourceBar.
--   icon    - spell/ability icon. Always present for every resource this
--             function currently emits, but callers should treat it as
--             optional: a future entry with no natural icon is still valid.
--
-- opts = { unit, pinned }
--   unit   - which unit to read (default "player"). "player", "target", and
--            "targettarget" are the three feeds that exist (ns.AUTO_TRACK_FEEDS'
--            `resources`, `targetResources`, and `totResources`); nothing
--            stops a caller passing another unit token, but only these
--            three are wired to a group in the UI. A unit that does not
--            exist (no target selected, or a target with no target of its
--            own) collects nothing at all - see the UnitExists guard below
--            - rather than surfacing a row of zeroed bars.
--   pinned - the resource keys ("mana", "rage", "energy") the user ticked in
--            Group Settings to always show, even when not the character's
--            current power type. Passed straight through
--            ns:NormalizePinnedResources (below), so either the current
--            ordered-list shape or the legacy set shape is accepted; see
--            that function's own comment for the two shapes and why both
--            still work. Applies to every unit the same way: the zero-max
--            guard in addEntry below already makes pinning a power the
--            unit does not have a no-op (a Mage pinning Rage shows nothing
--            today), so neither the target feed nor the target's-target
--            feed needs an extra guard to keep "pin Rage" harmless against
--            a unit that has none.
--
-- Class-resource applicability is CAPABILITY-PROBED, not UnitClass-gated.
--
-- EC-TRAP: there is no `UnitClass("player") == "DEATHKNIGHT"` (or ROGUE,
-- DRUID, WARLOCK) check anywhere in this function, which looks like a
-- missing guard - a future reader tidying this up might reach for UnitClass
-- again "to make it simpler". Do NOT: BarWarden's owner plays on Grimfall, a
-- classless private server where UnitClass("player") reports the SAME class
-- token (DRUID) for every character regardless of what that character can
-- actually do - a character there can genuinely have mana, energy, rage AND
-- six live runes all at once. Gating Runes/Runic Power/Soul Shards on a
-- class token made them permanently uncollectable for ANYONE on that
-- server, because the token they would need to match never appears. The
-- fix is to ask the game whether the resource is really there
-- (`HasRunes`/`HasRunicPower` above, `GetItemCount` for Soul Shards,
-- `GetComboPoints`'s own value for Combo Points) instead of inferring it
-- from a class name - which is also more correct on a normal Blizzard
-- server, since it no longer depends on UnitClass returning anything
-- meaningful at all.
--
--   * Runes and Runic Power are the PLAYER's own resource pools -
--     GetRuneCooldown/GetRuneType and UnitPower("player", 6) always read the
--     player's own runes/pool regardless of what `unit` names, so gating
--     them on a target's data (or a target's class - which does not even
--     exist; UnitClass(unit) returns nil for a non-player unit on this
--     client) would show YOUR OWN runes/runic power under a label that
--     implies they belong to whatever is targeted. They are therefore only
--     ever collected for unit == "player", gated on `HasRunes()`/
--     `HasRunicPower()` (above) instead of a class token.
--   * Soul Shards have no capability API at all: `GetItemCount` is a plain
--     bag count, exactly as truthful for a character that has simply never
--     picked one up as for one that structurally never can hold one.
--     Showing "0 Soul Shards" to every character would be noise (worse on a
--     classless server, where every character's class token is identical,
--     but true on a normal one too, for every class that never carries
--     one), so the shown-only-when-real rule Combo Points already use below
--     is reused here: a Soul Shard entry appears only once `GetItemCount`
--     reports at least one, and disappears again once the last one is
--     spent. There is deliberately still no pin for this (v2.5.0 added one
--     for Runic Power and Runes but not Soul Shards): the owner only asked
--     for the two DK pools, and shipping a third, unrequested tickbox in the
--     same change would be scope creep with no test coverage behind it. If
--     one is ever wanted it should gate the same way the Runic Power/Runes
--     pins do below (guard the unconditional add with `not
--     pinnedKeys.soulshards`, add it again in the pinned-extras loop, gated
--     on `GetItemCount(...) > 0` the same as the unconditional add), not by
--     resurrecting a class check.
--   * Combo Points are different again: GetComboPoints("player", "target")
--     is already, unconditionally, a "your points on your CURRENT target"
--     reading - it does not change meaning depending on whether the player
--     or target feed asks for it, and (unlike Runes/Runic Power/Soul
--     Shards) it carries its own honest zero: a character that cannot
--     generate combo points reads back 0 the exact same way as one that
--     simply has none banked right now, so there is nothing further to
--     probe. Blizzard's own UI agrees that they travel with the target, not
--     the player: ComboFrame is anchored to TargetFrame, not PlayerFrame
--     (see Core.lua's BLIZZARD_FRAME_GROUPS). They are offered on the
--     player feed and the target feed - unlike Runes/Runic Power/Soul
--     Shards, showing them via the target feed is never a mislabelled read
--     of your own data, it is the same reading either way. They stop at the
--     target's-target feed (unit == "targettarget"), because GetComboPoints
--     has no "on my target's target" reading to offer - it is hardcoded to
--     "target", so showing them under a targettarget group would just
--     repeat the exact same player/target number under a label that implies
--     it belongs to a different unit entirely. Health and the current-
--     power-type step above are not like this: they genuinely describe
--     whatever "targettarget" resolves to, so they generalise cleanly where
--     Combo Points do not.
--
--     Visibility follows the same "shown while genuinely in use" rule as a
--     pinnable power type: `cur > 0`, or the owner has ticked "Keep Combo
--     Points Visible" (the pinned-extras block near the end of this
--     function). That inner condition is now the ONLY gate - there is no
--     outer class check any more - which is sufficient for every case except
--     one: pinning "Keep Combo Points Visible" for a character that
--     structurally never generates any still shows a static 0/5 bar, since
--     Combo Points have no zero-max signal the way a power pool does
--     (`UnitPowerMax(unit, powerType) <= 0` is what makes pinning Rage for a
--     Mage a no-op elsewhere in this function). That is accepted: it is a
--     harmless, opt-in cosmetic case - the owner has to tick the box
--     themselves, nothing appears on its own - and it is the only way to let
--     a classless server's non-Rogue/Druid characters pin real Combo Points
--     they can genuinely generate.
--
-- ----------------------------------------------------------------------------
-- Pinned-resource ordering (v2.5.0): groupData.autoPinnedResources used to be
-- a plain set ({ mana = true, rage = true }), which cannot express "the
-- order the owner ticked them in". It is now an ordered list of
-- { key, color? } entries, but a set saved before this existed has to keep
-- working - the functions below are the single place that shape decision
-- lives, so CollectResources, the Options_Bars.lua tickboxes, and
-- ns:GetPinnedResourceColor (Conditions.lua) all agree on it.
-- ----------------------------------------------------------------------------

-- Fallback order for the legacy set shape, which carries no sequence of its
-- own: alphabetical, matching the table.sort() this function replaces, so a
-- profile saved before pin order existed does not visibly reshuffle the
-- moment this code ships - it just keeps showing what it always did, now
-- expressed in the ordered shape.
local LEGACY_PINNED_ORDER = { "energy", "focus", "mana", "rage" }

-- ----------------------------------------------------------------------------
-- Resource families: which resources a unit frame shows.
--
-- ns:CollectResources is purely ADDITIVE - it decides what a unit genuinely
-- has and returns all of it, and `pinned` only ever adds MORE. That is right
-- for a resource group, whose Max Bars caps the list, but it is why a unit
-- frame on a character with runes drew nine rows with no way to say "not
-- those". Filtering happens here, after collection, rather than by teaching
-- CollectResources to exclude things: that function is shared with every
-- resource group and its ordering rules are load-bearing (see the pin-order
-- comments in it), so a post-filter cannot regress them.
--
-- Families rather than raw keys, because raw keys are not what a person
-- thinks in: "runes" is one decision, not six tickboxes for rune1..rune6
-- that change meaning when Pair Runes by Type is on and the keys become
-- runepair1..3. Every other family happens to be one key today; that is a
-- coincidence of the current resource list, not a reason to drop the
-- indirection.
-- ----------------------------------------------------------------------------

-- Display order and labels for the tick list. Order here is the order the
-- Frames tab draws them, chosen to match the order they normally appear in
-- the frame itself so the settings read like the thing they configure.
ns.RESOURCE_FAMILIES = {
    { key = "health",      label = "Health"      },
    { key = "mana",        label = "Mana",   power = true },
    { key = "rage",        label = "Rage",   power = true },
    { key = "energy",      label = "Energy", power = true },
    -- Focus is deliberately NOT offered. On 3.3.5a it is a hunter PET's
    -- power type, never a player character's, so on a player frame the
    -- tickbox could never change anything: CollectResources only emits focus
    -- when it is the unit's current power type, and it is not one of the
    -- three types that can be pinned either (PINNABLE_POWER_TYPES). It was
    -- listed once and did nothing, which is worse than not listing it.
    -- `focus` still maps to a family below so a pet or target frame showing
    -- one filters correctly; only the tick list drops it.
    { key = "runicpower",  label = "Runic Power" },
    { key = "runes",       label = "Runes"       },
    { key = "combopoints", label = "Combo Points"},
    { key = "soulshards",  label = "Soul Shards" },
}

-- The three power types ns:CollectResources can be asked to include even
-- when they are not the unit's CURRENT power type (its PINNABLE_POWER_TYPES).
-- These started life as one "Power" family on the reasoning that a druid's
-- key changes as they shift form and a single tickbox survives that. On a
-- classless server where one character genuinely has mana AND rage AND
-- energy at once, that reasoning fails: there is no single "power" to tick.
-- Split per type, and ticked means "always show this pool if it is real",
-- which needs the pin (a filter alone can only ever hide what the current
-- power type already produced).
--
-- Pinning a pool the unit does not have is safe: CollectResources drops any
-- entry whose max is 0, so a mage with Rage ticked still gets no rage bar.
local PINNABLE_RESOURCE_FAMILIES = { mana = true, rage = true, energy = true }

-- Build the `pinned` list for ns:CollectResources from a unit frame's hidden
-- set: every pinnable power family the owner has NOT switched off. Returns
-- the ordered-list shape NormalizePinnedResources produces, so it can be
-- handed straight to CollectResources.
function ns:BuildUnitFramePins(hidden)
    local list = {}
    for _, family in ipairs(ns.RESOURCE_FAMILIES) do
        if PINNABLE_RESOURCE_FAMILIES[family.key]
           and not (hidden and hidden[family.key]) then
            list[#list + 1] = { key = family.key }
        end
    end
    return list
end

-- Every non-rune key CollectResources can emit, mapped to its family. Rune
-- keys are matched by prefix instead (rune1..rune6 and runepair1..3), so
-- this table does not need nine rune rows that would then have to be kept in
-- step with collectRuneEntries.
local RESOURCE_FAMILY_BY_KEY = {
    health      = "health",
    mana        = "mana",
    rage        = "rage",
    energy      = "energy",
    focus       = "focus",
    runicpower  = "runicpower",
    combopoints = "combopoints",
    soulshards  = "soulshards",
}

-- Which family a collected entry belongs to, or nil for a key this does not
-- recognise. Nil is meaningful: ns:FilterResourceEntries keeps unrecognised
-- entries rather than dropping them, so a resource added to CollectResources
-- later shows up by default instead of silently vanishing because nobody
-- remembered to add it here.
function ns:ResourceFamilyForKey(key)
    if type(key) ~= "string" then return nil end
    local family = RESOURCE_FAMILY_BY_KEY[key]
    if family then return family end
    -- "runepair1" also starts with "rune", and both views are the one
    -- Runes decision, so a plain prefix test covers each without caring
    -- which view is active.
    if key:sub(1, 4) == "rune" then return "runes" end
    return nil
end

-- Drop entries whose family the owner has switched off. `hidden` is a set of
-- family keys ({ runes = true }), deliberately storing what is OFF rather
-- than what is on: an empty/absent table then means "show everything", which
-- is exactly the behaviour every existing save already has, so this needed no
-- migration and no schema bump.
--
-- Returns a fresh list; the caller's table is never mutated.
function ns:FilterResourceEntries(entries, hidden)
    local kept = {}
    if not entries then return kept end
    if not hidden then
        for i = 1, #entries do kept[i] = entries[i] end
        return kept
    end
    for _, e in ipairs(entries) do
        local family = ns:ResourceFamilyForKey(e and e.key)
        -- An unrecognised family is kept on purpose - see above.
        if not (family and hidden[family]) then
            kept[#kept + 1] = e
        end
    end
    return kept
end

-- Pure: given a group's raw autoPinnedResources value (nil, the legacy set,
-- or the current ordered list), returns a FRESH ordered list of
-- { key = "mana", color = {r,g,b} | nil } entries. Never the caller's own
-- table, so callers can table.remove/insert on the result without mutating
-- the DB - ns:TogglePinnedResource and ns:SetPinnedResourceColor below rely
-- on that to stay pure themselves.
--
-- Shape detection: the ordered list always has a table at index 1 (a
-- string key never lands on a numeric index via plain assignment), so
-- `pinned[1] ~= nil` is enough to tell it apart from the legacy set (whose
-- keys are always the resource-name strings) or an empty/nil table.
function ns:NormalizePinnedResources(pinned)
    local list = {}
    if not pinned then return list end

    if pinned[1] ~= nil then
        for _, entry in ipairs(pinned) do
            if type(entry) == "table" and entry.key then
                list[#list + 1] = { key = entry.key, color = entry.color }
            elseif type(entry) == "string" then
                list[#list + 1] = { key = entry }
            end
        end
        return list
    end

    for _, key in ipairs(LEGACY_PINNED_ORDER) do
        if pinned[key] then
            list[#list + 1] = { key = key }
        end
    end
    return list
end

-- Pure state transition for one resource's tickbox: given the group's
-- current autoPinnedResources value (either shape) and the key just
-- ticked/unticked, returns the new ordered list to save back.
--
-- Always removes any existing entry for `key` first, then re-appends it
-- when ticked - so unticking then re-ticking moves it to the END, not back
-- to wherever it used to sit, which is what "the order you ticked them"
-- means. Unticking drops the entry (colour included, mirroring how turning
-- off Custom Bar Colour clears g.barColor): re-pinning the same resource
-- later starts it fresh at the end with no leftover colour.
function ns:TogglePinnedResource(pinned, key, ticked)
    local list = ns:NormalizePinnedResources(pinned)
    for i = #list, 1, -1 do
        if list[i].key == key then table.remove(list, i) end
    end
    if ticked then
        list[#list + 1] = { key = key }
    end
    return list
end

-- Pure: sets (or clears) the stored colour for one pinned entry, returning
-- the updated ordered list. If `key` is not currently pinned - should not
-- happen through the UI, since the swatch only shows while ticked - it is
-- appended rather than the colour choice silently being dropped.
function ns:SetPinnedResourceColor(pinned, key, color)
    local list = ns:NormalizePinnedResources(pinned)
    for _, entry in ipairs(list) do
        if entry.key == key then
            entry.color = color
            return list
        end
    end
    list[#list + 1] = { key = key, color = color }
    return list
end

-- Always returns a table (never nil), even with nothing to show.
function ns:CollectResources(opts)
    opts = opts or {}
    local unit = opts.unit or "player"
    local pinned = opts.pinned or {}
    -- Pair Runes by Type (v2.5.0, commit 3): groupData.autoPairRunes, off by
    -- default so an existing group's six-bar view is unchanged until the
    -- owner opts in. Threaded straight to collectRuneEntries() below at both
    -- call sites, so the six-bar/paired choice applies the same way whether
    -- Runes are currently pinned or just shown unconditionally.
    local pairRunes = opts.pairRunes
    local entries = {}
    local seen = {}

    -- stacks/trackMode are optional and only carried for Runes: UpdateResourceBar
    -- (BarEngine.lua) special-cases trackMode == "Runes" to show the "Ns"
    -- countdown-to-ready text instead of a plain current/max fraction, and
    -- reads that countdown from `stacks` (CheckRunes' ceil(cdRemaining)).
    -- Every other entry leaves both nil, so ns:ScanAutoGroup's resource
    -- branch falls back to current for stacks and a non-Runes trackMode.
    -- runeType (1 Blood, 2 Unholy, 3 Frost, 4 Death) is likewise only ever
    -- set for the six rune entries below; ScanAutoResourceGroup stamps it
    -- onto bd.runeType so ns:GetResourcePowerColor (Conditions.lua) can
    -- colour the bar by rune type instead of the addon-wide default.
    local function addEntry(key, label, current, max, icon, stacks, trackMode, runeType)
        if not key or seen[key] then return end
        if not max or max <= 0 then return end
        seen[key] = true
        entries[#entries + 1] = {
            key = key, label = label, current = current or 0, max = max,
            icon = icon, stacks = stacks, trackMode = trackMode, runeType = runeType,
        }
    end

    -- A unit that is not there right now (no target selected) has nothing to
    -- show. UnitExists is the honest, unit-scoped question - relying on
    -- UnitHealth/UnitPowerMax to degrade to 0 on their own would work on a
    -- real 3.3.5a client, but leaves an absent target one odd private-server
    -- API response (nil instead of 0) away from surfacing a row of
    -- meaningless zeroed bars instead of no bars at all. "player" always
    -- exists, so this only ever actually bails for "target".
    if unit ~= "player" and not (UnitExists and UnitExists(unit)) then
        return entries
    end

    -- Health first, always: it is the one everybody wants at the top.
    local _, hCur, hMax, hIcon, hName = CheckHealth({ unit = unit })
    addEntry("health", hName, hCur, hMax, hIcon)

    -- The unit's CURRENT power type, via UnitPowerType - this is what makes
    -- the bar follow a druid through Bear/Cat/Caster form changes live, on
    -- either feed (a druid can be targeted just as easily as played).
    --
    -- Deliberately NOT routed through CheckMana/CheckRage/CheckEnergy/
    -- CheckRunicPower: each of those forces a non-zero max as a display
    -- fallback for a bar the user placed by hand (see their own comments),
    -- which would defeat the zero-max "doesn't apply" skip below for a
    -- PINNED power type the character/target genuinely does not have (a
    -- Mage pinning Rage). Calling UnitPower/UnitPowerMax directly - the same
    -- globals those checkers call internally, just without the masking - is
    -- honest for both the current-power step and the pinned step alike.
    -- Focus has no dedicated track mode/checker (out of scope: only
    -- Health/Mana/Energy/Rage were added in v2.5.0) and is no longer
    -- pinnable (Always Show Focus was removed - see PINNABLE_POWER_TYPES
    -- below), but it stays listed here: a hunter pet targeted through the
    -- target feed genuinely uses Focus as its current power type, and this
    -- table is a true description of the game's power types, not of what a
    -- player character can have.
    local POWER_TYPE_INFO = {
        [0] = { key = "mana",       label = "Mana",        icon = MANA_ICON },
        [1] = { key = "rage",       label = "Rage",        icon = RAGE_ICON },
        [2] = { key = "focus",      label = "Focus",       icon = "Interface\\Icons\\Ability_Hunter_FocusedAim" },
        [3] = { key = "energy",     label = "Energy",      icon = ENERGY_ICON },
        [6] = { key = "runicpower", label = "Runic Power", icon = RUNIC_POWER_ICON },
    }

    local function addPowerType(powerType)
        local info = powerType and POWER_TYPE_INFO[powerType]
        if not info then return end
        addEntry(info.key, info.label, UnitPower(unit, powerType) or 0,
                 UnitPowerMax(unit, powerType) or 0, info.icon)
    end

    addPowerType((UnitPowerType(unit)))

    -- Normalized once so both the Combo Points gate below and the pinned-
    -- extras loop at the bottom of this function read the same list, rather
    -- than each calling ns:NormalizePinnedResources on the raw opts.pinned
    -- separately.
    local normalizedPinned = ns:NormalizePinnedResources(pinned)
    local pinnedKeys = {}
    for _, entry in ipairs(normalizedPinned) do
        pinnedKeys[entry.key] = true
    end

    -- Combo Points: always your own, always about your CURRENT target, so
    -- they are meaningful on the player feed and the target feed without
    -- reading anything off `unit` itself (see the file comment above for
    -- why this is not the same reasoning as Runes/Runic Power/Soul Shards
    -- below). They do NOT belong on the target's-target feed
    -- (unit == "targettarget"): GetComboPoints has no notion of "points on
    -- my target's target" to read there at all, so showing them would just
    -- be the exact same player/target reading, mislabelled under a group
    -- about a third, different unit - unlike Health/current-power-type
    -- above, which genuinely describe whatever "targettarget" resolves to.
    --
    -- Visibility (v2.5.0): shown while "in use" (cur > 0), same as a power
    -- type is shown while it is the current one, OR when the owner has
    -- ticked "Keep Combo Points Visible" (autoPinnedResources' "combopoints"
    -- key) - matching how a pinned power type stays up even when it is not
    -- the current one. No class check wraps this any more (see the file
    -- comment above for why, and for the one cosmetic case it accepts): the
    -- `cur > 0` half of this condition IS the capability probe, since
    -- GetComboPoints already reads back a genuine 0 for a character that
    -- cannot generate any.
    --
    -- Pinned Combo Points are deliberately NOT added here (v2.5.0 fix):
    -- addEntry's `seen` guard means whichever add runs first wins the slot,
    -- and this block runs well before the pinned-extras loop below that
    -- honours tick order, so a pinned Combo Points entry used to always land
    -- right after Health/current-power regardless of when it was ticked
    -- relative to another pinned resource (e.g. always above Rage, even when
    -- Rage was pinned first). The pinned-extras loop now adds Combo Points
    -- itself when pinned, in its rightful ordered slot; this block only
    -- handles the UNpinned "currently in use" case, so an active-but-unpinned
    -- count still shows immediately without waiting on pin order.
    if (unit == "player" or unit == "target") and not pinnedKeys.combopoints then
        local _, cur, mx, icon, name = CheckComboPoints({})
        if cur and cur > 0 then
            addEntry("combopoints", name, cur, mx, icon)
        end
    end

    -- Runes, Runic Power, and Soul Shards are the PLAYER's own resource
    -- pools (see the file comment above): only ever collected for the
    -- player's own feed, gated on capability (HasRunicPower/HasRunes/
    -- GetItemCount), never on UnitClass. A character with Runic Power gets
    -- it here too, even though it is usually already added above via the
    -- current-power-type step; addEntry's `seen` guard makes the explicit
    -- add below a harmless no-op rather than a duplicate bar.
    --
    -- Runic Power and Runes are guarded by `not pinnedKeys.X` (v2.5.0 pin
    -- fix): without that guard, a pinned entry would still be added HERE,
    -- ahead of the ordered pinned-extras loop below, and addEntry's `seen`
    -- guard means whichever add runs first wins the slot - reproducing the
    -- exact bug just fixed for Combo Points (see that block's comment
    -- above), where a pinned resource always landed right after
    -- Health/current-power regardless of tick order. This block now only
    -- ever handles the UNPINNED "always visible because the pool is real"
    -- case; the pinned case is handled entirely by the pinned-extras loop.
    if unit == "player" then
        if HasRunicPower() and not pinnedKeys.runicpower then
            local _, rpCur, rpMax, rpIcon, rpName = CheckRunicPower({})
            addEntry("runicpower", rpName, rpCur, rpMax, rpIcon)
        end

        if HasRunes() and not pinnedKeys.runes then
            for _, e in ipairs(collectRuneEntries(pairRunes)) do
                addEntry(e.key, e.label, e.current, e.max, e.icon, e.stacks, e.trackMode, e.runeType)
            end
        end

        -- No capability API exists for Soul Shards (see the file comment
        -- above): GetItemCount > 0 is the only honest "has one right now"
        -- signal, so the bar appears with the count already in hand rather
        -- than a class-inferred, possibly-empty one. No pin exists for this
        -- one (see the file comment above for why that is a deliberate,
        -- separate decision, not an oversight).
        local shardCount = GetItemCount(SOUL_SHARD_ITEM_ID) or 0
        if shardCount > 0 then
            local _, cur, mx, icon, name = CheckSoulShards({})
            addEntry("soulshards", name, cur, mx, icon)
        end
    end

    -- Pinned extras: resources the user always wants visible even when not
    -- currently in use (e.g. a caster Druid pinning Energy), in the order
    -- they were ticked (ns:NormalizePinnedResources also accepts the legacy
    -- unordered set, falling back to a deterministic alphabetical order for
    -- it). addEntry's zero-max guard still applies, so pinning a power the
    -- unit truly cannot have (a Mage pinning Rage) shows nothing - on
    -- either feed, which is why pinning needs no unit-specific carve-out.
    -- "focus" is deliberately absent (Always Show Focus was removed: 3.3.5a
    -- players never have a Focus pool, so the tickbox could never do
    -- anything - see CHANGELOG). A legacy save that still has `focus`
    -- pinned/ticked just finds no entry here and is silently dropped; see
    -- ns:NormalizePinnedResources, which does not itself filter by key.
    --
    -- Combo Points are handled here too, alongside mana/rage/energy, so a
    -- pinned entry takes its slot in tick order like everything else (see
    -- the comment above the Combo Points block above for why the early add
    -- there deliberately steps aside while pinned). Still gated on unit ==
    -- player/target: GetComboPoints has no target's-target reading, so
    -- pinning it must not conjure one on that feed either (see the file
    -- comment's Combo Points section).
    --
    -- Runic Power and Runes (v2.5.0) follow the exact same shape: gated on
    -- unit == "player" (they are the PLAYER's own pools, never a target's -
    -- see the file comment above), and re-checking their own capability
    -- (HasRunicPower/HasRunes) here too, since a pin must not conjure a bar
    -- for a pool that genuinely is not there. Runes adds however many
    -- entries collectRuneEntries() currently produces (all six slots, or
    -- the three type pairs once Pair Runes by Type is on) as one ordered
    -- block, so the whole group of rune bars moves together as a single
    -- pinned item regardless of which view is active. Soul Shards still has
    -- no pin tickbox (Options_Bars.lua) - see the file comment above for why
    -- - so it is not listed here.
    local PINNABLE_POWER_TYPES = { mana = 0, rage = 1, energy = 3 }
    for _, entry in ipairs(normalizedPinned) do
        local powerType = PINNABLE_POWER_TYPES[entry.key]
        if powerType then
            addPowerType(powerType)
        elseif entry.key == "combopoints" and (unit == "player" or unit == "target") then
            local _, cur, mx, icon, name = CheckComboPoints({})
            addEntry("combopoints", name, cur, mx, icon)
        elseif entry.key == "runicpower" and unit == "player" and HasRunicPower() then
            local _, rpCur, rpMax, rpIcon, rpName = CheckRunicPower({})
            addEntry("runicpower", rpName, rpCur, rpMax, rpIcon)
        elseif entry.key == "runes" and unit == "player" and HasRunes() then
            for _, e in ipairs(collectRuneEntries(pairRunes)) do
                addEntry(e.key, e.label, e.current, e.max, e.icon, e.stacks, e.trackMode, e.runeType)
            end
        end
    end

    return entries
end
