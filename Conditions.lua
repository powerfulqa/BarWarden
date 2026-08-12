-- Conditions.lua - Visibility condition registry and evaluator.
-- Author:  Serv
-- Source:  https://github.com/powerfulqa/BarWarden
-- License: see LICENSE; attribution preservation is required.

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
