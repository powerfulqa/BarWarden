-- tests/test_frame_manager.lua
-- Covers ns.CompareAppearance and ns.IsGroupEmptyForBackdrop, the pure
-- functions exposed off FrameManager.lua, plus ns:UpdateGroupLayout's anchoring
-- rules driven through the StubGroup geometry model below. The rest of the file
-- builds real WoW frames (CreateFrame), which is out of scope for this harness
-- and rides the in-game smoke test instead.

local assertx    = require("assert")
local load_addon = require("load_addon")

local M = {}

local function fresh()
    local ns = {}
    load_addon.load("Utils.lua", "BarWarden", ns)
    load_addon.load("DB.lua", "BarWarden", ns)
    load_addon.load("FrameManager.lua", "BarWarden", ns)
    return ns
end

-- Lower appearanceOrder means "started earlier", so it sorts first.
function M.test_appearance_ordersOldestFirst()
    local ns = fresh()
    local older = { appearanceOrder = 1 }
    local newer = { appearanceOrder = 2 }
    assertx.assertTrue(ns.CompareAppearance(older, newer))
    assertx.assertFalse(ns.CompareAppearance(newer, older))
end

-- A resource bar (or anything that never went through ActivateBar /
-- ActivateStaticBar) carries no stamp at all and must sort last, not error.
function M.test_unstampedBarSortsLast()
    local ns = fresh()
    local stamped   = { appearanceOrder = 5 }
    local unstamped = {}
    assertx.assertTrue(ns.CompareAppearance(stamped, unstamped))
    assertx.assertFalse(ns.CompareAppearance(unstamped, stamped))
end

-- table.sort requires a strict weak ordering: two elements can never both
-- compare "less than" each other. Two unstamped bars used to be the risky
-- case (nothing to compare), so check that explicitly.
function M.test_twoUnstampedBars_neverBothCompareTrue()
    local ns = fresh()
    local x, y = {}, {}
    local xLessY = ns.CompareAppearance(x, y)
    local yLessX = ns.CompareAppearance(y, x)
    assertx.assertFalse(xLessY and yLessX, "comparator is not a strict weak ordering")
end

-- Sanity check against table.sort itself: mixed stamped/unstamped bars sort
-- into ascending appearance order with every unstamped bar trailing.
function M.test_sortWithMixedStamps()
    local ns = fresh()
    local bars = {
        { name = "c", appearanceOrder = 3 },
        { name = "unstamped1" },
        { name = "a", appearanceOrder = 1 },
        { name = "unstamped2" },
        { name = "b", appearanceOrder = 2 },
    }
    table.sort(bars, ns.CompareAppearance)
    assertx.assertEqual(bars[1].name, "a")
    assertx.assertEqual(bars[2].name, "b")
    assertx.assertEqual(bars[3].name, "c")
    -- The two unstamped bars trail, in some order; just confirm both are last.
    local tailNames = { bars[4].name, bars[5].name }
    table.sort(tailNames)
    assertx.assertEqual(tailNames[1], "unstamped1")
    assertx.assertEqual(tailNames[2], "unstamped2")
end

-- IsGroupEmptyForBackdrop: the v2.2.1 regression. An ordinary group's
-- emptiness is its configured bar count, same as before this was pulled out.
function M.test_isGroupEmptyForBackdrop_ordinaryGroup_noBars()
    local ns = fresh()
    local group = { isAutoGroup = false }
    local frameData = { bars = {} }
    assertx.assertTrue(ns.IsGroupEmptyForBackdrop(group, frameData, 0))
end

function M.test_isGroupEmptyForBackdrop_ordinaryGroup_withBars()
    local ns = fresh()
    local group = { isAutoGroup = false }
    local frameData = { bars = { { name = "Bar 1" } } }
    -- visibleCount = 0 on purpose: an ordinary group with a configured bar
    -- that just isn't showing right now still counts as "not empty" - it is
    -- keyed off configured bars, not what is currently on screen.
    assertx.assertFalse(ns.IsGroupEmptyForBackdrop(group, frameData, 0))
end

