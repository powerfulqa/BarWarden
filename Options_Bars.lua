-- Options_Bars.lua - Bars / Groups tab (group-and-bar editor).
-- Author:  Serv
-- Source:  https://github.com/powerfulqa/BarWarden
-- License: see LICENSE; attribution preservation is required.

local addonName, ns = ...

-- ============================================================================
-- Options_Bars.lua - Tab 2: Bars / Groups configuration
-- ============================================================================

local TRACK_MODES = {
    "Cooldown", "Buff", "Debuff", "Proc",
    "Item", "Enchant MH", "Enchant OH", "Totem",
    -- Class resources (Combo Points/Runic Power/Soul Shards are event-driven;
    -- Runes is time-based with spellId as the slot number 1..6).
    "Combo Points", "Runes", "Runic Power", "Soul Shards",
    -- Plain character-stat resources, same event-driven fill-not-countdown
    -- rendering as the class resources above.
    "Health", "Mana", "Energy", "Rage",
}
local TARGET_UNITS = { "player", "target", "focus", "pet", "mouseover" }
local GROUP_LIST_HEIGHT = 16
local BAR_LIST_HEIGHT = 16
-- Lists show up to this many rows (the box grows with the item count, minimum
-- one line) before they start scrolling. Six keeps the settings/editor below
-- visible even at the smallest window size; Groups and Bars use the same cap.
local MAX_GROUP_ROWS = 6
local MAX_BAR_ROWS = 6
-- The banned-spells list under Auto Track is a framed icon/name/id table
-- (mirrors the Activity Tracker table in Options_Stats.lua) with a FIXED
-- number of visible rows: it never grows or shrinks its container, it only
-- scrolls once there are more entries than fit. A fixed footprint is what
-- keeps fitGroupHeight's measurement predictable (a ban count that resized
-- this section would need its own reflow trigger, on top of the Auto Track
-- section's); see fitGroupHeight, further down, and the block comment above
-- the ban-list section.
local MAX_BAN_ROWS = 10
local BAN_ROW_HEIGHT = 18
local BAN_ICON_SIZE = 16

-- Blizzard's FauxScrollFrame_Update HIDES the whole scroll frame when the list
-- fits without scrolling. Both lists have the rest of their column anchored to
-- that frame (the buttons, then the settings block below them), and anchoring
-- to a frame that gets hidden out from under you strands the dependants - they
-- fall back towards the panel origin and the page visibly comes apart until
-- something re-shows the frame.
--
-- Deleting the 7th group is the exact trigger: 7 > 6 keeps it shown, dropping
-- back to 6 hides it. Adding a group put it right again, which is what made the
-- bug look like it was about deleting.
--
-- So keep the scroll frame itself shown always and hide only its scrollbar,
-- which is what the auto-hide elsewhere in the addon does too.
--
-- EC-TRAP: the Show() below looks redundant right after FauxScrollFrame_Update
-- and is not. Removing it re-breaks the Bar Control page whenever a list drops
-- from 7 items to 6. Never anchor anything to a frame Blizzard's own helpers
-- show and hide.
local function KeepListFrameShown(scrollFrame, scrollBarName, needsScrollBar)
    if not scrollFrame then return end
    scrollFrame:Show()
    local sb = _G[scrollBarName]
    if sb then
        if needsScrollBar then sb:Show() else sb:Hide() end
    end
end

-- Helper: create a new default bar table
local function NewBar(name)
    return {
        name = name or "New Bar",
        enabled = true,
        trackMode = "Cooldown",
        unit = "player",
        spellName = "",
        spellId = nil,
        itemId = nil,
        onlyMine = true,
        conditions = {
            combatOnly = false,
            outOfCombatOnly = false,
            requireBuff = nil,
            requireClass = nil,  -- set by class-starter presets; hides bar for other classes
            healthBelow = nil,
            inGroup = false,
            inRaid = false,
            hideWhileMounted = false,
            hideWhileResting = false,
            hideInVehicle = false,
            onlyInInstance = false,
            hideWhenInactive = false,
            showEmpty = true,
        },
        display = {
            progressDirection = "LTR",
            lingerTime = 0,
            barAlpha = 0.6,
            showName = nil,
            showIcon = nil,
            textFormat = nil,
            colorOverride = nil,
            textureOverride = nil,
            style = nil,
            -- Colour-by-time (nil = inherit global)
            colorByTime = nil,
            -- Glow on ready / pulse on ready
            glowOnReady = false,
            pulseOnReady = false,
            -- Icon crop (nil = inherit global)
            iconCrop = nil,
            -- Per-bar scale multiplier (nil = 1.0 = group default)
            scaleOverride = nil,
        },
    }
end

-- Helper: create a new default group (frame) table
local function NewGroup(name)
    return {
        name = name or "New Group",
        enabled = true,
        locked = true,
        visible = true,
        position = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 0 },
        width = 200,
        columns = 1,
        bgAlpha = 0.6,
        borderAlpha = 0.8,
        scale = 1.0,
        sortMode = "manual",
        groupConditions = {},
        bars = {},
    }
end

-- ============================================================================
-- Main Tab Creation
-- ============================================================================

local selectedGroupIndex = nil
local selectedBarIndex = nil

