-- Conditions.lua - Visibility condition registry and evaluator.
-- Author:  Serv
-- Source:  https://github.com/powerfulqa/BarWarden
-- License: GNU GPL v3 (see LICENSE); attribution preservation is required.

local addonName, ns = ...
local MAX_AURA_INDEX = ns.MAX_AURA_INDEX

-- ============================================================================
-- Conditions.lua: extensible visibility-condition registry + evaluator.
--
-- Use ns:RegisterCondition(name, fn) to add new condition checks. The
-- evaluator iterates them in registration order; the first one to return
-- false hides the bar. Each check function receives the bar's `conditions`
-- table and returns true (keep visible) or false (hide).
--
-- Built-in conditions register themselves at module load order. Future
-- conditions (smart-visibility, spec check, etc.) plug in by calling
-- RegisterCondition without editing core logic.
-- ============================================================================

-- Ordered list of { name, fn } entries. Registration order matters because
-- it defines the short-circuit order of the evaluator.
local registered = {}

function ns:RegisterCondition(name, fn)
    registered[#registered + 1] = { name = name, fn = fn }
end

-- Exposed for introspection (e.g. the bug-report dumper) and tests.
ns.conditionChecks = registered

function ns:EvaluateConditions(bar, conditions)
    if not conditions then return true end
    for _, entry in ipairs(registered) do
        if not entry.fn(conditions) then return false end
    end
    return true
end

-- hideWhenInactive is queried by the bar engine during active/inactive
-- transitions rather than inside EvaluateConditions, so it stays a standalone
-- query rather than going through the registry.
--
-- The old `showEmpty` companion was retired in v2.1.1: nothing ever read it, so
-- its checkbox had never done anything and was indistinguishable from Hide When
-- Inactive. Existing `conditions.showEmpty` data is left alone (harmless).

-- A bar the user switched off must never be drawn. Four places used to decide
-- this independently and disagreed, so an unticked "Enabled" bar was hidden at
-- build time and then shown again by the very next refresh. Everything that can
-- show a bar asks here.
function ns:IsBarEnabled(bar)
    local bd = bar and bar.barData
    return not (bd and bd.enabled == false)
end

-- Resolve "hide when inactive" for a live bar.
--
-- The group switch is authoritative once it has been touched: ticked hides
-- every bar in the group, unticked keeps every bar visible even if the bars
-- have their own boxes ticked. A group that has never been touched leaves the
-- decision to each bar.
--
-- It is deliberately NOT an OR of the two. An OR could only ever add hiding, so
-- a group whose bars all set the flag themselves could never be revealed from
-- the group control - which is the whole point of having one.
function ns:ResolveHideWhenInactive(bar)
    local groupData = bar and bar.frameIndex and BarWardenDB and BarWardenDB.frames
                      and BarWardenDB.frames[bar.frameIndex]
    local groupCond = groupData and groupData.groupConditions
    if groupCond and groupCond.hideWhenInactive ~= nil then
        return not not groupCond.hideWhenInactive
    end

    local barCond = bar and bar.barData and bar.barData.conditions
    return not not (barCond and barCond.hideWhenInactive)
end

-- Whether an empty group's frame (backdrop, title, everything) should hide.
-- "Empty" means every bar/slot in the group has already resolved to hidden -
-- AreAllBarsHidden (BarEngine.lua) is the only caller and has done that check
-- before asking, so this only decides what an empty group does next.
--
-- conditionsFailed is the caller's own evaluation of the group's Combat
-- Only / Hide Mounted / etc conditions (see AreAllBarsHidden), passed in
-- rather than evaluated here so this stays a pure decision function and the
-- caller keeps control of when that evaluation is worth doing. It outranks
-- everything below: the owner explicitly told this group to hide right now,
-- which beats both the Hide When Inactive setting and the auto-group
-- unlocked carve-out. Without this, an auto-tracking group whose Combat
-- Only condition failed would still show while unlocked, because "empty"
-- read as "nothing matched yet" instead of "the owner said hide this".
--
-- Same group-authoritative, ~= nil shape as ResolveHideWhenInactive just
-- above: once Hide When Inactive has been touched on the group it wins
-- outright, in both directions, regardless of lock state or group type.
-- Untouched (nil), it reproduces the behaviour that existed before this
-- setting had any say over the frame: an auto-tracking group (slots filled
-- from whatever is on the unit, so "empty" is the normal idle state, not a
-- misconfiguration) stays on screen while unlocked so it can still be found
-- and arranged, and hides once locked, the normal playing state. An
-- ordinary group has never had that carve-out, so it always hides when
-- empty, locked or not.
function ns:ShouldHideEmptyGroup(frameData, isAutoGroup, isLocked, conditionsFailed)
    if conditionsFailed then return true end

    local groupCond = frameData and frameData.groupConditions
    if groupCond and groupCond.hideWhenInactive ~= nil then
        return not not groupCond.hideWhenInactive
    end

    if isAutoGroup then
        return not not isLocked
    end
    return true
end

-- Resolve "switch mode" (on/off, no countdown) for a live bar.
--
-- Same group-over-bar shape as ResolveHideWhenInactive: the group's Bar
-- Style is authoritative once set, in both directions, so a group can force
-- every bar in it to read as a switch (or force countdown bars back on) even
-- if individual bars disagree. A group with no opinion ("" / nil barStyle)
-- leaves the call to each bar's own display.switchMode.
function ns:IsSwitchBar(bar)
    local groupData = bar and bar.frameIndex and BarWardenDB and BarWardenDB.frames
                      and BarWardenDB.frames[bar.frameIndex]
    local groupStyle = groupData and groupData.barStyle
    if groupStyle == "SWITCH" then return true end
    if groupStyle == "COUNTDOWN" then return false end
    local disp = bar and bar.barData and bar.barData.display
    return not not (disp and disp.switchMode)
end

-- Resolve the stack-count font size for a live bar: bar override, then group
-- override, then the addon-wide default (Visuals tab). Same bar-then-group-
-- then-global shape as IsSwitchBar/ResolveHideWhenInactive above, but
-- resolving a value instead of a boolean, so it falls through on a missing
-- level rather than an OR/AND of one. Nil-safe at every step (nil bar, nil
-- barData, nil display, missing frameIndex or an absent group) so a
-- still-building bar reads the global value rather than erroring.
function ns:GetStackFontSize(bar)
    local disp = bar and bar.barData and bar.barData.display
    if disp and disp.stackFontSize then return disp.stackFontSize end

    local groupData = bar and bar.frameIndex and BarWardenDB and BarWardenDB.frames
                      and BarWardenDB.frames[bar.frameIndex]
    if groupData and groupData.stackFontSize then return groupData.stackFontSize end

    local visual = ns:GetVisual()
    return visual.stackFontSize or 12
end

-- Resolve the stack-count colour the same way. Returns a { r, g, b } table,
-- matching how ns:RenderBarStacks (BarEngine.lua) already consumes
-- visual.stackColor - callers use the fields directly, no unpacking needed.
function ns:GetStackColor(bar)
    local disp = bar and bar.barData and bar.barData.display
    if disp and disp.stackColor then return disp.stackColor end

    local groupData = bar and bar.frameIndex and BarWardenDB and BarWardenDB.frames
                      and BarWardenDB.frames[bar.frameIndex]
    if groupData and groupData.stackColor then return groupData.stackColor end

    local visual = ns:GetVisual()
    return visual.stackColor or { r = 1, g = 1, b = 1 }
end

-- Resolve "glow on ready" for a live bar: most-specific-wins (bar, then
-- group, then off), the same per-level shape as GetStackFontSize/
-- GetStackColor above rather than IsSwitchBar's group-authoritative one.
-- An auto slot's display never carries this key at all (NewAutoBarData,
-- FrameManager.lua, seeds only lingerTime), so it always falls through to
-- the group - which is the whole point of offering it at group level.
function ns:GetBarGlowOnReady(bar)
    local disp = bar and bar.barData and bar.barData.display
    if disp and disp.glowOnReady then return true end

    local groupData = bar and bar.frameIndex and BarWardenDB and BarWardenDB.frames
                      and BarWardenDB.frames[bar.frameIndex]
    return not not (groupData and groupData.glowOnReady)