-- A pure auto group's frameData.bars is always the dormant hand-list (empty
-- for a group that has never been anything but auto-tracking), so #bars == 0
-- must NOT force the solid backdrop here - that was the v2.2.1 bug: Background
-- Opacity 0 still showed a solid black panel whenever the group had anything
-- in it, because this check looked at the wrong list.
function M.test_isGroupEmptyForBackdrop_autoGroup_slotsFilled()
    local ns = fresh()
    local group = { isAutoGroup = true }
    local frameData = { bars = {}, autoTrack = "player" }
    assertx.assertFalse(ns.IsGroupEmptyForBackdrop(group, frameData, 3))
end

-- An auto group with nothing currently on the unit still needs the solid
-- backdrop, or an unlocked-but-momentarily-empty group would vanish into the
-- user's own (possibly near-invisible) background alpha.
function M.test_isGroupEmptyForBackdrop_autoGroup_noneVisible()
    local ns = fresh()
    local group = { isAutoGroup = true }
    local frameData = { bars = {}, autoTrack = "player" }
    assertx.assertTrue(ns.IsGroupEmptyForBackdrop(group, frameData, 0))
end

-- ---------------------------------------------------------------------------
-- ns:UpdateGroupLayout anchoring
--
-- UpdateGroupLayout never calls CreateFrame; it only calls methods on the group
-- it is handed. StubGroup is therefore enough to drive it, and it models the one
-- WoW rule the anchoring depends on: a resize grows the frame AWAY from the
-- corner it is currently pinned by, so a TOPLEFT-pinned frame keeps its top and
-- a BOTTOMLEFT-pinned one keeps its bottom. Offsets are in the group's own unit
-- space against UIParent's BOTTOMLEFT, which is what ns:NormalizeGroupAnchor
-- produces (see its comment for why no scale conversion belongs anywhere here).
-- ---------------------------------------------------------------------------

local BAR_HEIGHT, BAR_SPACING, TITLE_OFFSET = 20, 2, 16

-- The height UpdateGroupLayout will give a group showing `rows` bars.
local function heightFor(rows)
    if rows < 1 then rows = 1 end
    return TITLE_OFFSET + rows * (BAR_HEIGHT + BAR_SPACING) + 4
end

local function StubBar(shown)
    local bar = { shownFlag = shown and true or false, barData = { display = {} } }
    function bar:IsShown()        return self.shownFlag end
    function bar:ClearAllPoints() end
    function bar:SetPoint()       end
    function bar:SetWidth()       end
    function bar:SetHeight()      end
    function bar:SetScale()       end
    return bar
end

-- point/x/y describe the anchor the group starts on; h is the height it starts
-- at (ns:CreateGroupFrame leaves a fresh frame on its 30px placeholder).
local function StubGroup(point, x, y, h, visibleBars)
    local g = { frameIndex = 1, bars = {}, left = x, height = h, pinned = point }
    -- `bottom` is the single stored edge; top is derived, so a resize moving one
    -- of them can never leave the two inconsistent.
    if point == "BOTTOMLEFT" then g.bottom = y else g.bottom = y - h end
    for i = 1, (visibleBars or 0) do g.bars[i] = StubBar(true) end

    function g:GetPoint()      return self.pinned end
    function g:GetLeft()       return self.left end
    function g:GetBottom()     return self.bottom end
    function g:GetTop()        return self.bottom + self.height end
    function g:SetWidth(w)     self.width = w end
    function g:SetHeight(newH)
        -- Grow away from the pinned corner: BOTTOMLEFT holds the bottom edge
        -- still, anything else holds the top.
        if self.pinned ~= "BOTTOMLEFT" then
            local top = self.bottom + self.height
            self.bottom = top - newH
        end
        self.height = newH
    end
    function g:ClearAllPoints() self.pinned = nil end
    function g:SetPoint(pt, _relFrame, _relPoint, px, py)
        self.pinned, self.left = pt, px
        if pt == "BOTTOMLEFT" then self.bottom = py else self.bottom = py - self.height end
    end
    function g:SetBackdropColor() end
    return g
end

