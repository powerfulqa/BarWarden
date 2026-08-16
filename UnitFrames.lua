-- UnitFrames.lua - Unit frame widget: portrait + name/level + health/power
-- bars + a values column, driven by a unit token.
-- Author:  Serv
-- Source:  https://github.com/powerfulqa/BarWarden
-- License: GNU GPL v3 (see LICENSE); attribution preservation is required.

local addonName, ns = ...

-- ============================================================================
-- UnitFrames.lua
--
-- A second, separate way to show the same data a resource group already can
-- (see ns:CollectResources, Trackers.lua): the owner found a resource group
-- reads as "bars in a box" and wanted the conventional arrangement instead -
-- portrait on the left, a name/level header, health and power bars stacked
-- tightly, and the numbers either beside the bars or on them. Resource
-- groups are untouched by this file; both stay as separate, equally-supported
-- options.
--
-- The thing that makes this read as a unit frame rather than as a stack of
-- bars is NOT the borrowed artwork - it is the row hierarchy in
-- ns:PlanUnitFrameRows: health and power take a full row each, runes share
-- one row, combo points divide a row into lit segments, and secondary rows
-- draw shorter than primary ones. The first version gave every resource an
-- identical full-width bar and no amount of texture fixed it. Read that
-- section before changing how anything is positioned.
--
-- Nine frames: player, target, target's target, pet, focus, and four party
-- slots. There is only ONE widget - everything below is keyed by a unit
-- token (UNIT_TOKENS / UNIT_FRAME_KEYS), so a new frame is a row in those
-- tables plus a ns.DEFAULTS.unitFrames entry, not new code.
--
-- Two keyings, deliberately: a FRAME key ("party2") names one on-screen
-- frame, a CONFIG key ("party") names the settings block it reads. They are
-- the same for every frame except the party slots, which share one set of
-- settings while each keeping its own position. UNIT_FRAME_CONFIG maps
-- between them; read ConfigKeyFor / UnitFramePosition before touching
-- anything that indexes ns.db.unitFrames directly.
--
-- Roster changes need no events: the 0.25s scan already asks UnitExists for
-- every frame, and a frame whose unit is absent hides itself. Leaving and
-- joining a party is picked up within a tick without registering
-- PARTY_MEMBERS_CHANGED at all.
--
-- Positioning/dragging/rescaling is NOT a second implementation: it reuses
-- ns:ApplySavedFramePosition, ns:OnFrameDragStart, ns:OnFrameDragStop, and
-- ns:RescaleFrame (all FrameManager.lua, extracted from the group-frame code
-- specifically so this file could reuse them - see that file's comment
-- above ns:ApplySavedFramePosition). Bars are borrowed from the shared pool
-- via ns:AcquireBar/ns:ReleaseBar (BarPool.lua), the same as every other bar
-- in the addon; no CreateFrame("StatusBar") appears here, so the rule in
-- CLAUDE.md/ADDON_GUIDE.md needed no change. Resource data comes from
-- ns:CollectResources (Trackers.lua) and is drawn through the existing
-- ns:UpdateResourceBar (BarEngine.lua), so colouring, the rune-pair view, and
-- every other resource-bar behaviour documented there applies here for free.
-- Updates ride the existing 0.25s scan loop (ns:ScanUnitFrames is called
-- from Core.lua's OnUpdate ticker, right alongside ns:ScanAllBars) rather
-- than a second OnUpdate frame.
-- ============================================================================

local floor = math.floor
local max   = math.max

ns.unitFrames = {}  -- [key] = WoW frame object, mirrors ns.groupFrames

-- Unit token each frame key reads. UNIT_FRAME_KEYS is the scan/rebuild
-- iteration order, kept as a separate list so adding a frame is one line in
-- each rather than a restructure of either loop.
--
-- Pet, focus and party are not here yet. Pet and focus would be one line
-- each; party needs a roster that grows and shrinks on
-- PARTY_MEMBERS_CHANGED, which is a different shape of problem and belongs
-- in its own slice.
local UNIT_TOKENS = {
    player       = "player",
    target       = "target",
    targettarget = "targettarget",
    pet          = "pet",
    -- The FOCUS UNIT, which 3.3.5a does have (/focus, FocusFrame). Not to be
    -- confused with focus the POWER TYPE, which is a hunter pet's energy and
    -- is deliberately absent from ns.RESOURCE_FAMILIES because a player
    -- character never has it. Same word, unrelated things.
    focus        = "focus",
    party1       = "party1",
    party2       = "party2",
    party3       = "party3",
    party4       = "party4",
}
local UNIT_FRAME_KEYS = {
    "player", "target", "targettarget", "pet", "focus",
    "party1", "party2", "party3", "party4",
}

-- Which ns.DEFAULTS.unitFrames entry each frame reads its settings from.
--
-- All four party frames share ONE config, because nobody wants to set the
-- bar height four times. Everything except position is therefore shared;
-- position cannot be, so it is stored per frame key (see UnitFramePosition
-- below). A frame whose key is missing here configures itself, which is the
-- normal case.
local UNIT_FRAME_CONFIG = {
    party1 = "party", party2 = "party", party3 = "party", party4 = "party",
}

local function ConfigKeyFor(frameKey)
    return UNIT_FRAME_CONFIG[frameKey] or frameKey
end

local function UnitFrameConfig(frameKey)
    local db = ns.db and ns.db.unitFrames
    return db and db[ConfigKeyFor(frameKey)]
end

-- Read/write one frame's saved position. Frames with their own config store
-- it as cfg.position, which is where every existing save already has it;
-- frames sharing a config (party) store theirs under cfg.positions[key], so
-- four party frames can be dragged independently while sharing every other
-- setting.
-- Exposed on ns (rather than kept file-local like ConfigKeyFor) because the
-- split they encode is easy to get wrong and silent when wrong: a party
-- frame writing to cfg.position would have all four overwrite each other and
-- pile up on one spot, which reads as "dragging does not save" rather than
-- as a bug in position storage. Covered in tests/test_unit_frames.lua.
function ns:UnitFramePosition(cfg, frameKey)
    if not cfg then return nil end
    if ConfigKeyFor(frameKey) == frameKey then return cfg.position end
    return cfg.positions and cfg.positions[frameKey]
end

function ns:SaveUnitFramePosition(cfg, frameKey, pos)
    if not cfg then return end
    if ConfigKeyFor(frameKey) == frameKey then
        cfg.position = pos
    else
        cfg.positions = cfg.positions or {}
        cfg.positions[frameKey] = pos
    end
end

local function UnitFramePosition(cfg, frameKey)
    return ns:UnitFramePosition(cfg, frameKey)
end

local function SaveUnitFramePosition(cfg, frameKey, pos)
    return ns:SaveUnitFramePosition(cfg, frameKey, pos)
end

ns.UNIT_FRAME_KEYS = UNIT_FRAME_KEYS

-- Where each frame sits before it has ever been dragged. Loosely mirrors the
-- default UI (player left of centre, target right of it, target's target
-- further right again) so enabling all three gives a usable arrangement
-- rather than three frames piled on the same spot.
local UNIT_FRAME_DEFAULT_POSITIONS = {
    player       = { point = "CENTER", relativePoint = "CENTER", x = -270, y = -120 },
    target       = { point = "CENTER", relativePoint = "CENTER", x =  270, y = -120 },
    targettarget = { point = "CENTER", relativePoint = "CENTER", x =  450, y = -120 },
    pet          = { point = "CENTER", relativePoint = "CENTER", x = -270, y = -230 },
    focus        = { point = "CENTER", relativePoint = "CENTER", x =  450, y =   10 },
    -- Party frames stack down the left, clear of the others. Each is still
    -- dragged on its own; these only decide where they first appear.
    party1       = { point = "LEFT",   relativePoint = "LEFT",   x =   20, y =  180 },
    party2       = { point = "LEFT",   relativePoint = "LEFT",   x =   20, y =   90 },
    party3       = { point = "LEFT",   relativePoint = "LEFT",   x =   20, y =    0 },
    party4       = { point = "LEFT",   relativePoint = "LEFT",   x =   20, y =  -90 },
}

-- Pre-allocated resource-row slots. ns:CollectResources for the player
-- returns at most health + current power + a handful of class resources
-- (six rune slots is the largest single feed), so this comfortably covers
-- every case with room to spare, matching the headroom a resource
-- auto-tracking group gets from its own (user-configurable) Max Bars.
local MAX_UNIT_FRAME_SLOTS = 24

-- How many pooled bars each frame reserves. Sized per frame rather than
-- given every frame the player's allowance, because that allowance exists
-- for the player alone: health, up to three pinned power types, runic power,
-- six runes, five combo-point segments and soul shards. Nine frames at 24
-- each would hold 216 bars for a UI that can never draw more than a fraction
-- of them.
--
-- ns:CollectResources decides these numbers, not guesswork: runes, runic
-- power and soul shards are gated on unit == "player", and combo points are
-- excluded for targettarget, so only the player and the target can exceed
-- health-plus-power at all.
local UNIT_FRAME_SLOT_COUNTS = {
    player = MAX_UNIT_FRAME_SLOTS,
    -- Health, current power, and up to five combo-point segments, with room
    -- spare.
    target = 10,
}

-- Everything else shows health plus a power type. Six is already generous.
local DEFAULT_UNIT_FRAME_SLOTS = 6

local function SlotCountFor(frameKey)
    return UNIT_FRAME_SLOT_COUNTS[frameKey] or DEFAULT_UNIT_FRAME_SLOTS
end

-- ----------------------------------------------------------------------------
-- Pure layout constants + arithmetic. No frame objects are touched by
-- anything in this section, so it is fully unit-testable (tests/test_unit_frames.lua).
-- ----------------------------------------------------------------------------

local UF_BAR_WIDTH    = 120
local UF_BAR_HEIGHT   = 16
local UF_BAR_SPACING  = 1
local UF_HEADER_HEIGHT = 14
local UF_PADDING       = 4

-- Breathing room above and below the name inside the header band. Outlined
-- text needs a little more than its nominal point size or the outline itself
-- clips against the band edges.
local UF_HEADER_TEXT_PADDING = 4

-- The same allowance for the numbers inside a bar row.
local UF_ROW_TEXT_PADDING = 4

-- Floor for a segment/split row. Below this a rune strip stops reading as a
-- bar at all.
local UF_MIN_SEGMENT_HEIGHT = 6

-- Ceiling on how many segments one SPLIT resource may divide into. Real
-- values are five (combo points, soul shards); this only exists so a private
-- server reporting a nonsense max cannot ask for hundreds of slivers and
-- exhaust the bar pool.
local UF_MAX_SPLIT_SEGMENTS = 10

-- Bounds for the Bar Height setting. The floor is the point below which the
-- value text stops fitting on a bar at all; the ceiling just stops a typo or
-- a hand-edited profile producing a frame taller than the screen.
local UF_MIN_BAR_HEIGHT = 8
local UF_MAX_BAR_HEIGHT = 40

-- Fallback width for the values column, used only until the first scan has
-- real text to measure (see ns:MeasureUnitFrameValuesWidth and the
-- measured-width note above it). Deliberately narrow: the frame widens to
-- fit on the very next tick, and starting narrow-then-growing looks better
-- than starting wide-then-shrinking.
local UF_VALUES_MIN_WIDTH = 40

-- X-Perl's own frame backdrop, reproduced with its geometry exactly as
-- XPerl_BorderStyleTemplate declares it (XPerl_Globals.xml): its
-- XPerl_FrameBack tile, Blizzard's tooltip border, edge 16, tile 32, inset
-- 4. The artwork is GPL v3 and redistributed under that licence - it is the
-- reason this addon is GPL at all (see LICENSE and NOTICE.md).
--
-- This deliberately does NOT reuse ns.GROUP_BACKDROP: a bar group is a
-- container the player positions and should recede, whereas a unit frame is
-- meant to read as a piece of UI in its own right, the way the frames it
-- replaces do. They looked identical before this and that was the single
-- biggest reason the unit frame read as unfinished next to X-Perl.
local UNIT_FRAME_BACKDROP = {
    bgFile   = "Interface\\AddOns\\BarWarden\\Textures\\XPerl\\XPerl_FrameBack",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 32, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

-- X-Perl's own backdrop tint, from its option defaults: the frame fill is
-- BLACK and the border a mid grey (XPerl_FrameOptions.lua sets
-- colour.frame = {0,0,0,1} and colour.border = {0.5,0.5,0.5,1}).
--
-- This file originally drew the backdrop white, reasoning that tinting it
-- would mute the artwork. That was simply wrong about how X-Perl uses its
-- own tile: XPerl_FrameBack is a light texture that is MEANT to be tinted
-- dark, and leaving it white is why the frame read as washed-out grey and
-- why a 3D portrait appeared to sit on a grey background - the model is
-- transparent around the character, so the untinted tile showed through it.
local UF_BORDER_COLOR = { r = 0.5, g = 0.5, b = 0.5 }

-- Read one opacity setting, clamped to 0-1, defaulting to fully opaque for
-- anything unset or non-numeric (a hand-edited or imported profile). Every
-- part of the frame gets its own, so the panel, the portrait, the bars and
-- the border can each be faded independently.
function ns:GetUnitFrameOpacity(cfg, key)
    local alpha = cfg and cfg[key]
    if type(alpha) ~= "number" then return 1.0 end
    if alpha < 0 then return 0 end
    if alpha > 1 then return 1 end
    return alpha
end

-- Apply the backdrop tint to a frame or its portrait box. The colour is not
-- a setting, only the opacity: anything other than black stops looking like
-- the addon this artwork came from.
local function ApplyUnitFrameBackdropColor(f, cfg, opacityKey)
    f:SetBackdropColor(0, 0, 0, ns:GetUnitFrameOpacity(cfg, opacityKey))
    f:SetBackdropBorderColor(UF_BORDER_COLOR.r, UF_BORDER_COLOR.g, UF_BORDER_COLOR.b,
                             ns:GetUnitFrameOpacity(cfg, "borderOpacity"))
end

-- How much of each edge of a unit portrait to crop away. Blizzard's portrait
-- images carry a transparent margin around a circular subject; this is the
-- long-standing value that trims it without cutting into the face.
local UF_PORTRAIT_CROP = 0.15

-- Default bar texture for a unit frame. Registered by both SharedMedia.lua
-- (for LSM) and Bar.lua (for the LSM-less fallback) under this exact name,
-- so the default resolves either way.
local UF_DEFAULT_TEXTURE = "XP Perl v2"

-- Resolve a font path + size for one of the frame's fontstrings, falling
-- back to the addon-wide Visuals settings for anything the frame leaves
-- unset. Empty string / 0 mean "inherit" rather than being stored as a copy
-- of the current global, so a frame keeps following a later Visuals change.
--
-- Returns nil when there is no usable font at all, which is the caller's
-- signal to leave the fontstring on its template font rather than calling
-- SetFont with a nil path (which errors).
-- The LSM step is not optional and its absence is a silent failure: the font
-- dropdowns are populated from ns:LSMDropdownItems, which yields LSM NAMES
-- ("BW Adventure"), not file paths. SetFont given a name simply does nothing
-- and leaves the fontstring on its template font - which is exactly how this
-- first shipped, making the font AND size controls both look inert (no
-- SetFont call happens at all, so the size never lands either). Bar.lua's
-- ApplyVisualConfig does the same LSMFetch for the same reason.
local function ResolveUnitFrameFont(font, size, sizeBump)
    local visual = ns:GetVisual()
    local path = (font and font ~= "") and font or visual.font
    if not path or path == "" then
        path = "Fonts\\FRIZQT__.TTF"
    elseif ns.LSM then
        path = ns:LSMFetch("font", path) or path
    end
    local resolved = size
    if not resolved or resolved <= 0 then
        resolved = (visual.fontSize or 11) + (sizeBump or 0)
    end
    if resolved < 1 then resolved = 1 end
    return path, resolved
end

-- Which optional elements a unit frame currently shows, resolved from its
-- saved config. Nil-safe (a not-yet-built cfg reads as "show everything",
-- matching ns.DEFAULTS.unitFrames.player) so this can be called defensively
-- from anywhere without a live frame or a populated DB.
-- `values` is specifically "a values COLUMN is drawn", because that is the
-- only element that changes the layout arithmetic - values drawn on the bars
-- reserve no width. Placement is resolved here rather than at each use site
-- so the two settings that produce it (Show Values, and where) are read in
-- exactly one place: showValues == false must win over any placement, and
-- splitting that rule across callers is how one of them ends up disagreeing.
function ns:ResolveUnitFrameElements(cfg)
    cfg = cfg or {}
    local showValues = cfg.showValues ~= false
    local onBar = showValues and cfg.valuePlacement == "ONBAR"
    local name = cfg.showName ~= false
    local level = cfg.showLevel ~= false
    return {
        portrait    = cfg.showPortrait ~= false,
        portrait3D  = cfg.portraitStyle == "3D",
        name        = name,
        level       = level,
        -- The header band only exists if something goes in it. With both the
        -- name and the level switched off it collapses entirely rather than
        -- leaving an empty strip across the top of the frame.
        header      = name or level,
        values      = showValues and not onBar,
        valuesOnBar = onBar,
        barHeight   = cfg.barHeight,
    }
end

-- Pure layout arithmetic for the widget: given which optional elements are
-- shown and how many resource rows this scan collected, compute the frame's
-- overall size and where each piece anchors. ns:LayoutUnitFrame below is the
-- thin impure layer that feeds these numbers into SetPoint/SetSize calls.
--
-- The header (portrait-adjacent name/level text) is not itself an optional
-- element - a unit frame always has a name - only whether the level is
-- appended to it is a toggle (ns:ResolveUnitFrameElements above), so it does
-- not change this arithmetic at all.
-- `measuredValuesWidth` is the width the widest values-column string
-- actually needs, measured from the live fontstrings by
-- ns:MeasureUnitFrameValuesWidth. It is a parameter rather than a constant
-- because a fixed width is what broke this column in the first place: a
-- FontString given an explicit width wraps at spaces on 3.3.5a (there is no
-- SetWordWrap before 4.0), so "2489 / 2489 (100%)" in a 74px column split
-- across two lines and every row collided with the row beneath it. The
-- column is now never given a width at all - it cannot wrap - and the frame
-- widens to fit instead. Nil (no measurement yet) falls back to a narrow
-- starting width.
function ns:ComputeUnitFrameLayout(elements, barCount, measuredValuesWidth)
    elements = elements or {}
    if type(barCount) ~= "table" then
        barCount = max(barCount or 0, 1)
    end

    -- Bar height is a setting (X-Perl's bars are chunkier than the 14px this
    -- started at, and a values-on-the-bar frame needs the room), clamped so
    -- a hand-edited or imported profile cannot produce a frame with
    -- zero-height or absurd rows.
    local barHeight = elements.barHeight or UF_BAR_HEIGHT
    if barHeight < UF_MIN_BAR_HEIGHT then barHeight = UF_MIN_BAR_HEIGHT end
    if barHeight > UF_MAX_BAR_HEIGHT then barHeight = UF_MAX_BAR_HEIGHT end

    -- A bar must be at least as tall as the numbers it carries, exactly as
    -- the header band must fit the name. Without this the Values Size slider
    -- silently capped out around 12 for the same reason Name Size did: the
    -- text drew taller than its row and was clipped, so the slider looked
    -- broken rather than limited. This raises the FLOOR only, so an explicit
    -- Bar Height above it is still honoured.
    local valueSize = elements.valueFontSize
    if valueSize and valueSize + UF_ROW_TEXT_PADDING > barHeight then
        barHeight = valueSize + UF_ROW_TEXT_PADDING
    end

    -- `elements.header` is nil for a caller that predates the name toggle
    -- (and for the tests' minimal element tables), so nil reads as "there is
    -- a header", matching every frame built before it became optional.
    --
    -- The band grows with the name font. It used to be a flat 14px, which
    -- silently capped the Name Size slider: anything past about 12 drew
    -- taller than the band and was clipped, so the slider appeared to stop
    -- working rather than being visibly limited.
    local headerHeight = 0
    if elements.header ~= false then
        headerHeight = UF_HEADER_HEIGHT
        local nameSize = elements.nameFontSize
        if nameSize and nameSize + UF_HEADER_TEXT_PADDING > headerHeight then
            headerHeight = nameSize + UF_HEADER_TEXT_PADDING
        end
    end

    -- `barCount` is a plan table from ns:PlanUnitFrameRows when the caller has
    -- one, or a plain row count. The number form exists because most of this
    -- function's arithmetic never cared how tall the stack got, only that it
    -- had a height, and every test that predates segment rows passes a count.
    local barsHeight
    if type(barCount) == "table" then
        barsHeight = barCount.height or 0
    else
        barsHeight = barCount * barHeight + (barCount - 1) * UF_BAR_SPACING
    end
    local bodyHeight = headerHeight + barsHeight
    local portraitSize = elements.portrait and bodyHeight or 0

    -- Left edge of the body sits inside the backdrop's own 4px inset, so the
    -- artwork's border never overlaps the portrait or the first bar.
    --
    -- The bars butt straight up against the portrait with no gap. There used
    -- to be a UF_PADDING between them, on the reasoning that elements need
    -- breathing room; on screen it just read as a hole in the frame, because
    -- the portrait and the bars are one block, not two.
    local bodyX = UF_PADDING
    local barsX = bodyX + portraitSize

    local valuesWidth = 0
    if elements.values then
        valuesWidth = max(measuredValuesWidth or 0, UF_VALUES_MIN_WIDTH)
    end
    local valuesX = barsX + UF_BAR_WIDTH + (valuesWidth > 0 and UF_PADDING or 0)

    return {
        width        = valuesX + valuesWidth + UF_PADDING,
        height       = bodyHeight + UF_PADDING * 2,
        portraitSize = portraitSize,
        bodyX        = bodyX,
        barsX        = barsX,
        headerHeight = headerHeight,
        barsTop      = UF_PADDING + headerHeight,
        valuesX      = valuesX,
        valuesWidth  = valuesWidth,
        barWidth     = UF_BAR_WIDTH,
        barHeight    = barHeight,
        barSpacing   = UF_BAR_SPACING,
    }
end

-- ----------------------------------------------------------------------------
-- Row planning: what actually makes this look like a unit frame.
--
-- The first version of this widget gave every resource its own full-width
-- bar of equal height. That is not how a unit frame looks and no amount of
-- borrowed artwork fixed it: a death knight showed nine identical bars and
-- read as a stack in a box, with a rune slot given the same visual weight as
-- health. X-Perl (and Blizzard, and every other unit-frame addon) does two
-- things differently, and this section is both of them.
--
--   PRIMARY   health and whichever power the unit uses. One full-width bar
--             each, at the full configured bar height. These are the pools
--             you actually watch.
--   SEGMENT   runes. Every rune shares ONE row, side by side, rather than
--             taking a row each - six rows collapse to one.
--   SPLIT     combo points and soul shards. One row, divided into as many
--             segments as the resource has (five combo points, five segments),
--             each lit or unlit. This is the one case where a single
--             collected entry expands into several drawn slots.
--
-- SEGMENT and SPLIT rows draw at a reduced height, which is what actually
-- creates the hierarchy - a lit rune should not be as loud as the health bar.
--
-- All of this is pure: it takes the entry list ns:CollectResources produced
-- and returns positions, touching no frames. Widths and offsets come back as
-- FRACTIONS of the bar width (0-1) rather than pixels, so the plan is
-- independent of the frame's size and can be asserted on directly.
-- ----------------------------------------------------------------------------

-- How each resource is drawn. Keyed by the entry key CollectResources emits.
-- Anything unlisted is PRIMARY, so a resource added later gets a normal bar
-- rather than silently vanishing from the layout.
--
-- Rune keys are matched by prefix ("rune1".."rune6" and "runepair1".."3"),
-- the same test ns:ResourceFamilyForKey (Trackers.lua) uses. That knowledge
-- is deliberately duplicated rather than imported: this file's pure section
-- is loaded on its own by tests/test_unit_frames.lua, and reaching into
-- Trackers.lua would drag its mock requirements in for one string compare.
local ROW_STYLE = {
    combopoints = "SPLIT",
    soulshards  = "SPLIT",
}

function ns:UnitFrameRowStyle(key)
    if type(key) ~= "string" then return "PRIMARY" end
    if ROW_STYLE[key] then return ROW_STYLE[key] end
    if key:sub(1, 4) == "rune" then
        -- "runicpower" also starts with "rune" and is a genuine pool with its
        -- own full-width bar, not a rune slot. Excluded explicitly, because
        -- getting this wrong makes runic power a one-segment strip.
        if key ~= "runicpower" then return "SEGMENT" end
    end
    return "PRIMARY"
end

-- Gap between segments within a row, as a fraction of the bar width. Small
-- enough that six runes still read as one bar divided up rather than six
-- separate things.
local UF_SEGMENT_GAP = 0.012

-- Plan the rows for one scan's entries.
--
-- Returns { rows = { {height, top, valueEntry}, ... },
--           slots = { {entryIndex, row, offset, width, segIndex, segMax}, ... },
--           height = <total pixels> }
--
-- `slots` is in draw order and maps one-to-one onto pooled bars. A SPLIT
-- entry contributes several slots, which is why slots are not simply the
-- entries again.
--
-- `valueEntry` is the entry index whose numbers that row shows in the values
-- column, or nil for a row that shows none. A rune row deliberately shows
-- none: "4/6" next to six rune segments says nothing the segments have not
-- already said, and X-Perl prints nothing there either.
-- `maxSlots` caps how many drawable slots the plan may use, because a frame
-- only reserves so many pooled bars and the draw loops stop at that number.
-- Enforced at a ROW boundary rather than by letting the loops run out: a
-- truncated rune strip would draw four of six segments with no hint that two
-- were missing, which is the same silently-dropped-bar shape as a resource
-- group overflowing its Max Bars. Dropping the whole row is at least
-- visible. Nil means no cap.
function ns:PlanUnitFrameRows(entries, barHeight, secondaryHeight, maxSlots)
    entries = entries or {}
    barHeight = barHeight or UF_BAR_HEIGHT
    -- 0 (the stored "work it out" value) and nil both mean derive it.
    if not secondaryHeight or secondaryHeight < 1 then
        secondaryHeight = max(floor(barHeight * 0.6), UF_MIN_SEGMENT_HEIGHT)
    elseif secondaryHeight < UF_MIN_SEGMENT_HEIGHT then
        secondaryHeight = UF_MIN_SEGMENT_HEIGHT
    end

    local rows, slots = {}, {}
    local top = 0
    local openStyle, openKeyFamily

    local function newRow(height, valueEntry)
        if #rows > 0 then top = top + UF_BAR_SPACING end
        rows[#rows + 1] = { height = height, top = top, valueEntry = valueEntry }
        top = top + height
        return #rows
    end

    -- Would adding `count` more slots overrun the frame's reserved bars?
    -- Checked BEFORE a row is opened so the row is dropped whole rather than
    -- half-drawn.
    local function wouldOverrun(count)
        return maxSlots ~= nil and (#slots + count) > maxSlots
    end

    for i, e in ipairs(entries) do
        local style = ns:UnitFrameRowStyle(e and e.key)

        if style == "SEGMENT" then
            -- Consecutive runes share the open row. Grouping is by adjacency
            -- rather than by gathering all runes together, so the order
            -- CollectResources chose is never rearranged behind its back -
            -- its pin-ordering rules are load-bearing (see that function).
            if not wouldOverrun(1) then
                local rowIndex
                if openStyle == "SEGMENT" and openKeyFamily == "runes" then
                    rowIndex = #rows
                else
                    rowIndex = newRow(secondaryHeight, nil)
                    openStyle, openKeyFamily = "SEGMENT", "runes"
                end
                slots[#slots + 1] = { entryIndex = i, row = rowIndex }
            end

        elseif style == "SPLIT" then
            local segMax = e.max or 1
            if segMax < 1 then segMax = 1 end
            -- Capped so a private server reporting a nonsense max cannot ask
            -- for hundreds of slivers, each too thin to see, and exhaust the
            -- bar pool in the process.
            if segMax > UF_MAX_SPLIT_SEGMENTS then segMax = UF_MAX_SPLIT_SEGMENTS end
            if not wouldOverrun(segMax) then
                local rowIndex = newRow(secondaryHeight, i)
                for seg = 1, segMax do
                    slots[#slots + 1] = {
                        entryIndex = i, row = rowIndex, segIndex = seg, segMax = segMax,
                    }
                end
                openStyle, openKeyFamily = "SPLIT", nil
            end

        else
            if not wouldOverrun(1) then
                local rowIndex = newRow(barHeight, i)
                slots[#slots + 1] = { entryIndex = i, row = rowIndex }
                openStyle, openKeyFamily = "PRIMARY", nil
            end
        end
    end

    -- Second pass for the horizontal split. Done after the rows are known
    -- because a segment's width depends on how many ended up sharing its row,
    -- which is not known while the row is still being filled.
    local perRow = {}
    for _, s in ipairs(slots) do
        perRow[s.row] = (perRow[s.row] or 0) + 1
    end
    local seen = {}
    for _, s in ipairs(slots) do
        local n = perRow[s.row]
        local index = (seen[s.row] or 0)
        seen[s.row] = index + 1
        if n <= 1 then
            s.offset, s.width = 0, 1
        else
            local gap = UF_SEGMENT_GAP
            local w = (1 - gap * (n - 1)) / n
            s.offset = index * (w + gap)
            s.width = w
        end
    end

    return { rows = rows, slots = slots, height = top }
end

-- Width the values column needs to show every visible row without wrapping,
-- measured from the live fontstrings. GetStringWidth reports a FontString's
-- natural single-line width, which is only meaningful because these
-- fontstrings are never given an explicit width - see the note on
-- ns:ComputeUnitFrameLayout above.
--
-- Called only when a values string actually changed (ScanUnitFrame diffs
-- them already), so a frame whose numbers are steady pays nothing, and a
-- frame whose numbers tick pays a handful of GetStringWidth calls - the same
-- order of cost as the UnitHealth/UnitPower reads that produced them.
function ns:MeasureUnitFrameValuesWidth(valueTexts, count)
    local widest = 0
    for i = 1, count do
        local fs = valueTexts[i]
        if fs and fs:IsShown() then
            local w = fs:GetStringWidth() or 0
            if w > widest then widest = w end
        end
    end
    -- Ceil to a whole pixel: a fractional width would differ from the stored
    -- value on every comparison and re-layout the frame on every single tick.
    return floor(widest + 0.999)
end

-- Values-column text for one resource row: the raw current/max fraction plus
-- a percentage, e.g. "3000 / 4500 (67%)" - both pieces the owner asked for,
-- on one line so a tightly-stacked bar still has room for it. A resource
-- with no real max (should not happen for anything ns:CollectResources
-- returns, which already skips max <= 0, but this is guarded independently
-- so a malformed private-server read degrades to the bare current value
-- instead of dividing by zero) just shows the current number. Percent is
-- clamped to 0-100 so a stale server read just above full doesn't print
-- "104%".
function ns:FormatUnitFrameValue(current, max_)
    current = current or 0
    if not max_ or max_ <= 0 then
        return tostring(current)
    end
    local pct = current / max_
    if pct < 0 then pct = 0 elseif pct > 1 then pct = 1 end
    return string.format("%d / %d (%d%%)", current, max_, floor(pct * 100 + 0.5))
end

-- ----------------------------------------------------------------------------
-- Impure: frame construction, layout application, scanning, teardown.
-- ----------------------------------------------------------------------------

-- Apply a layout computed by ns:ComputeUnitFrameLayout to the live frame:
-- resize it, place the portrait/header, and position every bar + values
-- text. Only called when the number of resource rows actually changes
-- (see ScanUnitFrame below) - a per-scan reformat of unchanged geometry
-- would be exactly the kind of per-frame-path work CLAUDE.md asks this
-- slice to avoid.
local function LayoutUnitFrame(frame, elements, plan, measuredValuesWidth)
    local layout = ns:ComputeUnitFrameLayout(elements, plan, measuredValuesWidth)

    frame:SetWidth(layout.width)
    frame:SetHeight(layout.height)

    if frame.portraitFrame then
        if elements.portrait then
            frame.portraitFrame:ClearAllPoints()
            frame.portraitFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", layout.bodyX, -UF_PADDING)
            frame.portraitFrame:SetWidth(layout.portraitSize)
            frame.portraitFrame:SetHeight(layout.portraitSize)
            frame.portraitFrame:Show()
        else
            frame.portraitFrame:Hide()
        end
    end

    -- The click targets track what they sit over, so they are re-anchored
    -- here rather than once at build time: the portrait and the header band
    -- both change size with the bar count and the name font.
    if frame.portraitButton then
        if elements.portrait then
            frame.portraitButton:ClearAllPoints()
            frame.portraitButton:SetAllPoints(frame.portraitFrame)
            frame.portraitButton:Show()
        else
            frame.portraitButton:Hide()
        end
    end

    -- The header strip spans the bars and the values column together, so the
    -- name and the numbers share one band across the top of the frame.
    local headerShown = layout.headerHeight > 0
    if frame.headerStrip then
        if headerShown then
            frame.headerStrip:ClearAllPoints()
            frame.headerStrip:SetPoint("TOPLEFT", frame, "TOPLEFT", layout.barsX, -UF_PADDING)
            frame.headerStrip:SetWidth(layout.valuesX + layout.valuesWidth - layout.barsX)
            frame.headerStrip:SetHeight(layout.headerHeight)
            frame.headerStrip:Show()
        else
            frame.headerStrip:Hide()
        end
    end

    if frame.nameButton then
        if headerShown then
            frame.nameButton:ClearAllPoints()
            frame.nameButton:SetPoint("TOPLEFT", frame, "TOPLEFT", layout.barsX, -UF_PADDING)
            frame.nameButton:SetWidth(layout.valuesX + layout.valuesWidth - layout.barsX)
            frame.nameButton:SetHeight(layout.headerHeight)
            frame.nameButton:Show()
        else
            frame.nameButton:Hide()
        end
    end

    if headerShown then
        frame.nameText:ClearAllPoints()
        frame.nameText:SetPoint("LEFT", frame, "TOPLEFT",
            layout.barsX + 3, -(UF_PADDING + layout.headerHeight / 2))
        frame.nameText:SetPoint("RIGHT", frame, "TOPLEFT",
            layout.valuesX + layout.valuesWidth - 3, -(UF_PADDING + layout.headerHeight / 2))
        frame.nameText:Show()
    else
        frame.nameText:Hide()
    end

    -- Place each planned slot. A slot's offset and width are fractions of the
    -- bar width (see ns:PlanUnitFrameRows), so six runes sharing a row each
    -- get a sixth of it, and a lone health bar gets all of it - one code path
    -- rather than a special case per row style.
    local slots = plan and plan.slots or {}
    local rows  = plan and plan.rows  or {}

    for i = 1, frame.slotCount do
        local bar = frame.bars[i]
        local bg = frame.barBackdrops[i]
        local slot = slots[i]

        if slot then
            local row = rows[slot.row]
            local y = -(layout.barsTop + (row and row.top or 0))
            local h = row and row.height or layout.barHeight
            local x = layout.barsX + slot.offset * layout.barWidth
            local w = slot.width * layout.barWidth

            bar:ClearAllPoints()
            bar:SetPoint("TOPLEFT", frame, "TOPLEFT", x, y)
            bar:SetWidth(w)
            bar:SetHeight(h)

            -- The unfilled remainder of a bar. Without this a resource sitting
            -- at zero (an out-of-combat rage bar, a spent rune) drew as a bare
            -- hole in the backdrop rather than as an empty bar.
            bg:ClearAllPoints()
            bg:SetPoint("TOPLEFT", frame, "TOPLEFT", x, y)
            bg:SetWidth(w)
            bg:SetHeight(h)
        end
    end

    -- One values entry per ROW, not per slot: a row of six rune segments has
    -- one set of numbers at most, and rows that show none (runes) simply have
    -- no valueEntry.
    for i = 1, frame.slotCount do
        local valueText = frame.valueTexts[i]
        local row = rows[i]
        valueText:ClearAllPoints()
        if row then
            valueText:SetPoint("RIGHT", frame, "TOPLEFT",
                layout.valuesX + layout.valuesWidth,
                -(layout.barsTop + row.top + row.height / 2))
        end
    end

    frame.lastLayoutBarCount = plan and #plan.slots or 0
    frame.lastLayoutRowCount = plan and #plan.rows or 0
    frame.lastValuesWidth = layout.valuesWidth
    -- The MEASUREMENT this layout was built from, kept separate from the
    -- width actually applied. They differ whenever the measurement falls
    -- under UF_VALUES_MIN_WIDTH, and comparing the next measurement against
    -- the applied width instead would then never match - re-laying the frame
    -- out on every tick that touched a number.
    frame.lastValuesMeasured = measuredValuesWidth or 0
    return layout
end

-- Build the frame for `key` (currently only ever "player"). Bars are
-- acquired from the shared pool exactly like an auto-tracking resource
-- group's slots (see NewAutoBarData, FrameManager.lua): each carries a
-- runtime-only barData, never written to SavedVariables. frameIndex is
-- deliberately left nil (unlike a group's bars) - that integer indexes
-- BarWardenDB.frames (bar GROUPS), a different table this widget has
-- nothing to do with, so leaving it unset is what keeps every frameIndex-
-- gated resolver (GetBarColor's per-group override, GetBarTextFormat's
-- group text format, and so on) a harmless no-op here rather than a
-- collision with an unrelated group.
local function BuildUnitFrame(key)
    local unit = UNIT_TOKENS[key]
    local cfg = UnitFrameConfig(key)
    if not unit or not cfg then return nil end

    -- The bar texture this frame draws with, resolved up front because both
    -- the header strip and every bar background need it. Applied to the bars
    -- themselves as a per-bar textureOverride (the highest-precedence level
    -- ns:ApplyVisualConfig resolves) rather than left to the addon-wide
    -- visual.texture: a unit frame should look like a unit frame regardless
    -- of the texture chosen for timer bars. It is still a setting, so anyone
    -- who wants them to match can say so.
    local barTexture = cfg.barTexture or UF_DEFAULT_TEXTURE

    local frame = CreateFrame("Frame", "BarWardenUnitFrame" .. key, UIParent)
    frame.isUnitFrame = true
    frame.unitKey = key

    frame:SetBackdrop(UNIT_FRAME_BACKDROP)
    ApplyUnitFrameBackdropColor(frame, cfg, "frameOpacity")
    frame:SetWidth(160)
    frame:SetHeight(40)  -- placeholder; the first ScanUnitFrame pass resizes it

    -- Only used until the frame is first dragged (ns:ApplySavedFramePosition
    -- prefers cfg.position whenever there is one). A per-key default matters:
    -- with a single shared one, enabling all three frames would stack them
    -- exactly on top of each other at dead centre and look broken until each
    -- was found and dragged apart.
    ns:ApplySavedFramePosition(frame, UnitFramePosition(cfg, key),
        UNIT_FRAME_DEFAULT_POSITIONS[key] or
        { point = "CENTER", relativePoint = "CENTER", x = 0, y = 0 })

    local scale = math.max(ns.MIN_FRAME_SCALE, math.min(ns.MAX_FRAME_SCALE, cfg.scale or 1.0))
    frame:SetScale(scale)

    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", ns.OnFrameDragStart)
    frame:SetScript("OnDragStop", function(self)
        ns:OnFrameDragStop(self, false, function(pos)
            SaveUnitFramePosition(UnitFrameConfig(key), key, pos)
        end)
    end)
    if BarWardenDB and BarWardenDB.global.locked then
        frame:EnableMouse(false)
    end

    -- Click-to-target. A unit frame you cannot click is a picture of a unit
    -- frame, so the portrait and the name band both select the unit they
    -- describe, and right-click opens its unit menu.
    --
    -- These are SecureUnitButtonTemplate buttons rather than plain OnMouseUp
    -- handlers because TargetUnit is protected in combat on 3.3.5a: an
    -- insecure script calling it mid-fight is blocked, which is precisely
    -- when clicking a party frame matters. The secure template does the
    -- targeting itself from the attributes below, with no addon code running
    -- at click time.
    --
    -- They are CHILDREN of the frame, and deliberately keep their own mouse
    -- enabled when the frame is locked: locking is about not dragging things
    -- by accident, not about making the frame inert. A child's mouse
    -- handling is independent of its parent's EnableMouse, so this survives
    -- ns:LockAllFrames without that function needing to know about them.
    local function MakeClickTarget(name)
        -- pcall: SetAttribute on a secure frame is blocked in combat, and a
        -- rebuild CAN be triggered from the options panel mid-fight. Failing
        -- to be clickable until the next rebuild is an acceptable outcome;
        -- erroring the whole frame build is not.
        local ok, button = pcall(CreateFrame, "Button", name, frame,
                                 "SecureUnitButtonTemplate")
        if not ok or not button then return nil end

        pcall(function()
            button:SetAttribute("unit", unit)
            button:SetAttribute("type1", "target")
            button:SetAttribute("type2", "togglemenu")
            button:RegisterForClicks("AnyUp")
        end)

        -- Above everything else in the frame. These buttons are created
        -- before the portrait and the bars, so without this they would sit
        -- UNDER them in child order. Nothing above them enables mouse today,
        -- so clicks would still land - but that is an accident of what those
        -- pieces happen to do, not something to rely on.
        button:SetFrameLevel(frame:GetFrameLevel() + 10)

        -- Drag is forwarded to the parent so an unlocked frame can still be
        -- picked up by its portrait or its name, which is where anyone would
        -- naturally grab it. Without this the two most obvious grab handles
        -- would swallow the drag and the frame would only move from its edges.
        button:RegisterForDrag("LeftButton")
        button:SetScript("OnDragStart", function()
            if BarWardenDB and BarWardenDB.global.locked then return end
            ns.OnFrameDragStart(frame)
        end)
        button:SetScript("OnDragStop", function()
            if BarWardenDB and BarWardenDB.global.locked then return end
            ns:OnFrameDragStop(frame, false, function(pos)
                SaveUnitFramePosition(UnitFrameConfig(key), key, pos)
            end)
        end)
        return button
    end

    frame.portraitButton = MakeClickTarget("BarWardenUnitFramePortrait" .. key)
    frame.nameButton     = MakeClickTarget("BarWardenUnitFrameName" .. key)

    -- Portrait. SetPortraitTexture(texture, unit) is the standard 3.3.5a API;
    -- guarded with pcall since a private server is not trusted to implement
    -- it identically (per-3.3.5a-private-server rule).
    --
    -- The portrait gets its own bordered sub-frame rather than being a bare
    -- texture on the parent, matching XPerl_Portrait_Template: X-Perl's
    -- portrait is ringed by the same border as the frame body, and without
    -- that ring the portrait art just bled into the backdrop with no edge.
    local portraitFrame = CreateFrame("Frame", nil, frame)
    -- No backdrop of its own. It used to carry the full bordered panel, which
    -- meant the portrait art sat inside two borders (its own and the frame's)
    -- and could not line up with the bars beside it: the art started 5px
    -- inside a box whose own edge was already inset from the panel. Dropping
    -- the border lets the portrait occupy exactly the same vertical span as
    -- the header plus the bar stack, so the two columns align at top and
    -- bottom whether or not the borders are visible.
    --
    -- A plain black fill stays behind it: a 3D model is transparent around
    -- the character, so without a backing the game world shows through its
    -- head.
    --
    -- Portrait opacity is applied to the WHOLE portrait frame, not just this
    -- backing. Fading only the backing did nothing visible whenever the panel
    -- behind it was solid, because the portrait sits ON TOP of the panel -
    -- turning the backing transparent simply revealed the panel through it,
    -- so the portrait appeared to follow the Panel slider and ignore its own.
    -- Setting the frame's alpha fades the backing, the picture and the 3D
    -- model together, which is what "portrait opacity" has to mean for the
    -- slider to do anything at all over an opaque panel.
    local portraitBG = portraitFrame:CreateTexture(nil, "BACKGROUND")
    portraitBG:SetAllPoints(portraitFrame)
    portraitBG:SetTexture("Interface\\Buttons\\WHITE8x8")
    portraitBG:SetVertexColor(0, 0, 0, 1)
    portraitFrame:SetAlpha(ns:GetUnitFrameOpacity(cfg, "portraitOpacity"))
    frame.portraitBG = portraitBG
    frame.portraitFrame = portraitFrame

    local portrait = portraitFrame:CreateTexture(nil, "ARTWORK")
    portrait:SetAllPoints(portraitFrame)
    -- SetPortraitTexture hands back a square image whose subject is a circle
    -- with transparent corners - drawn raw it reads as a small head floating
    -- in a black box, which is exactly how it looked. Cropping past the
    -- transparent margin makes the portrait fill its frame, which is what
    -- X-Perl and every other unit-frame addon does with it.
    portrait:SetTexCoord(UF_PORTRAIT_CROP, 1 - UF_PORTRAIT_CROP,
                         UF_PORTRAIT_CROP, 1 - UF_PORTRAIT_CROP)
    frame.portrait = portrait

    -- Live 3D model, the same approach X-Perl uses (XPerl_Portrait_Template
    -- carries a PlayerModel alongside the flat texture, and XPerlSetPortrait3D
    -- drives it with ClearModel/SetUnit/SetCamera(0) for the head shot).
    -- Created unconditionally but only shown when asked for: building it
    -- lazily would mean a CreateFrame on a settings change, and an unshown
    -- PlayerModel costs nothing.
    --
    -- pcall-guarded because PlayerModel is the one frame type a private
    -- server is most likely to have altered, and a missing SetUnit must
    -- degrade to the flat portrait rather than error on a 4 Hz path.
    local ok, model = pcall(CreateFrame, "PlayerModel", nil, portraitFrame)
    if ok and model then
        model:SetAllPoints(portraitFrame)
        model:Hide()
        frame.portrait3D = model
    end

    -- Header: name, optionally with a colour-escaped level suffix
    -- (ns:FormatUnitLevelSuffix, FrameManager.lua - already built and tested
    -- for the "Group Name Follows Target" resource-group feature; reused
    -- verbatim rather than re-implemented).
    local visual = ns:GetVisual()

    -- A strip behind the name, so the header reads as part of the frame
    -- rather than as text floating over the backdrop. X-Perl's name sits on
    -- its own panel; this is the same idea with the artwork already loaded.
    local headerStrip = frame:CreateTexture(nil, "BORDER")
    headerStrip:SetTexture(ns.ResolveTextureName and ns:ResolveTextureName(barTexture)
        or "Interface\\Buttons\\WHITE8x8")
    -- Fades with the Panel slider, not on its own: the name band reads as
    -- part of the same dark surface as the frame background and the bar
    -- backgrounds, so leaving it at a fixed alpha made it the one piece that
    -- stayed solid when everything around it was turned down.
    headerStrip:SetVertexColor(0.1, 0.1, 0.1,
        0.85 * ns:GetUnitFrameOpacity(cfg, "frameOpacity"))
    frame.headerStrip = headerStrip

    local nameText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameText:SetJustifyH("LEFT")
    -- +1 on the inherited size: the name is the frame's title and reads a
    -- step above the numbers unless the owner sets an explicit size.
    local nameFontPath, nameFontSize = ResolveUnitFrameFont(cfg.nameFont, cfg.nameFontSize, 1)
    if nameFontPath then
        nameText:SetFont(nameFontPath, nameFontSize, "OUTLINE")
    end
    -- Fed into the layout so the header band grows with the font instead of
    -- clipping it (see ns:ComputeUnitFrameLayout).
    frame.nameFontSize = nameFontSize
    frame.nameText = nameText
    frame.lastHeaderText = nil

    -- Resolved once for the whole slot loop rather than per slot: every
    -- values fontstring uses the same font, and ResolveUnitFrameFont reads
    -- ns:GetVisual() each call.
    local valueFontPath, valueFontSize = ResolveUnitFrameFont(cfg.valueFont, cfg.valueFontSize, 0)
    -- Stashed on the frame because the on-bar placement has to re-apply them
    -- on every scan (see the note in ScanUnitFrame), not just at build time.
    frame.valueFontPath = valueFontPath
    frame.valueFontSize = valueFontSize

    -- Bars vs panel, and why this changed twice.
    --
    -- This first faded the bar FILLS, then was moved to fade only the
    -- unfilled background behind them, because dimming the fill dims the
    -- data. In practice that made the slider look broken: the background is
    -- only visible on the UNFILLED part of a bar, and a unit frame's bars sit
    -- at 100% almost all the time (full health, full mana, a ready rune), so
    -- there was usually nothing left of it to see. The black a player reads
    -- as "behind the bars" is the panel backdrop, not this.
    --
    -- So the two are now split the way they actually look: "Panel" covers
    -- the frame backdrop AND these bar backgrounds, since they read as one
    -- surface, and "Bars" goes back to the fills. Note that fading a bar
    -- fades its on-bar numbers too - they are regions of the same frame -
    -- which is consistent with what the slider claims to do.
    local barOpacity = ns:GetUnitFrameOpacity(cfg, "barOpacity")
    frame.barOpacity = barOpacity
    local panelOpacity = ns:GetUnitFrameOpacity(cfg, "frameOpacity")

    -- Set before the loop below, and read by every later pass over this
    -- frame's slots (layout, scan, values measurement) so each frame walks
    -- only the bars it actually reserved.
    frame.slotCount = SlotCountFor(key)

    frame.bars = {}
    frame.valueTexts = {}
    frame.barBackdrops = {}
    for i = 1, frame.slotCount do
        -- Drawn before the bar is acquired so it sits behind it: the pool
        -- parents bars to this frame at a higher draw layer.
        local bg = frame:CreateTexture(nil, "BACKGROUND")
        bg:SetTexture(ns.ResolveTextureName and ns:ResolveTextureName(barTexture)
            or "Interface\\Buttons\\WHITE8x8")
        bg:SetVertexColor(0.15, 0.15, 0.15, 0.9 * panelOpacity)
        bg:Hide()
        frame.barBackdrops[i] = bg

        local bar = ns:AcquireBar(frame)
        bar.barData = {
            name = "", enabled = false, trackMode = "Buff", unit = unit,
            -- showIcon = false: a unit frame's bars are plain fills, not
            -- icon rows - identity lives in the header, numbers live in the
            -- values column, so a per-row icon would just be clutter.
            display = { lingerTime = 0, showIcon = false, textureOverride = barTexture },
            conditions = {},
        }
        bar.barIndex   = i
        bar.frameIndex = nil
        bar.isAutoBar  = false
        bar.isResourceBar = false
        bar.barState = ns.BAR_STATE and ns.BAR_STATE.INACTIVE or 0
        if ns.ApplyVisualConfig then ns:ApplyVisualConfig(bar) end
        bar:Hide()
        frame.bars[i] = bar

        -- No SetWidth, ever: an explicit width makes a 3.3.5a FontString
        -- wrap at spaces, which is what stacked two lines of every row on top
        -- of the row below it. Width is reserved by the frame instead
        -- (ns:MeasureUnitFrameValuesWidth).
        local valueText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        valueText:SetJustifyH("RIGHT")
        valueText:SetJustifyV("MIDDLE")
        if valueFontPath then
            valueText:SetFont(valueFontPath, valueFontSize, "OUTLINE")
        end
        -- The values column can overhang the frame edge onto the game world
        -- while the frame is mid-resize, so it carries its own shadow rather
        -- than relying on the backdrop behind it for contrast.
        valueText:SetShadowColor(0, 0, 0, 1)
        valueText:SetShadowOffset(1, -1)
        valueText:Hide()
        frame.valueTexts[i] = valueText
    end

    ns.unitFrames[key] = frame
    return frame
end

local function DestroyUnitFrame(key)
    local frame = ns.unitFrames[key]
    if not frame then return end
    ns:ReleaseFrameBars(frame)
    frame:Hide()
    frame:ClearAllPoints()
    frame:SetParent(UIParent)
    ns.unitFrames[key] = nil
end

-- Refresh one unit frame's bars, header, and values column from
-- ns:CollectResources. Called every 0.25s scan tick (ns:ScanUnitFrames
-- below), same cadence a resource auto-tracking group's slots refresh at.
--
-- Per-frame-path discipline (CLAUDE.md): the header text and each values-
-- column entry are cached and only written when they actually changed,
-- exactly as ns:ScanAutoResourceGroup (BarEngine.lua) already does for a
-- resource group's title. The full per-bar reposition (LayoutUnitFrame) is
-- similarly skipped unless the number of resource rows changed since the
-- last pass. Bar fill/colour/text is NOT diffed here beyond that: it goes
-- through ns:UpdateResourceBar, the same function every resource bar
-- (hand-placed or auto-tracked) already runs through every tick, so this
-- adds no new per-tick cost class beyond what that shared path already pays.
local function ScanUnitFrame(key)
    local frame = ns.unitFrames[key]
    if not frame then return end
    local cfg = UnitFrameConfig(key)
    if not cfg or not cfg.enabled then return end
    local unit = UNIT_TOKENS[key]
    if not unit then return end

    -- A frame for a unit that is not there right now hides completely rather
    -- than sitting as an empty bordered box with a blank portrait. "player"
    -- always exists, so this only ever fires for target / target's target,
    -- which is exactly the behaviour the default UI has and what makes an
    -- empty target frame disappear the moment you clear your target.
    --
    -- Deliberately checked here rather than left to ns:CollectResources
    -- returning nothing: an entry-less frame would still draw its panel,
    -- border and header.
    if unit ~= "player" and not (UnitExists and UnitExists(unit)) then
        if frame:IsShown() then
            frame:Hide()
            -- Dropped so re-targeting re-seats the 3D model and rewrites the
            -- header rather than trusting values stamped for the last target.
            frame.lastPortraitGUID = nil
            frame.lastHeaderText = nil
        end
        return
    end
    if not frame:IsShown() then frame:Show() end

    local elements = ns:ResolveUnitFrameElements(cfg)
    -- The resolved (not configured) name size: cfg.nameFontSize is 0 for
    -- "inherit", and the header has to size itself to what was actually
    -- applied, which only BuildUnitFrame knows.
    elements.nameFontSize = frame.nameFontSize
    elements.valueFontSize = frame.valueFontSize
    -- pairRunes collapses six rune rows to three ready-count rows. Reused
    -- from the resource-group feature rather than reimplemented, and defaulted
    -- ON for unit frames (unlike groups, where it stays off so an existing
    -- group's six-bar view is unchanged): six full-width rune bars are the
    -- single biggest reason a frame reads as cluttered, and a frame is a new
    -- surface with no existing look to preserve.
    --
    -- `pinned` carries the ticked power types (see ns:BuildUnitFramePins).
    -- Without it, mana/rage/energy only ever appear when one of them is the
    -- unit's CURRENT power type, so on a classless server a character with
    -- all three would still only ever see one - a filter can hide, but it
    -- cannot add. The filter afterwards is what honours the unticked ones.
    --
    -- pinPowerTypes is what separates the player frame from the target's.
    -- The player frame offers a tick list because one character on a
    -- classless server has several pools at once and wants to choose; a
    -- target frame should behave like the default UI and show what the
    -- target actually has, which is health plus its current power type.
    --
    -- Getting that costs nothing: ns:CollectResources already gates runes,
    -- runic power and soul shards on unit == "player" (they are the player's
    -- own pools, see that function), and excludes combo points for
    -- targettarget. So a frame that passes no pins and no hidden set gets
    -- the standard shape for free. Do not "tidy" this by giving the target
    -- the player's config block - see docs/CODE_REVIEW.md item 25.
    local entries = ns:CollectResources({
        unit = unit,
        pairRunes = cfg.pairRunes ~= false,
        pinned = cfg.pinPowerTypes and ns:BuildUnitFramePins(cfg.hiddenResources) or nil,
    })
    entries = ns:FilterResourceEntries(entries, cfg.hiddenResources)

    -- The plan decides which entries share a row and how each row is divided
    -- (ns:PlanUnitFrameRows). It is rebuilt every scan because it is cheap
    -- arithmetic over a list of at most a dozen entries, and because the
    -- shape genuinely changes underfoot - a combo point gained changes
    -- nothing, but a druid shifting form or a rune being converted does.
    local plan = ns:PlanUnitFrameRows(entries, elements.barHeight,
                                      cfg.secondaryBarHeight, frame.slotCount)

    -- Re-layout on any change to the SHAPE (slot or row count), not just the
    -- entry count: six runes collapsing to three pairs changes the row
    -- heights while leaving the number of entries alone in some cases.
    if frame.lastLayoutBarCount ~= #plan.slots
       or frame.lastLayoutRowCount ~= #plan.rows then
        LayoutUnitFrame(frame, elements, plan, frame.lastValuesMeasured)
    end
    frame.plan = plan

    -- Header: name (+ level). Diffed against frame.lastHeaderText, a
    -- runtime-only cache field, so an unchanged header never touches the
    -- fontstring - mirrors group.lastTitleName in ns:ScanAutoResourceGroup.
    local exists = UnitExists and UnitExists(unit)
    local unitName = (elements.name and exists) and (UnitName(unit) or "") or ""
    local levelSuffix = (elements.level and exists) and ns:FormatUnitLevelSuffix(unit) or ""
    local headerText = (levelSuffix ~= "") and (unitName .. "  " .. levelSuffix) or unitName
    if frame.lastHeaderText ~= headerText then
        frame.lastHeaderText = headerText
        frame.nameText:SetText(headerText)
    end

    -- Portrait: not diffed the way text is - there is no cheap equality
    -- check for "did the texture change" the way there is for a string, and
    -- SetPortraitTexture is a single lightweight client call, no more
    -- expensive than the UnitHealth/UnitPower reads ns:CollectResources just
    -- made above for every row. Skipped entirely while hidden.
    if elements.portrait then
        -- A 3D model can only render a unit the client can actually see, so
        -- an out-of-range or out-of-view unit falls back to the flat
        -- portrait rather than showing an empty box. This is exactly the
        -- UnitIsVisible gate X-Perl uses for the same reason.
        local want3D = elements.portrait3D and frame.portrait3D
                       and UnitIsVisible and UnitIsVisible(unit)

        if want3D then
            frame.portrait:Hide()
            frame.portrait3D:Show()
            -- Re-seating the model is the expensive part and it visibly
            -- resets the pose, so it happens only when the unit actually
            -- changed - not on every one of the four scans a second. GUID
            -- rather than name, so two mobs sharing a name still re-seat.
            local guid = UnitGUID and UnitGUID(unit)
            if frame.lastPortraitGUID ~= guid then
                frame.lastPortraitGUID = guid
                pcall(function()
                    frame.portrait3D:ClearModel()
                    frame.portrait3D:SetUnit(unit)
                    frame.portrait3D:SetCamera(0)
                end)
            end
        else
            if frame.portrait3D then frame.portrait3D:Hide() end
            frame.portrait:Show()
            -- Cleared so returning to 3D re-seats the model rather than
            -- trusting a GUID stamped while the model was hidden.
            frame.lastPortraitGUID = nil
            if SetPortraitTexture then
                pcall(SetPortraitTexture, frame.portrait, unit)
            end
        end
    end

    local valuesChanged = false

    local slots = plan.slots

    for i = 1, frame.slotCount do
        local bar = frame.bars[i]
        local barBackdrop = frame.barBackdrops[i]
        local slot = slots[i]
        local e = slot and entries[slot.entryIndex]

        if e then
            local bd = bar.barData
            bd.enabled    = true
            bd.name       = e.label
            bd.resourceKey = e.key
            bd.runeType    = e.runeType
            bd.trackMode   = e.trackMode or "Buff"

            -- A SPLIT segment is one point of a divided resource, so it draws
            -- as simply lit or unlit rather than as a fraction: combo point 3
            -- of 5 is full when you have 3 or more and empty otherwise. Every
            -- other slot draws its resource's real current/max.
            if slot.segIndex then
                local lit = (e.current or 0) >= slot.segIndex
                ns:UpdateResourceBar(bar, lit and 1 or 0, 1, e.icon, e.label, lit and 1 or 0)
            else
                ns:UpdateResourceBar(bar, e.current, e.max, e.icon, e.label,
                                     e.stacks or e.current)
            end

            -- The resource NAME is never drawn on the bar: the header already
            -- names the unit, and a row labelled "Health" next to a health
            -- bar tells nobody anything. The numbers are a real choice
            -- though, and this is where "on the bar" is honoured -
            -- UpdateResourceBar has just written its own text into timeText,
            -- so this overwrites it with the same string the column would
            -- have shown, keeping the two placements identical in content.
            if bar.nameText then bar.nameText:Hide() end

            -- Numbers belong to the ROW, and only to a row that has any: a
            -- rune strip shows none, and a combo-point strip shows one "3/5"
            -- rather than a digit on every segment.
            local row = plan.rows[slot.row]
            local ownsRowText = row and row.valueEntry == slot.entryIndex
                                and not slot.segIndex
            local text
            if ownsRowText and (elements.values or elements.valuesOnBar) then
                text = ns:FormatUnitFrameValue(e.current, e.max)
            end

            if bar.timeText then
                if text and elements.valuesOnBar then
                    if bar.timeText.lastUFText ~= text then
                        bar.timeText.lastUFText = text
                        bar.timeText:SetText(text)
                    end
                    -- Re-apply the frame's own Values Font/Size every pass.
                    -- This is NOT redundant with the build-time setup the
                    -- values COLUMN gets: ns:UpdateResourceBar above runs
                    -- ns:ApplyVisualConfig, which re-fonts timeText from the
                    -- addon-wide Visuals settings on every tick, so a font
                    -- applied once at build time would be overwritten four
                    -- times a second. Until this existed, Values Font and
                    -- Values Size did nothing whatsoever in on-bar mode
                    -- while working normally in column mode.
                    if frame.valueFontPath then
                        bar.timeText:SetFont(frame.valueFontPath, frame.valueFontSize, "OUTLINE")
                    end
                    bar.timeText:Show()
                else
                    bar.timeText.lastUFText = nil
                    bar.timeText:Hide()
                end
            end

            -- Applied here, after ns:UpdateResourceBar, because that sets the
            -- bar's alpha from visual.activeAlpha on every scan and would
            -- otherwise overwrite this a quarter of a second later.
            if frame.barOpacity then bar:SetAlpha(frame.barOpacity) end
            bar:Show()
            barBackdrop:Show()
        else
            if bar.barData.enabled then
                bar.barData.enabled = false
                bar.barData.resourceKey = nil
                bar.barData.runeType = nil
                ns:DeactivateBar(bar, true)
            end
            bar:Hide()
            barBackdrop:Hide()
        end
    end

    -- The values column, one entry per ROW. Separate from the slot loop above
    -- because slots and rows are no longer one-to-one: six rune segments are
    -- six slots on a single row, and a row with no valueEntry (runes) shows
    -- nothing at all.
    for i = 1, frame.slotCount do
        local valueText = frame.valueTexts[i]
        local row = plan.rows[i]
        local e = row and row.valueEntry and entries[row.valueEntry]

        if e and elements.values then
            local text = ns:FormatUnitFrameValue(e.current, e.max)
            if valueText.lastText ~= text then
                valueText.lastText = text
                valueText:SetText(text)
                valuesChanged = true
            end
            valueText:Show()
        else
            valueText:Hide()
        end
    end

    -- Re-reserve the values column only when a string actually changed and
    -- the width it needs actually moved. Health ticking 2489 -> 2488 changes
    -- the text but not its width, so the common case costs a measurement and
    -- nothing more. The frame is only ever re-laid-out when the numbers grow
    -- or shrink a digit.
    if valuesChanged and elements.values then
        local needed = ns:MeasureUnitFrameValuesWidth(frame.valueTexts, frame.slotCount)
        if needed ~= frame.lastValuesMeasured then
            LayoutUnitFrame(frame, elements, plan, needed)
        end
    end
end

-- Rebuild every known unit frame from the live config: destroy it if it
-- exists, then (re)build + do an immediate scan pass when enabled. Called
-- once from ns:OnInitialize and from the Frames tab's own settings (any
-- change there is infrequent, so a full rebuild rather than a targeted
-- per-setting updater is the simplest correct answer for a single frame).
function ns:RebuildUnitFrames()
    -- Blizzard's equivalent frames are hidden by the same pass that builds
    -- ours, because "is the BarWarden frame on" is now an input to whether
    -- Blizzard's should be up (ns:ResolveBlizzardFrameHidden, Conditions.lua).
    -- Every settings change on the Frames tab routes through here, so this is
    -- the one place that has to remember.
    if ns.ApplyBlizzardFrameHiding then ns:ApplyBlizzardFrameHiding() end

    for _, key in ipairs(UNIT_FRAME_KEYS) do
        DestroyUnitFrame(key)
        local cfg = UnitFrameConfig(key)
        if cfg and cfg.enabled then
            if BuildUnitFrame(key) then
                ScanUnitFrame(key)
            end
        end
    end
end

-- Set a unit frame's scale, preserving its on-screen position - reuses
-- ns:RescaleFrame (FrameManager.lua) exactly like ns:SetFrameScale does for
-- a bar group, rather than a second copy of that offset-conversion maths.
-- growUp is always false: a unit frame never grows (it always shows the
-- same fixed header + bar stack), unlike a bar group whose bar count varies.
-- `key` here is a CONFIG key, not a frame key: the Frames tab has one Scale
-- slider per settings block, and the party block covers four frames. Every
-- built frame reading that config is rescaled, or moving the party slider
-- would resize party1 and leave the other three behind.
function ns:SetUnitFrameScale(key, scale)
    local cfg = ns.db and ns.db.unitFrames and ns.db.unitFrames[key]
    local applied

    for _, frameKey in ipairs(UNIT_FRAME_KEYS) do
        if ConfigKeyFor(frameKey) == key then
            local frame = ns.unitFrames[frameKey]
            if frame then
                applied = ns:RescaleFrame(frame, scale, false, function(pos)
                    SaveUnitFramePosition(cfg, frameKey, pos)
                end)
            end
        end
    end

    -- No frame was built (the whole section is switched off), so there is
    -- nothing to rescale - just clamp and store, so the value is right when
    -- one is next built.
    if not applied then
        applied = math.max(ns.MIN_FRAME_SCALE, math.min(ns.MAX_FRAME_SCALE, scale))
    end

    if cfg then cfg.scale = applied end
end

-- Called from Core.lua's 0.25s OnUpdate ticker, right alongside
-- ns:ScanAllBars - reusing the existing scan loop rather than adding a
-- second one, per CLAUDE.md. Each frame guards its own enabled state, so
-- this is a cheap no-op pass whenever no unit frame is built.
function ns:ScanUnitFrames()
    for _, key in ipairs(UNIT_FRAME_KEYS) do
        if ns.unitFrames[key] then
            ScanUnitFrame(key)
        end
    end
end