local function CreateBarsTab(parent)
    local frame = CreateFrame("Frame", "BarWardenBarsTab", parent)
    frame:SetAllPoints(parent)
    frame:Hide()

    -- Drag-to-reorder: work out which row index the cursor is over in a
    -- FauxScrollFrame list, accounting for the scroll offset and UI scale.
    local function ComputeDropIndex(scrollFrame, rowHeight, total)
        local _, cy = GetCursorPosition()
        local scale = scrollFrame:GetEffectiveScale()
        local top = scrollFrame:GetTop()
        if not cy or not scale or scale == 0 or not top then return nil end
        local offset = FauxScrollFrame_GetOffset(scrollFrame) or 0
        local idx = offset + math.floor((top - cy / scale) / rowHeight) + 1
        if idx < 1 then idx = 1 end
        if idx > total then idx = total end
        return idx
    end

    -- ========================================================================
    -- LEFT PANEL: Group List
    -- ========================================================================
    local leftPanel = CreateFrame("Frame", nil, frame)
    -- v2: start near the top (no tab bar to clear) and fill the panel height, so
    -- the group list + settings use the full column instead of a 360px box.
    -- Groups tab content: fills the page below the title, above the tab bar.
    leftPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -44)
    leftPanel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 40)

    local groupHeader = leftPanel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    groupHeader:SetPoint("TOPLEFT", leftPanel, "TOPLEFT", 0, 0)
    groupHeader:SetText("Groups")
    ns:CreateHelpIcon(leftPanel, groupHeader, "LEFT", "RIGHT", 6, 0, "create-group")

    -- Group scroll frame
    -- List spans the full page width; its height is set dynamically in
    -- UpdateGroupList (grows with the group count, up to MAX_GROUP_ROWS rows,
    -- then scrolls). The buttons + settings below follow its bottom edge.
    local groupScrollFrame = CreateFrame("ScrollFrame", "BarWardenGroupScroll", leftPanel, "FauxScrollFrameTemplate")
    groupScrollFrame:SetPoint("TOPLEFT", groupHeader, "BOTTOMLEFT", 0, -6)
    -- Fixed width = the shared settings width, so the list + its selection
    -- highlight are contained at the same limit as the settings below, instead
    -- of the highlight stretching across the whole window.
    groupScrollFrame:SetWidth(ns.SETTINGS_MAX_WIDTH or 300)
    groupScrollFrame:SetHeight(MAX_GROUP_ROWS * GROUP_LIST_HEIGHT)

    local groupRows = {}
    for i = 1, MAX_GROUP_ROWS do
        local row = CreateFrame("Button", "BarWardenGroupRow" .. i, leftPanel)
        row:SetHeight(GROUP_LIST_HEIGHT)
        if i == 1 then
            row:SetPoint("TOPLEFT",  groupScrollFrame, "TOPLEFT",   0, 0)
            row:SetPoint("TOPRIGHT", groupScrollFrame, "TOPRIGHT", -22, 0)
        else
            row:SetPoint("TOPLEFT",  groupRows[i - 1], "BOTTOMLEFT",  0, 0)
            row:SetPoint("TOPRIGHT", groupRows[i - 1], "BOTTOMRIGHT", 0, 0)
        end

        local highlight = row:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetTexture(1, 1, 1, 0.1)

        local selected = row:CreateTexture(nil, "BACKGROUND")
        selected:SetAllPoints()
        selected:SetTexture(0.2, 0.4, 0.8, 0.3)
        selected:Hide()
        row.selected = selected

        local text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        text:SetPoint("LEFT",  row, "LEFT",   4, 0)
        text:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        text:SetJustifyH("LEFT")
        row.text = text

        row:SetScript("OnClick", function(self)
            selectedGroupIndex = self.index
            selectedBarIndex = nil
            frame:Refresh()
        end)

        -- Drag-to-reorder groups (a plain click still selects).
        row:RegisterForDrag("LeftButton")
        row:SetScript("OnDragStart", function(self) frame._dragGroup = self.index end)
        row:SetScript("OnDragStop", function()
            local from = frame._dragGroup
            frame._dragGroup = nil
            local frames = BarWardenDB and BarWardenDB.frames
            if not from or not frames or #frames < 2 then return end
            local to = ComputeDropIndex(groupScrollFrame, GROUP_LIST_HEIGHT, #frames)
            if to and to ~= from then
                table.insert(frames, to, table.remove(frames, from))
                selectedGroupIndex = to
                selectedBarIndex = nil
                frame:Refresh()
                ns:RebuildAllFrames()
            end
        end)

        groupRows[i] = row
    end

    -- Group buttons: Add / Delete / Dupe split the list width into equal thirds
    -- so the row fills the panel even at its narrowest. Two gaps between three
    -- buttons; the last button absorbs the rounding remainder so the row's right
    -- edge lands exactly on the list's right edge.
    local GROUP_BTN_GAP  = 4
    local GROUP_ROW_W    = ns.SETTINGS_MAX_WIDTH or 300
    local groupBtnW      = math.floor((GROUP_ROW_W - 2 * GROUP_BTN_GAP) / 3)
    local groupBtnWLast  = GROUP_ROW_W - 2 * groupBtnW - 2 * GROUP_BTN_GAP

    -- Group buttons
    local addGroupBtn = ns:CreateButton(leftPanel, "Add", groupBtnW, function()
        local frames = BarWardenDB.frames
        if #frames >= (ns.MAX_FRAMES or 20) then
            ns:Print("Maximum of " .. (ns.MAX_FRAMES or 20) .. " groups reached.")
            return
        end
        local group = NewGroup("Group " .. (#frames + 1))
        table.insert(frames, group)
        selectedGroupIndex = #frames
        selectedBarIndex = nil
        frame:Refresh()
        ns:RebuildAllFrames()
    end)
    addGroupBtn:SetPoint("TOPLEFT", groupScrollFrame, "BOTTOMLEFT", 0, -4)

    local deleteGroupBtn = ns:CreateButton(leftPanel, "Delete", groupBtnW, function()
        if not selectedGroupIndex then ns:Print("Select a group first."); return end
        local frames = BarWardenDB.frames
        local g = frames[selectedGroupIndex]
        if not g then return end
        -- Capture the target group itself, not the live selection: the popup is
        -- not modal, so the user can click another row while it is open. Acting
        -- on the selection at accept time deleted whichever group they clicked
        -- last rather than the one the popup names.
        local targetGroup = g
        local popup = StaticPopup_Show("BARWARDEN_CONFIRM_DELETE", g.name or "this group")
        if popup then
            popup.data = {
                onAccept = function()
                    local idx
                    for i, f in ipairs(frames) do
                        if f == targetGroup then idx = i; break end
                    end
                    if not idx then
                        ns:Print("That group no longer exists.")
                        return
                    end
                    ns:BackupFrames("delete group")
                    table.remove(frames, idx)
                    if selectedGroupIndex and selectedGroupIndex > #frames then
                        selectedGroupIndex = #frames > 0 and #frames or nil
                    end
                    selectedBarIndex = nil
                    frame:Refresh()
                    ns:RebuildAllFrames()
                end,
            }
        end
    end)
    deleteGroupBtn:SetPoint("LEFT", addGroupBtn, "RIGHT", GROUP_BTN_GAP, 0)

    local dupeGroupBtn = ns:CreateButton(leftPanel, "Dupe", groupBtnWLast, function()
        if not selectedGroupIndex then ns:Print("Select a group first."); return end
        local frames = BarWardenDB.frames
        local g = frames[selectedGroupIndex]
        if not g then return end
        local copy = ns:CopyTable(g)
        copy.name = g.name .. " (copy)"
        copy.position.x = copy.position.x + 20
        copy.position.y = copy.position.y - 20
        table.insert(frames, copy)
        selectedGroupIndex = #frames
        selectedBarIndex = nil
        frame:Refresh()
        ns:RebuildAllFrames()
    end)
    dupeGroupBtn:SetPoint("LEFT", deleteGroupBtn, "RIGHT", GROUP_BTN_GAP, 0)

    -- Group settings sit BELOW the list + buttons and span the full page width
    -- (stacked layout, uniform with the Bars tab). This keeps the settings
    -- visible even at the smallest window size. The scroll fills the remaining
    -- height and reflows on resize.
    local groupSettingsHeader = leftPanel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    groupSettingsHeader:SetPoint("TOPLEFT", addGroupBtn, "BOTTOMLEFT", 0, -10)
    groupSettingsHeader:SetText("Group Settings")

    local groupSettingsScroll = CreateFrame("ScrollFrame", "BarWardenGroupSettingsScroll", leftPanel, "UIPanelScrollFrameTemplate")
    groupSettingsScroll:SetPoint("TOPLEFT", groupSettingsHeader, "BOTTOMLEFT", 0, -6)
    groupSettingsScroll:SetPoint("BOTTOMRIGHT", leftPanel, "BOTTOMRIGHT", -24, 0)

    local groupSettingsContent = CreateFrame("Frame", nil, groupSettingsScroll)
    groupSettingsContent:SetWidth(320)
    -- Generous fallback height so all group settings (down to the Group
    -- Conditions toggles) are reachable; fitGroupHeight() trims it once shown.
    groupSettingsContent:SetHeight(700)
    groupSettingsScroll:SetScrollChild(groupSettingsContent)

    -- Populated by BuildSettings (ids below); used to fill the group dropdowns
    -- to the panel width on resize, matching the Bars editor.
    local groupSettingsWidgets = {}

    -- Reflow the settings content to the live viewport width on resize, and
    -- fill the dropdowns (their box width is a template property, not an anchor).
    groupSettingsScroll:SetScript("OnSizeChanged", function(_, w)
        if w and w > 100 then
            -- Cap at the shared settings width (parity with the Bars editor).
            local cw = math.min(w, ns.SETTINGS_MAX_WIDTH or 300)
            groupSettingsContent:SetWidth(cw)
            local ddW = math.max(120, cw - 60)
            for _, id in ipairs({ "grpSortDD", "grpGrowthDD", "grpTextureDD", "grpTextFormatDD", "grpBarStyleDD", "grpAutoTrackDD", "grpAutoValueTextDD" }) do
                local dd = groupSettingsWidgets[id]
                if dd then UIDropDownMenu_SetWidth(dd, ddW) end
            end
        end
    end)

    -- Group-settings schema: declarative via BuildSettings.
    -- All entries use get/set escape hatches because the target is the
    -- currently selected group (selectedGroupIndex), not a fixed DB path.

    local function getGroup()
        return selectedGroupIndex and BarWardenDB.frames[selectedGroupIndex]
    end

    local sortModeItems = {
        { text = "Manual",         value = "manual" },
        { text = "Remaining Time", value = "remaining" },
        { text = "Alphabetical",   value = "alpha" },
        { text = "As They Come",   value = "appearance" },
    }

    local growDirectionItems = {
        { text = "Down (default)", value = "DOWN" },
        { text = "Up",             value = "UP" },
    }

    -- Per-group bar-texture choices: "Inherit" (use the addon-wide texture from
    -- the Visuals page) plus the shared media list. "Custom" is dropped here;
    -- a custom texture path stays a global-only setting.
    local groupTextureItems = { { text = "Inherit (default)", value = "" } }
    do
        local list = ns.LSMDropdownItems and ns:LSMDropdownItems("statusbar")
        if list then
            for _, item in ipairs(list) do
                if item.value ~= "Custom" then
                    groupTextureItems[#groupTextureItems + 1] = item
                end
            end
        else
            for _, n in ipairs({ "Flat", "Smooth", "Gloss", "Aluminum", "Armory" }) do
                groupTextureItems[#groupTextureItems + 1] = { text = n, value = n }
            end
        end
    end

    -- Text-format override list: Inherit plus the same formats the Visuals page
    -- offers, so one group can show stacks (or names only) without changing
    -- every other bar in the addon.
    local groupTextFormatItems = {
        { text = "Inherit (default)", value = ""              },
        { text = "Name + Duration",   value = "NAME_DURATION" },
        { text = "Name Only",         value = "NAME_ONLY"     },
        { text = "Duration Only",     value = "DURATION"      },
        { text = "Name + Stacks",     value = "NAME_STACKS"   },
        { text = "Stacks Only",       value = "STACKS"        },
        { text = "None",              value = "NONE"          },
    }

    -- Auto-tracking feeds. Values must match the keys in ns.AUTO_TRACK_FEEDS.
    local autoTrackItems = {
        { text = "Off",                                  value = ""                 },
        { text = "All buffs on player",                  value = "playerBuffs"      },
        { text = "All debuffs on player",                value = "playerDebuffs"    },
        { text = "All buffs on target",                  value = "targetBuffs"      },
        { text = "All debuffs on target",                value = "targetDebuffs"    },
        { text = "Health and power",                     value = "resources"        },
        { text = "Health and power (target)",             value = "targetResources"  },
        { text = "Health and power (target of target)",   value = "totResources"     },
    }

    -- The auto sub-settings mean nothing with no feed picked, so they hide.
    -- BuildSettings can now reflow the visible widgets around a hidden one
    -- (see Options_Builder.lua's Reflow), so this block no longer needs to
    -- sit last on the page to keep a hidden sub-section from punching a hole
    -- through the middle of the panel. It stays last anyway because the
    -- Banned Spells list further down is paired with it (a per-group ban list
    -- only means anything for an auto-tracking group) and is anchored
    -- directly below this section's last widget; moving Auto Track without
    -- also moving that list would split one feature across two places in the
    -- panel for no benefit.
    --
    -- Split three ways rather than one flat list: some sub-settings apply to
    -- ANY feed, some only make sense for an aura feed (a resource group has
    -- no spell list to limit, filter, or ban), and some only make sense for
    -- the resource feed (there is nothing to "pin" on a buff/debuff group).
    local AUTO_SUB_WIDGET_IDS = {
        "grpAutoMaxBars", "grpAutoStableOrder",
    }
    local AUTO_AURA_ONLY_WIDGET_IDS = {
        "grpAutoMaxDuration", "grpAutoIncludePermanent", "grpAutoOnlyMine", "grpAutoSkipTracked",
    }
    local AUTO_RESOURCE_ONLY_WIDGET_IDS = {
        "grpAutoPinMana", "grpAutoPinManaColor",
        "grpAutoPinRage", "grpAutoPinRageColor",
        "grpAutoPinEnergy", "grpAutoPinEnergyColor",
        "grpAutoPinCombo", "grpAutoPinComboColor",
        "grpAutoValueTextDD", "grpAutoShowIcon",
    }
    -- Group Name Follows Target (v2.5.0) only means anything on the two
    -- feeds that read a unit other than the player: a player-resources
    -- group's title following "you" would just repeat the group's own name
    -- back, and every aura feed has no single "the unit" it is about in the
    -- same way. Its own bucket rather than folding into
    -- AUTO_RESOURCE_ONLY_WIDGET_IDS above, since that one shows for all
    -- three resource feeds and this is narrower still.
    local AUTO_TARGET_RESOURCE_ONLY_WIDGET_IDS = {
        "grpAutoTitleFollowsUnit",
        "grpAutoTitleShowsLevel",
    }
    -- Runic Power / Runes (v2.5.0) only ever mean anything on the PLAYER
    -- resource feed: both pools belong to the player alone
    -- (ns:CollectResources gates them on unit == "player" - Trackers.lua),
    -- so showing them on the target/target's-target feeds would be dead
    -- controls that can never do anything, the same reasoning that gives
    -- AUTO_TARGET_RESOURCE_ONLY_WIDGET_IDS above its own narrower bucket.
    local AUTO_PLAYER_RESOURCE_ONLY_WIDGET_IDS = {
        "grpAutoPinRunicPower", "grpAutoPinRunicPowerColor",
        "grpAutoPinRunes", "grpAutoPinRunesColor",
    }

    -- Whether the selected group has an AURA feed picked (not "resources").
    -- The banned-spells section (built further down) is keyed off this too:
    -- alt-click-to-hide-one-spell (Bar.lua) only ever means anything for a
    -- spell list, so it hides for the resource feed the same as for no feed
    -- at all. UpdateBanList is forward-declared here (not where it is
    -- assigned, further down) so SetAutoSubWidgetsShown, defined above that
    -- point, can still call it: an upvalue is only visible to functions
    -- defined after its `local`, not before.
    local autoFeedShown = false
    local UpdateBanList

    -- Forward-declared (same reason as UpdateBanList above) so
    -- SetAutoSubWidgetsShown and the other group-settings show/hide helpers,
    -- all defined ahead of the BuildSettings call that assigns these, can
    -- reflow and re-measure right after they change visibility instead of
    -- only picking up the change on the next full Refresh pass.
    local reflowGroupSettings
    local fitGroupHeight

    -- value is the Track dropdown's raw value: "" (off), one of the four
    -- aura feed keys, or "resources".
    local function SetAutoSubWidgetsShown(value)
        local hasFeed = value ~= nil and value ~= ""
        local isTargetResource = value == "targetResources" or value == "totResources"
        local isAura  = hasFeed and value ~= "resources" and not isTargetResource
        local isPlayerResource = value == "resources"

        local function setAll(ids, shown)
            for _, id in ipairs(ids) do
                local w = groupSettingsWidgets[id]
                if w then
                    if shown then w:Show() else w:Hide() end
                end
            end
        end

        setAll(AUTO_SUB_WIDGET_IDS, hasFeed)
        setAll(AUTO_AURA_ONLY_WIDGET_IDS, isAura)
        setAll(AUTO_RESOURCE_ONLY_WIDGET_IDS, hasFeed and not isAura)
        setAll(AUTO_TARGET_RESOURCE_ONLY_WIDGET_IDS, isTargetResource)
        setAll(AUTO_PLAYER_RESOURCE_ONLY_WIDGET_IDS, isPlayerResource)

        autoFeedShown = isAura
        if UpdateBanList then UpdateBanList() end
        if reflowGroupSettings then reflowGroupSettings() end
        -- Re-measure once the Show/Hide above has actually taken effect (see
        -- fitGroupHeight's own comment for why this needs a frame's delay).
        if fitGroupHeight and ns.After then ns:After(0, fitGroupHeight) end
    end

    -- Forward-declared so schema `set` closures below can re-run the group
    -- settings Refresh (e.g. to re-check the Custom Bar Colour toggle after the
    -- colour swatch writes g.barColor). Assigned by BuildSettings just below.
    local refreshGroupSettings

    -- Pinned resources (v2.5.0): whether `key` is currently pinned, and its
    -- stored colour if it has one, both read through
    -- ns:NormalizePinnedResources (Trackers.lua) so a group still holding
    -- the pre-order set shape keeps ticking/unticking correctly instead of
    -- needing its own separate read path.
    --
    -- Only used when a key has no conventional colour of its own (combo
    -- points: see the comment above RESOURCE_COLOR_TOKENS, Conditions.lua) -
    -- otherwise the swatch's own default now comes from
    -- ns:GetResourceKeyDefaultColor below, the same resolver GetBarColor
    -- (Bar.lua) reads for the bar itself, so the swatch shown here always
    -- starts on the colour actually drawn on screen (mana blue, rage red,
    -- energy yellow) instead of one fixed blue for every resource.
    local DEFAULT_PIN_SWATCH_COLOR = { r = 0.2, g = 0.6, b = 1.0 }

    local function isResourcePinned(g, key)
        if not g or not g.autoPinnedResources then return false end
        for _, entry in ipairs(ns:NormalizePinnedResources(g.autoPinnedResources)) do
            if entry.key == key then return true end
        end
        return false
    end

    local function getPinnedResourceColor(g, key)
        if g and g.autoPinnedResources then
            for _, entry in ipairs(ns:NormalizePinnedResources(g.autoPinnedResources)) do
                if entry.key == key and entry.color then return entry.color end
            end
        end
        local r, gg, b = ns:GetResourceKeyDefaultColor(key)
        if r then return { r = r, g = gg, b = b } end
        return DEFAULT_PIN_SWATCH_COLOR
    end

    -- Same toggle-reveals-swatch mechanism as Custom Bar Colour: shows/hides
    -- swatchId with the tickbox and reflows immediately, since a live click
    -- bypasses the Refresh pass that would otherwise pick this up.
    local function onPinToggleChanged(swatchId, value)
        local sw = groupSettingsWidgets[swatchId]
        if sw then
            if value then sw:Show() else sw:Hide() end
        end
        if reflowGroupSettings then reflowGroupSettings() end
        if fitGroupHeight and ns.After then ns:After(0, fitGroupHeight) end
    end

    local GROUP_SETTINGS_SCHEMA = {
        { type = "editbox", label = "Group Name", width = 155, stretch = true,
          tooltip = "A label for this group, shown on the frame when 'Show "
                 .. "Group Name' is ticked.",
          get = function() local g = getGroup(); return g and g.name or "" end,
          set = function(_, text)
              local g = getGroup(); if not g then return end
              g.name = text
              local gf = ns.groupFrames[selectedGroupIndex]
              if gf and gf.titleText then gf.titleText:SetText(text) end
              frame:Refresh()
          end,
          offsetX = ns.OFFSET_EDITBOX },
        { type = "toggle", label = "Show Group Name",
          tooltip = "Show or hide the group name on the bar frame.",
          get = function() local g = getGroup(); return g and g.showTitle ~= false end,
          set = function(_, checked)
              local g = getGroup(); if not g then return end
              g.showTitle = checked and true or false
              local gf = ns.groupFrames[selectedGroupIndex]
              if gf and gf.titleText then
                  if checked then gf.titleText:Show() else gf.titleText:Hide() end
              end
          end,
          offsetX = ns.OFFSET_TOGGLE, spacing = 4 },
        { type = "slider", label = "Width", min = 10, max = 600, step = 5, width = 150, stretch = true,
          tooltip = "How wide the bars in this group are, in pixels. With "
               .. "Show Icons Only turned on under Bar Overrides, this sets the "
               .. "icon size instead.",
          get = function() local g = getGroup(); return g and g.width or 200 end,
          set = function(_, value)
              local g = getGroup(); if not g then return end
              g.width = value
              local gf = ns.groupFrames[selectedGroupIndex]
              if gf then ns:UpdateGroupLayout(gf) end
          end,
          offsetX = ns.OFFSET_SLIDER, spacing = 12 },
        { type = "slider", label = "Scale", min = 0.5, max = 3.0, step = 0.1, width = 150, stretch = true,
          tooltip = "Overall size of this group. 1.00 is normal size.",
          get = function() local g = getGroup(); return g and g.scale or 1.0 end,
          set = function(_, value)
              if not selectedGroupIndex then return end
              ns:SetFrameScale(selectedGroupIndex, value)
              local g = getGroup(); if g then g.scale = value end
          end,
          offsetX = ns.OFFSET_SLIDER, spacing = 16 },
        { type = "slider", label = "Columns", min = 1, max = 10, step = 1, width = 150, stretch = true,
          tooltip = "Number of columns the bars in this group are arranged into. "
               .. "1 = vertical stack (default); 2-10 splits the bars across that "
               .. "many columns side by side. Useful when tracking many bars in a "
               .. "compact footprint.",
          get = function() local g = getGroup(); return g and g.columns or 1 end,
          set = function(_, value)
              if selectedGroupIndex then ns:SetGroupColumns(selectedGroupIndex, value) end
          end,
          offsetX = ns.OFFSET_SLIDER, spacing = 16 },
        { type = "slider", label = "Background Opacity", min = 0, max = 1, step = 0.05, width = 150, stretch = true,
          tooltip = "Opacity of this group's background panel. 0 hides it.",
          get = function() local g = getGroup(); return g and (g.bgAlpha ~= nil and g.bgAlpha or 0.6) end,
          set = function(_, value)
              if selectedGroupIndex then ns:SetGroupBgAlpha(selectedGroupIndex, value) end
          end,
          offsetX = ns.OFFSET_SLIDER, spacing = 16 },
        { type = "slider", label = "Border Opacity", min = 0, max = 1, step = 0.05, width = 150, stretch = true,
          tooltip = "Opacity of this group's border. 0 hides it.",
          get = function() local g = getGroup(); return g and (g.borderAlpha ~= nil and g.borderAlpha or 0.8) end,
          set = function(_, value)
              if selectedGroupIndex then ns:SetGroupBorderAlpha(selectedGroupIndex, value) end
          end,
          offsetX = ns.OFFSET_SLIDER, spacing = 16 },
        { type = "dropdown", id = "grpSortDD", label = "Sort Mode", items = sortModeItems, width = 130,
          tooltip = "Order the bars in this group: Manual (drag to reorder), by "
                 .. "remaining time, alphabetically, or As They Come, which "
                 .. "puts each new bar at the end and keeps it there for as "
                 .. "long as it lasts, so the list only closes up when one "
                 .. "drops off.",
          get = function() local g = getGroup(); return g and g.sortMode or "manual" end,
          set = function(_, value)
              local g = getGroup(); if not g then return end
              g.sortMode = value
              local gf = ns.groupFrames[selectedGroupIndex]
              if gf then ns:UpdateGroupLayout(gf) end
          end,
          offsetX = ns.OFFSET_DROPDOWN, spacing = 28 },
        { type = "dropdown", id = "grpGrowthDD", label = "Growth Direction", items = growDirectionItems, width = 130,
          tooltip = "Direction bars stack within this group. Down (default) "
               .. "grows bars downward from the title. Up grows bars upward, "
               .. "useful when you want the group anchored at the bottom of "
               .. "the screen.",
          get = function() local g = getGroup(); return g and g.growDirection or "DOWN" end,
          set = function(_, value)
              local g = getGroup(); if not g then return end
              g.growDirection = value
              local gf = ns.groupFrames[selectedGroupIndex]
              if gf then ns:UpdateGroupLayout(gf) end
          end,
          offsetX = ns.OFFSET_DROPDOWN, spacing = 16 },

        -- Group-level bar visuals. These override the addon-wide look from the
        -- Visuals page for just this group's bars; left on Inherit / off, they
        -- use the global default.
        { type = "header", text = "Bar Overrides", spacing = 16, offsetX = ns.OFFSET_HEADER, large = true },
        { type = "dropdown", id = "grpTextureDD", label = "Bar Texture", items = groupTextureItems, width = 150,
          tooltip = "Texture for this group's bars. Inherit uses the addon-wide "
               .. "texture set on the Visuals page.",
          get = function() local g = getGroup(); return g and g.barTexture or "" end,
          set = function(_, value)
              local g = getGroup(); if not g then return end
              g.barTexture = (value ~= "" and value) or nil
              ns:RefreshAllBars()
          end,
          offsetX = ns.OFFSET_DROPDOWN, spacing = 28 },
        { type = "dropdown", id = "grpTextFormatDD", label = "Text Format",
          items = groupTextFormatItems, width = 150,
          tooltip = "What this group's bars show as text. Inherit uses the "
               .. "addon-wide format set on the Visuals page.",
          get = function() local g = getGroup(); return g and g.textFormat or "" end,
          set = function(_, value)
              local g = getGroup(); if not g then return end
              g.textFormat = (value ~= "" and value) or nil
              ns:RefreshAllBars()
          end,
          offsetX = ns.OFFSET_DROPDOWN, spacing = 28 },
        { type = "dropdown", id = "grpBarStyleDD", label = "Bar Style",
          items = {
              { text = "Inherit (default)", value = "" },
              { text = "Countdown", value = "COUNTDOWN" },
              { text = "On or Off", value = "SWITCH" },
          }, width = 150,
          tooltip = "How this group's bars show what they track. Countdown "
               .. "ticks down, On or Off just fills while it is active.",
          get = function() local g = getGroup(); return g and g.barStyle or "" end,
          set = function(_, value)
              local g = getGroup(); if not g then return end
              g.barStyle = (value ~= "" and value) or nil
              ns:RefreshAllBars()
          end,
          offsetX = ns.OFFSET_DROPDOWN, spacing = 28 },
        { type = "toggle", label = "Custom Bar Colour",
          tooltip = "Give this group's bars their own colour instead of the "
               .. "addon-wide default. Turn off to go back to the default.",
          get = function() local g = getGroup(); return g and g.barColor ~= nil end,
          set = function(_, checked)
              local g = getGroup(); if not g then return end
              if checked then
                  g.barColor = g.barColor or { r = 0.2, g = 0.6, b = 1.0 }
              else
                  g.barColor = nil
              end
              ns:RefreshBarSettings()
              ns:RefreshAllBars()
          end,
          -- Show the swatch only while the override is on, matching how the
          -- Visuals page couples Colour Mode to its own swatch. It used to sit
          -- there permanently, and clicking it silently switched the override on.
          onChange = function(value)
              local sw = groupSettingsWidgets.grpColorSwatch
              if sw then
                  if value then sw:Show() else sw:Hide() end
              end
              -- Live click bypasses Refresh (this fires from the checkbox's
              -- own set callback, not the schema walk), so reflow directly
              -- rather than waiting for the next full Refresh pass.
              if reflowGroupSettings then reflowGroupSettings() end
              if fitGroupHeight and ns.After then ns:After(0, fitGroupHeight) end
          end,
          offsetX = ns.OFFSET_TOGGLE, spacing = 8 },
        -- Deliberate sub-item: indented 10px further right than the Custom
        -- Bar Colour toggle above it (which it is shown/hidden with), not
        -- one of the canonical per-type columns.
        { type = "color", id = "grpColorSwatch", label = "Bar Colour",
          get = function() local g = getGroup(); return (g and g.barColor) or { r = 0.2, g = 0.6, b = 1.0 } end,
          set = function(_, color)
              local g = getGroup(); if not g then return end
              g.barColor = { r = color.r, g = color.g, b = color.b }
              -- Picking a colour implies "custom colour on" - re-run Refresh so
              -- the Custom Bar Colour toggle reflects that immediately.
              if refreshGroupSettings then refreshGroupSettings() end
              ns:RefreshAllBars()
          end,
          offsetX = ns.OFFSET_TOGGLE + 10, spacing = 8 },
        { type = "toggle", id = "grpIconOnly", label = "Show Icons Only",
          tooltip = "Only show the spell icons for this group's bars, with no "
               .. "bar behind them. Use the Width slider to size the icons.",
          get = function() local g = getGroup(); return g and g.iconOnly end,
          set = function(_, v)
              local g = getGroup(); if not g then return end
              g.iconOnly = v and true or false
              -- RefreshAllBars re-applies visual config on every bar and
              -- relayouts every group, matching the Bar Texture/Text
              -- Format/Bar Style dropdowns above, which flip a group-wide
              -- look the same way.
              ns:RefreshAllBars()
          end,
          offsetX = ns.OFFSET_TOGGLE, spacing = 12 },
        { type = "toggle", label = "Custom Stack Text",
          tooltip = "Give this group's bars their own size and colour for "
               .. "the stack count instead of the addon-wide default. Turn "
               .. "off to go back to the default.",
          get = function()
              local g = getGroup()
              return g and (g.stackFontSize ~= nil or g.stackColor ~= nil)
          end,
          set = function(_, checked)
              local g = getGroup(); if not g then return end
              if checked then
                  g.stackFontSize = g.stackFontSize or 12
                  g.stackColor = g.stackColor or { r = 1, g = 1, b = 1 }
              else
                  g.stackFontSize = nil
                  g.stackColor = nil
              end
              ns:RefreshAllBars()
          end,
          -- Same toggle-reveals-swatch mechanism as Custom Bar Colour above.
          onChange = function(value)
              local slider = groupSettingsWidgets.grpStackSizeSlider
              local sw = groupSettingsWidgets.grpStackColorSwatch
              if slider then if value then slider:Show() else slider:Hide() end end
              if sw then if value then sw:Show() else sw:Hide() end end
              -- Live click bypasses Refresh; see the Custom Bar Colour
              -- onChange above for why this reflows directly.
              if reflowGroupSettings then reflowGroupSettings() end
              if fitGroupHeight and ns.After then ns:After(0, fitGroupHeight) end
          end,
          offsetX = ns.OFFSET_TOGGLE, spacing = 12 },
        -- Deliberate sub-items: indented like grpColorSwatch above (shown/
        -- hidden together with the toggle), not the canonical per-type column.
        { type = "slider", id = "grpStackSizeSlider", label = "Stack Text Size",
          min = 6, max = 32, step = 1, width = 150, stretch = true,
          tooltip = "Size of the stack count on this group's bar icons.",
          get = function() local g = getGroup(); return (g and g.stackFontSize) or 12 end,
          set = function(_, value)
              local g = getGroup(); if not g then return end
              g.stackFontSize = value
              ns:RefreshAllBars()
          end,
          offsetX = ns.OFFSET_TOGGLE + 10, spacing = 8 },
        { type = "color", id = "grpStackColorSwatch", label = "Stack Text Colour",
          get = function() local g = getGroup(); return (g and g.stackColor) or { r = 1, g = 1, b = 1 } end,
          set = function(_, color)
              local g = getGroup(); if not g then return end
              g.stackColor = { r = color.r, g = color.g, b = color.b }
              -- Picking a colour implies "custom stack text on" - re-run
              -- Refresh so the toggle reflects that immediately, matching
              -- grpColorSwatch's set above.
              if refreshGroupSettings then refreshGroupSettings() end
              ns:RefreshAllBars()
          end,
          offsetX = ns.OFFSET_TOGGLE + 10, spacing = 8 },

        -- Same toggle-reveals-dependents shape as Custom Stack Text above:
        -- "off" clears all three keys back to nil so every bar in the group
        -- falls through to its own setting (ns:GetBarGlowOnReady/
        -- GetBarPulseOnReady/GetBarLingerTime, Conditions.lua). This is also
        -- the only way an auto-tracking group's slots - which have no bar
        -- list of their own to set these on - can glow, pulse, or linger.
        { type = "toggle", id = "grpBarEffectsToggle", label = "Custom Bar Effects",
          tooltip = "Give this group's bars their own Glow on Ready, Pulse "
               .. "on Ready and Linger Time instead of leaving it to each "
               .. "bar. Turn off to let each bar decide for itself again.",
          get = function()
              local g = getGroup()
              return g and (g.glowOnReady ~= nil or g.pulseOnReady ~= nil or g.lingerTime ~= nil)
          end,
          set = function(_, checked)
              local g = getGroup(); if not g then return end
              if checked then
                  g.glowOnReady = g.glowOnReady or false
                  g.pulseOnReady = g.pulseOnReady or false
                  g.lingerTime = g.lingerTime or 0
              else
                  g.glowOnReady = nil
                  g.pulseOnReady = nil
                  g.lingerTime = nil
              end
              ns:RefreshAllBars()
          end,
          onChange = function(value)
              local glowCB = groupSettingsWidgets.grpGlowToggle
              local pulseCB = groupSettingsWidgets.grpPulseToggle
              local slider = groupSettingsWidgets.grpLingerSlider
              if glowCB then if value then glowCB:Show() else glowCB:Hide() end end
              if pulseCB then if value then pulseCB:Show() else pulseCB:Hide() end end
              if slider then if value then slider:Show() else slider:Hide() end end
              -- Live click bypasses Refresh; see the Custom Bar Colour
              -- onChange above for why this reflows directly.
              if reflowGroupSettings then reflowGroupSettings() end
              if fitGroupHeight and ns.After then ns:After(0, fitGroupHeight) end
          end,
          offsetX = ns.OFFSET_TOGGLE, spacing = 12 },
        -- Deliberate sub-items: indented like grpStackSizeSlider above (shown/
        -- hidden together with the toggle), not the canonical per-type column.
        { type = "toggle", id = "grpGlowToggle", label = "Glow on Ready",
          tooltip = "Flash the icon on this group's bars when a cooldown "
               .. "finishes or a tracked buff or debuff runs out.",
          get = function() local g = getGroup(); return g and g.glowOnReady end,
          set = function(_, v)
              local g = getGroup(); if not g then return end
              g.glowOnReady = v and true or false
              ns:RefreshAllBars()
          end,
          offsetX = ns.OFFSET_TOGGLE + 10, spacing = 6 },
        { type = "toggle", id = "grpPulseToggle", label = "Pulse on Ready",
          tooltip = "Flash the spell icon at the centre of the screen when "
               .. "this group's bars come off cooldown or a tracked buff or "
               .. "debuff runs out.",
          get = function() local g = getGroup(); return g and g.pulseOnReady end,
          set = function(_, v)
              local g = getGroup(); if not g then return end
              g.pulseOnReady = v and true or false
              ns:RefreshAllBars()
          end,
          offsetX = ns.OFFSET_TOGGLE + 10, spacing = 6 },
        { type = "slider", id = "grpLingerSlider", label = "Linger Time (sec)",
          min = 0, max = 5, step = 0.5, width = 150, stretch = true,
          tooltip = "After a tracked cooldown or buff expires, this group's "
               .. "bars hold at 0 for this many seconds before fading out. "
               .. "Same range as the per-bar Linger Time slider.",
          get = function() local g = getGroup(); return (g and g.lingerTime) or 0 end,
          set = function(_, v)
              local g = getGroup(); if not g then return end
              g.lingerTime = v
              ns:RefreshAllBars()
          end,
          offsetX = ns.OFFSET_TOGGLE + 10, spacing = 8 },

        -- Group-level visibility conditions. These hide the ENTIRE group
        -- (frame + all bars) when the condition fails, saving the user from
        -- ticking the same checkbox on every bar individually.
        --
        -- offsetX below is now an ABSOLUTE indent from the panel's left edge
        -- (see Options_Builder.lua), so every header uses ns.OFFSET_HEADER,
        -- every toggle ns.OFFSET_TOGGLE, every dropdown ns.OFFSET_DROPDOWN,
        -- matching the rest of this schema instead of a running total.
        { type = "header", text = "Group Conditions", spacing = 16, offsetX = ns.OFFSET_HEADER, id = "grpCondHeader", large = true },
        { type = "toggle", label = "Hide When Inactive",
          tooltip = "Controls the whole group once you use it: ticked hides "
               .. "every bar while it has nothing to show, unticked keeps them "
               .. "all visible even if individual bars are set to hide. Leave it "
               .. "alone to let each bar decide. Also decides whether the group "
               .. "itself, name and all, stays on screen when it has nothing to "
               .. "show: ticked lets it disappear, unticked keeps it up.",
          get = function() local g = getGroup(); return g and g.groupConditions and g.groupConditions.hideWhenInactive end,
          set = function(_, v) local g = getGroup(); if not g then return end
              if not g.groupConditions then g.groupConditions = {} end
              g.groupConditions.hideWhenInactive = v
              -- RefreshBarSettings already refreshes the live bars, matching
              -- the other group-condition toggles.
              ns:RefreshBarSettings() end,
          offsetX = ns.OFFSET_TOGGLE, spacing = 4 },
        { type = "toggle", label = "Combat Only",
          tooltip = "Hide this entire group when out of combat.",
          get = function() local g = getGroup(); return g and g.groupConditions and g.groupConditions.combatOnly end,
          set = function(_, v) local g = getGroup(); if not g then return end
              if not g.groupConditions then g.groupConditions = {} end
              g.groupConditions.combatOnly = v
              if v then g.groupConditions.outOfCombatOnly = false end
              ns:RefreshBarSettings() end,
          offsetX = ns.OFFSET_TOGGLE, spacing = 4 },
        { type = "toggle", label = "Out of Combat Only",
          tooltip = "Hide this entire group when in combat.",
          get = function() local g = getGroup(); return g and g.groupConditions and g.groupConditions.outOfCombatOnly end,
          set = function(_, v) local g = getGroup(); if not g then return end
              if not g.groupConditions then g.groupConditions = {} end
              g.groupConditions.outOfCombatOnly = v
              if v then g.groupConditions.combatOnly = false end
              ns:RefreshBarSettings() end,
          offsetX = ns.OFFSET_TOGGLE, spacing = 2 },
        { type = "toggle", label = "Hide Mounted",
          tooltip = "Hide this entire group while mounted.",
          get = function() local g = getGroup(); return g and g.groupConditions and g.groupConditions.hideWhileMounted end,
          set = function(_, v) local g = getGroup(); if not g then return end
              if not g.groupConditions then g.groupConditions = {} end; g.groupConditions.hideWhileMounted = v; ns:RefreshBarSettings() end,
          offsetX = ns.OFFSET_TOGGLE, spacing = 2 },
        { type = "toggle", label = "Hide Resting",
          tooltip = "Hide this entire group while in an inn or capital city.",
          get = function() local g = getGroup(); return g and g.groupConditions and g.groupConditions.hideWhileResting end,
          set = function(_, v) local g = getGroup(); if not g then return end
              if not g.groupConditions then g.groupConditions = {} end; g.groupConditions.hideWhileResting = v; ns:RefreshBarSettings() end,
          offsetX = ns.OFFSET_TOGGLE, spacing = 2 },
        { type = "toggle", label = "Hide In Vehicle",
          tooltip = "Hide this entire group while in a vehicle.",
          get = function() local g = getGroup(); return g and g.groupConditions and g.groupConditions.hideInVehicle end,
          set = function(_, v) local g = getGroup(); if not g then return end
              if not g.groupConditions then g.groupConditions = {} end; g.groupConditions.hideInVehicle = v; ns:RefreshBarSettings() end,
          offsetX = ns.OFFSET_TOGGLE, spacing = 2 },
        { type = "toggle", label = "Only In Instance",
          tooltip = "Only show this entire group inside a dungeon, raid, arena, or battleground.",
          get = function() local g = getGroup(); return g and g.groupConditions and g.groupConditions.onlyInInstance end,
          set = function(_, v) local g = getGroup(); if not g then return end
              if not g.groupConditions then g.groupConditions = {} end; g.groupConditions.onlyInInstance = v; ns:RefreshBarSettings() end,
          offsetX = ns.OFFSET_TOGGLE, spacing = 2 },

        -- Auto tracking. Last on the page on purpose: BuildSettings lays widgets
        -- out once, so a block whose sub-settings hide has to sit at the end or
        -- hiding them punches a hole through the middle of the panel.
        { type = "header", text = "Auto Track", spacing = 16, offsetX = ns.OFFSET_HEADER, id = "grpAutoHeader", large = true },
        { type = "dropdown", id = "grpAutoTrackDD", label = "Track", items = autoTrackItems, width = 150,
          tooltip = "Fill this group by itself instead of adding bars one at a "
               .. "time: every buff or debuff on you or your target, or "
               .. "health and power for you, your target, or your target's "
               .. "target. The bars you added by hand are kept and come "
               .. "back when you set this to Off.",
          get = function() local g = getGroup(); return g and g.autoTrack or "" end,
          set = function(_, value)
              local g = getGroup(); if not g then return end
              g.autoTrack = (value ~= "" and value) or nil
              if g.autoTrack then
                  g.autoMaxBars     = g.autoMaxBars     or 10
                  g.autoMaxDuration = g.autoMaxDuration or 300
                  if g.autoOnlyMine == nil then
                      -- On a target, your own casts are what you are managing.
                      -- On yourself, a debuff someone else put there is exactly
                      -- the thing you want to see.
                      g.autoOnlyMine = (value == "targetBuffs" or value == "targetDebuffs")
                  end
              end
              ns:RebuildAllFrames()
              frame:Refresh()
          end,
          onChange = function(value) SetAutoSubWidgetsShown(value) end,
          offsetX = ns.OFFSET_DROPDOWN, spacing = 28 },
        { type = "slider", id = "grpAutoMaxBars", label = "Max Bars", min = 1, max = 30, step = 1,
          width = 150, stretch = true,
          tooltip = "How many bars this group can show at once.",
          get = function() local g = getGroup(); return g and g.autoMaxBars or 10 end,
          set = function(_, value)
              local g = getGroup(); if not g then return end
              g.autoMaxBars = value
              -- CreateSlider fires onChange on every drag step, so a full
              -- ns:RebuildAllFrames() here would tear down and recreate every
              -- group in the addon up to 30 times on one drag. Rebuild just
              -- this group's bars instead, matching the other Bars-tab
              -- setters (Width/Scale/Columns) that target one group.
              ns:BuildBarsForFrame(selectedGroupIndex)
              if ns.RebuildAllBarsCache then ns:RebuildAllBarsCache() end
              local gf = ns.groupFrames[selectedGroupIndex]
              if gf then ns:UpdateGroupLayout(gf) end
          end,
          offsetX = ns.OFFSET_SLIDER, spacing = 16 },
        -- Max raised from 1800 to 3600 (one hour) so a 30 minute buff can be
        -- admitted with headroom instead of sitting exactly on the ceiling
        -- (`duration > maxDuration` never keeps a buff at its own max).
        -- Step stays 30 across the doubled range: OptionsSliderTemplate only
        -- takes one SetValueStep, so there is no cheap way to grow it near
        -- the top, and 30s across 0-3600 is 120 stops, still fine enough to
        -- drag by feel while the format label carries the exact value.
        { type = "slider", id = "grpAutoMaxDuration", label = "Skip If It Lasts Over", min = 0, max = 3600, step = 30,
          width = 150, stretch = true, format = ns.FormatSettingDuration,
          tooltip = "Leave out anything that lasts longer than this in total, so "
               .. "food, flasks and raid buffs stay out of the way. Goes by the "
               .. "buff's full length, not how much time is left on it: a 30 "
               .. "minute buff like Seal of Light stays hidden even with only a "
               .. "few minutes left, because 30 minutes is still more than this "
               .. "setting.",
          get = function() local g = getGroup(); return g and (g.autoMaxDuration ~= nil and g.autoMaxDuration or 300) end,
          set = function(_, value)
              local g = getGroup(); if not g then return end
              g.autoMaxDuration = value
          end,
          offsetX = ns.OFFSET_SLIDER, spacing = 16 },
        { type = "toggle", id = "grpAutoIncludePermanent", label = "Include Always On",
          tooltip = "Also show things that have no timer, like class auras and "
               .. "tracking. They sit at the top of the group and stay put.",
          get = function() local g = getGroup(); return g and g.autoIncludePermanent end,
          set = function(_, v)
              local g = getGroup(); if not g then return end
              g.autoIncludePermanent = v and true or false
              ns:RefreshBarSettings()
          end,
          offsetX = ns.OFFSET_TOGGLE, spacing = 8 },
        { type = "toggle", id = "grpAutoOnlyMine", label = "Only Mine",
          tooltip = "Only show what you cast yourself.",
          get = function() local g = getGroup(); return g and g.autoOnlyMine end,
          set = function(_, v)
              local g = getGroup(); if not g then return end
              g.autoOnlyMine = v and true or false
          end,
          offsetX = ns.OFFSET_TOGGLE, spacing = 8 },
        { type = "toggle", id = "grpAutoStableOrder", label = "Keep Bars In Place",
          tooltip = "Keep each bar where it is for as long as it lasts, instead "
               .. "of reordering them as their timers change.",
          get = function() local g = getGroup(); return g and g.autoStableOrder end,
          set = function(_, v)
              local g = getGroup(); if not g then return end
              g.autoStableOrder = v and true or false
          end,
          offsetX = ns.OFFSET_TOGGLE, spacing = 4 },
        { type = "toggle", id = "grpAutoSkipTracked", label = "Skip Spells I Already Track",
          tooltip = "Leave out anything a bar in another group already shows, "
               .. "so this group only holds what you have not set up yourself.",
          get = function() local g = getGroup(); return g and g.autoSkipTracked end,
          set = function(_, v)
              local g = getGroup(); if not g then return end
              g.autoSkipTracked = v and true or false
              -- RefreshBarSettings invalidates the tracked-names cache and
              -- rescans, matching every other Group Conditions toggle above;
              -- without it, unticking this had no effect until the next bar
              -- edit or /reload.
              ns:RefreshBarSettings()
          end,
          offsetX = ns.OFFSET_TOGGLE, spacing = 4 },
        -- Pinned resources: only shown for one of the three resource feeds,
        -- "Health and power" (player), "Health and power (target)", or
        -- "Health and power (target of target)" (see
        -- AUTO_RESOURCE_ONLY_WIDGET_IDS above; all three are equally "not an
        -- aura feed" to SetAutoSubWidgetsShown). Each tickbox writes into an
        -- ORDERED list (autoPinnedResources: v2.5.0, replacing the older
        -- plain set) via ns:TogglePinnedResource (Trackers.lua), so the
        -- resulting bars appear in the order the tickboxes were ticked, not
        -- this fixed panel order; unticking then re-ticking moves a resource
        -- to the end rather than back to wherever it used to sit. Pinning
        -- reads off whichever unit the group's own feed names
        -- (ns:CollectResources' `opts.unit`), so "Keep Rage Visible" pins the
        -- TARGET's rage bar in a target-resources group, not the player's -
        -- the zero-max guard in CollectResources already makes it a no-op
        -- against a unit with no rage pool, same as it always has for the
        -- player feed.
        -- ns:NormalizePinnedResources tolerates a group still holding the
        -- pre-order set shape, so nothing here needed a migration.
        --
        -- Each tickbox is paired with a colour swatch (v2.5.0) storing a
        -- colour on that resource's own pinned entry - the most specific of
        -- the levels ns:GetPinnedResourceColor/ns:GetResourcePowerColor
        -- (Conditions.lua) resolve for GetBarColor (Bar.lua), ahead of this
        -- group's own Custom Bar Colour and the power-type default. Shown
        -- only while its tickbox is ticked, same toggle-reveals-swatch
        -- mechanism as Custom Bar Colour above.
        { type = "toggle", id = "grpAutoPinMana", label = "Keep Mana Visible",
          tooltip = "Mana already shows here on its own whenever it is the "
               .. "unit's current power. Tick this to keep the bar up the "
               .. "rest of the time too.",
          get = function() return isResourcePinned(getGroup(), "mana") end,
          set = function(_, v)
              local g = getGroup(); if not g then return end
              g.autoPinnedResources = ns:TogglePinnedResource(g.autoPinnedResources, "mana", v and true or false)
          end,
          onChange = function(value) onPinToggleChanged("grpAutoPinManaColor", value) end,
          offsetX = ns.OFFSET_TOGGLE, spacing = 8 },
        { type = "color", id = "grpAutoPinManaColor", label = "Mana Colour",
          get = function() return getPinnedResourceColor(getGroup(), "mana") end,
          set = function(_, color)
              local g = getGroup(); if not g then return end
              g.autoPinnedResources = ns:SetPinnedResourceColor(g.autoPinnedResources, "mana",
                  { r = color.r, g = color.g, b = color.b })
              ns:RefreshAllBars()
          end,
          offsetX = ns.OFFSET_TOGGLE + 10, spacing = 8 },
        { type = "toggle", id = "grpAutoPinRage", label = "Keep Rage Visible",
          tooltip = "Rage already shows here on its own whenever it is the "
               .. "unit's current power. Tick this to keep the bar up the "
               .. "rest of the time too.",
          get = function() return isResourcePinned(getGroup(), "rage") end,
          set = function(_, v)
              local g = getGroup(); if not g then return end
              g.autoPinnedResources = ns:TogglePinnedResource(g.autoPinnedResources, "rage", v and true or false)
          end,
          onChange = function(value) onPinToggleChanged("grpAutoPinRageColor", value) end,
          offsetX = ns.OFFSET_TOGGLE, spacing = 4 },
        { type = "color", id = "grpAutoPinRageColor", label = "Rage Colour",
          get = function() return getPinnedResourceColor(getGroup(), "rage") end,
          set = function(_, color)
              local g = getGroup(); if not g then return end
              g.autoPinnedResources = ns:SetPinnedResourceColor(g.autoPinnedResources, "rage",
                  { r = color.r, g = color.g, b = color.b })
              ns:RefreshAllBars()
          end,
          offsetX = ns.OFFSET_TOGGLE + 10, spacing = 8 },
        { type = "toggle", id = "grpAutoPinEnergy", label = "Keep Energy Visible",
          tooltip = "Energy already shows here on its own whenever it is the "
               .. "unit's current power. Tick this to keep the bar up the "
               .. "rest of the time too.",
          get = function() return isResourcePinned(getGroup(), "energy") end,
          set = function(_, v)
              local g = getGroup(); if not g then return end
              g.autoPinnedResources = ns:TogglePinnedResource(g.autoPinnedResources, "energy", v and true or false)
          end,
          onChange = function(value) onPinToggleChanged("grpAutoPinEnergyColor", value) end,
          offsetX = ns.OFFSET_TOGGLE, spacing = 4 },
        { type = "color", id = "grpAutoPinEnergyColor", label = "Energy Colour",
          get = function() return getPinnedResourceColor(getGroup(), "energy") end,
          set = function(_, color)
              local g = getGroup(); if not g then return end
              g.autoPinnedResources = ns:SetPinnedResourceColor(g.autoPinnedResources, "energy",
                  { r = color.r, g = color.g, b = color.b })
              ns:RefreshAllBars()
          end,
          offsetX = ns.OFFSET_TOGGLE + 10, spacing = 8 },
        -- Combo Points (v2.5.0): unlike Mana/Rage/Energy above, this is not a
        -- power type - it shows on its own once you have at least one point,
        -- and is gated to Rogue/Druid regardless of this tickbox (see
        -- ns:CollectResources, Trackers.lua): ticking it for a class that
        -- cannot generate any still shows nothing.
        { type = "toggle", id = "grpAutoPinCombo", label = "Keep Combo Points Visible",
          tooltip = "Combo points already show here once you have some. Tick "
               .. "this to keep the bar up at zero too.",
          get = function() return isResourcePinned(getGroup(), "combopoints") end,
          set = function(_, v)
              local g = getGroup(); if not g then return end
              g.autoPinnedResources = ns:TogglePinnedResource(g.autoPinnedResources, "combopoints", v and true or false)
          end,
          onChange = function(value) onPinToggleChanged("grpAutoPinComboColor", value) end,
          offsetX = ns.OFFSET_TOGGLE, spacing = 4 },
        { type = "color", id = "grpAutoPinComboColor", label = "Combo Points Colour",
          get = function() return getPinnedResourceColor(getGroup(), "combopoints") end,
          set = function(_, color)
              local g = getGroup(); if not g then return end
              g.autoPinnedResources = ns:SetPinnedResourceColor(g.autoPinnedResources, "combopoints",
                  { r = color.r, g = color.g, b = color.b })
              ns:RefreshAllBars()
          end,
          offsetX = ns.OFFSET_TOGGLE + 10, spacing = 8 },
        -- Runic Power / Runes (v2.5.0): only meaningful on the player feed -
        -- both are the PLAYER's own resource pools (ns:CollectResources'
        -- HasRunicPower/HasRunes probes, Trackers.lua), never a target's or
        -- a target's-target's - so these two sit in their own
        -- AUTO_PLAYER_RESOURCE_ONLY_WIDGET_IDS bucket rather than the
        -- AUTO_RESOURCE_ONLY_WIDGET_IDS one above (which shows for all three
        -- resource feeds). Unlike Mana/Rage/Energy, both already show
        -- unconditionally whenever the pool is real, so the tickbox only
        -- changes ORDER relative to the other pins, not whether the bar
        -- appears at all - see ns:CollectResources' own comment for the
        -- ordering fix this pin needed (the same one Combo Points needed: a
        -- pinned resource used to always land right after Health/current-
        -- power regardless of tick order).
        { type = "toggle", id = "grpAutoPinRunicPower", label = "Keep Runic Power Visible",
          tooltip = "Runic Power already shows here whenever you have a pool "
               .. "of it. Tick this to choose where it sits among your other "
               .. "pinned resources, instead of it always sitting right "
               .. "after Health.",
          get = function() return isResourcePinned(getGroup(), "runicpower") end,
          set = function(_, v)
              local g = getGroup(); if not g then return end
              g.autoPinnedResources = ns:TogglePinnedResource(g.autoPinnedResources, "runicpower", v and true or false)
          end,
          onChange = function(value) onPinToggleChanged("grpAutoPinRunicPowerColor", value) end,
          offsetX = ns.OFFSET_TOGGLE, spacing = 4 },
        { type = "color", id = "grpAutoPinRunicPowerColor", label = "Runic Power Colour",
          get = function() return getPinnedResourceColor(getGroup(), "runicpower") end,
          set = function(_, color)
              local g = getGroup(); if not g then return end
              g.autoPinnedResources = ns:SetPinnedResourceColor(g.autoPinnedResources, "runicpower",
                  { r = color.r, g = color.g, b = color.b })
              ns:RefreshAllBars()
          end,
          offsetX = ns.OFFSET_TOGGLE + 10, spacing = 8 },
        -- One tickbox/swatch covers every rune bar the group is currently
        -- showing (all six slots today), since there is no per-slot pin -
        -- the pin key is "runes", not "rune1".."rune6", and
        -- ns:GetPinnedResourceColor (Conditions.lua) maps each bar's own
        -- resourceKey back to this one shared entry for the colour swatch
        -- to actually reach them.
        { type = "toggle", id = "grpAutoPinRunes", label = "Keep Runes Visible",
          tooltip = "Runes already show here whenever you have any. Tick "
               .. "this to choose where they sit among your other pinned "
               .. "resources, instead of always sitting right after Health.",
          get = function() return isResourcePinned(getGroup(), "runes") end,
          set = function(_, v)
              local g = getGroup(); if not g then return end
              g.autoPinnedResources = ns:TogglePinnedResource(g.autoPinnedResources, "runes", v and true or false)
          end,
          onChange = function(value) onPinToggleChanged("grpAutoPinRunesColor", value) end,
          offsetX = ns.OFFSET_TOGGLE, spacing = 4 },
        { type = "color", id = "grpAutoPinRunesColor", label = "Runes Colour",
          get = function() return getPinnedResourceColor(getGroup(), "runes") end,
          set = function(_, color)
              local g = getGroup(); if not g then return end
              g.autoPinnedResources = ns:SetPinnedResourceColor(g.autoPinnedResources, "runes",
                  { r = color.r, g = color.g, b = color.b })
              ns:RefreshAllBars()
          end,
          offsetX = ns.OFFSET_TOGGLE + 10, spacing = 8 },
        -- Always Show Focus (and its colour swatch) was removed in v2.5.0:
        -- on 3.3.5a Focus is a hunter PET resource, never a player one
        -- (hunters use Mana until Cataclysm), so UnitPowerMax("player", 2)
        -- is always 0 and the pin could never produce a bar - see
        -- CHANGELOG. "focus" stays out of PINNABLE_POWER_TYPES
        -- (Trackers.lua); a legacy save that still has it pinned just finds
        -- no matching entry there and is silently dropped, no migration
        -- needed.
        { type = "dropdown", id = "grpAutoValueTextDD", label = "Value Text",
          items = {
              { text = "Current / Max", value = ""        },
              { text = "Percent",       value = "PERCENT" },
              { text = "Both",          value = "BOTH"    },
          }, width = 150,
          tooltip = "How each bar's number is shown: the amount and the "
               .. "total, just the percent, or both together.",
          get = function() local g = getGroup(); return g and g.autoResourceValueText or "" end,
          set = function(_, value)
              local g = getGroup(); if not g then return end
              g.autoResourceValueText = (value ~= "" and value) or nil
              ns:RefreshBarSettings()
          end,
          offsetX = ns.OFFSET_DROPDOWN, spacing = 16 },
        -- Icon on each resource bar (v2.5.0). Defaults to shown (nil reads
        -- as true) so an upgrading group's bars look exactly as they did
        -- before this tickbox existed - the collector already supplies a
        -- meaningful icon per resource (a class-resource spell icon, or the
        -- character-stat icons in Trackers.lua), so hiding it is the opt-out,
        -- not the default.
        { type = "toggle", id = "grpAutoShowIcon", label = "Show Icon",
          tooltip = "Show the resource icon on each bar in this group.",
          get = function() local g = getGroup(); return g and g.autoResourceShowIcon ~= false end,
          set = function(_, v)
              local g = getGroup(); if not g then return end
              g.autoResourceShowIcon = v and true or false
              ns:RefreshAllBars()
          end,
          offsetX = ns.OFFSET_TOGGLE, spacing = 8 },
        -- Group Name Follows Target (v2.5.0): only shown for the target and
        -- target's-target resource feeds (see
        -- AUTO_TARGET_RESOURCE_ONLY_WIDGET_IDS above) - a player-resources
        -- group following "you" would just repeat the group's own name.
        -- Nil by default, so an existing group's title is unaffected until
        -- ticked. Interacts with Show Group Name above it: that toggle still
        -- owns whether the title shows AT ALL; this one only changes what
        -- text it shows while it is visible - unticking Show Group Name
        -- hides the title exactly as before, regardless of this setting.
        -- The actual text is kept current by ns:ScanAutoResourceGroup
        -- (BarEngine.lua), which reads UnitName off this feed's own unit and
        -- only writes the fontstring when the resolved name actually
        -- changes - no live update wired here to avoid fighting that path;
        -- the 0.25s scan loop picks up a fresh toggle within one tick.
        { type = "toggle", id = "grpAutoTitleFollowsUnit", label = "Group Name Follows Target",
          tooltip = "Show the target's name as this group's title instead of "
               .. "the name above. With no target selected, the title falls "
               .. "back to the name above.",
          get = function() local g = getGroup(); return g and g.autoTitleFollowsUnit end,
          set = function(_, v)
              local g = getGroup(); if not g then return end
              g.autoTitleFollowsUnit = v and true or false
          end,
          offsetX = ns.OFFSET_TOGGLE, spacing = 8 },
        -- Show Target Level (v2.5.0): only does anything alongside Group
        -- Name Follows Target above (ns:ResolveGroupTitleName only appends a
        -- level once the title is actually following the unit), which is
        -- why it is listed right under it rather than with Show Icon/Value
        -- Text above. Off by default: Group Name Follows Target itself
        -- already ships off by default so an existing group's title stays
        -- untouched until opted in, and defaulting THIS on would silently
        -- change the title of anyone who had already ticked that one, the
        -- first time they update - the same reasoning, just one setting
        -- later. The level text and its colour are built by
        -- ns:FormatUnitLevelSuffix (FrameManager.lua): "80" for a normal
        -- level, "??" for a unit whose level cannot be determined (bosses),
        -- a trailing "+" for elite/boss, "R" for rare, "R+" for a rare
        -- elite, coloured by the game's own quest-difficulty colouring.
        { type = "toggle", id = "grpAutoTitleShowsLevel", label = "Show Target Level",
          tooltip = "Also show the target's level next to its name, "
               .. "coloured the same way the game colours it elsewhere. "
               .. "Only does anything while Group Name Follows Target above "
               .. "is ticked.",
          get = function() local g = getGroup(); return g and g.autoTitleShowsLevel end,
          set = function(_, v)
              local g = getGroup(); if not g then return end
              g.autoTitleShowsLevel = v and true or false
          end,
          offsetX = ns.OFFSET_TOGGLE, spacing = 8 },
        -- Invisible sentinel (no visible content, so no canonical column
        -- applies); offsetX is picked so the externally-anchored ban-list
        -- header below (Options_Bars.lua's "Hidden In This Group" block,
        -- anchored to this widget's id, not part of this schema) lands on
        -- ns.OFFSET_HEADER: -4 + 6 = 2.
        { type = "spacer", id = "groupLastWidget", height = 4, offsetX = -4 },
    }

    refreshGroupSettings, reflowGroupSettings = ns:BuildSettings(groupSettingsContent, GROUP_SETTINGS_SCHEMA, groupSettingsWidgets,
        { firstX = 0, firstY = 0 })

    -- Deep-link the Group Conditions section to its Help answer.
    if groupSettingsWidgets.grpCondHeader and ns.CreateHelpIcon then
        ns:CreateHelpIcon(groupSettingsContent, groupSettingsWidgets.grpCondHeader,
            "LEFT", "RIGHT", 6, 0, "group-conditions")
    end

    -- Deep-link the Auto Track section to its Help answer. This used to be
    -- reachable only by finding it filed under Conditions & Visibility in the
    -- Help tab; a direct [?] here is the fix for that.
    if groupSettingsWidgets.grpAutoHeader and ns.CreateHelpIcon then
        ns:CreateHelpIcon(groupSettingsContent, groupSettingsWidgets.grpAutoHeader,
            "LEFT", "RIGHT", 6, 0, "auto-track")
    end

    -- ========================================================================
    -- BANNED SPELLS: management list for the Alt-click bans set from a bar's
    -- icon (Bar.lua). Built directly with frames, not through BuildSettings /
    -- GROUP_SETTINGS_SCHEMA above: a per-group list of unknown, changing
    -- length is not something the declarative schema can express. Anchored
    -- below the trailing spacer (groupLastWidget) from that schema.
    --
    -- A framed icon/name/id table, matching the look of the Activity Tracker
    -- table in Options_Stats.lua: a tinted, bordered panel with a small
    -- column-heading row above a FauxScrollFrame of recycled rows.
    --
    -- The container is a FIXED height (MAX_BAN_ROWS rows) that never grows or
    -- shrinks with the ban count - only the FauxScrollFrame's scroll offset
    -- changes. That is deliberate, not a missed "grow with content" polish
    -- pass: fitGroupHeight (further down this file) measures the scroll
    -- child's height against this section's bottom sentinel every time it
    -- runs (a group's settings can reflow the schema section above this one
    -- at any point). A section whose OWN footprint could also change size
    -- would need its own reflow trigger on top of that, so this container's
    -- bottom edge has to land in the same place every time, whether it is
    -- showing 0, 1, or 100 banned spells.
    --
    -- No mouse wheel is bound on the inner FauxScrollFrame, matching every
    -- other list in this addon (Groups, Bars, and the Activity table all
    -- scroll only by dragging the scrollbar or clicking its arrows, never by
    -- wheel). This list sits inside groupSettingsContent, itself the scroll
    -- child of groupSettingsScroll; a wheel-enabled inner scroll region would
    -- capture wheel events meant for the outer Group Settings panel whenever
    -- the cursor happened to be over this table.
    -- ========================================================================
    local banHeader = groupSettingsContent:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    banHeader:SetText("Hidden In This Group")
    banHeader:SetPoint("TOPLEFT", groupSettingsWidgets.groupLastWidget, "BOTTOMLEFT", 6, -16)

    local banEmptyText = groupSettingsContent:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    banEmptyText:SetJustifyH("LEFT")
    -- Flush with banHeader's own x (0, not a negative nudge): a bare
    -- fontstring has no internal left inset to absorb a negative offset, so
    -- -6 here used to push its first few pixels past the scroll child's own
    -- left edge and into the clip region, shaving the leading letter off
    -- both this line and the row text below.
    banEmptyText:SetPoint("TOPLEFT", banHeader, "BOTTOMLEFT", 0, -8)
    -- Wrap against groupSettingsContent's own width (~320, resized on the fly
    -- by the OnSizeChanged handler above), not ns:ApplyWidth's PANEL_WIDTH:
    -- that sizes off the whole options panel (~570), which this fontstring
    -- does not span - it only fit today because the string is short.
    banEmptyText:SetPoint("RIGHT", groupSettingsContent, "RIGHT", -6, 0)
    banEmptyText:SetText("Alt-click a bar's icon to hide it from this group.")

    -- UpdateBanList itself is forward-declared above (before
    -- SetAutoSubWidgetsShown), since that gate needs to call it too.

    -- Column heading row, matching Options_Stats.lua's headerFrame: an icon
    -- spacer, a flexing Name column, and a fixed-width right-anchored ID
    -- column. No click-to-sort - the list is name-sorted and short enough
    -- that sorting adds nothing.
    local banHeaderRow = CreateFrame("Frame", nil, groupSettingsContent)
    banHeaderRow:SetHeight(14)
    banHeaderRow:SetPoint("TOPLEFT", banHeader, "BOTTOMLEFT", 0, -8)
    banHeaderRow:SetPoint("RIGHT", groupSettingsContent, "RIGHT", -6, 0)

    local banHIcon = banHeaderRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    banHIcon:SetPoint("LEFT", banHeaderRow, "LEFT", 4, 0)
    banHIcon:SetWidth(BAN_ICON_SIZE + 4)
    banHIcon:SetText("")

    local banHId = banHeaderRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    banHId:SetPoint("RIGHT", banHeaderRow, "RIGHT", -22, 0)  -- clears the scrollbar, matching the rows below
    banHId:SetWidth(50)
    banHId:SetJustifyH("RIGHT")
    banHId:SetText("ID")

    local banHName = banHeaderRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    banHName:SetPoint("LEFT", banHIcon, "RIGHT", 2, 0)
    banHName:SetPoint("RIGHT", banHId, "LEFT", -6, 0)
    banHName:SetJustifyH("LEFT")
    banHName:SetText("Name")

    -- Framed list container: fixed height regardless of ban count (see the
    -- block comment above), a tinted background matching the Activity
    -- table's listBg, plus a thin border so the section reads as a framed
    -- panel rather than a loose scroll region.
    local banListFrame = CreateFrame("Frame", nil, groupSettingsContent)
    banListFrame:SetPoint("TOPLEFT", banHeaderRow, "BOTTOMLEFT", 0, -2)
    banListFrame:SetPoint("RIGHT", groupSettingsContent, "RIGHT", -6, 0)
    banListFrame:SetHeight(MAX_BAN_ROWS * BAN_ROW_HEIGHT + 4)

    local banListBg = banListFrame:CreateTexture(nil, "BACKGROUND")
    banListBg:SetAllPoints()
    banListBg:SetTexture(0, 0, 0, 0.3)

    banListFrame:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
    })
    banListFrame:SetBackdropBorderColor(1, 1, 1, 0.3)

    local banScrollFrame = CreateFrame("ScrollFrame", "BarWardenBanScrollFrame", banListFrame, "FauxScrollFrameTemplate")
    banScrollFrame:SetPoint("TOPLEFT", 2, -2)
    banScrollFrame:SetPoint("BOTTOMRIGHT", -22, 2)

    local banRows = {}
    for i = 1, MAX_BAN_ROWS do
        -- Rows are children of banListFrame (a fixed frame), not of
        -- banScrollFrame: Blizzard's FauxScrollFrame_Update can hide the
        -- scroll frame itself once the list fits without scrolling (see the
        -- EC-TRAP note on KeepListFrameShown, above), and anchoring the rows
        -- to a frame that gets hidden out from under them would strand the
        -- Clear All button below. Matches Options_Stats.lua's row parenting.
        local row = CreateFrame("Button", nil, banListFrame)
        row:SetHeight(BAN_ROW_HEIGHT)
        if i == 1 then
            row:SetPoint("TOPLEFT",  banListFrame, "TOPLEFT",   2, -2)
            row:SetPoint("TOPRIGHT", banListFrame, "TOPRIGHT", -22, -2)
        else
            row:SetPoint("TOPLEFT",  banRows[i - 1], "BOTTOMLEFT",  0, 0)
            row:SetPoint("TOPRIGHT", banRows[i - 1], "BOTTOMRIGHT", 0, 0)
        end

        local highlight = row:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetTexture(1, 1, 1, 0.1)

        local iconTex = row:CreateTexture(nil, "ARTWORK")
        iconTex:SetPoint("LEFT", row, "LEFT", 4, 0)
        iconTex:SetSize(BAN_ICON_SIZE, BAN_ICON_SIZE)
        iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.iconTex = iconTex

        local idText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        idText:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        idText:SetWidth(50)
        idText:SetJustifyH("RIGHT")
        row.idText = idText

        local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        nameText:SetPoint("LEFT", iconTex, "RIGHT", 4, 0)
        nameText:SetPoint("RIGHT", idText, "LEFT", -6, 0)
        nameText:SetJustifyH("LEFT")
        if nameText.SetWordWrap then nameText:SetWordWrap(false) end
        row.nameText = nameText

        row:SetScript("OnEnter", function(self)
            if not self.banKey then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(self.banLabel or "", 1, 1, 1)
            GameTooltip:AddLine("Click to bring this back.", 0.6, 0.6, 0.6)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)

        row:SetScript("OnClick", function(self)
            if not self.banKey then return end
            local g = getGroup()
            if not g or not g.autoBanned then return end
            g.autoBanned[self.banKey] = nil
            -- Nil the table once empty rather than leaving `{}` behind: the
            -- documented shape is nil-on-nothing-banned, and ns:BuildAutoSkipSet
            -- treats a non-nil autoBanned (even empty) as "something to skip",
            -- which would otherwise cost CollectAutoAuras its cheap no-skipNames
            -- path for the rest of the group's life plus leave SavedVariables
            -- litter.
            if not next(g.autoBanned) then g.autoBanned = nil end
            if ns.InvalidateTrackedNames then ns:InvalidateTrackedNames() end
            UpdateBanList()
            if selectedGroupIndex and ns.ScanAutoGroup then ns:ScanAutoGroup(selectedGroupIndex) end
        end)

        banRows[i] = row
    end

    local banClearAllBtn = ns:CreateButton(groupSettingsContent, "Clear All", 100, function()
        local g = getGroup()
        if not g or not g.autoBanned then return end
        g.autoBanned = nil
        if ns.InvalidateTrackedNames then ns:InvalidateTrackedNames() end
        UpdateBanList()
        if selectedGroupIndex and ns.ScanAutoGroup then ns:ScanAutoGroup(selectedGroupIndex) end
    end)
    banClearAllBtn:SetPoint("TOPLEFT", banListFrame, "BOTTOMLEFT", 6, -6)

    -- Fixed sentinel marking the true bottom of this whole section, whichever
    -- state is showing (its own anchor chain never changes: banListFrame's
    -- height is constant, so banClearAllBtn's position beneath it never
    -- moves). fitGroupHeight measures against this instead of groupLastWidget
    -- once it exists.
    local banListBottom = CreateFrame("Frame", nil, groupSettingsContent)
    banListBottom:SetSize(1, 4)
    banListBottom:SetPoint("TOPLEFT", banClearAllBtn, "BOTTOMLEFT", 0, -4)
    groupSettingsWidgets.banListLastWidget = banListBottom

    -- Repopulate the list for the selected group. A name-sorted list keeps
    -- row order predictable between refreshes instead of following
    -- pairs()'s undefined iteration order.
    UpdateBanList = function()
        -- No feed picked: the whole section means nothing (Bar.lua's
        -- alt-click handler returns early on anything that is not
        -- bar.isAutoBar), so hide it entirely rather than show an inert
        -- "Hidden In This Group" header on an ordinary group.
        if not autoFeedShown then
            banHeader:Hide()
            banHeaderRow:Hide()
            banListFrame:Hide()
            banClearAllBtn:Hide()
            banEmptyText:Hide()
            return
        end
        banHeader:Show()

        local g = getGroup()
        local banned = g and g.autoBanned

        local list = {}
        if banned then
            for key, entry in pairs(banned) do
                list[#list + 1] = { key = key, name = entry.name or key, id = entry.id }
            end
            table.sort(list, function(a, b) return a.name < b.name end)
        end

        local count = #list
        if count == 0 then
            banHeaderRow:Hide()
            banListFrame:Hide()
            banClearAllBtn:Hide()
            banEmptyText:Show()
            return
        end

        banEmptyText:Hide()
        banHeaderRow:Show()
        banListFrame:Show()
        banClearAllBtn:Show()

        local offset = FauxScrollFrame_GetOffset(banScrollFrame)
        FauxScrollFrame_Update(banScrollFrame, count, MAX_BAN_ROWS, BAN_ROW_HEIGHT)

        for i = 1, MAX_BAN_ROWS do
            local row = banRows[i]
            local item = list[i + offset]
            if item then
                row.banKey = item.key
                row.banLabel = item.id and (item.name .. " (" .. item.id .. ")") or item.name
                row.nameText:SetText(item.name)
                row.idText:SetText(item.id and tostring(item.id) or "")

                -- GetSpellInfo returns nil for a spell id the client cannot
                -- resolve (live on the owner's private server with custom
                -- ids). The stored name still renders; SetTexture(nil) just
                -- clears the icon rather than erroring.
                local icon
                if item.id then
                    local _, _, spellIcon = GetSpellInfo(item.id)
                    icon = spellIcon
                end
                row.iconTex:SetTexture(icon)

                row:Show()
            else
                row.banKey = nil
                row.banLabel = nil
                row:Hide()
            end
        end
    end

    banScrollFrame:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, BAN_ROW_HEIGHT, UpdateBanList)
    end)

    -- ========================================================================
    -- RIGHT PANEL: Bar List + Bar Editor
    -- ========================================================================
    -- Bars tab content: same full-page region as the Groups tab (they occupy
    -- the same space and are shown one at a time by the bottom tabs).
    local rightPanel = CreateFrame("Frame", nil, frame)
    rightPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -44)
    rightPanel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 40)

    local barHeader = rightPanel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    barHeader:SetPoint("TOPLEFT", rightPanel, "TOPLEFT", 0, 0)
    barHeader:SetText("Bars")
    ns:CreateHelpIcon(rightPanel, barHeader, "LEFT", "RIGHT", 6, 0, "add-bar")

    -- Bar list spans the full page width; its height is set dynamically in
    -- UpdateBarList (grows with the bar count, up to MAX_BAR_ROWS rows, then
    -- scrolls). The buttons + editor below follow its bottom edge.
    local barScrollFrame = CreateFrame("ScrollFrame", "BarWardenBarScroll", rightPanel, "FauxScrollFrameTemplate")
    barScrollFrame:SetPoint("TOPLEFT", barHeader, "BOTTOMLEFT", 0, -6)
    -- Fixed width = the shared settings width (the button-row / Paste-button
    -- edge), so the list + its selection highlight stop at the same limit as
    -- everything else instead of stretching across the whole window.
    barScrollFrame:SetWidth(ns.SETTINGS_MAX_WIDTH or 300)
    barScrollFrame:SetHeight(MAX_BAR_ROWS * BAR_LIST_HEIGHT)

    local barRows = {}
    for i = 1, MAX_BAR_ROWS do
        local row = CreateFrame("Button", "BarWardenBarRow" .. i, rightPanel)
        row:SetHeight(BAR_LIST_HEIGHT)
        if i == 1 then
            row:SetPoint("TOPLEFT",  barScrollFrame, "TOPLEFT",   0, 0)
            row:SetPoint("TOPRIGHT", barScrollFrame, "TOPRIGHT", -22, 0)
        else
            row:SetPoint("TOPLEFT",  barRows[i - 1], "BOTTOMLEFT",  0, 0)
            row:SetPoint("TOPRIGHT", barRows[i - 1], "BOTTOMRIGHT", 0, 0)
        end

        local highlight = row:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetTexture(1, 1, 1, 0.1)

        local selected = row:CreateTexture(nil, "BACKGROUND")
        selected:SetAllPoints()
        selected:SetTexture(0.2, 0.4, 0.8, 0.3)
        selected:Hide()
        row.selected = selected

        -- Columns sized to fit within the capped list width (name + mode +
        -- target all land before the list's right edge, no clipping).
        local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        nameText:SetPoint("LEFT", row, "LEFT", 4, 0)
        nameText:SetJustifyH("LEFT")
        nameText:SetWidth(120)
        row.nameText = nameText

        local modeText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        modeText:SetPoint("LEFT", nameText, "RIGHT", 6, 0)
        modeText:SetJustifyH("LEFT")
        modeText:SetWidth(70)
        row.modeText = modeText

        local targetText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        targetText:SetPoint("LEFT", modeText, "RIGHT", 6, 0)
        targetText:SetJustifyH("LEFT")
        targetText:SetWidth(56)
        row.targetText = targetText

        row:SetScript("OnClick", function(self)
            selectedBarIndex = self.index
            frame:Refresh()
        end)

        -- Drag-to-reorder bars within the selected group (click still selects).
        -- Refused for a sorted group: its bar order comes from Sort Mode, not
        -- this array, so a drop would land in an unrelated slot and even a
        -- "successful" one has no visible effect (CODE_REVIEW.md's Resolved
        -- section, "drag-reorder was wrong under a sorted group"). The
        -- in-game ghost drag (DragReorder.lua) is refused the same way and
        -- shares this wording via ns:ExplainSortedDragRefusal.
        row:RegisterForDrag("LeftButton")
        row:SetScript("OnDragStart", function(self)
            local g = selectedGroupIndex and BarWardenDB and BarWardenDB.frames[selectedGroupIndex]
            if g and g.sortMode and g.sortMode ~= "manual" then
                if ns.ExplainSortedDragRefusal then ns:ExplainSortedDragRefusal() end
                return
            end
            frame._dragBar = self.index
        end)
        row:SetScript("OnDragStop", function()
            local from = frame._dragBar
            frame._dragBar = nil
            local g = selectedGroupIndex and BarWardenDB and BarWardenDB.frames[selectedGroupIndex]
            local bars = g and g.bars
            if not from or not bars or #bars < 2 then return end
            local to = ComputeDropIndex(barScrollFrame, BAR_LIST_HEIGHT, #bars)
            if to and to ~= from then
                table.insert(bars, to, table.remove(bars, from))
                selectedBarIndex = to
                frame:Refresh()
                ns:RebuildAllFrames()
            end
        end)

        barRows[i] = row
    end

    -- Bar list buttons: compact single row.
    -- +/- for add/delete, arrows for reorder, Dupe/Paste for copy-paste.
    local addBarBtn = ns:CreateButton(rightPanel, "+", 42, function()
        if not selectedGroupIndex then ns:Print("Select a group first."); return end
        local g = BarWardenDB.frames[selectedGroupIndex]
        if not g then return end
        if g.autoTrack then
            ns:Print("This group fills itself. Set Auto Track to Off to add bars by hand.")
            return
        end
        local maxBars = ns.MAX_BARS_PER_FRAME or 30
        if #g.bars >= maxBars then
            ns:Print("Maximum of " .. maxBars .. " bars per group reached.")
            return
        end
        local bar = NewBar("Bar " .. (#g.bars + 1))
        table.insert(g.bars, bar)
        selectedBarIndex = #g.bars
        frame:Refresh()
        ns:RebuildAllFrames()
    end)
    addBarBtn:SetPoint("TOPLEFT", barScrollFrame, "BOTTOMLEFT", 0, -4)

    local deleteBarBtn = ns:CreateButton(rightPanel, "-", 42, function()
        if not selectedGroupIndex or not selectedBarIndex then ns:Print("Select a bar first."); return end
        local g = BarWardenDB.frames[selectedGroupIndex]
        if not g then return end
        if g.autoTrack then
            ns:Print("This group fills itself. Set Auto Track to Off to change its bars.")
            return
        end
        local bar = g.bars[selectedBarIndex]
        if not bar then return end
        -- Capture the bar itself; the popup is not modal, so re-reading the
        -- selection at accept time could remove a different bar (or the wrong
        -- index of a different group) than the one the popup names.
        local targetBar = bar
        local popup = StaticPopup_Show("BARWARDEN_CONFIRM_DELETE", bar.name or "this bar")
        if popup then
            popup.data = {
                onAccept = function()
                    local idx
                    for i, b in ipairs(g.bars) do
                        if b == targetBar then idx = i; break end
                    end
                    if not idx then
                        ns:Print("That bar no longer exists.")
                        return
                    end
                    ns:BackupFrames("delete bar")
                    table.remove(g.bars, idx)
                    if selectedBarIndex and selectedBarIndex > #g.bars then
                        selectedBarIndex = #g.bars > 0 and #g.bars or nil
                    end
                    frame:Refresh()
                    ns:RebuildAllFrames()
                end,
            }
        end
    end)
    deleteBarBtn:SetPoint("LEFT", addBarBtn, "RIGHT", 1, 0)

    local moveUpBtn = ns:CreateButton(rightPanel, "Up", 44, function()
        if not selectedGroupIndex or not selectedBarIndex then ns:Print("Select a bar first."); return end
        local bars = BarWardenDB.frames[selectedGroupIndex].bars
        if selectedBarIndex <= 1 then return end
        bars[selectedBarIndex], bars[selectedBarIndex - 1] = bars[selectedBarIndex - 1], bars[selectedBarIndex]
        selectedBarIndex = selectedBarIndex - 1
        frame:Refresh()
        ns:RebuildAllFrames()
    end)
    moveUpBtn:SetPoint("LEFT", deleteBarBtn, "RIGHT", 1, 0)

    local moveDownBtn = ns:CreateButton(rightPanel, "Dn", 44, function()
        if not selectedGroupIndex or not selectedBarIndex then ns:Print("Select a bar first."); return end
        local bars = BarWardenDB.frames[selectedGroupIndex].bars
        if selectedBarIndex >= #bars then return end
        bars[selectedBarIndex], bars[selectedBarIndex + 1] = bars[selectedBarIndex + 1], bars[selectedBarIndex]
        selectedBarIndex = selectedBarIndex + 1
        frame:Refresh()
        ns:RebuildAllFrames()
    end)
    moveDownBtn:SetPoint("LEFT", moveUpBtn, "RIGHT", 1, 0)

    local copyBarBtn = ns:CreateButton(rightPanel, "Dupe", 60, function()
        if not selectedGroupIndex or not selectedBarIndex then ns:Print("Select a bar first."); return end
        local bar = frame:GetSelectedBar()
        if not bar then return end
        ns.copiedBar = ns:CopyTable(bar)
        ns:Print("Bar copied: " .. (bar.name or "unnamed"))
    end)
    copyBarBtn:SetPoint("LEFT", moveDownBtn, "RIGHT", 1, 0)

    local pasteBarBtn = ns:CreateButton(rightPanel, "Paste", 60, function()
        if not selectedGroupIndex then ns:Print("Select a group first."); return end
        if not ns.copiedBar then ns:Print("Nothing to paste. Copy a bar first."); return end
        local g = BarWardenDB.frames[selectedGroupIndex]
        if not g then return end
        if g.autoTrack then
            ns:Print("This group fills itself. Set Auto Track to Off to add bars by hand.")
            return
        end
        local maxBars = ns.MAX_BARS_PER_FRAME or 30
        if #g.bars >= maxBars then
            ns:Print("Maximum of " .. maxBars .. " bars per group reached.")
            return
        end
        local pasted = ns:CopyTable(ns.copiedBar)
        pasted.name = (pasted.name or "Bar") .. " (paste)"
        table.insert(g.bars, pasted)
        selectedBarIndex = #g.bars
        frame:Refresh()
        ns:RebuildAllFrames()
        ns:Print("Bar pasted: " .. pasted.name)
    end)
    pasteBarBtn:SetPoint("LEFT", copyBarBtn, "RIGHT", 1, 0)

    -- ========================================================================
    -- BAR EDITOR SUB-PANEL (scroll frame so content doesn't clip)
    -- ========================================================================
    -- The editor sits BELOW the bar list + buttons and spans the full page
    -- width (stacked layout, uniform with the Groups tab). This keeps the
    -- editor visible even at the smallest window size. It fills the remaining
    -- height and reflows on resize.
    local editorHeader = rightPanel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    editorHeader:SetPoint("TOPLEFT", addBarBtn, "BOTTOMLEFT", 0, -10)
    editorHeader:SetText("Bar Settings")

    local editorPanel = CreateFrame("Frame", nil, rightPanel)
    editorPanel:SetPoint("TOPLEFT", editorHeader, "BOTTOMLEFT", 0, -6)
    editorPanel:SetPoint("BOTTOMRIGHT", rightPanel, "BOTTOMRIGHT", 0, 0)

    local editorScroll = CreateFrame("ScrollFrame", "BarWardenBarEditorScrollFrame", editorPanel, "UIPanelScrollFrameTemplate")
    editorScroll:SetPoint("TOPLEFT",     editorPanel, "TOPLEFT",     0,   0)
    editorScroll:SetPoint("BOTTOMRIGHT", editorPanel, "BOTTOMRIGHT", -24, 0)

    local ec = CreateFrame("Frame", nil, editorScroll)  -- ec = editor content (scroll child)
    ec:SetWidth(340)   -- initial width; OnShow resizes to match the scroll viewport
    -- Generous fallback height so the full single-column editor is always
    -- reachable; fitEditorHeight() trims it to the real content once the editor
    -- is first shown (a fixed 660 used to clip the lower half off the scroll).
    ec:SetHeight(1100)
    editorScroll:SetScrollChild(ec)

    -- Bar name (first field, flush top to match group editor layout)
    local barNameEdit = ns:CreateEditBox(ec, "", 130, function(self, text)
        local bar = frame:GetSelectedBar()
        if bar then
            bar.name = text
            frame:Refresh()  -- updates the bar-list row on the left
            ns:RefreshBarSettings()
        end
    end,
    "A label for this bar, shown in the list and (if Show Bar Name is on) on "
 .. "the bar itself.")
    barNameEdit:SetPoint("TOPLEFT", ec, "TOPLEFT", 4, 0)
    -- Stretch the name box to the editor width so it uses the space (reactive:
    -- ec reflows to the viewport, and the RIGHT anchor follows). Right margin
    -- matches the schema stretch pad so every field lines up on the right.
    barNameEdit:SetPoint("RIGHT", ec, "RIGHT", -6, 0)

    -- Bar enabled checkbox
    local barEnabledCB = ns:CreateCheckbox(ec, "Enabled", "Enable or disable this bar", function(self, checked)
        local bar = frame:GetSelectedBar()
        if bar then
            bar.enabled = checked
            -- A bar you switch off stops counting as "already tracked", so the
            -- auto-tracking duplicate filter has to recompute.
            if ns.InvalidateTrackedNames then ns:InvalidateTrackedNames() end
            for _, liveBar in ipairs(ns:GetAllBars()) do
                if liveBar.barData == bar then
                    if checked then
                        local visual = ns:GetVisual()
                        liveBar:SetAlpha(visual.inactiveAlpha or 0.3)
                        liveBar:Show()
                    else
                        ns:DeactivateBar(liveBar)
                        liveBar:Hide()
                    end
                    break
                end
            end
            local gf = selectedGroupIndex and ns.groupFrames[selectedGroupIndex]
            if gf then ns:UpdateGroupLayout(gf) end
        end
    end)
    barEnabledCB:SetPoint("TOPLEFT", barNameEdit, "BOTTOMLEFT", -6, -4)

    -- Spell Name / ID
    local spellEdit = ns:CreateEditBox(ec, "Spell Name or ID", 130, function(self, text)
        local bar = frame:GetSelectedBar()
        if bar then
            -- Clear all legacy fields so old values don't override the new one
            bar.spell = nil
            bar.spellInput = nil
            local id = tonumber(text)
            if id then
                bar.spellId = id
                bar.spellName = nil
            else
                bar.spellId = nil
                bar.spellName = text
            end
            ns:RefreshBarSettings()
        end
    end,
    "The spell, item, or totem this bar tracks. Accepts a spell name "
 .. "(e.g. 'Evasion'), a numeric spell/item ID, or multiple "
 .. "comma-separated names for one bar to match any of them "
 .. "(e.g. 'Rupture, Garrote'). Press Enter to apply.")
    spellEdit:SetPoint("TOPLEFT", barEnabledCB, "BOTTOMLEFT", 6, -18)
    spellEdit:SetPoint("RIGHT", ec, "RIGHT", -6, 0)  -- stretch to editor width

    -- Single-column layout: Track Mode and Target stack vertically below
    -- Spell. The -16 x offset on the dropdowns compensates for WoW's
    -- invisible ~16 px left padding on UIDropDownMenu so the dropdown's
    -- label aligns with the edit-box labels above.

    -- Track Mode dropdown
    local trackModeDD = ns:CreateDropdown(ec, "Track Mode", TRACK_MODES, function(dd, value, index)
        local bar = frame:GetSelectedBar()
        if bar then
            bar.trackMode = value
            frame:Refresh()
            ns:RefreshBarSettings()
        end
    end,
    "What this bar watches: a spell cooldown, buff, debuff, proc, item "
 .. "cooldown, weapon enchant, totem, or a class resource.")
    UIDropDownMenu_SetWidth(trackModeDD, 180)
    trackModeDD:SetPoint("TOPLEFT", spellEdit, "BOTTOMLEFT", -16, -18)

    -- Target dropdown
    local targetDD = ns:CreateDropdown(ec, "Target", TARGET_UNITS, function(dd, value, index)
        local bar = frame:GetSelectedBar()
        if bar then
            bar.unit = value
            bar.target = nil  -- clear legacy field so unit takes effect
            frame:Refresh()
            ns:RefreshBarSettings()
        end
    end,
    "Whose buff or debuff this bar watches (you, your target, focus, pet, or "
 .. "mouseover). Ignored for cooldowns and items.")
    UIDropDownMenu_SetWidth(targetDD, 180)
    targetDD:SetPoint("TOPLEFT", trackModeDD, "BOTTOMLEFT", 0, -18)

    -- Only Mine checkbox: +16 x offset reverses the dropdown's -16 so
    -- this aligns with barNameEdit / spellEdit on the left.
    local onlyMineCB = ns:CreateCheckbox(ec, "Only Mine", "Only track auras cast by you", function(self, checked)
        local bar = frame:GetSelectedBar()
        if bar then
            bar.onlyMine = checked
            ns:RefreshBarSettings()
        end
    end)
    onlyMineCB:SetPoint("TOPLEFT", targetDD, "BOTTOMLEFT", 16, -6)

    -- ========================================================================
    -- CONDITIONS + DISPLAY: declarative schema (ns:BuildSettings).
    --
    -- All entries use get/set closures (not db paths) because the target bar
    -- is dynamic: it changes whenever the user selects a different bar in the
    -- list. refreshEditorSettings() is called from UpdateBarEditor on every
    -- bar selection change, re-reading all values from the new bar.
    -- ========================================================================

    local editorWidgets = {}

    -- GetSelectedBar is defined later in CreateBarsTab. At BuildSettings
    -- build time the method doesn't exist yet, so guard against nil.
    local function getBar()
        return frame.GetSelectedBar and frame:GetSelectedBar() or nil
    end
    local function getCond()
        local bar = getBar()
        return bar and (bar.conditions or {}) or {}
    end
    local function getDisp()
        local bar = getBar()
        return bar and (bar.display or {}) or {}
    end

    -- Forward-declared so UpdateAlertWidgetsShown and the schema's onChange
    -- closures below, all defined ahead of the BuildSettings call that
    -- assigns these, can reflow and re-measure right after they change
    -- visibility rather than only picking it up on the next full Refresh
    -- (same reasoning as reflowGroupSettings/fitGroupHeight on the Groups tab).
    local reflowEditorSettings
    local fitEditorHeight

    -- Bar Alerts' master toggle, unit dropdown, and style dropdown between
    -- them gate which of the sub-widgets show (the master gates all of
    -- them; the unit picks Seconds vs. Percent slider; the style shows the
    -- swatch only when it includes colour), so one shared updater - matching
    -- SetAutoSubWidgetsShown's shape on the Groups tab - is hooked to all
    -- three onChange callbacks (and re-runs on every Refresh pass) instead
    -- of duplicating this three-way visibility logic per widget.
    local function UpdateAlertWidgetsShown()
        local d = getDisp()
        local masterOn = d.sparkleAlert
        local unit = d.alertUnit or "SECONDS"
        local action = d.alertAction or "SPARKLE"

        local function setShown(id, shown)
            local w = editorWidgets[id]
            if w then
                if shown then w:Show() else w:Hide() end
            end
        end

        setShown("alertUnitDD", masterOn)
        setShown("dispAlertSecondsSlider", masterOn and unit == "SECONDS")
        setShown("dispAlertPercentSlider", masterOn and unit == "PERCENT")
        setShown("alertActionDD", masterOn)
        setShown("alertColorSwatch", masterOn and (action == "COLOUR" or action == "BOTH"))

        -- Live click bypasses Refresh (this fires from the widget's own set
        -- callback, not the schema walk), so reflow directly rather than
        -- waiting for the next full Refresh pass.
        if reflowEditorSettings then reflowEditorSettings() end
        -- Re-measure once the Show/Hide above has actually taken effect (see
        -- fitEditorHeight's own comment for why this needs a frame's delay).
        if fitEditorHeight and ns.After then ns:After(0, fitEditorHeight) end
    end

    -- Factory: condition-toggle schema entry (1 line per checkbox)
    local function condCheck(label, field, tip, extra)
        local e = { type = "toggle", label = label, tooltip = tip,
            get = function() return getCond()[field] end,
            set = function(_, v)
                local bar = getBar(); if not bar then return end
                if not bar.conditions then bar.conditions = {} end
                bar.conditions[field] = v
                ns:RefreshBarSettings()
            end,
            offsetX = ns.OFFSET_TOGGLE, spacing = 2 }
        if extra then for k, v in pairs(extra) do e[k] = v end end
        return e
    end

    -- Factory: display-toggle schema entry
    local function dispCheck(label, field, tip, extra)
        local e = { type = "toggle", label = label, tooltip = tip,
            get = function() return getDisp()[field] end,
            set = function(_, v)
                local bar = getBar(); if not bar then return end
                if not bar.display then bar.display = {} end
                bar.display[field] = v and true or false
                ns:RefreshBarSettings()
            end,
            offsetX = ns.OFFSET_TOGGLE, spacing = 2 }
        if extra then for k, v in pairs(extra) do e[k] = v end end
        return e
    end

    -- Factory: display-slider schema entry. offsetX always resolves to the
    -- canonical slider column (ns.OFFSET_SLIDER); a handful of call sites
    -- below (Alert/High/Med Threshold, Glow Duration) are sub-items whose
    -- setting only matters while the toggle above them is on, but that is a
    -- tighter `spacing` (grouping them visually with their toggle), not a
    -- different offsetX - they sit flush with every other slider in this
    -- panel, matching how they actually rendered before the offsetX refactor.
    local function dispSlider(label, field, mn, mx, st, default, tip, extra)
        local e = { type = "slider", label = label, tooltip = tip,
            min = mn, max = mx, step = st, width = 140, stretch = true,
            get = function() return getDisp()[field] or default end,
            set = function(_, v)
                local bar = getBar(); if not bar then return end
                if not bar.display then bar.display = {} end
                bar.display[field] = v
                ns:RefreshBarSettings()
            end,
            spacing = 24, offsetX = ns.OFFSET_SLIDER }
        if extra then for k, v in pairs(extra) do e[k] = v end end
        return e
    end

    local EDITOR_SCHEMA = {
        -- ---- Conditions ----
        { type = "header", text = "Conditions", id = "conditionsHeader", offsetX = ns.OFFSET_HEADER },

        -- Combat / OOC are mutually exclusive: set writes both DB fields,
        -- onChange visually unchecks the partner widget via editorWidgets ref.
        { type = "toggle", id = "combatOnly", label = "Combat Only",
          tooltip = "Show only in combat",
          get = function() return getCond().combatOnly end,
          set = function(_, v)
              local bar = getBar(); if not bar then return end
              if not bar.conditions then bar.conditions = {} end
              bar.conditions.combatOnly = v
              if v then bar.conditions.outOfCombatOnly = false end
              ns:RefreshBarSettings()
          end,
          onChange = function(v)
              if v and editorWidgets.oocOnly then editorWidgets.oocOnly:SetChecked(false) end
          end,
          offsetX = ns.OFFSET_TOGGLE, spacing = 4 },

        { type = "toggle", id = "oocOnly", label = "Out of Combat Only",
          tooltip = "Show only out of combat",
          get = function() return getCond().outOfCombatOnly end,
          set = function(_, v)
              local bar = getBar(); if not bar then return end
              if not bar.conditions then bar.conditions = {} end
              bar.conditions.outOfCombatOnly = v
              if v then bar.conditions.combatOnly = false end
              ns:RefreshBarSettings()
          end,
          onChange = function(v)
              if v and editorWidgets.combatOnly then editorWidgets.combatOnly:SetChecked(false) end
          end,
          offsetX = ns.OFFSET_TOGGLE, spacing = 2 },

        condCheck("In Group",            "inGroup",           "Show only when in a group"),
        condCheck("In Raid",             "inRaid",            "Show only when in a raid"),
        condCheck("Hide While Mounted",  "hideWhileMounted",  "Hide this bar while you are on a mount."),
        condCheck("Hide While Resting",  "hideWhileResting",  "Hide this bar while in an inn or capital city (resting)."),
        condCheck("Hide In Vehicle",     "hideInVehicle",     "Hide this bar while in a vehicle (siege engines, drakes, etc.)."),
        condCheck("Only In Instance",    "onlyInInstance",    "Only show this bar inside a dungeon, raid, arena, or battleground."),
        condCheck("Hide When Inactive",  "hideWhenInactive",  "Hide bar completely when not tracking anything."),

        { type = "editbox", label = "Health Below %", width = 60, stretch = true,
          tooltip = "Only show this bar when your own HP is below this percentage. "
                 .. "Useful for execute-range spells (Kill Shot, Hammer of Wrath, "
                 .. "Execute) and panic buttons (Healthstone). Enter a number 1-100 "
                 .. "and press Enter to apply, or leave empty to disable.",
          get = function()
              local v = getCond().healthBelow
              return v and tostring(v) or ""
          end,
          set = function(_, text)
              local bar = getBar(); if not bar then return end
              if not bar.conditions then bar.conditions = {} end
              local val = tonumber(text)
              bar.conditions.healthBelow = (val and val > 0 and val <= 100) and val or nil
              ns:RefreshBarSettings()
          end,
          offsetX = ns.OFFSET_EDITBOX, spacing = 18 },

        { type = "editbox", label = "Require Buff", width = 130, stretch = true,
          tooltip = "Only show this bar while you have the named buff active. "
                 .. "Accepts a buff name or spell ID. Useful for state-gated abilities "
                 .. "(stealth-only cooldowns, bear-form abilities, proc reactions). "
                 .. "Press Enter to apply, or leave empty to disable.",
          get = function() return getCond().requireBuff or "" end,
          set = function(_, text)
              local bar = getBar(); if not bar then return end
              if not bar.conditions then bar.conditions = {} end
              bar.conditions.requireBuff = (text and text ~= "") and text or nil
              ns:RefreshBarSettings()
          end,
          offsetX = ns.OFFSET_EDITBOX, spacing = 18 },

        -- ---- Display Options ----
        { type = "header", text = "Display Options", offsetX = ns.OFFSET_HEADER, spacing = 12 },

        dispSlider("Linger Time (sec)", "lingerTime", 0, 5, 0.5, 0,
            "After a tracked cooldown or buff expires, the bar holds at 0 for "
         .. "this many seconds before fading out. Pairs nicely with Glow on "
         .. "Ready so you can see the moment a spell came off cooldown. "
         .. "Set to 0 for the bar to disappear instantly on expiry."),

        { type = "slider", label = "Bar Scale",
          min = 0.5, max = 2.0, step = 0.1, width = 140, stretch = true,
          tooltip = "Scale this bar individually. 1.0 is the group default. Values above "
                 .. "1.0 may visually overlap neighbouring bars in multi-column groups; "
                 .. "increase Bar Spacing in the Visuals tab or use a single-column group "
                 .. "to compensate.",
          get = function() return getDisp().scaleOverride or 1.0 end,
          set = function(_, v)
              local bar = getBar(); if not bar then return end
              if not bar.display then bar.display = {} end
              bar.display.scaleOverride = (v ~= 1.0) and v or nil
              ns:RefreshBarSettings()
          end,
          offsetX = ns.OFFSET_SLIDER, spacing = 24 },

        dispCheck("Show Bar Name", "showName",
            "Display the Bar Name text on this bar.", { spacing = 24 }),
        dispCheck("Show Icon", "showIcon",
            "Display the spell icon on this bar."),
        dispCheck("Show as On or Off", "switchMode",
            "Fill the bar while this is active and leave it empty when it "
         .. "is not, with no countdown."),

        { type = "slider", label = "Bar Darkness",
          min = 0, max = 100, step = 1, width = 140, stretch = true,
          tooltip = "How dark the bar's empty/unfilled background is. 0 = fully "
                 .. "transparent (invisible background), 100 = solid black background. "
                 .. "Lower values make the filled portion stand out more; higher "
                 .. "values make empty bars easier to see at a glance.",
          get = function() return (getDisp().barAlpha or 0.6) * 100 end,
          set = function(_, v)
              local bar = getBar(); if not bar then return end
              if not bar.display then bar.display = {} end
              bar.display.barAlpha = v / 100
              ns:RefreshBarSettings()
          end,
          offsetX = ns.OFFSET_SLIDER, spacing = 24 },

        dispCheck("Sparkle Alert", "sparkleAlert",
            "Flash the bar, change its colour, or both once the timer gets "
         .. "close to running out. Alert When and Alert Style below decide "
         .. "the details.",
            { spacing = 24, onChange = function() UpdateAlertWidgetsShown() end }),

        -- Sub-items of Sparkle Alert above: all hidden together with it via
        -- UpdateAlertWidgetsShown, matching the Custom Bar Colour / Custom
        -- Stack Text toggle-reveals-widget pattern elsewhere in this file
        -- (see the comment above UpdateAlertWidgetsShown, further up).
        { type = "dropdown", id = "alertUnitDD", label = "Alert When",
          items = {
              { text = "Seconds Remaining (default)", value = "SECONDS" },
              { text = "Percent Remaining",           value = "PERCENT" },
          }, width = 150,
          tooltip = "Whether the threshold below is read as a fixed number "
               .. "of seconds left, or as a percent of the buff's full "
               .. "length. Percent scales with the timer, so the same "
               .. "setting works for a short cooldown and a half-hour buff "
               .. "alike.",
          get = function() return getDisp().alertUnit or "SECONDS" end,
          set = function(_, value)
              local bar = getBar(); if not bar then return end
              if not bar.display then bar.display = {} end
              bar.display.alertUnit = (value ~= "SECONDS") and value or nil
              ns:RefreshBarSettings()
          end,
          onChange = function() UpdateAlertWidgetsShown() end,
          spacing = 8, offsetX = ns.OFFSET_DROPDOWN },

        -- Seconds and Percent each get their own slider (rather than
        -- re-ranging one) because a slider's min/max are fixed at build
        -- time; UpdateAlertWidgetsShown shows whichever matches Alert When.
        dispSlider("Alert Threshold", "sparkleThreshold", 1, 15, 1, 5,
            "When Alert When is set to Seconds Remaining, the alert fires "
         .. "once the remaining time drops below this many seconds. Has no "
         .. "effect unless Sparkle Alert is ticked and Alert When is "
         .. "Seconds Remaining.",
            { spacing = 16, id = "dispAlertSecondsSlider" }),

        dispSlider("Alert Threshold (%)", "alertPercent", 1, 100, 1, 20,
            "When Alert When is set to Percent Remaining, the alert fires "
         .. "once the remaining time drops below this percent of the "
         .. "buff's full length. Has no effect unless Sparkle Alert is "
         .. "ticked and Alert When is Percent Remaining.",
            { spacing = 8, id = "dispAlertPercentSlider" }),

        { type = "dropdown", id = "alertActionDD", label = "Alert Style",
          items = {
              { text = "Sparkle (default)", value = "SPARKLE" },
              { text = "Colour",            value = "COLOUR"  },
              { text = "Both",              value = "BOTH"    },
          }, width = 150,
          tooltip = "What happens once the threshold above is reached: "
               .. "flash the bar, turn it a colour you pick below, or both.",
          get = function() return getDisp().alertAction or "SPARKLE" end,
          set = function(_, value)
              local bar = getBar(); if not bar then return end
              if not bar.display then bar.display = {} end
              bar.display.alertAction = (value ~= "SPARKLE") and value or nil
              ns:RefreshBarSettings()
          end,
          onChange = function() UpdateAlertWidgetsShown() end,
          spacing = 16, offsetX = ns.OFFSET_DROPDOWN },

        -- Color swatches have no tooltip support (CreateColorSwatch,
        -- Widgets.lua); matches Color Override / Stack Text Colour below,
        -- neither of which carries one either.
        { type = "color", id = "alertColorSwatch", label = "Alert Colour",
          get = function() return getDisp().alertColor or { r = 1, g = 0, b = 0 } end,
          set = function(_, color)
              local bar = getBar(); if not bar then return end
              if not bar.display then bar.display = {} end
              bar.display.alertColor = { r = color.r, g = color.g, b = color.b }
              ns:RefreshBarSettings()
          end,
          offsetX = ns.OFFSET_COLOR, spacing = 8 },

        { type = "color", label = "Color Override",
          get = function()
              return getDisp().colorOverride or { r = 1, g = 1, b = 1 }
          end,
          set = function(_, color)
              local bar = getBar(); if not bar then return end
              if not bar.display then bar.display = {} end
              bar.display.colorOverride = { r = color.r, g = color.g, b = color.b }
              ns:RefreshBarSettings()
          end,
          offsetX = ns.OFFSET_COLOR, spacing = 8 },

        dispCheck("Colour by Time", "colorByTime",
            "Bar colour changes from green to red as the timer counts down.",
            { spacing = 12 }),

        -- Both thresholds only matter while Colour by Time is on above; both
        -- sit on the same canonical slider column as everything else in this
        -- panel (the old schema indented Med Threshold a further step past
        -- High Threshold, an accumulation-bug artifact rather than an
        -- intended design - lining them up flush is the fix, not a regression).
        dispSlider("High Threshold (sec)", "colorHighSeconds", 1, 30, 1, 10,
            "When Colour by Time is enabled, the bar stays green while "
         .. "remaining time is at or above this many seconds, then fades "
         .. "toward yellow as it counts down. Set higher for earlier warning; "
         .. "lower to keep the bar green for longer.",
            { spacing = 20 }),

        dispSlider("Med Threshold (sec)", "colorMedSeconds", 1, 30, 1, 5,
            "When Colour by Time is enabled, the bar fades from yellow to red "
         .. "once remaining time drops below this many seconds. Should be "
         .. "lower than High Threshold; the gap between them is the "
         .. "yellow zone."),

        dispCheck("Glow on Ready", "glowOnReady",
            "Flash the icon when the cooldown finishes and the spell is ready.",
            { spacing = 20 }),

        dispCheck("Pulse on Ready", "pulseOnReady",
            "Flash the spell icon at the centre of the screen when this "
         .. "cooldown or buff expires. Gives a strong visual cue that the "
         .. "spell is available again, even if the bar is at the edge of "
         .. "your view.",
            { spacing = 8 }),

        -- Sub-item of Glow on Ready above: only takes effect while it is on;
        -- same slider column as everything else in this panel.
        dispSlider("Glow Duration (sec)", "glowDuration", 1, 10, 1, 3,
            "How long the icon keeps pulsing when Glow on Ready fires "
         .. "(spell comes off cooldown / buff expires). Has no effect unless "
         .. "Glow on Ready is ticked.",
            { spacing = 20 }),

        dispCheck("Crop Icon", "iconCrop",
            "Trim icon border pixels to prevent stretching.",
            { spacing = 20 }),

        -- Toggle-reveals-swatch, matching Custom Bar Colour on the Groups
        -- tab: "off" clears both display keys back to nil so the bar falls
        -- through to the group, then the addon-wide default (see
        -- ns:GetStackFontSize / ns:GetStackColor, Conditions.lua). Hand-
        -- rolled rather than dispCheck: dispCheck always writes a boolean,
        -- and "off" here must write nil, not false.
        { type = "toggle", id = "barStackTextToggle", label = "Custom Stack Text",
          tooltip = "Give this bar its own size and colour for the stack "
               .. "count instead of the addon-wide default. Turn off to go "
               .. "back to the default.",
          get = function()
              local d = getDisp()
              return d.stackFontSize ~= nil or d.stackColor ~= nil
          end,
          set = function(_, checked)
              local bar = getBar(); if not bar then return end
              if not bar.display then bar.display = {} end
              if checked then
                  bar.display.stackFontSize = bar.display.stackFontSize or 12
                  bar.display.stackColor = bar.display.stackColor or { r = 1, g = 1, b = 1 }
              else
                  bar.display.stackFontSize = nil
                  bar.display.stackColor = nil
              end
              ns:RefreshBarSettings()
          end,
          onChange = function(value)
              local slider = editorWidgets.barStackSizeSlider
              local sw = editorWidgets.editorLastWidget
              if slider then if value then slider:Show() else slider:Hide() end end
              if sw then if value then sw:Show() else sw:Hide() end end
              -- Live click bypasses Refresh; see UpdateAlertWidgetsShown
              -- above for why this reflows directly. editorLastWidget - the
              -- schema's own last entry - is exactly the widget this toggle
              -- can hide, so fitEditorHeight's sentinel needs the reflow's
              -- own "last VISIBLE widget" bottom rather than that fixed id.
              if reflowEditorSettings then reflowEditorSettings() end
              if fitEditorHeight and ns.After then ns:After(0, fitEditorHeight) end
          end,
          spacing = 20, offsetX = ns.OFFSET_TOGGLE },

        dispSlider("Stack Text Size", "stackFontSize", 6, 32, 1, 12,
            "Size of the stack count on this bar's icon.",
            { offsetX = ns.OFFSET_TOGGLE + 10, spacing = 8, id = "barStackSizeSlider" }),

        -- Last widget in the panel. It used to double as the fitEditorHeight
        -- sentinel directly (same as Crop Icon carried before this section
        -- was added); now that Custom Stack Text above can hide it, that
        -- sentinel role has moved to reflowEditorSettings()'s own "last
        -- VISIBLE widget" return value (see fitEditorHeight), so this id
        -- staying last in the schema is no longer load-bearing for that -
        -- it is just where the entry naturally falls.
        { type = "color", id = "editorLastWidget", label = "Stack Text Colour",
          get = function() return getDisp().stackColor or { r = 1, g = 1, b = 1 } end,
          set = function(_, color)
              local bar = getBar(); if not bar then return end
              if not bar.display then bar.display = {} end
              bar.display.stackColor = { r = color.r, g = color.g, b = color.b }
              ns:RefreshBarSettings()
          end,
          offsetX = ns.OFFSET_TOGGLE + 10, spacing = 8 },
    }

    -- Container frame for the schema-managed region, anchored below the
    -- imperative identity widgets (barEnabled through onlyMine).
    local editorSettingsFrame = CreateFrame("Frame", nil, ec)
    editorSettingsFrame:SetPoint("TOPLEFT", onlyMineCB, "BOTTOMLEFT", 0, -12)
    -- RIGHT-anchor to ec so the frame's right edge tracks the editor width; the
    -- schema's stretch widgets pin their RIGHT to this frame.
    editorSettingsFrame:SetPoint("RIGHT", ec, "RIGHT", 0, 0)
    editorSettingsFrame:SetHeight(800)

    local refreshEditorSettings
    refreshEditorSettings, reflowEditorSettings = ns:BuildSettings(
        editorSettingsFrame, EDITOR_SCHEMA, editorWidgets,
        { firstX = 0, firstY = 0 })

    if editorWidgets.conditionsHeader then
        ns:CreateHelpIcon(editorSettingsFrame, editorWidgets.conditionsHeader,
            "LEFT", "RIGHT", 6, 0, "conditions-overview")
    end

    -- Reflow the editor content (and its schema-managed child) to the live
    -- viewport width, so the editor uses whatever width the right column has.
    local function reflowEditor(w)
        w = w or editorScroll:GetWidth()
        if w and w > 100 then
            -- Cap at the shared settings width so controls do not stretch
            -- absurdly wide on a large window (editorSettingsFrame tracks ec
            -- via its RIGHT anchor; the stretch widgets follow).
            local cw = math.min(w, ns.SETTINGS_MAX_WIDTH or 300)
            ec:SetWidth(cw)
            -- Dropdowns fill the same width (their box width is a template
            -- property, set here rather than via a RIGHT anchor).
            local ddW = math.max(120, cw - 60)
            if trackModeDD then UIDropDownMenu_SetWidth(trackModeDD, ddW) end
            if targetDD then UIDropDownMenu_SetWidth(targetDD, ddW) end
        end
    end
    editorScroll:SetScript("OnSizeChanged", function(_, w) reflowEditor(w) end)

    -- Trim the scroll children to their real content, so the scroll range
    -- covers every VISIBLE control (and no more). Used to latch after a
    -- single first measurement (the widget set was fixed); now that a master
    -- toggle/dropdown can reflow the panel at any time, the live content
    -- height changes with it, so both functions re-measure on every call
    -- instead. Always invoked via ns:After(0, ...) (see the show/hide
    -- helpers above, and UpdateBarEditor/UpdateGroupName below): reading
    -- geometry in the same frame a widget was Shown/Hidden can return stale
    -- positions, so the measurement always waits a frame after the
    -- visibility change even though Reflow's SetPoint calls land
    -- immediately. The generous fallback heights (ec/groupSettingsContent
    -- SetHeight above) keep content reachable before the first measurement.
    -- Assigned (not `local function`) into the forward-declared upvalues
    -- from earlier in this file, so the show/hide helpers defined ahead of
    -- these bodies (SetAutoSubWidgetsShown, UpdateAlertWidgetsShown, and the
    -- Custom Bar Colour/Stack Text/Bar Effects onChange closures) already
    -- close over the SAME variable rather than a shadowing new local that
    -- would leave their captured upvalue permanently nil.
    fitEditorHeight = function()
        local top = ec:GetTop()
        -- reflowEditorSettings() both re-anchors the visible widgets (a
        -- harmless no-op if nothing has changed since the last call) and
        -- returns the screen-space bottom of the last VISIBLE one. That is
        -- deliberately used here instead of a fixed sentinel id: the
        -- schema's own last entry (editorLastWidget, the Stack Text Colour
        -- swatch) is itself one of the widgets Custom Stack Text can hide,
        -- so a fixed id would measure to a hidden widget's position instead
        -- of the panel's true (now shorter) bottom.
        local bottom = reflowEditorSettings and reflowEditorSettings()
        if top and bottom and top > bottom then
            ec:SetHeight(top - bottom + 24)
        end
    end
    fitGroupHeight = function()
        -- The banned-spells section (built above) sits below groupLastWidget
        -- and has its own fixed-position bottom sentinel; measure against
        -- that instead. Unlike editorLastWidget above, banListLastWidget is
        -- a plain frame built outside the schema and is never itself
        -- hidden - only its position moves as the schema above it reflows -
        -- so the fixed sentinel is still correct here, it just needs
        -- re-reading instead of latching the first answer.
        local last = groupSettingsWidgets.banListLastWidget
        local top = groupSettingsContent:GetTop()
        local bottom = last and last:GetBottom()
        if top and bottom and top > bottom then
            groupSettingsContent:SetHeight(top - bottom + 24)
        end
    end

    -- ========================================================================
    -- HELPER: Get selected bar data
    -- ========================================================================
    function frame:GetSelectedBar()
        if not selectedGroupIndex or not selectedBarIndex then return nil end
        local g = BarWardenDB.frames[selectedGroupIndex]
        if not g then return nil end
        return g.bars[selectedBarIndex]
    end

    -- ========================================================================
    -- REFRESH
    -- ========================================================================
    -- Empty-state lines, shown when a list has no rows.
    local groupEmptyText = leftPanel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    groupEmptyText:SetPoint("TOPLEFT", groupScrollFrame, "TOPLEFT", 4, -4)
    groupEmptyText:SetWidth((ns.SETTINGS_MAX_WIDTH or 300) - 20)
    groupEmptyText:SetJustifyH("LEFT")
    groupEmptyText:SetText("No groups yet. Click Add to create one.")
    groupEmptyText:Hide()

    local barEmptyText = rightPanel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    barEmptyText:SetPoint("TOPLEFT", barScrollFrame, "TOPLEFT", 4, -4)
    barEmptyText:SetWidth((ns.SETTINGS_MAX_WIDTH or 300) - 20)
    barEmptyText:SetJustifyH("LEFT")
    barEmptyText:Hide()

    local function UpdateGroupList()
        local frames = BarWardenDB and BarWardenDB.frames or {}
        local offset = FauxScrollFrame_GetOffset(groupScrollFrame)
        local total = #frames

        -- Grow the list box to the item count (min one line, max MAX_GROUP_ROWS
        -- rows), so the buttons + settings below sit right under the list and
        -- stay visible at the smallest window; overflow scrolls.
        local shown = math.max(1, math.min(total, MAX_GROUP_ROWS))
        groupScrollFrame:SetHeight(shown * GROUP_LIST_HEIGHT)

        FauxScrollFrame_Update(groupScrollFrame, total, MAX_GROUP_ROWS, GROUP_LIST_HEIGHT)
        KeepListFrameShown(groupScrollFrame, "BarWardenGroupScrollScrollBar",
                           total > MAX_GROUP_ROWS)
        if total == 0 then groupEmptyText:Show() else groupEmptyText:Hide() end

        for i = 1, MAX_GROUP_ROWS do
            local row = groupRows[i]
            local idx = offset + i
            if idx <= total then
                local g = frames[idx]
                row.text:SetText(g.name or ("Group " .. idx))
                row.index = idx
                row:Show()
                if idx == selectedGroupIndex then
                    row.selected:Show()
                else
                    row.selected:Hide()
                end
            else
                row:Hide()
            end
        end
    end

    local function UpdateBarList()
        local groupData = selectedGroupIndex and BarWardenDB
                          and BarWardenDB.frames[selectedGroupIndex]
        -- An auto group's stored bars are dormant while it fills itself, so
        -- listing them would offer rows that do nothing.
        local isAuto = groupData and groupData.autoTrack
        local bars = (not isAuto and groupData and groupData.bars) or {}
        local offset = FauxScrollFrame_GetOffset(barScrollFrame)
        local total = #bars

        -- Grow the list box to the bar count (min one line, max MAX_BAR_ROWS
        -- rows); overflow scrolls. Uniform with the Groups tab. An auto
        -- group shows no rows but its explanatory message wraps to about two
        -- lines at this width, so floor its height at two rows or the
        -- message overlaps the + button anchored below the list.
        local minRows = isAuto and 2 or 1
        local shown = math.max(minRows, math.min(total, MAX_BAR_ROWS))
        barScrollFrame:SetHeight(shown * BAR_LIST_HEIGHT)

        FauxScrollFrame_Update(barScrollFrame, total, MAX_BAR_ROWS, BAR_LIST_HEIGHT)
        KeepListFrameShown(barScrollFrame, "BarWardenBarScrollScrollBar",
                           total > MAX_BAR_ROWS)
        if isAuto then
            barEmptyText:SetText("This group fills itself. Your own bars come back "
                              .. "when Auto Track is Off.")
            barEmptyText:Show()
        elseif total == 0 then
            if selectedGroupIndex then
                barEmptyText:SetText("No bars in this group yet. Click + to add one.")
            else
                barEmptyText:SetText("Select a group on the Groups tab first.")
            end
            barEmptyText:Show()
        else
            barEmptyText:Hide()
        end

        for i = 1, MAX_BAR_ROWS do
            local row = barRows[i]
            local idx = offset + i
            if idx <= total then
                local b = bars[idx]
                -- ns.GetBarDisplayName falls back to the resolved spell name
                -- when the bar has none of its own, so an ID-configured bar
                -- doesn't read as a blank or stale "Bar N" placeholder here.
                row.nameText:SetText(ns.GetBarDisplayName(b))
                row.modeText:SetText(b.trackMode or "")
                row.targetText:SetText(b.unit or b.target or "")
                row.index = idx
                row:Show()
                if idx == selectedBarIndex then
                    row.selected:Show()
                else
                    row.selected:Hide()
                end
            else
                row:Hide()
            end
        end
    end

    local function UpdateBarEditor()
        local bar = frame:GetSelectedBar()
        if not bar then
            editorPanel:Hide()
            editorHeader:Hide()
            return
        end
        editorPanel:Show()
        editorHeader:Show()
        if ns.After then ns:After(0, fitEditorHeight) end  -- trim scroll once shown

        barEnabledCB:SetChecked(bar.enabled)
        barNameEdit:SetText(bar.name or "")
        spellEdit:SetText(bar.spellId and tostring(bar.spellId) or (bar.spellName or ""))
        onlyMineCB:SetChecked(bar.onlyMine)

        -- Track mode dropdown
        for i, mode in ipairs(TRACK_MODES) do
            if mode == bar.trackMode then
                UIDropDownMenu_SetSelectedID(trackModeDD, i)
                UIDropDownMenu_SetText(trackModeDD, mode)
                break
            end
        end

        -- Target dropdown (bar.unit is canonical after migration; bar.target is legacy fallback)
        local barUnit = bar.unit or bar.target or "player"
        for i, unit in ipairs(TARGET_UNITS) do
            if unit == barUnit then
                UIDropDownMenu_SetSelectedID(targetDD, i)
                UIDropDownMenu_SetText(targetDD, unit)
                break
            end
        end

        -- Conditions + Display: delegate to the BuildSettings Refresh closure.
        -- It re-reads all 28 fields from the currently-selected bar via the
        -- get closures in EDITOR_SCHEMA. Nil-safe (getCond/getDisp guard).
        refreshEditorSettings()
    end

    local function UpdateGroupName()
        -- Hide the settings column when no group is selected, so the right
        -- side isn't a panel of blank controls.
        if selectedGroupIndex then
            groupSettingsHeader:Show()
            groupSettingsScroll:Show()
            if ns.After then ns:After(0, fitGroupHeight) end  -- trim scroll once shown
        else
            groupSettingsHeader:Hide()
            groupSettingsScroll:Hide()
        end
        refreshGroupSettings()
        -- Repopulate (or hide, via getGroup() returning nil) the banned-
        -- spells list for whichever group is now selected.
        UpdateBanList()
    end

    function frame:Refresh()
        if not BarWardenDB then return end

        -- Validate selection
        local frames = BarWardenDB.frames
        if selectedGroupIndex and (selectedGroupIndex < 1 or selectedGroupIndex > #frames) then
            selectedGroupIndex = #frames > 0 and 1 or nil
        end
        if selectedGroupIndex then
            local gd = frames[selectedGroupIndex]
            if gd.autoTrack then
                -- An auto group offers no bar to edit: the list above shows it
                -- empty (its stored bars are dormant), so a surviving selection
                -- would open the editor on a row the panel says does not exist.
                selectedBarIndex = nil
            else
                local bars = gd.bars or {}
                if selectedBarIndex and (selectedBarIndex < 1 or selectedBarIndex > #bars) then
                    selectedBarIndex = #bars > 0 and 1 or nil
                end
            end
        else
            selectedBarIndex = nil
        end

        UpdateGroupList()
        UpdateGroupName()
        UpdateBarList()
        UpdateBarEditor()
    end


    -- FauxScrollFrame update hooks
    groupScrollFrame:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, GROUP_LIST_HEIGHT, UpdateGroupList)
    end)

    barScrollFrame:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, BAR_LIST_HEIGHT, UpdateBarList)
    end)

    -- Resize the editor-content frame to match the scroll viewport so the
    -- per-bar editor uses whatever width the InterfaceOptionsFrame gives us.
    -- Mirrors the pattern in Options_Visuals.lua.
    -- ========================================================================
    -- Page title + bottom tabs. "Bar Control" is a two-tab editor (Groups /
    -- Bars) rather than a flat panel, because managing groups and editing the
    -- bars inside them is a two-part workflow that shares one page.
    -- ========================================================================
    local pageTitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    pageTitle:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -16)
    pageTitle:SetText("Bar Control")

    local BC_TABS = { "Groups", "Bars" }
    local bcTabs = {}
    local function ShowBarControlTab(index)
        PanelTemplates_SetTab(frame, index)
        if index == 2 then
            rightPanel:Show()
            leftPanel:Hide()
        else
            leftPanel:Show()
            rightPanel:Hide()
        end
    end
    for i, label in ipairs(BC_TABS) do
        -- Named "<frameName>Tab<i>" so PanelTemplates_UpdateTabs finds them
        -- (and the v2-test rename stays correct since it derives from GetName).
        local tab = CreateFrame("Button", frame:GetName() .. "Tab" .. i, frame,
                                "CharacterFrameTabButtonTemplate")
        tab:SetText(label)
        tab:SetID(i)
        -- Larger tabs: scale the whole tab up (taller + bigger text) and pad it
        -- out well beyond its text width.
        tab:SetScale(1.3)
        if PanelTemplates_TabResize then PanelTemplates_TabResize(tab, 60) end
        tab:SetScript("OnClick", function(self)
            ShowBarControlTab(self:GetID())
            PlaySound("igCharacterInfoTab")
        end)
        if i == 1 then
            tab:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 8, 4)
        else
            tab:SetPoint("LEFT", bcTabs[i - 1], "RIGHT", -14, 0)
        end
        bcTabs[i] = tab
    end
    PanelTemplates_SetNumTabs(frame, #BC_TABS)
    ShowBarControlTab(1)

    frame:SetScript("OnShow", function(self)
        reflowEditor()
        if self.Refresh then self:Refresh() end
    end)

    return frame
end

ns:RegisterOptionsTab(2, CreateBarsTab)