end

-- Same shape as GetBarGlowOnReady, for the centre-screen icon pulse.
function ns:GetBarPulseOnReady(bar)
    local disp = bar and bar.barData and bar.barData.display
    if disp and disp.pulseOnReady then return true end

    local groupData = bar and bar.frameIndex and BarWardenDB and BarWardenDB.frames
                      and BarWardenDB.frames[bar.frameIndex]
    return not not (groupData and groupData.pulseOnReady)
end

-- Resolve linger time the same way, but a bare truthy check does not work
-- here: 0 is BarWarden's own "off" sentinel for this field (Bar_OnUpdate and
-- ScanBar, BarEngine.lua, both gate on `lingerTime > 0`), and 0 is truthy in
-- Lua. `if disp.lingerTime then` would misread every bar's untouched default
-- of 0 (NewBar, Options_Bars.lua, and NewAutoBarData, FrameManager.lua) as an
-- explicit override and the group's value would never be reachable. `> 0` is
-- what makes "no bar override" mean the same thing here as at every other
-- lingerTime read site.
function ns:GetBarLingerTime(bar)
    local disp = bar and bar.barData and bar.barData.display
    if disp and disp.lingerTime and disp.lingerTime > 0 then return disp.lingerTime end

    local groupData = bar and bar.frameIndex and BarWardenDB and BarWardenDB.frames
                      and BarWardenDB.frames[bar.frameIndex]
    if groupData and groupData.lingerTime and groupData.lingerTime > 0 then return groupData.lingerTime end

    return 0
