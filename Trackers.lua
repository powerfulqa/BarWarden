-- Trackers.lua - Per-trackMode checkers (aura, cooldown, resource modes).
-- Author:  Serv
-- Source:  https://github.com/powerfulqa/BarWarden
-- License: see LICENSE; attribution preservation is required.

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
    playerBuffs     = { unit = "player", kind = "buff"     },
    playerDebuffs   = { unit = "player", kind = "debuff"   },
    targetBuffs     = { unit = "target", kind = "buff"     },
    targetDebuffs   = { unit = "target", kind = "debuff"   },
    resources       = { unit = "player", kind = "resource" },
    targetResources = { unit = "target", kind = "resource" },
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
-- Returns (isActive, current, max, icon, name, stacks) where:
--   current = max when ready, 0..max as the rune regenerates
--   max     = the rune's cooldown duration (10 s baseline; server may vary)
--   stacks  = ceil(cdRemaining) in seconds, 0 means ready (used by the text
--             display in UpdateResourceBar)
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
        return true, DEFAULT_RUNE_CD, DEFAULT_RUNE_CD, icon, name, 0
    end

    -- Ready: full bar, no countdown text.
    if ready then
        return true, duration, duration, icon, name, 0
    end

    -- On cooldown: bar fills from 0 toward max as the rune regenerates.
    local cdRemaining = (start + duration) - GetTime()
    if cdRemaining <= 0 then
        return true, duration, duration, icon, name, 0
    end

    local current = duration - cdRemaining
    if current < 0 then current = 0 end

    return true, current, duration, icon, name, ceil(cdRemaining)
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
--   unit   - which unit to read (default "player"). "player" and "target"
--            are the two feeds that exist (ns.AUTO_TRACK_FEEDS' `resources`
--            and `targetResources`); nothing stops a caller passing another
--            unit token, but only these two are wired to a group in the UI.
--            A unit that does not exist (no target selected) collects
--            nothing at all - see the UnitExists guard below - rather than
--            surfacing a row of zeroed bars.
--   pinned - the resource keys ("mana", "rage", "energy", "focus") the user
--            ticked in Group Settings to always show, even when not the
--            character's current power type. Passed straight through
--            ns:NormalizePinnedResources (below), so either the current
--            ordered-list shape or the legacy set shape is accepted; see
--            that function's own comment for the two shapes and why both
--            still work. Applies to either unit the same way: the zero-max
--            guard in addEntry below already makes pinning a power the
--            character/target does not have a no-op (a Mage pinning Rage
--            shows nothing today), so a target feed needs no extra guard to
--            keep "pin Rage" harmless against a target that has none.
--
-- Class-resource applicability splits three ways, not one UnitClass(unit)
-- call generalised naively:
--   * Runes, Runic Power, and Soul Shards are the PLAYER's own resource
--     pools - GetRuneCooldown/GetRuneType, UnitPower("player", 6) and
--     GetItemCount(SOUL_SHARD_ITEM_ID) all read the player's own runes/bags
--     regardless of what `unit` names, so gating them on UnitClass(unit)
--     for a target feed would show YOUR OWN soul shards under a label that
--     implies they belong to whatever is targeted. They are therefore only
--     ever collected for unit == "player", still gated on UnitClass("player")
--     - the same signal Conditions.lua's requireClass condition already uses
--     to keep a DK's rune bar off a Mage's copied profile. None of the three
--     checkers themselves encode "does this class have this resource":
--     CheckRunicPower and CheckSoulShards both force a non-zero max as a
--     display fallback for a hand-placed bar (see their own comments), so
--     calling them alone could never tell an applicable class from an
--     inapplicable one; UnitClass is the only honest signal available here.
--   * Combo Points are different: GetComboPoints("player", "target") is
--     already, unconditionally, a "your points on your CURRENT target"
--     reading - it does not change meaning depending on which feed asks for
--     it. Blizzard's own UI agrees: the combo-point display (ComboFrame) is
--     anchored to the target frame, not the player frame, so "combo points
--     belong with the target you're building them on" is not a new idea
--     here. They are offered on BOTH feeds - unlike Runes/Runic
--     Power/Soul Shards, showing them via the target feed is never a
--     mislabelled read of your own data, it is the same reading either way -
--     still gated on the PLAYER's own class (only a Rogue or Druid has combo
--     points at all, whatever is targeted).
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
    local entries = {}
    local seen = {}

    -- stacks/trackMode are optional and only carried for Runes: UpdateResourceBar
    -- (BarEngine.lua) special-cases trackMode == "Runes" to show the "Ns"
    -- countdown-to-ready text instead of a plain current/max fraction, and
    -- reads that countdown from `stacks` (CheckRunes' ceil(cdRemaining)).
    -- Every other entry leaves both nil, so ns:ScanAutoGroup's resource
    -- branch falls back to current for stacks and a non-Runes trackMode.
    local function addEntry(key, label, current, max, icon, stacks, trackMode)
        if not key or seen[key] then return end
        if not max or max <= 0 then return end
        seen[key] = true
        entries[#entries + 1] = {
            key = key, label = label, current = current or 0, max = max,
            icon = icon, stacks = stacks, trackMode = trackMode,
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
    -- Health/Mana/Energy/Rage were added in v2.5.0), so it is listed here
    -- with its own icon/label instead of borrowing one from a checker.
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

    -- Combo Points: always your own, always about your CURRENT target, so
    -- they are meaningful on either feed without reading anything off
    -- `unit` itself (see the file comment above for why this is not the
    -- same reasoning as Runes/Runic Power/Soul Shards below). Gated on the
    -- PLAYER's class regardless of which feed is asking.
    local _, classToken = UnitClass("player")

    if classToken == "ROGUE" or classToken == "DRUID" then
        local _, cur, mx, icon, name = CheckComboPoints({})
        addEntry("combopoints", name, cur, mx, icon)
    end

    -- Runes, Runic Power, and Soul Shards are the PLAYER's own resource
    -- pools (see the file comment above): only ever collected for the
    -- player's own feed, gated the same way as before. A Death Knight gets
    -- Runes plus Runic Power (already added above via their current power
    -- type; addEntry's `seen` guard makes the explicit add below a harmless
    -- no-op rather than a duplicate bar), a Warlock gets Soul Shards.
    if unit == "player" then
        if classToken == "DEATHKNIGHT" then
            local _, rpCur, rpMax, rpIcon, rpName = CheckRunicPower({})
            addEntry("runicpower", rpName, rpCur, rpMax, rpIcon)
            for slot = 1, 6 do
                local _, cur, mx, icon, name, stacks = CheckRunes({ spellId = slot })
                addEntry("rune" .. slot, name, cur, mx, icon, stacks, "Runes")
            end
        end

        if classToken == "WARLOCK" then
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
    local PINNABLE_POWER_TYPES = { mana = 0, rage = 1, focus = 2, energy = 3 }
    for _, entry in ipairs(ns:NormalizePinnedResources(pinned)) do
        local powerType = PINNABLE_POWER_TYPES[entry.key]
        if powerType then addPowerType(powerType) end
    end

    return entries
end