local function layoutOnce(savedPoint, growDirection, startHeight, visibleBars)
    local ns = fresh()
    local group = StubGroup(savedPoint, 400, 500, startHeight, visibleBars)
    _G.BarWardenDB = {
        global = { enabled = true, locked = false },
        visual = { barWidth = 200, barHeight = BAR_HEIGHT, barSpacing = BAR_SPACING },
        frames = { {
            name = "G", width = 200, columns = 1, sortMode = "manual",
            growDirection = growDirection, bgAlpha = 0.6, bars = {},
        } },
    }
    local frameData = _G.BarWardenDB.frames[1]
    frameData.position = { point = savedPoint, relativePoint = "BOTTOMLEFT", x = 400, y = 500 }
    local savedTable = frameData.position
    ns:UpdateGroupLayout(group)
    local result = {
        group = group, frameData = frameData, savedTable = savedTable,
        top = group:GetTop(), bottom = group:GetBottom(),
    }
    _G.BarWardenDB = nil
    return result
end

-- The bug: ns:RebuildAllFrames lays a group out while ns:CreateGroupFrame's
-- 30px placeholder is still on it, so re-anchoring a grow-up group whose saved
-- corner is TOPLEFT used to pin the bottom at (saved top - 30) and then grow the
-- real height up from there, landing the group (real height - 30) too high AND
-- writing that spot to SavedVariables. The saved top edge must survive.
function M.test_repinOnRebuild_keepsSavedTopEdge_whenGrowthIsUp()
    local r = layoutOnce("TOPLEFT", "UP", 30, 6)
    assertx.assertEqual(r.group.pinned, "BOTTOMLEFT", "grow-up group must pin BOTTOMLEFT")
    assertx.assertEqual(r.top, 500, "saved top edge must not move")
    assertx.assertEqual(r.bottom, 500 - heightFor(6), "bottom follows from the real height")
    assertx.assertEqual(r.frameData.position.y, 500 - heightFor(6))
end

-- Mirror case: a grow-down group carrying a BOTTOMLEFT anchor keeps its bottom.
function M.test_repinOnRebuild_keepsSavedBottomEdge_whenGrowthIsDown()
    local r = layoutOnce("BOTTOMLEFT", "DOWN", 30, 6)
    assertx.assertEqual(r.group.pinned, "TOPLEFT", "grow-down group must pin TOPLEFT")
    assertx.assertEqual(r.bottom, 500, "saved bottom edge must not move")
    assertx.assertEqual(r.top, 500 + heightFor(6))
end

-- The displacement scaled with the group's height, which is why a tall group
-- looked far more broken than a short one. Same start, more bars, same answer.
function M.test_repinOnRebuild_isIndependentOfBarCount()
    local six    = layoutOnce("TOPLEFT", "UP", 30, 6)
    local twelve = layoutOnce("TOPLEFT", "UP", 30, 12)
    assertx.assertEqual(six.top, 500)
    assertx.assertEqual(twelve.top, 500, "a taller group must not land anywhere else")
end

-- An auto-tracking group is laid out with every slot hidden on the pass straight
-- after a rebuild, so its height there is the one-row minimum rather than what
-- the user sees once auras arrive. The anchor must still come from a size the
-- frame actually has, not from the placeholder it was created at.
function M.test_repinOnRebuild_emptyAutoGroup_usesItsOwnHeight()
    local r = layoutOnce("TOPLEFT", "UP", 30, 0)
    assertx.assertEqual(r.top, 500, "saved top edge must not move")
    assertx.assertEqual(r.bottom, 500 - heightFor(0))
end

-- The v2.0.2 guard: a group already pinned by the right corner must NOT be
-- re-derived, because relayout runs on every bar activate/deactivate and
-- re-deriving there is what made scaled groups creep towards the corner. Assert
-- table identity, so a re-derivation that happens to compute the same numbers
-- still fails.
function M.test_noRepin_whenPinAlreadyMatchesGrowth()
    local r = layoutOnce("TOPLEFT", "DOWN", 30, 6)
    assertx.assertTrue(r.frameData.position == r.savedTable,
        "position must not be rewritten when the pinned corner is already correct")
    assertx.assertEqual(r.top, 500)
end

function M.test_noRepin_whenGrowUpGroupAlreadyPinsBottom()
    local r = layoutOnce("BOTTOMLEFT", "UP", 30, 6)
    assertx.assertTrue(r.frameData.position == r.savedTable,
        "position must not be rewritten when the pinned corner is already correct")
    assertx.assertEqual(r.bottom, 500)
