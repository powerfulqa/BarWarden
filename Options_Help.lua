-- Options_Help.lua - Help / FAQ tab and the [?] deep-link target.
-- Author:  Serv
-- Source:  https://github.com/powerfulqa/BarWarden
-- License: GNU GPL v3 (see LICENSE); attribution preservation is required.

local addonName, ns = ...

-- ============================================================================
-- HELP_ENTRIES
-- ----------------------------------------------------------------------------
-- Ordered flat list. Two entry kinds:
--   * Section marker:  { section = "<key>", title = "<display>" }
--   * Content entry:   { id = "<stable-id>", q = "<question>", a = "<answer>" }
-- The tab builder walks this list: section markers start a collapsible group,
-- content entries render between markers. Section keys must match the seeded
-- defaults in DB.lua (global.helpCollapsed). Content ids are stable: the [?]
-- deep-link icons (ns:CreateHelpIcon) reference them, and test_help.lua checks
-- that every deep-link target id resolves here.
-- ============================================================================

local HELP_ENTRIES = {
    -- ===================================================================
    { section = "gettingStarted", title = "Getting Started" },
    -- ===================================================================
    {
        id = "what-is-barwarden",
        q = "What does BarWarden do?",
        a = "BarWarden draws timer bars that track your spell cooldowns, "
          .. "buffs, debuffs, procs, item cooldowns, weapon enchants, totems, "
          .. "and class resources.\n\n"
          .. "When something goes on cooldown or a buff is applied, the "
          .. "matching bar fills and counts down, so you always know when it "
          .. "is ready or about to expire.\n\n"
          .. "It also replaces the default unit frames. On the Frames tab you "
          .. "can turn on a portrait frame for yourself, your target, your "
          .. "target's target, your pet, your focus, and everyone in your "
          .. "party. Use as much or as little of it as you like.",
    },
    {
        id = "getting-started",
        q = "I just installed this. Where do I start?",
        a = "Type /bw to open the settings. The quickest setup is the "
          .. "Profiles tab: Load Class Starter gives you a curated set of "
          .. "bars for your class and spec in one click.\n\n"
          .. "To build your own instead, go to the Bars / Groups tab, click "
          .. "Add to make a group, then Add a bar inside it.\n\n"
          .. "If you also want new unit frames, the Frames tab is separate "
          .. "and needs nothing set up first: tick Show Player Frame and it "
          .. "appears straight away.",
    },
    {
        id = "open-settings",
        q = "How do I open the settings?",
        a = "Left-click the BarWarden minimap button, or type /bw in chat.\n\n"
          .. "Right-click the minimap button to quickly enable or disable the "
          .. "addon. Hover any slider, dropdown, or text field for a tooltip "
          .. "explaining what it does.",
    },
    {
        id = "create-group",
        q = "How do I create a group?",
        a = "Groups are containers that hold your bars, like Cooldowns or "
          .. "Target Debuffs. On the Bars / Groups tab, click Add to create a "
          .. "group.\n\n"
          .. "Give it a name and set the width, scale, and columns. Each "
          .. "group can hold up to 30 bars, and you can have up to 20 groups.",
    },
    {
        id = "add-bar",
        q = "How do I add a bar?",
        a = "On Bar Control, pick a group on the Groups tab, switch to the "
          .. "Bars tab, and click +.\n\n"
          .. "Choose a Track Mode (Cooldown, Buff, Debuff, and so on), choose "
          .. "a target, and type the spell name or spell ID. The bar starts "
          .. "tracking the next time that spell or effect is active.",
    },
    {
        id = "move-groups",
        q = "How do I move my groups around the screen?",
        a = "Groups are locked by default so you do not move them by accident. "
          .. "Type /bw lock to unlock everything, drag the groups where you "
          .. "want them, then /bw lock again to lock them back in place.\n\n"
          .. "Unit frames move the same way, and each one is dragged "
          .. "separately - including the four party frames, even though they "
          .. "share one set of settings.",
    },

    -- ===================================================================
    { section = "trackingModes", title = "Tracking Modes" },
    -- ===================================================================
    {
        id = "track-cooldown",
        q = "Cooldown",
        a = "Tracks when one of your spells is on cooldown. The bar fills and "
          .. "counts down until the spell is ready again. Short global-cooldown "
          .. "triggers (under 1.5s) are ignored so the bar only reacts to real "
          .. "cooldowns.",
    },
    {
        id = "track-buff-debuff",
        q = "Buff and Debuff",
        a = "Buff tracks a buff on you or another unit and shows its remaining "
          .. "time and stack count. Debuff tracks a debuff on your target or "
          .. "another unit; by default it shows only debuffs you applied.\n\n"
          .. "Only Mine works the same way on either: tick it to count just "
          .. "your own, untick it to count them from anyone.",
    },
    {
        id = "track-proc",
        q = "Proc",
        a = "Tracks short-lived proc buffs on you. Works like Buff mode but "
          .. "always targets yourself, which is handy for reactive abilities "
          .. "like The Art of War or Clearcasting.",
    },
    {
        id = "track-item",
        q = "Item",
        a = "Tracks an item's cooldown by item ID or name, useful for trinkets, "
          .. "engineering tinkers, or your Hearthstone. To find an item ID, "
          .. "hover the item and look it up on a database site like Wowhead.",
    },
    {
        id = "track-enchant",
        q = "Enchant (mainhand / offhand)",
        a = "Tracks temporary weapon enchants like poisons, sharpening stones, "
          .. "or shaman weapon buffs.\n\n"
          .. "Pick Enchant MH for your mainhand or Enchant OH for your "
          .. "offhand. The Spell field is not used; use the Bar Name field to "
          .. "label it, for example Deadly Poison.",
    },
    {
        id = "track-totem",
        q = "Totem",
        a = "Tracks active totems by name or slot number. Use a slot number in "
          .. "the Spell field: 1 Fire, 2 Earth, 3 Water, 4 Air. Useful for "
          .. "shamans watching totem uptime.",
    },
    {
        id = "track-resources",
        q = "Class resources (Combo Points, Runes, Runic Power, Soul Shards)",
        a = "These fill as the resource builds rather than counting down.\n\n"
          .. "Combo Points (rogue/druid) fill 0 to 5 on your target. Runes "
          .. "(DK) use 1-6 in the Spell field for the slot. Runic Power (DK) "
          .. "fills 0 to 100. Soul Shards (warlock) shows the count in your "
          .. "bag.\n\n"
          .. "The class starter profiles pre-fill these for you.",
    },
    {
        id = "track-character-resources",
        q = "Health, Mana, Energy, and Rage",
        a = "These fill with your current health or power instead of "
          .. "counting down, the same as the class resources above. The "
          .. "Spell and Target fields are not used.\n\n"
          .. "Mana, Energy, and Rage each show that pool whether or not it "
          .. "is the one you are currently using, which is handy if you "
          .. "want to watch one on its own bar.\n\n"
          .. "For a group that shows your health and whichever power you "
          .. "are currently using without adding any of these by hand, see "
          .. "Resource Groups under Auto Tracking Groups.",
    },
    {
        id = "multiple-spells",
        q = "Can one bar track more than one spell?",
        a = "Yes. Separate the names with commas, for example "
          .. "Rupture, Garrote. The bar reacts to whichever is active.",
    },
    {
        id = "aura-groups",
        -- The id stays "aura-groups" on purpose: it is the internal name of
        -- the feature (AuraGroups.lua) and a [?] link target, and ids are not
        -- shown to anyone. Only the wording changed, to keep "aura" out of
        -- player-facing text - this was the last place it appeared.
        id = "aura-groups",
        q = "What are shortcuts like @Stunned?",
        a = "Instead of listing every crowd-control spell by hand, use one "
          .. "shortcut: @Stunned, @Bleeding, @Silenced, @Incapacitated, "
          .. "@Feared, @Rooted, @MovementSlowed, @Disarmed. One bar then "
          .. "tracks any spell of that kind. You can mix shortcuts and names: "
          .. "@Stunned, Blind.",
    },

    -- ===================================================================
    { section = "autoTracking", title = "Auto Tracking Groups" },
    -- ===================================================================
    -- Moved out of Conditions & Visibility: this grew from a single toggle
    -- into a small feature of its own (caps, ordering, alt-click bans), and
    -- nobody looking for it thought to check Conditions. The id stays
    -- "auto-track" so the existing [?] deep-links keep resolving.
    --
    -- This used to be one ~200-word answer covering four distinct questions
    -- (what it is, what the settings do, hiding a single spell, what to
    -- expect). Split into four entries so each one reads as a short,
    -- skimmable answer instead of a wall of text; "auto-track" stays the
    -- lead entry since it is the deep-link target.
    {
        id = "auto-track",
        q = "Can a group fill itself?",
        a = "Yes. On the Groups tab of Bar Control, set Auto Track to one of "
          .. "the seven choices: all buffs or all debuffs on you or your "
          .. "target, or health and power for you, your target, or your "
          .. "target's target.\n\n"
          .. "The group then shows whatever is there, without you naming a "
          .. "single spell, which is how you catch a boss debuff or an "
          .. "unfamiliar proc. Bars you added by hand are kept and come back "
          .. "when you set Auto Track to Off.",
    },
    {
        id = "auto-track-settings",
        q = "What do the Auto Track settings do?",
        a = "Max Bars caps how many show at once, and Skip If It Lasts Over "
          .. "keeps food, flasks and raid buffs out of the way by going on "
          .. "their full length, not the time left on them (set it to 0 to "
          .. "show everything).\n\n"
          .. "Include Always On adds things that never run out, like class "
          .. "buffs and tracking, pinned above the rest. Only Mine limits it "
          .. "to your own casts.\n\n"
          .. "Skip Spells I Already Track leaves out anything a bar in "
          .. "another group already covers, so the group only holds what you "
          .. "have not set up yourself. Keep Bars In Place stops the bars "
          .. "reordering as timers count down: each one stays put for as long "
          .. "as it lasts, and only fading frees its spot for something new.",
    },
    {
        id = "auto-track-hide-spell",
        q = "Can I hide just one spell from an auto-tracking group?",
        a = "Yes. Alt-click a bar's icon to hide that one spell from this "
          .. "group only.\n\n"
          .. "To bring it back, or clear everything you have hidden, open the "
          .. "Hidden In This Group list under Auto Track in the group's "
          .. "settings.",
    },
    {
        id = "disable-a-group",
        q = "Can I turn a group off without losing it?",
        a = "Yes. Untick Enabled at the top of that group's settings. The "
          .. "group disappears from the screen, and its bars, position and "
          .. "every setting stay exactly as they were. Tick it again and it "
          .. "comes straight back.\n\n"
          .. "A group that is off costs nothing and shows nothing, so an "
          .. "auto-tracking group with Skip Spells I Already Track will now "
          .. "show spells that only the switched-off group was tracking.\n\n"
          .. "This is per group. /bw disable turns the whole addon off "
          .. "instead, and hands back any default frames BarWarden was "
          .. "hiding.",
    },
    {
        id = "auto-track-hide-blizzard",
        q = "Can I hide the default buff and debuff icons?",
        a = "Yes. Set a group to track all buffs on you or all debuffs on "
          .. "you, and Hide Blizzard Buffs and Debuffs appears just under "
          .. "that dropdown.\n\n"
          .. "Buffs and debuffs go together because the game draws them as "
          .. "one piece, so the tick hides both. Weapon enchants are left "
          .. "alone. It is one setting for the whole addon rather than per "
          .. "group, so a buff group and a debuff group cannot disagree about "
          .. "it - tick it in either and it applies once.\n\n"
          .. "Untick it to bring the icons back, or /bw disable to hand back "
          .. "everything BarWarden is hiding.",
    },
    {
        id = "auto-track-tips",
        q = "What should I expect from an auto-tracking group?",
        a = "The group is empty until something real is actually active on "
          .. "you or your target, so unlock your frames to position it before "
          .. "that happens. Test bars do not appear in it, since there is "
          .. "nothing real to show.\n\n"
          .. "A spell counts as already tracked whenever a bar for it exists "
          .. "in another group, even while that group is hidden. So with Skip "
          .. "Spells I Already Track on, a spell tracked only in a Combat "
          .. "Only group will not appear here while you are out of combat "
          .. "either.",
    },
    {
        id = "auto-track-resources",
        q = "Can a group show my health and power automatically?",
        a = "Yes. Set Auto Track to Health and power instead of a buff or "
          .. "debuff choice. It shows Health first, then whatever power you "
          .. "are currently using, which is why it follows you through Bear, "
          .. "Cat, and Caster form live if you play a druid. Your class "
          .. "resources come after: combo points, runes, runic power, or "
          .. "soul shards, whichever apply. Bars use the game's own colours "
          .. "by default: a blue mana bar, a red rage bar, a yellow energy "
          .. "bar, and so on. Runes are coloured by type too: blood red, "
          .. "frost blue, unholy green, and death runes their own distinct "
          .. "colour.\n\n"
          .. "Health and power (target) does the same thing for whatever "
          .. "you have targeted: its health, then its current power. Combo "
          .. "Points show here too, alongside the player choice above, "
          .. "since they are always your points on your current target "
          .. "either way. A target with nothing selected just shows "
          .. "nothing. Tick Group Name Follows Target and the group's title "
          .. "shows the target's own name instead of the name you gave the "
          .. "group; with nothing selected, it falls back to that name. "
          .. "Show Target Level, next to it, also adds the target's level: "
          .. "?? for a boss whose level cannot be read, a + for an elite "
          .. "or boss, R for a rare, and R+ for a rare elite, coloured the "
          .. "same way the game colours it elsewhere. It only does "
          .. "anything while Group Name Follows Target is also ticked.\n\n"
          .. "Health and power (target of target) does it again for "
          .. "whatever your target has targeted. Combo Points do NOT show "
          .. "here: they are always your points on your OWN target, never "
          .. "on whatever your target is looking at, so showing them here "
          .. "would just repeat the other group's number under the wrong "
          .. "label. A target with nothing of its own targeted shows "
          .. "nothing. Group Name Follows Target works here too, showing "
          .. "your target's target's name.\n\n"
          .. "Keep Mana, Rage, and Energy Visible tick boxes let you pin a "
          .. "power you always want visible, even when it is not the one "
          .. "currently in use. They work on any of the three choices, "
          .. "pinning that group's own unit's power. Keep Combo Points "
          .. "Visible works the same way: combo points already show once "
          .. "you have some, and this keeps the bar up at zero too - it "
          .. "only does anything for a class that can generate them. On "
          .. "the player's own group, Keep Runic Power Visible and Keep "
          .. "Runes Visible do much the same, except both already show on "
          .. "their own whenever you actually have them, so ticking either "
          .. "one just lets you choose where it sits among your other "
          .. "pinned resources rather than turning it on or off. They all "
          .. "appear in the order you tick them, and each gets its own "
          .. "colour swatch if you want one (one swatch covers every rune "
          .. "bar). Show Icon turns the bar icons on or off for this "
          .. "group. Value Text picks how each number is shown: the "
          .. "amount and the total, just the percent, or both.\n\n"
          .. "Six rune bars taking up too much room? Tick Pair Runes by "
          .. "Type on the player's own group and each rune type shows as "
          .. "one bar instead of two: Blood, Unholy, and Frost, each "
          .. "reading how many of that pair are currently ready (2 of 2, "
          .. "1 of 2 while one recharges). Off by default, so an existing "
          .. "group keeps its six-bar look until you turn it on. A rune "
          .. "that has been turned into a Death rune still counts toward "
          .. "its own pair rather than getting a bar of its own.\n\n"
          .. "The settings for limiting or filtering a spell list (Skip If "
          .. "It Lasts Over, Only Mine, Include Always On, Skip Spells I "
          .. "Already Track, and the hidden-spells list) hide for all "
          .. "three, since none of them apply to a number that is not a "
          .. "spell.\n\n"
          .. "A resource group already shows the same health and power the "
          .. "default player or target frame does, so if you would rather "
          .. "not see the same numbers twice, tick Hide Blizzard Player "
          .. "Frame and/or Hide Blizzard Target Frame on the General tab - "
          .. "they work independently of each other. Hiding the player "
          .. "frame also hides the Death Knight rune display, and hiding "
          .. "the target frame also hides the combo point display. Neither "
          .. "one touches the target-of-target display; build a target of "
          .. "target group first if you want to replace that too.",
    },

    -- ===================================================================
    { section = "unitFrames", title = "Unit Frames" },
    -- ===================================================================
    {
        id = "unit-frames-overview",
        q = "What is a unit frame, and how is it different from a resource group?",
        a = "Both show the same health, power, and class resource data. A "
          .. "resource group draws it as a stack of timer-style bars; a unit "
          .. "frame draws it in the usual arrangement instead: a portrait, "
          .. "the name and level, a bar each for health and power, and runes "
          .. "or combo points as a compact strip. The amounts sit beside the "
          .. "bars or on them, whichever you prefer.\n\n"
          .. "There are frames for you, your target, your target's target, "
          .. "your pet, your focus, and all four party slots. Every one "
          .. "except your own shows what that unit actually has, and hides "
          .. "itself when there is nobody there.\n\n"
          .. "They are two separate, independent options - use whichever "
          .. "reads better. Turning one on does not change or remove the "
          .. "other.",
    },
    {
        id = "unit-frames-setup",
        q = "How do I turn on my unit frame?",
        a = "The Frames tab has a tab of its own along the bottom for each "
          .. "one: Player, Target, Party, Target's Target, Pet and Focus. "
          .. "Pick one and tick Show at the top of it.\n\n"
          .. "Each has the same settings: "
          .. "Scale resizes without moving, Bar Look and Bar Height change the "
          .. "bars, the Opacity sliders fade each part on its own, and Show "
          .. "Portrait, Show Name, Show Level and Show Values turn parts off.\n\n"
          .. "The player frame also lets you pick exactly which resources "
          .. "appear. The others show what that unit has, so they need no "
          .. "such list. The four party frames share one set of settings but "
          .. "are dragged separately.\n\n"
          .. "They start near the middle of the screen; unlock your frames "
          .. "(/bw lock) to drag each into place, then lock them again.",
    },
    {
        id = "unit-frames-blizzard",
        q = "My normal player frame disappeared. Where did it go?",
        a = "Turning on a BarWarden frame hides the default one it replaces, "
          .. "because two frames showing the same character in the same place "
          .. "is rarely what anyone wants. This happens for the player, "
          .. "target, target's target, pet, focus and party frames.\n\n"
          .. "Turn the BarWarden frame back off and the default one returns. "
          .. "The General tab also has Hide Blizzard Player Frame and Hide "
          .. "Blizzard Target Frame if you want the default gone without "
          .. "running a BarWarden frame at all.\n\n"
          .. "If you ever want everything back at once, /bw disable hands "
          .. "every default frame straight back.",
    },
    {
        id = "unit-frames-clicking",
        q = "Can I click a unit frame to target someone?",
        a = "Yes. Left-click the portrait or the name to target that unit, so "
          .. "clicking a party frame targets that party member. Right-click "
          .. "either one for the usual menu: leave party, promote, set focus, "
          .. "raid target icon, whisper, inspect, and the rest.\n\n"
          .. "This works whether your frames are locked or not. Locking only "
          .. "stops you dragging them by accident. While unlocked you can "
          .. "still drag a frame by its portrait or its name.",
    },
    {
        id = "unit-frames-resources",
        q = "How do I choose what my frame shows?",
        a = "Under Resources Shown on the player frame, untick anything you do "
          .. "not want: health, mana, rage, energy, runic power, runes, combo "
          .. "points, soul shards.\n\n"
          .. "Mana, rage and energy behave a little differently from the "
          .. "rest. Ticking one keeps it on your frame even when it is not the "
          .. "pool you are currently using, which matters if your character "
          .. "has more than one. It still never appears if your character does "
          .. "not have it at all.\n\n"
          .. "Combine Runes by Type turns six rune bars into three, one per "
          .. "type. Runes and combo points draw as a compact strip of segments "
          .. "rather than a bar each, so health and power stand out; Strip "
          .. "Height sets how tall those are.\n\n"
          .. "Target and party frames have no such list. They show what that "
          .. "unit actually has, the way the default frames do.",
    },
    {
        id = "unit-frames-appearance",
        q = "How do I change how a frame looks?",
        a = "Portrait Style picks a picture or a live 3D model of the "
          .. "character. The model falls back to the picture for anyone out of "
          .. "sight, since it cannot draw what the game cannot see.\n\n"
          .. "The Opacity sliders fade each part on its own. Panel is every "
          .. "dark surface: the background, the strip behind the name, and the "
          .. "box behind the portrait. Portrait fades the picture itself. Bars "
          .. "fades the bars and any numbers sitting on them. Border is the "
          .. "edge. Any of them will go to fully see-through.\n\n"
          .. "Name Font, Name Size, Values Font and Values Size set the text. "
          .. "Leave a size on Auto to follow your Visuals settings, so "
          .. "changing the font there changes the frame too. The frame grows "
          .. "to fit whatever size you pick.",
    },

    -- ===================================================================
    { section = "conditions", title = "Conditions & Visibility" },
    -- ===================================================================
    {
        id = "conditions-overview",
        q = "What are conditions?",
        a = "Conditions decide when a bar shows. Set them per bar so a bar only "
          .. "appears in combat, below a health threshold, in a group, for a "
          .. "specific class, and more. A bar whose conditions are not met is "
          .. "hidden.",
    },
    {
        id = "group-conditions",
        q = "Can I hide a whole group at once?",
        a = "Yes. Group Conditions, on the Groups tab of Bar Control, apply to "
          .. "an entire group at once instead of ticking every bar by hand: "
          .. "Hide When Inactive, Combat Only, Out of Combat Only, Hide "
          .. "Mounted, Hide Resting, Hide In Vehicle, Only In Instance.\n\n"
          .. "Hide When Inactive takes charge of the group once you use it: "
          .. "ticked hides every bar while it has nothing to show, unticked "
          .. "keeps them all visible even if individual bars are set to hide. "
          .. "Leave it alone and each bar decides for itself.\n\n"
          .. "It also decides whether the group itself, name and all, stays on "
          .. "screen when it has nothing to show: ticked lets it disappear, "
          .. "unticked keeps it up. Leave it alone and an auto-tracking group "
          .. "stays up while frames are unlocked so you can still find it, and "
          .. "hides once locked, same as before.",
    },
    {
        id = "condition-health-buff-class",
        q = "What do Health Below, Require Buff, and Require Class do?",
        a = "Health Below % shows the bar only when your HP drops under a "
          .. "percentage, good for execute spells or panic buttons.\n\n"
          .. "Require Buff shows the bar only while you have a named buff "
          .. "active (for example Stealth on Ambush).\n\n"
          .. "Require Class pins a bar to one class so a shared profile does "
          .. "not leak, say, rune bars onto non-DKs.",
    },
    {
        id = "smart-visibility",
        q = "Can bars hide themselves while mounted or resting?",
        a = "Yes. Smart visibility hides bars while mounted, resting, or in a "
          .. "vehicle, or shows them only inside dungeons and raids. Set these "
          .. "per bar, or per group with Group Conditions.",
    },

    -- ===================================================================
    { section = "visuals", title = "Visuals" },
    -- ===================================================================
    {
        id = "visuals-overview",
        q = "Where are the look-and-feel settings?",
        a = "The Visuals tab holds settings that apply to all bars: height and "
          .. "spacing, colour mode, bar texture, text position and font, "
          .. "duration style, icon size, and opacity. Many of these can be "
          .. "overridden per bar on the Bars / Groups tab.",
    },
    {
        id = "colour-mode",
        q = "How do I colour my bars?",
        a = "Colour Mode, on the Visuals page, sets the default: by class, by "
          .. "tracking mode, or a custom colour you pick. A group can override "
          .. "it under Bar Overrides, and a single bar can be given its own "
          .. "colour in the bar editor.\n\n"
          .. "Colour by Time transitions a bar from green to yellow to red as "
          .. "it counts down.",
    },
    {
        id = "textures-fonts",
        q = "Can I use my own textures and fonts?",
        a = "BarWarden ships 13 bar textures and 15 fonts. If you have a "
          .. "LibSharedMedia-aware addon, its textures and fonts appear in the "
          .. "dropdowns too. You can also type a custom texture path.",
    },
    {
        id = "duration-styles",
        q = "How can I change how the timer text reads?",
        a = "Two settings on the Visuals page control this. Text Format picks "
          .. "what a bar shows: name and countdown, name only, countdown "
          .. "only, stacks, or nothing. Duration Style picks how the "
          .. "countdown is written: seconds with a decimal, whole seconds, "
          .. "min:sec, short text, or an auto style that adapts to the time "
          .. "left.\n\n"
          .. "A single group can use its own Text Format under Bar Control > "
          .. "Groups > Bar Overrides, so you can change one group without "
          .. "touching the rest.",
    },
    {
        id = "visuals-stacks",
        q = "How do I see how many stacks something has?",
        a = "Anything with two or more stacks shows the number on its icon "
          .. "automatically, whatever text format you use. There is a Show "
          .. "Stack Count switch on the Visuals page if you would rather not "
          .. "have it, along with Stack Text Size and Stack Text Colour to "
          .. "make that number bigger and give it its own colour.",
    },
    {
        id = "bar-style",
        q = "Can a bar just show on or off instead of counting down?",
        a = "Yes. Turn on Show as On or Off for a bar and it fills while the "
          .. "thing it tracks is active and sits empty the rest of the time, "
          .. "with no ticking countdown.\n\n"
          .. "You can set it per bar in the bar's own settings, or for a whole "
          .. "group at once with the Bar Style dropdown under Bar Control > "
          .. "Groups > Bar Overrides.",
    },
    {
        id = "icon-only",
        q = "Can a group show just icons instead of bars?",
        a = "Yes. Show Icons Only, under Bar Control > Groups > Bar Overrides, "
          .. "swaps that group's bars for a plain grid of spell icons, no bar "
          .. "or text underneath.\n\n"
          .. "Size the icons with the Width slider and lay them out with "
          .. "Columns. Works on any group, hand-built or auto-tracking.",
    },

    -- ===================================================================
    { section = "profiles", title = "Profiles & Starters" },
    -- ===================================================================
    {
        id = "profiles-overview",
        q = "How do profiles work?",
        a = "Profiles save and load whole bar layouts and are account-wide, so "
          .. "you can set up bars on one character and load them on "
          .. "another.\n\n"
          .. "Save your current setup under a name, load a saved profile to "
          .. "switch, or rename and delete profiles on the Profiles tab.",
    },
    {
        id = "class-starters",
        q = "What are class starter profiles?",
        a = "Pre-curated bar loadouts for all 10 classes, drawn from the "
          .. "cooldowns, procs, and resources that matter for each.\n\n"
          .. "Load Class Starter replaces your current groups with the preset "
          .. "for your class and spec; Add Class Starter adds them alongside "
          .. "what you already have. A preview lists what will be added "
          .. "before you commit.",
    },
    {
        id = "export-import",
        q = "Can I share a profile with someone else?",
        a = "Yes. Export turns a profile into a text string you can copy; the "
          .. "other person uses Import and pastes it in. This is also how you "
          .. "move a setup between accounts.\n\n"
          .. "A profile carries your groups and bars, your Visuals settings, "
          .. "and everything on the Frames tab, so a shared setup arrives "
          .. "looking the way it did for the person who sent it.",
    },

    -- ===================================================================
    { section = "activity", title = "Activity Tracker" },
    -- ===================================================================
    {
        id = "activity-overview",
        q = "What is the Activity Tracker?",
        a = "It passively watches everything on your character: every cooldown "
          .. "you use, buff you gain, debuff you apply, weapon enchant, and "
          .. "totem, with no setup needed. Use it to discover what is worth "
          .. "tracking. Open it on the Activity page or with "
          .. "/bw stats.",
    },
    {
        id = "create-bar-from-stats",
        q = "Can I make a bar from something the tracker found?",
        a = "Yes. Select any detected spell in the Activity Tracker, click "
          .. "Create Bar, pick a group, and it adds a pre-configured bar with "
          .. "one click.",
    },
    {
        id = "activity-search-sort",
        q = "How do I find something in the tracker list?",
        a = "Type in the search box to only show matching names, use the "
          .. "category dropdown to narrow by type, and click a column heading "
          .. "to sort (click again to reverse the order).\n\n"
          .. "The list keeps itself current while the tab is open.",
    },

    -- ===================================================================
    { section = "troubleshooting", title = "Troubleshooting" },
    -- ===================================================================
    {
        id = "trouble-not-in-menu",
        q = "BarWarden does not appear in the AddOns menu.",
        a = "Make sure the folder is named exactly BarWarden, so the path is "
          .. "Interface/AddOns/BarWarden/BarWarden.toc. A GitHub download often "
          .. "unzips as barwarden-main; rename it to BarWarden.",
    },
    {
        id = "trouble-bars-not-showing",
        q = "My bars are not showing.",
        a = "Most often the bar is set to hide while it has nothing to track. "
          .. "Check Hide When Inactive on the bar, and under Group Conditions "
          .. "for the whole group - conditions such as Combat Only hide the "
          .. "whole group at once.\n\n"
          .. "Also check the bar's Enabled tickbox, that the addon itself is "
          .. "on (/bw enable), and that the bar has a valid spell name.\n\n"
          .. "If a group has been dragged off screen, /bw reset puts them all "
          .. "back where you can see them.",
    },
    {
        id = "trouble-frame-not-showing",
        q = "A unit frame is not showing.",
        a = "A frame hides itself when there is nobody to show. The target "
          .. "frame is not there until you have a target, the pet frame until "
          .. "you have a pet, and a party frame until someone is in that "
          .. "slot. Your own frame is the only one always present.\n\n"
          .. "If it should be there, check it is ticked on the Frames tab, "
          .. "that the addon is on (/bw enable), and that the Opacity sliders "
          .. "are not turned down to nothing.\n\n"
          .. "If it has been dragged off screen, /bw reset puts everything "
          .. "back where you can see it.",
    },
    {
        id = "trouble-frame-resizing",
        q = "My target frame changes size when I change target.",
        a = "A mob has no mana, so it needs fewer bars than a player does, and "
          .. "the frame used to shrink to fit. Minimum Bars, on the Frames "
          .. "tab, keeps room for at least that many bars whatever you have "
          .. "targeted. Two is enough for health and power; raise it if you "
          .. "also want room kept for combo points.\n\n"
          .. "The spare row draws as an empty bar, the same way the default "
          .. "frames leave a mana bar undrawn on a creature.",
    },
    {
        id = "trouble-spell-not-tracked",
        q = "A spell is not being tracked.",
        a = "Some private servers use different spell IDs than you expect. Try "
          .. "the spell name (like Evasion) instead of a number. Run /bw scan "
          .. "to see exactly what the game returns for each bar's lookup.",
    },
    {
        id = "trouble-minimap-missing",
        q = "The minimap button is missing.",
        a = "Open /bw and tick Show Minimap Icon on the main BarWarden page.",
    },
    {
        id = "trouble-undo",
        q = "I made a mess of my layout. Can I get it back?",
        a = "Type /bw restore to put back the layout you had before the last "
          .. "big change.\n\n"
          .. "BarWarden takes a snapshot before anything that replaces your "
          .. "bars: loading a profile or a class starter, resetting to "
          .. "defaults, deleting a group or a bar, and upgrading to a new "
          .. "version.\n\n"
          .. "Restoring takes a snapshot too, so running it twice brings you "
          .. "back again.",
    },
    {
        id = "trouble-lua-errors",
        q = "I am seeing Lua errors.",
        a = "Type /bw bugreport to generate a copyable diagnostic snapshot for "
          .. "a bug report, or /bw debug for a quick chat dump. As a last "
          .. "resort you can reset to defaults from the Profiles tab.",
    },
    {
        id = "trouble-test-mode",
        q = "How do I preview my layout without casting?",
        a = "Type /bw test to show every bar with a fake 30s timer so you can "
          .. "arrange your layout. Entering combat automatically turns test "
          .. "mode off.",
    },
}