end

-- Bar Alerts (v2.4.0): whether a bar is inside its expiry alert window.
-- display.sparkleAlert is the master on/off (unchanged from the original
-- sparkle-only feature, and still what a bar with none of the newer fields
-- set reads as: this function's seconds branch below reproduces the old
-- inline `remaining <= threshold` check in Bar_OnUpdate exactly). No group
-- override exists for this feature (unlike the resolvers above), so this is
-- a plain bar-only decision, but pulled out of BarEngine.lua for the same
-- reason as the others: BarEngine.lua's frame-heavy locals cannot load under
-- the test harness, and the arithmetic itself is pure.
--
-- alertUnit picks how the threshold is read:
--   nil / "SECONDS" - remaining <= sparkleThreshold (today's behaviour).
--   "PERCENT"       - remaining <= duration * alertPercent / 100.
--
-- A missing or zero duration in percent mode returns false rather than
-- dividing by zero: a permanent or static bar (duration nil, see
-- ns:ActivateStaticBar/UpdateResourceBar, BarEngine.lua) has no "full
-- length" to take a percentage of, so it has no meaningful percentage
-- threshold at all - reads as "never alerting" in that mode, not an error
-- and not "always alerting" (which 0/0 or x/0 could otherwise be misread as).
function ns:IsBarAlerting(display, remaining, duration)
    if not display or not display.sparkleAlert or remaining == nil then
        return false
    end

    if display.alertUnit == "PERCENT" then
        if not duration or duration <= 0 then return false end
        local percent = display.alertPercent or 20
        return remaining <= duration * percent / 100
    end

    local threshold = display.sparkleThreshold or 5
    return remaining <= threshold
end

-- Resolve the alert colour for a bar, so the drawing code (ns.GetTimeBasedColor,
-- Bar.lua) has one place to ask instead of re-checking alertAction and
-- re-deriving the alert window itself. Returns (r, g, b) - matching
-- GetTimeBasedColor's own multi-return shape, since that is this resolver's
-- only caller - or nil when the bar is not alerting or its alert action does
-- not include colour ("SPARKLE", the default, or a bar not currently inside
-- its window). display.alertColor defaults to a plain red: a vivid, obvious
-- "this is about to end" cue distinct from colorByTime's softer low-end red.
function ns:GetBarAlertColor(display, remaining, duration)
    if not display then return nil end
    local action = display.alertAction or "SPARKLE"
    if action ~= "COLOUR" and action ~= "BOTH" then return nil end
    if not ns:IsBarAlerting(display, remaining, duration) then return nil end

    local c = display.alertColor or { r = 1, g = 0, b = 0 }
    return c.r or 1, c.g or 0, c.b or 0
end

-- Resolve whether Blizzard's PlayerFrame (or TargetFrame) should be hidden
-- right now (Options_General.lua's "Hide Blizzard Player/Target Frame";
-- applied by ApplyFrameHidden, Core.lua). Kept here rather than in Core.lua
-- for the same reason as the Bar Alerts pair above: pure arithmetic the test
-- harness can reach without touching the PlayerFrame/TargetFrame globals.
-- `wantHidden` already folds in both the tickbox and the addon's own
-- enabled state (see Core.lua's WantPlayerFrameHidden/WantTargetFrameHidden),
-- so /bw disable reads as "does not want it hidden" here without this
-- function knowing anything about enable/disable.
--
-- This used to also take an `inCombat` argument and return false while it
-- was true, deferring the hide until combat ended: the idea was that
-- Hide() might not be safe on a secure frame mid-fight, so staying visible
-- one extra moment was worth it to avoid gambling on that. Neither
-- PlayerFrame nor TargetFrame is built on a secure template in 3.3.5a
-- though (ApplyFrameHidden's pcall around Hide()/Show() is the genuine
-- safety net for that, in case this assumption is ever wrong on some client
-- build), so the combat check was never protecting anything real. What it
-- DID do, in the OnShow hook (ApplyFrameHidden, Core.lua) that keeps these
-- frames down between calls, was make the hook decline to re-hide the frame
-- on every Show() Blizzard fired while in combat, which is most of what
-- combat does to these frames: ticking Hide Blizzard Target Frame and then
-- entering combat brought the target frame straight back for the rest of
-- the fight. Do not reintroduce an inCombat parameter (or any other combat
-- check) here.
function ns:ResolvePlayerFrameHidden(wantHidden)
    return not not wantHidden
end

-- Should a Blizzard frame group be suppressed? Composes the three inputs
-- that can ask for it (see BLIZZARD_FRAME_GROUPS, Core.lua):
--
--   addonEnabled      /bw disable hands every frame back. A disabled
--                     BarWarden must not be suppressing any UI, so this
--                     vetoes the other two outright.
--   manualHide        the standalone tickbox on the General tab, for someone
--                     who wants Blizzard's frame gone without running a
--                     BarWarden one. Only player and target have one.
--   unitFrameEnabled  the BarWarden frame that REPLACES this group is on.
--                     The two draw the same unit in the same place, so
--                     leaving both up is never what anyone wants - hiding
--                     Blizzard's is automatic rather than a second tickbox
--                     the owner has to find.
--
-- Deliberately OR rather than "the tickbox wins": someone who ticked Hide
-- Blizzard Player Frame and then ALSO turned on a BarWarden player frame
-- wants it gone twice over, and unticking one must not bring it back while
-- the other still stands.
--
-- Combat is not an input here, and must not become one - see the long note
-- on ns:ResolvePlayerFrameHidden above for what that cost last time.
function ns:ResolveBlizzardFrameHidden(addonEnabled, manualHide, unitFrameEnabled)
    if not addonEnabled then return false end
    return (manualHide or unitFrameEnabled) and true or false
end

-- ----------------------------------------------------------------------------
-- Resource bar default colours (v2.5.0): a resource bar (health, the
-- character's current power, a pinned extra) should read in the game's own
-- conventional colours - a blue mana bar, a yellow energy bar, a red rage
-- bar - rather than the addon-wide default. Both resolvers below are pure
-- (bar in, colour out) for the same reason as the Bar Alerts pair above:
-- GetBarColor (Bar.lua) is where they get consulted, but the arithmetic
-- itself belongs beside the other resolvers, not in frame code.
--
-- Precedence for a resource bar's colour, most specific first (see
-- GetBarColor, Bar.lua, for where each level slots in among the pre-existing
-- per-bar/per-group/global levels):
--   1. per-bar colorOverride (pre-existing; practically unreachable for an
--      auto-tracking slot, which has no per-bar editor, but still honoured)
--   2. this pinned resource's own colour (ns:GetPinnedResourceColor)
--   3. the group's Custom Bar Colour (pre-existing group.barColor)
--   4. the power-type default below (ns:GetResourcePowerColor)
--   5. the addon-wide Colour Mode default (pre-existing)
-- ----------------------------------------------------------------------------

-- ns:CollectResources' resource keys (Trackers.lua) that ARE power types,
-- mapped to the string token PowerBarColor is keyed by on 3.3.5a - the same
-- token UnitPowerType's second return uses, since Blizzard's own UnitFrame.lua
-- reads PowerBarColor that way. Health and the class resources with no
-- single conventional colour (combo points render as pips, not a status
-- bar) are not in this table at all - they either use RESOURCE_COLOR_FALLBACK
-- directly (health, soul shards) or fall through to the addon-wide default
-- (combo points). The six runes DO each have a colour by TYPE - see
-- RUNE_TYPE_COLORS and ns:GetResourcePowerColor below, which is where that
-- gets threaded in ahead of this table, not through it.
local RESOURCE_COLOR_TOKENS = {
    mana       = "MANA",
    rage       = "RAGE",
    focus      = "FOCUS",
    energy     = "ENERGY",
    runicpower = "RUNIC_POWER",
}

-- Used when PowerBarColor is absent (a client build that does not define
-- it) or missing a specific token, and for the two keys above that are not
-- power types (health has never been one; soul shards' Blizzard purple, in
-- case some build's PowerBarColor lacks the entry). Health's green is the
-- conventional "healthy" colour used across WoW's own UI and virtually every
-- unit-frame addon; picked over class-colouring since the addon-wide Colour
-- Mode (which can already be CLASS) is what a user wants for that look.
local RESOURCE_COLOR_FALLBACK = {
    health      = { r = 0,    g = 1,    b = 0    },
    mana        = { r = 0,    g = 0,    b = 1    },
    rage        = { r = 1,    g = 0,    b = 0    },
    focus       = { r = 1,    g = 0.5,  b = 0.25 },
    energy      = { r = 1,    g = 1,    b = 0    },
    runicpower  = { r = 0,    g = 0.82, b = 1    },
    soulshards  = { r = 0.5,  g = 0.32, b = 0.55 },
}

-- Resolve the power-type default colour for a resource KEY ("mana", "rage",
-- "health", ...) directly, with no bar involved. Reads the client's own
-- PowerBarColor table when present (so a colour patched by Blizzard, or an
-- item/skin that swaps it, is picked up rather than hardcoded), falling back
-- to RESOURCE_COLOR_FALLBACK for anything missing. Returns (r, g, b), or nil
-- for a key with no known default (not a resource key at all, or one of the
-- keys - combo points, runes - with no single conventional colour; see the
-- comment above RESOURCE_COLOR_TOKENS).
--
-- Pulled out of ns:GetResourcePowerColor below so the pinned-resource colour
-- swatch (Options_Bars.lua) can resolve the SAME starting colour the bar
-- itself would draw without needing a live bar object to ask - the options
-- panel builds its swatch before any bar exists for an unticked pin, and a
-- group need not even be built yet.
function ns:GetResourceKeyDefaultColor(key)
    if not key then return nil end
    local token = RESOURCE_COLOR_TOKENS[key]
    local fromClient = token and _G.PowerBarColor and _G.PowerBarColor[token]
    local c = fromClient or RESOURCE_COLOR_FALLBACK[key]
    if not c then return nil end
    return c.r or 0, c.g or 0, c.b or 0
end

-- Death Knight rune colours by type: 1 Blood, 2 Unholy, 3 Frost, 4 Death
-- (GetRuneType's own numbering; matches RUNE_ICONS/RUNE_NAMES, Trackers.lua).
--
-- 3.3.5a's FrameXML (RuneFrame.lua) defines this palette, but as a
-- file-local `runeColors` table with no addon-visible equivalent of
-- PowerBarColor for rune types, so - unlike the power-type colours above -
-- it cannot be read live from the client at all; these values are copied
-- from Blizzard's own client source rather than invented, so a rune bar
-- looks the same as Blizzard's default rune display. Death is a distinct
-- magenta/purple in Blizzard's own table, not white or a repeat of one of
-- the three basic types - kept as-is rather than picking a "nicer" colour.
--
-- Frost is the one deliberate divergence. Blizzard's own value is pure cyan
-- (0, 1, 1); the owner asked for frost runes to read as blue after seeing
-- cyan on a live frame, so this is a requested change, not a stylistic
-- tweak someone made in passing. Do not "restore" it to Blizzard's cyan on
-- the grounds that the rest of the table matches the client.
local RUNE_TYPE_COLORS = {
    [1] = { r = 1,   g = 0,    b = 0 },   -- Blood
    [2] = { r = 0,   g = 0.5,  b = 0 },   -- Unholy
    [3] = { r = 0.2, g = 0.55, b = 1 },   -- Frost (see note above)
    [4] = { r = 0.8, g = 0.1,  b = 1 },   -- Death
}

-- Resolve the power-type default colour for a resource bar. Returns (r, g, b),
-- or nil for a bar with no resourceKey (not a resource bar, or a resource
-- ScanAutoResourceGroup has not stamped one onto yet).
--
-- A rune bar (bar.barData.runeType set - ScanAutoResourceGroup stamps it
-- alongside resourceKey, see ns:CollectResources' rune loop, Trackers.lua)
-- is coloured by its TYPE rather than going through RESOURCE_COLOR_TOKENS/
-- RESOURCE_COLOR_FALLBACK: "rune3" etc. are not power-type keys and have no
-- fallback entry either, so without this branch every rune bar would return
-- nil here and fall all the way through to the addon-wide default - the
-- exact gap RESOURCE_COLOR_TOKENS' comment used to describe. This still
-- sits at precedence level 4 (see the comment at the top of this section):
-- a per-bar colorOverride, this resource's own pinned colour, or the
-- group's Custom Bar Colour are all resolved by the caller BEFORE this
-- function is ever consulted, so any of those still wins over a rune's type
-- colour exactly like they win over the power-type default.
function ns:GetResourcePowerColor(bar)
    local bd = bar and bar.barData
    local key = bd and bd.resourceKey
    if not key then return nil end

    if bd.runeType then
        local c = RUNE_TYPE_COLORS[bd.runeType]
        if c then return c.r, c.g, c.b end
    end

    return ns:GetResourceKeyDefaultColor(key)
end

-- Resolve a per-pinned-resource colour override for a resource bar: the
-- colour swatch under a pinned resource's tickbox (Options_Bars.lua),
-- stored on the matching entry in groupData.autoPinnedResources. Reads
-- through ns:NormalizePinnedResources (Trackers.lua) so both the ordered
-- shape and the legacy set (which carries no colour at all) are handled the
-- same way. Returns (r, g, b), or nil when the bar is not a resource bar,
-- the resource is not currently pinned, or it is pinned with no colour set.
function ns:GetPinnedResourceColor(bar)
    local key = bar and bar.barData and bar.barData.resourceKey
    if not key then return nil end

    local groupData = bar.frameIndex and BarWardenDB and BarWardenDB.frames
                      and BarWardenDB.frames[bar.frameIndex]
    local pinned = groupData and groupData.autoPinnedResources
    if not pinned then return nil end

    local list = ns:NormalizePinnedResources(pinned)
    for _, entry in ipairs(list) do
        if entry.key == key and entry.color then
            local c = entry.color
            return c.r or 1, c.g or 1, c.b or 1
        end
    end

    -- Runes are pinned as a single "Keep Runes Visible" entry (key "runes")
    -- covering every rune bar in the group at once - there is no tickbox for
    -- an individual slot or pair, unlike Mana/Rage/Energy/Combo Points/Runic
    -- Power, which each own exactly one resourceKey. A per-slot resourceKey
    -- ("rune1".."rune6") or per-pair one ("runepair1".."runepair3", once
    -- Pair Runes by Type is on - Trackers.lua's collectRuneEntries) that
    -- found no exact match above therefore falls back to the shared "runes"
    -- entry, so the one swatch actually reaches the bars it is meant to
    -- colour.
    if key:match("^rune%d") or key:match("^runepair%d") then
        for _, entry in ipairs(list) do
            if entry.key == "runes" and entry.color then
                local c = entry.color
                return c.r or 1, c.g or 1, c.b or 1
            end
        end
    end

    return nil
end

-- ----------------------------------------------------------------------------
-- Built-in conditions.
--
-- requireClass goes first. Class never changes during a session so the check
-- is effectively constant; putting it first means bars that don't belong to
-- the player's class bail out before any of the more expensive checks run.
-- ----------------------------------------------------------------------------

local _, playerClass = UnitClass("player")

ns:RegisterCondition("requireClass", function(conditions)
    local required = conditions.requireClass
    if not required or required == "" then return true end
    return playerClass == required
end)

ns:RegisterCondition("combatOnly", function(conditions)
    if conditions.combatOnly then
        return UnitAffectingCombat("player")
    end
    return true
end)

ns:RegisterCondition("outOfCombatOnly", function(conditions)
    if conditions.outOfCombatOnly then
        return not UnitAffectingCombat("player")
    end
    return true
end)

ns:RegisterCondition("requireBuff", function(conditions)
    local buffName = conditions.requireBuff
    if not buffName then return true end
    for i = 1, MAX_AURA_INDEX do
        local name, _, _, _, _, _, _, _, _, _, spellId = UnitBuff("player", i)
        if not name then break end
        if name == buffName or (tonumber(buffName) and spellId == tonumber(buffName)) then
            return true
        end
    end
    return false
end)

ns:RegisterCondition("healthBelow", function(conditions)
    local threshold = conditions.healthBelow
    if not threshold then return true end
    local health = UnitHealth("player")
    local maxHealth = UnitHealthMax("player")
    if maxHealth == 0 then return true end
    local pct = (health / maxHealth) * 100
    return pct < threshold
end)

-- EC-TRAP: GetNumPartyMembers / GetNumRaidMembers are the 3.3.5a group queries.
-- Do NOT replace with GetNumGroupMembers (Cataclysm+, absent here). See CLAUDE.md.
ns:RegisterCondition("inGroup", function(conditions)
    if conditions.inGroup then
        return GetNumPartyMembers() > 0
    end
    return true
end)

ns:RegisterCondition("inRaid", function(conditions)
    if conditions.inRaid then
        return GetNumRaidMembers() > 0
    end
    return true
end)

-- Smart-visibility conditions (player state). All four APIs are confirmed
-- present on 3.3.5a (used by WeakAuras, DiminishingReturns, Forte, etc.).
-- The 0.25 s scan loop evaluates these cheaply; no dedicated events needed.

ns:RegisterCondition("hideWhileMounted", function(conditions)
    if conditions.hideWhileMounted then
        return not IsMounted()
    end
    return true
end)

ns:RegisterCondition("hideWhileResting", function(conditions)
    if conditions.hideWhileResting then
        return not IsResting()
    end
    return true
end)

ns:RegisterCondition("hideInVehicle", function(conditions)
    if conditions.hideInVehicle then
        return not UnitInVehicle("player")
    end
    return true
end)

ns:RegisterCondition("onlyInInstance", function(conditions)
    if conditions.onlyInInstance then
        local inInstance = IsInInstance()
        return inInstance
    end
    return true
end)