end

-- A settled group flipping growth direction mid-session is the case the old
-- read-edges-first ordering existed to serve: its size does not change, so both
-- orderings agree and the group must not budge.
function M.test_growthFlipOnSettledGroup_doesNotMove()
    local r = layoutOnce("TOPLEFT", "UP", heightFor(6), 6)
    assertx.assertEqual(r.group.pinned, "BOTTOMLEFT")
    assertx.assertEqual(r.top, 500, "a settled group must stay exactly where it is")
    assertx.assertEqual(r.bottom, 500 - heightFor(6))
end

-- ---------------------------------------------------------------------------
-- ns:UpdateGroupLayout backdrop alpha: the v2.2.4 bug. Background/Border
-- Opacity 0 on an empty group used to be permanently overridden to a solid
-- 0.85 fill. HasRealAnchor narrows that override to a group that has never
-- had a real screen anchor written to it (still on NewGroup's CENTER
-- placeholder); everything else honours its own alpha even while empty.
-- ---------------------------------------------------------------------------

local function StubGroupForBackdrop(point)
    local g = { frameIndex = 1, bars = {}, left = 100, bottom = 100, height = 30, pinned = point }
    function g:GetPoint()      return self.pinned end
    function g:GetLeft()      return self.left end
    function g:GetBottom()    return self.bottom end
    function g:GetTop()       return self.bottom + self.height end
    function g:SetWidth(w)    self.width = w end
    function g:SetHeight(h)   self.height = h end
    function g:ClearAllPoints() end
    function g:SetPoint(pt, _relFrame, _relPoint, px, py)
        self.pinned, self.left, self.bottom = pt, px, py
    end
    function g:SetBackdropColor(_r, _g, _b, a) self.bgAlpha = a end
    return g
end

-- Drives ns:UpdateGroupLayout end to end (rather than calling the alpha
-- decision in isolation) so the test proves what the owner actually sees,
-- through the same repin path a real relayout takes.
local function backdropAlphaFor(point, configuredBars, bgAlpha)
    local ns = fresh()
    local group = StubGroupForBackdrop(point)
    _G.BarWardenDB = {
        global = { enabled = true, locked = false },
        visual = { barWidth = 200, barHeight = BAR_HEIGHT, barSpacing = BAR_SPACING },
        frames = { {
            name = "G", width = 200, columns = 1, sortMode = "manual",
            growDirection = "DOWN", bgAlpha = bgAlpha, bars = configuredBars,
            position = { point = point, relativePoint = "BOTTOMLEFT", x = 100, y = 100 },
        } },
    }
    ns:UpdateGroupLayout(group)
    local alpha = group.bgAlpha
    _G.BarWardenDB = nil
    return alpha
end

-- The bug itself: an empty group still on the CENTER creation placeholder
-- gets the solid emphasis backdrop so a brand-new group can be found and
-- dragged, even when its own Background Opacity is 0.
function M.test_backdrop_emptyGroup_neverPositioned_getsEmphasis()
    local alpha = backdropAlphaFor("CENTER", {}, 0)
    assertx.assertEqual(alpha, 0.85, "an unpositioned empty group must show the solid emphasis backdrop")
end

-- The fix: once a group has a real corner anchor, an empty group honours its
-- own Background Opacity, including 0, exactly like a populated one.
function M.test_backdrop_emptyGroup_positioned_honoursOwnAlpha()
    local alpha = backdropAlphaFor("TOPLEFT", {}, 0)
    assertx.assertEqual(alpha, 0, "an empty group with a real anchor must honour its own alpha, even 0")
end

-- A populated group always honours its own alpha, positioned or not - the
-- emphasis backdrop only ever applies while a group is both empty and
-- unpositioned.
function M.test_backdrop_populatedGroup_neverPositioned_honoursOwnAlpha()
    local alpha = backdropAlphaFor("CENTER", { { name = "Bar 1" } }, 0)
    assertx.assertEqual(alpha, 0, "a populated group must honour its own alpha regardless of anchor")
end

return M