ns.HELP_ENTRIES = HELP_ENTRIES  -- exposed for test_help.lua

local HELP_TAB_INDEX = 6
local ENTRY_WIDTH = 520  -- content width (544) minus indent + right margin

-- ----------------------------------------------------------------------------
-- Deep-link scroll generation counter. A later OpenHelpEntry supersedes any
-- in-flight deferred scroll from an earlier rapid click.
-- ----------------------------------------------------------------------------
local scrollGeneration = 0

local function GetCollapsed()
    if ns.db and ns.db.global and ns.db.global.helpCollapsed then
        return ns.db.global.helpCollapsed
    end
    return {}
end

-- ----------------------------------------------------------------------------
-- Tab builder
-- ----------------------------------------------------------------------------
local function CreateHelpTab(parent)
    local frame = CreateFrame("Frame", "BarWardenHelpTab", parent)
    frame:SetAllPoints(parent)
    frame:Hide()

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -16)
    title:SetText("Help")

    local desc = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    desc:SetJustifyH("LEFT")
    if desc.SetWordWrap then desc:SetWordWrap(true) end
    -- Reactive width so it wraps to the live panel width (a two-point
    -- TOPLEFT+RIGHT anchor does not wrap reliably on 3.3.5a).
    if ns.ApplyWidth then ns:ApplyWidth(desc, 32) end
    desc:SetText("Click a section to expand it. The [?] icons around the "
              .. "settings jump straight to the matching answer here.")

    -- "Back" button: shown only when the user arrived via a [?] deep-link, so
    -- one click returns them to the section they came from.
    local backBtn = ns:CreateButton(frame, "< Back", 90, function(self)
        local target = ns.helpReturnTab
        ns.helpReturnTab = nil
        self:Hide()
        if target and ns.SelectOptionsTab then ns:SelectOptionsTab(target) end
    end)
    backBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -16, -14)
    backBtn:Hide()
    frame.backBtn = backBtn

    local function UpdateBackButton()
        local target = ns.helpReturnTab
        local label = target and ns.TAB_NAMES and ns.TAB_NAMES[target]
        if label then
            backBtn:SetText("< Back to " .. label)
            local fs = backBtn:GetFontString()
            local tw = (fs and fs:GetStringWidth()) or 100
            backBtn:SetWidth(tw + 26)
            backBtn:Show()
        else
            backBtn:Hide()
        end
    end
    frame.UpdateBackButton = UpdateBackButton

    local scrollFrame = CreateFrame("ScrollFrame", "BarWardenHelpScrollFrame",
                                    frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT",     desc, "BOTTOMLEFT",  -12,  -6)
    scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -28,   4)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetWidth(544)
    content:SetHeight(1)
    scrollFrame:SetScrollChild(content)

    frame.scrollFrame = scrollFrame
    frame.content = content

    -- Build a widget per entry once; collapse just hides/re-anchors them.
    local items = {}       -- ordered render items
    local itemById = {}    -- id -> content-entry container, for deep-link
    frame.items = items
    frame.itemById = itemById

    local currentSection

    for _, entry in ipairs(HELP_ENTRIES) do
        if entry.section then
            currentSection = entry.section

            local header = CreateFrame("Button", nil, content)
            header:SetSize(ENTRY_WIDTH, 20)
            local htext = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            htext:SetPoint("LEFT", header, "LEFT", 0, 0)
            header.label = htext
            header.sectionTitle = entry.title

            local sectionKey = entry.section
            header.UpdateArrow = function(collapsed)
                htext:SetText("|cffffd870" .. (collapsed and "+ " or "- ")
                           .. header.sectionTitle .. "|r")
            end
            header:SetScript("OnClick", function()
                local c = GetCollapsed()
                c[sectionKey] = not c[sectionKey]
                frame.Relayout()
            end)
            header:SetScript("OnEnter", function()
                htext:SetTextColor(1, 1, 1)
            end)
            header:SetScript("OnLeave", function()
                htext:SetTextColor(1, 0.82, 0)
            end)

            items[#items + 1] = { kind = "section", widget = header, section = sectionKey }
        else
            local e = CreateFrame("Frame", nil, content)
            e:SetWidth(ENTRY_WIDTH)

            local flash = e:CreateTexture(nil, "BACKGROUND")
            flash:SetAllPoints()
            flash:SetTexture(0.30, 0.56, 1.0, 0.25)
            flash:SetAlpha(0)
            e.flash = flash

            local q = e:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            q:SetPoint("TOPLEFT", e, "TOPLEFT", 0, 0)
            q:SetWidth(ENTRY_WIDTH)
            q:SetJustifyH("LEFT")
            q:SetText("|cff4db8ff" .. entry.q .. "|r")

            local a = e:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            a:SetPoint("TOPLEFT", q, "BOTTOMLEFT", 0, -3)
            a:SetWidth(ENTRY_WIDTH)
            a:SetJustifyH("LEFT")
            a:SetText(entry.a)

            e.Flash = function()
                if not UIFrameFlash then return end
                UIFrameFlash(e.flash, 0.25, 0.45, 1.4, false, 0, 0.35)
            end

            -- Apply the current text width, then size the entry to the wrapped
            -- height at that width. Called from Relayout with the live width so
            -- the answer reflows when the panel viewport changes size.
            e._apply = function(tw)
                e:SetWidth(tw)
                q:SetWidth(tw)
                a:SetWidth(tw)
                local qh = q:GetStringHeight() or 12
                local ah = a:GetStringHeight() or 12
                e:SetHeight(qh + 3 + ah)
            end

            items[#items + 1] = { kind = "q", id = entry.id, widget = e, section = currentSection }
            if entry.id then itemById[entry.id] = e end
        end
    end

    -- Walk items top to bottom, anchoring each visible one to content by a
    -- cumulative offset (no prev-widget chain, so a hidden entry never strands
    -- the ones below it). Collapsed sections hide their content entries.
    function frame.Relayout()
        local collapsed = GetCollapsed()
        -- Reflow to the live scroll-viewport width so wrapped answer text is
        -- never clipped when the Interface Options panel is a different size
        -- than the build-time guess. Falls back to 544 before the frame is
        -- first shown (GetWidth is 0 until then).
        local w = scrollFrame:GetWidth()
        if not w or w < 100 then w = 544 end
        content:SetWidth(w)
        local textW = w - 16 - 8   -- entries anchor at x=16; keep an 8px right margin
        local y = -8
        for _, item in ipairs(items) do
            if item.kind == "section" then
                item.widget.UpdateArrow(collapsed[item.section])
                item.widget:SetWidth(w - 8)
                item.widget:ClearAllPoints()
                item.widget:SetPoint("TOPLEFT", content, "TOPLEFT", 4, y)
                item.widget:Show()
                y = y - 20 - 6
            else
                if collapsed[item.section] then
                    item.widget:Hide()
                else
                    item.widget._apply(textW)
                    item.widget:ClearAllPoints()
                    item.widget:SetPoint("TOPLEFT", content, "TOPLEFT", 16, y)
                    item.widget:Show()
                    y = y - item.widget:GetHeight() - 10
                end
            end
        end
        content:SetHeight(math.max(1, -y + 20))
    end

    -- Lay out on first show and whenever shown (collapse state may have changed
    -- via a deep-link while the tab was hidden), and reflow whenever the scroll
    -- viewport resizes (UI scale change or a differently-sized options panel)
    -- so the wrapped text tracks the real width instead of a fixed guess.
    frame:SetScript("OnShow", function()
        frame.Relayout()
        UpdateBackButton()
    end)
    scrollFrame:SetScript("OnSizeChanged", function() frame.Relayout() end)
    frame.Relayout()

    ns._helpTab = frame
    return frame
end

ns:RegisterOptionsTab(HELP_TAB_INDEX, CreateHelpTab)

-- ----------------------------------------------------------------------------
-- ns:OpenHelpEntry(id): deep-link from a [?] icon. Opens the panel, switches
-- to the Help tab, expands the owning section, then scrolls to + flashes the
-- entry. Passing nil just opens the Help tab.
-- ----------------------------------------------------------------------------
function ns:OpenHelpEntry(id)
    -- Expand the section that owns this entry before the tab lays out.
    if id and ns.db and ns.db.global then
        -- Track the section headings we pass, and only keep the last one if we
        -- actually reach the entry. Without the `found` flag an unknown id ran
        -- off the end and expanded whichever section happened to be last.
        local owner, found
        for _, entry in ipairs(HELP_ENTRIES) do
            if entry.section then
                owner = entry.section
            elseif entry.id == id then
                found = true
                break
            end
        end
        if owner and found then
            ns.db.global.helpCollapsed = ns.db.global.helpCollapsed or {}
            ns.db.global.helpCollapsed[owner] = false
        end
    end

    -- Open the Help section's own category (ns:SelectOptionsTab handles the
    -- 3.3.5a double-call quirk internally).
    if ns.SelectOptionsTab then ns:SelectOptionsTab(HELP_TAB_INDEX) end

    local tab = ns._helpTab
    if tab and tab.Relayout then tab.Relayout() end
    if not id or not tab then return end

    scrollGeneration = scrollGeneration + 1
    local gen = scrollGeneration

    local function doScroll()
        if scrollGeneration ~= gen then return end
        local widget = tab.itemById and tab.itemById[id]
        local sf = tab.scrollFrame
        if not widget or not sf or not widget:GetTop() or not sf:GetTop() then
            return
        end
        -- widget:GetTop() already reflects the current scroll, so the target
        -- offset is current + (scrollTop - widgetTop). A naive scrollTop -
        -- widgetTop only works from a scroll of 0 and sends the second pass
        -- back to the top.
        local current = sf:GetVerticalScroll() or 0
        local offset = current + (sf:GetTop() - widget:GetTop())
        if offset < 0 then offset = 0 end
        local range = sf:GetVerticalScrollRange() or 0
        if offset > range then offset = range end
        sf:SetVerticalScroll(offset)
        if widget.Flash then widget.Flash() end
    end

    -- Two passes: the first after OnShow + Relayout settle, the second after
    -- the scroll range re-measures with the now-expanded section. Both are
    -- gated by the generation counter so a later click cancels them.
    if ns.After then
        ns:After(0.05, doScroll)
        ns:After(0.20, doScroll)
    else
        doScroll()
    end
end
