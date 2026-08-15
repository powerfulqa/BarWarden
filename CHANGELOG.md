# BarWarden - Changelog

Per-release notes for [BarWarden](README.md). For the player-level
overview of what the addon does, see the [README](README.md). For
contributor-facing architecture and development discipline, see
[docs/ADDON_GUIDE.md](docs/ADDON_GUIDE.md). For the shared-convention
relationship with the sibling addon EbonClearance, see
[NOTICE.md](NOTICE.md).

This changelog was started at v1.10.6. Entries for earlier versions are
backfilled from the release history and are summaries rather than
exhaustive notes.

---

### v2.5.0

**A group can now show your health and power automatically, following you
through form changes.** Four new track modes, Health, Mana, Energy and Rage,
join the existing Combo Points, Runes, Runic Power and Soul Shards as
value-based resource bars. A new "Health and power" choice on Auto Track
builds on them: the group fills itself with Health, whichever power you are
currently using, and your class resources, with nothing to name by hand. A
druid's power slot follows Bear, Cat and Caster form live because it reads
the same current-power-type signal the game itself uses.

- **Health, Mana, Energy and Rage join the Track Mode dropdown**, alongside
  the existing class resources. Pick one for a bar the same way as any other
  track mode; each fills rather than counts down, exactly like Combo Points
  and the rest.
- **A new Auto Track choice, "Health and power", fills a group by itself**
  with Health first, then your current power, then your class resources
  (combo points, runes, runic power, or soul shards, whichever apply) - no
  spell to name, and no bar list to keep up to date as you level or respec.
- **Always Show Mana / Rage / Energy / Focus** pin a power you always want
  visible in a resource group, even when it is not the one you are currently
  using.
- **Value Text** picks how a resource group's bars show their number:
  Current / Max (`4200/5100`), Percent (`82%`), or Both (`4200/5100 (82%)`).
- The buff/debuff-only Auto Track settings (Skip If It Lasts Over, Only Mine,
  Include Always On, Skip Spells I Already Track, and the hidden-spells
  list) hide for a resources group, since none of them apply to a number
  that is not a spell.
- **Hide Blizzard Player Frame**, a new General tab tickbox, hides the
  default player frame for anyone who would rather not see their health and
  power twice alongside a resource group. It stays reversible: unticking it
  (or `/bw disable`) shows the frame again straight away, and a hide
  requested mid-fight waits for combat to end rather than risking an error.
  It now also hides the Death Knight rune display, which used to stay on
  screen after ticking the box.
- **Resource bars now use the game's own colours by default** - a blue mana
  bar, a yellow energy bar, a red rage bar, and so on - instead of the
  addon-wide default colour. A group's own Custom Bar Colour still overrides
  it.
- **A new Show Icon tickbox** on a resource group lets you hide the bar
  icons for a plainer look. On by default, matching how resource bars have
  always looked.

---

### v2.4.0

**Combat Only and the other group conditions now hide a group outright, even
while its frames are unlocked.** An unlocked auto-tracking group with nothing
on the unit is kept visible on purpose, so it can still be found and dragged,
but that same carve-out was also catching a group that was empty because its
own condition - Combat Only, Out of Combat Only, Hide Mounted, Hide Resting,
Hide In Vehicle or Only In Instance - said to hide it, letting the group sit
on screen anyway while unlocked. An explicit condition now wins regardless of
lock state. A group whose conditions pass is unaffected and comes straight
back, same as before.

- **Settings panels no longer leave a gap where a hidden setting used to be.**
  Turning off Custom Bar Colour, Custom Stack Text, Custom Bar Effects, or
  Sparkle Alert, setting Auto Track back to Off, or switching Color Mode or
  Bar Texture away from Custom now closes the space its sub-settings left
  behind, on Group Settings, the bar editor, and the Visuals tab alike,
  instead of leaving an empty strip in the middle of the panel.
- **`/bw bug` now records more of a group's setup.** The pasted report now
  includes each group's Background and Border Opacity and, for auto-tracking
  groups, its tracking setup, plus several addon-wide display toggles it had
  been leaving out. This only affects what a bug report shows, not anything
  you see in game.
- **Dragging a bar to reorder it now tells you why it's refused in a sorted
  group.** A group sorted by remaining time, alphabetically, or As They Come
  decides its own bar order, so dragging couldn't do anything useful there;
  it now says so instead of the drag silently going nowhere. Switch that
  group's Sort Mode to Manual to drag bars by hand.
- **A bar set up by spell ID now shows its real name.** A bar you configured
  by typing an ID instead of a name used to show blank, or whatever
  placeholder name it started with, both on the bar and in the Bars tab
  list. It now shows the spell's own name instead, so you can tell what
  every bar tracks at a glance.
- **Groups can now set Glow on Ready, Pulse on Ready and Linger Time for
  every bar at once.** A new Custom Bar Effects option on the Groups tab
  applies these to the whole group in one go instead of setting them bar by
  bar, and it is the only way to turn them on for an auto-tracking group,
  which has no bar list of its own to set them on.
- **Sparkle Alert can now warn by percent, and turn the bar a colour of your
  choosing instead of just flashing it.** A new Alert When setting picks
  between a fixed number of seconds and a percent of the buff's full length,
  so the same warning still means something on a 30 minute buff instead of
  disappearing into its last sixth. A new Alert Style setting picks Sparkle,
  Colour, or Both, with an Alert Colour swatch for the colour you want.
  Existing bars with only Sparkle Alert ticked keep behaving exactly as they
  do today.

---

### v2.3.0

**A clearer group-visibility rule and a friendlier auto-tracking duration
slider.** Locking your frames no longer hides an empty group's name out from
under Hide When Inactive, and the slider that limits which buffs an
auto-tracking group picks up now reads in real units, has a clearer name, and
reaches a full hour.

- **The duration slider (Groups tab, auto-tracking) now shows minutes and
  seconds instead of a bare number.** It reads in seconds underneath, but
  nothing on screen said so, leaving a raw number like "300" with no way to
  tell what unit it meant. It now shows "No limit", "45s", "5 min" or
  "7 min 30s" as you drag it, with the same wording at both ends of the
  track, and the tooltip no longer needs to explain that 0 means "show
  everything" - the slider says it directly. Sliders can now take an
  optional `format` function to render their value and end labels in real
  units; every other slider is unchanged.
- **Renamed Skip Longer Than to Skip If It Lasts Over, and raised its
  maximum from 30 minutes to 1 hour.** It was reported as a bug that a buff
  with 10 minutes left did not show at a 12 minute setting - it was working
  as designed, but nothing on screen said the setting goes by a buff's full
  length, not the time left on it, so the tooltip now says so directly,
  with an example. The old 30 minute ceiling also meant a 30 minute buff
  could never be admitted, since the test is "longer than this" and 1800 is
  never longer than 1800; the new one hour ceiling gives it room to spare,
  with the step still 30 seconds across the wider range.
  `ns.FormatSettingDuration` (Utils.lua) reads naturally past the old cap
  too: "1 hour", "1 hour 30 min", and so on.
- **Group Hide When Inactive now also decides whether an empty group's
  frame stays on screen.** An auto-tracking group with nothing on the unit
  hides every slot; that used to take the whole group frame with it, name
  and all, the moment Lock All Frames was ticked, because the carve-out
  that kept it up only applied while frames were unlocked. Show Group Name
  only draws a title inside a group that is already visible, so it could
  never rescue a group the lock state had just hidden. Untick Hide When
  Inactive on the group and it now stays up, locked or not, so its name
  stays visible; tick it and the group hides whether locked or unlocked.
  Leaving it alone keeps today's behaviour exactly: unlocked stays up,
  locked hides.

---

### v2.2.4

A single fix: Background Opacity 0 no longer gets ignored on empty groups.

- **Empty groups now honour Background Opacity 0 once they have been
  placed.** A group with nothing in it (an auto-tracking group with nothing
  currently on the unit, or any group with no bars) was always drawn as a
  solid black box, regardless of what its own Background Opacity slider said
  - fine for a brand-new group still sitting at the screen centre, so it can
  be found and dragged, but wrong for a group you had already positioned and
  turned transparent on purpose. Only a group that has never been moved
  keeps the solid fill now; once it has a real position, its own slider is
  respected even while empty. Border Opacity was already correct.

---

### v2.2.3

A single fix: groups no longer shift when the layout is rebuilt.

- **Groups stay put when you delete another group.** Deleting a group rebuilds
  every remaining one, and a group whose anchor did not match its growth
  direction was re-pinned from the wrong edge and moved up (or down) the screen
  by roughly its own height, keeping the new spot afterwards. Taller groups moved
  further. Grow-up groups and groups that had been through `/bw reset` were the
  ones affected. They now land exactly where you left them, and a group already
  anchored correctly is still left alone, so nothing drifts on the normal path.

---

### v2.2.2

Fixes
- **Auto-tracking groups are no longer offered the starter prompt.** A group set
  to Auto Track holds a real layout worth protecting - it fills itself from
  buffs or debuffs on a unit, so its saved bar array stays empty by design. The
  first-login prompt now recognises this and no longer offers to add a starter
  profile on top of it.

### v2.2.1

Fixes
- **Background Opacity set to 0 on an auto-tracking group now actually shows
  nothing behind the bars.** It was stuck showing a solid black panel
  whenever the group had anything in it, because the code used the group's
  hand-added bar list to decide whether it was empty, and an auto-tracking
  group never has any of those. Out of combat it looked fine, but only
  because the group hides entirely once it has nothing left to show.

### v2.2.0

**Groups that fill themselves.** Point a group at all buffs or all debuffs, on
you or on your target, and it shows whatever is there without you naming a
single spell. That means a bar for the boss debuff you have never seen before,
or the trinket proc you did not know to look for.

- New **Auto Track** setting on the Groups tab, with four choices: all buffs on
  player, all debuffs on player, all buffs on target, all debuffs on target.
- **Skip Longer Than** keeps food, flasks and raid buffs out of the way, so the
  group holds the short-lived things that matter in a fight. It goes by how
  long the buff lasts in total, not how much is left.
- **Include Always On** brings in things with no timer, like class buffs and
  tracking, which are skipped by default. They sit in a fixed block above the
  rest of the group instead of shuffling around.
- **Max Bars** caps how many show at once. The soonest to expire win.
- **Only Mine** limits the group to your own casts. On by default for target
  groups, off for groups watching yourself, so a debuff someone else put on you
  still shows.
- **Skip Spells I Already Track** leaves out anything a bar in another group
  covers, so the group only holds what you have not set up yourself. Off by
  default, so nothing is hidden unless you ask for it.
- **Keep Bars In Place** stops the bars reordering as timers count down: each
  one stays put for as long as it lasts, and only fading frees its spot for
  something new. Off by default.
- Bars you added by hand are kept while a group fills itself, and come back
  unchanged when you set Auto Track to Off.
- **Alt-click a bar's icon** to hide just that spell from its own group,
  without hiding it everywhere else. The new Hidden In This Group list under
  Auto Track shows what you have hidden per group, so you can bring one back
  or clear the lot.
- Fixed the Hidden In This Group list clipping its first line and the first
  letter of each hidden spell against the left edge of the panel.
- Auto Track now has its own **[?]** help link right on the Groups tab, and
  its answer moved into its own Help section instead of being filed under
  Conditions & Visibility, where nobody thought to look for it.

**Bars that light up instead of counting down.** A new display option for any
bar, not just auto-tracked ones.

- New **Show as On or Off** bar setting: the bar fills while the tracked thing
  is active and sits empty the rest of the time, with no countdown. Set it per
  bar, or for a whole group at once with the new Bar Style dropdown under Bar
  Overrides, so a catch-all group can read as a panel of lights.

**Straightened up the settings panels.** Headers, dropdowns, toggles and
sliders across the Groups, Bars, Visuals and General tabs now line up
consistently, including the Icon and Bar Opacity sections on the Visuals tab
that had drifted noticeably out of column.

**More room on the group sliders.** For building either larger layouts or
compact icon grids.

- **Width** now goes down to 10 px (was 50) and up to 600 px (was 400).
- **Scale** now goes up to 3.0 (was 2.0).
- **Columns** now goes up to 10 (was 6).

**A fourth Sort Mode: As They Come.** A bar takes its place the moment its
spell fires and holds that spot for as long as it lasts; when one above or
below it drops off, the rest close up. Pairs well with Keep Bars In Place on
an auto-tracking group, since that setting keeps each aura on the same slot
and this one decides where that slot draws.

**Show Icons Only for any group.** A new Bar Overrides tickbox draws a plain 
grid of spell icons instead of bars, no bar, background or text underneath, on 
a hand-made group as well as an auto-tracking one. Size the icons with the 
Width slider (now up to 600 px) and lay them out with Columns (now up to 10), 
for a compact cooldown or buff tray.

**A bigger, coloured stack count.** Two new settings on the Visuals tab,
beside Show Stack Count: **Stack Text Size** to match it to your icon size,
and **Stack Text Colour** to give it its own colour. Both default to how it
already looked, so nothing changes until you move them. The size slider now
goes up to 32 (was 24), and a new **Custom Stack Text** toggle lets a whole
group, or a single bar, use its own size and colour instead of the
addon-wide default, the same way Custom Bar Colour already works.

### v2.1.1

A full read-through of the addon, and the fixes that came out of it. Two of
these could lose your layout, so this one is worth taking.

Your layout is safer
- **Restoring no longer throws away what you had.** `/bw restore` swapped your
  current layout for the last backup and kept no copy of it, so restoring by
  mistake was permanent. It now backs up first, which also means running it
  twice takes you back.
- **Delete asks about one group and deletes that one.** If you clicked a
  different row while the confirmation was open, the click won and the wrong
  group or bar was deleted. Deleting also takes a backup now, so `/bw restore`
  brings it back.

Fixes
- **The Bar Control page no longer comes apart.** Deleting a group could leave
  the list, buttons and settings stranded in the corner of the screen, away from
  the settings window, until you added another group or reloaded. It happened
  whenever a list dropped from 7 items to 6.
- **The Enabled tickbox works.** Unticking it hid the bar until the next refresh
  or login, then the bar came back and kept its place in the group.
- **Settings boxes show the group or bar you actually picked.** Selecting a
  second group or bar left the previous one's tickboxes on screen, so the panel
  could describe settings that were not set.
- **A permanent buff with Linger no longer freezes a bar** at "0.0" until you
  reload.
- **Only Mine now works on buff bars** as it always has on debuffs.
- **`/bw enable` brings your bars back** after logging in disabled, instead of
  showing nothing until a reload.
- **`/bw reset` really does reset positions** - it said so but did nothing.
- **Bars stop swallowing mouse clicks** after you unlock and re-lock frames.
- **Changing a group's Scale no longer moves it** across the screen.
- Per-group Text Format now applies to combo point, rune, soul shard and runic
  power bars too, and its dropdown is the right width.
- Priest starters tracked Weakened Soul as a buff, so the bar never fired.
  Healer starters watched heal-over-time effects on the healer instead of the
  target, so a Resto druid's Lifebloom bar never lit up. Adding a class starter
  can no longer push you past the group limit.
- Help text still described the old menus (a "General tab", a "Statistics tab",
  a left/right layout that no longer exists).
- `/bw restore`, `/bw importv1` and `/bw commtest` were real commands that
  appeared in no list. They do now.

Changes
- **A group's Hide When Inactive now controls the whole group.** Ticking it
  hides every bar in the group; unticking it keeps them all visible even where
  individual bars are set to hide. Leave it alone and each bar decides for
  itself, as before. Previously it could only add hiding, so a group whose bars
  each had the box ticked could never be revealed from the group setting.
- **A new group is visible straight away**, in the middle of the screen with a
  solid background, so you can see it and drag it where you want before adding
  any bars. It goes back to your normal background once it holds a bar.
- **"Show Empty Bar" has been removed.** Nothing ever read it, so it had never
  done anything and only muddied its neighbour, Hide When Inactive.

Under the hood
- Removed dead code and several places where the same idea was written two
  different ways; tidied a hot combat path. No behaviour change from those.

### v2.1.0

Stack counts you can actually see, and two settings that no longer force an
all-or-nothing choice.

- **Stack counts show on the bar's icon.** Anything stacking two or more times
  (Sunder Armor, Deadly Poison, Lightning Shield, a stacking proc) now shows the
  number in the corner of its icon, whatever text format you use. There is a
  "Show Stack Count" switch on the Visuals page if you would rather not have it.
- **Text format per group.** Groups now have their own Text Format under Bar
  Overrides, so one group can show stacks or names only without changing every
  other bar you have. Leave it on Inherit to follow the Visuals page as before.
- **Hide When Inactive per group.** A new switch in Group Conditions hides every
  bar in that group while it has nothing to show, instead of ticking the same
  box on every bar. Bars set to hide on their own still do.
- **Fixed:** a permanent aura (one with no duration) showed the stack count it
  had when it first appeared and never updated it.

### v2.0.2

A single fix: groups no longer wander off on their own.

- **Groups stay where you put them.** A group with a scale other than 100%
  crept towards the bottom-left corner a little further every time one of its
  bars updated (entering combat, a buff coming and going, changing a visual
  setting), and the drifted spot was saved, so it kept its new home after a
  reload. Groups now hold their position at any scale and in either growth
  direction, and dragging one saves exactly where you dropped it.
- **One-off:** positions that already drifted cannot be recovered, so drag each
  affected group back where you want it once after updating. It will stay there.

### v2.0.1

A fixes-and-polish patch: more accurate Activity counts, tidier menus, and a
minimap crash guard.

Fixes
- **Activity "Procs" counts no longer creep up on reload.** Effects that were
  already active when you logged in or reloaded used to be counted again as if
  freshly triggered, inflating the all-time totals. They now count only when
  they genuinely fire. Existing totals are left as they are; use Reset All on
  the Activity tab for a clean baseline.
- **The minimap button no longer errors** when a second copy of BarWarden is
  present; it steps aside cleanly instead of failing to load.

Polish
- **Long uptimes now show days** (e.g. "4d 20h" instead of "116h 46m"), so the
  Activity column stays readable and fits at the smallest window.
- **Tidier menus.** The Activity controls, the Groups Add / Delete / Dupe
  buttons, and the Visuals controls now line up cleanly with the lists and
  panels around them.

Under the hood
- Removed an unused file; added tests around the Activity counting fix.

### v2.0.0

A ground-up rework of the settings menus, safer upgrades, and a round of
tracking fixes. Your existing bars, groups, profiles, and settings carry
straight over; nothing to re-import.

Menus
- **Roomier layout.** The cramped single window with tabs is gone. Each area
  now has its own focused page under a "BarWarden" tree in Interface Options:
  Bar Control, Visuals, Profiles, Activity, and Help. The old General options
  (Enable, Lock, minimap, update alerts) and the runnable slash-command list
  live on the main BarWarden page.
- **Everything scales with the window.** Panels, lists, and text re-wrap and
  reflow to the window width instead of clipping at a fixed size, and controls
  share one sensible maximum width so they never stretch absurdly wide.

Bar Control
- **Groups and Bars in one page** with tabs at the bottom. The lists sit full
  width and grow with your group/bar count; the settings and editor sit below.
- **Drag a row to reorder** groups or bars (a click still selects; the Up/Dn
  buttons still work).
- **Per-group looks.** A group can now override the **bar texture** and give
  its bars a **custom colour**, leaving everything else on the addon-wide
  default from the Visuals page.

Upgrades no longer lose bars
- The first-login starter prompt can never overwrite an existing layout.
- Every layout source (your live save, loaded profiles, imported strings,
  starter presets) runs through one migration path that fills in new defaults
  without ever touching what you configured.
- A snapshot is taken before any migration or reset, so a bad change is
  recoverable with `/bw restore`.
- **Reset to Defaults** now backs up first and no longer deletes your saved
  profiles (it resets the live layout only).

Tracking fixes
- **Stack counts** now show on buff/debuff bars using a "Stacks" text format
  (Sunder Armor, Deadly Poison, Lightning Shield, and the like).
- **Only Mine** now counts auras applied by your **pet or your vehicle** as
  yours, not just direct casts.
- **Permanent auras** (no duration, e.g. a paladin aura) now show as a full
  "present" bar instead of not showing at all.
- Short **item cooldowns** are no longer hidden.

Polish
- **Tooltips** on every slider, checkbox, text field, and dropdown that needed
  one; hover the Activity column headers to see what each counts.
- The **Help** page has a "Back" button that returns you to the section you
  came from after a `[?]` jump.
- Confirmation popups and the **colour picker always open on top** of the menu.

Under the hood
- Additive per-character `backups` ring and UI-state keys; downgrade-safe.
- Hardened the scan loop so an error can't freeze the layout; assorted
  reliability fixes across events, layout, and the data layer.

### v1.12.0

Closer alignment with the sibling addon EbonClearance, plus a new update
reminder so you know when you are behind.

- **Update reminder.** BarWarden now tells you in chat when someone in
  your group or guild is running a newer version, with a copyable
  download link. There is an off switch on the General tab ("Notify me
  about updates"), and `/bw commtest` self-checks the messaging.
- **Shared look.** The panel now uses the same colour palette as
  EbonClearance - the `[?]` help icons and slash-command emphasis are the
  family yellow - so the two addons read as one product family.
- **Richer minimap tooltip.** Hovering the minimap button shows the
  version, on/off status, and how many bars and groups you have.
- **Bug report polish.** The `/bw bugreport` window floats above the
  options panel instead of behind it, and includes the source link.
- **Help tab reflow fix.** Help answers now wrap to the live panel width
  instead of being clipped when the Interface Options window is sized
  differently from the addon's options panel.
- **Under the hood.** Lint/format configs (`.luacheckrc`, `stylua.toml`),
  a syntax-check CI gate, a hygiene test, and contributor docs
  (`ARCHITECTURE.md`, `CODE_REVIEW.md`). No gameplay impact.
- **Schema:** one additive account-wide-style field
  `global.versionAlerts` (default on), downgrade-safe.

### v1.11.0

In-game help. A new Help tab answers the common questions without leaving
the game, and the settings now point you to it.

- **Help tab.** A collapsible FAQ covering Getting Started, Tracking
  Modes, Conditions, Visuals, Profiles, the Activity Tracker, and
  Troubleshooting. Click a section to expand it; your open and closed
  choices are remembered.
- **[?] deep-link icons.** Small [?] icons next to the main section
  headers (Groups, Bars, Conditions, Bar Visuals, Class Starters, and the
  Activity Tracker) jump straight to the matching answer, expanding its
  section and scrolling to it.
- **Clearer empty states.** Lists that used to render blank now say what
  to do: an empty group list, an empty bar list, the Activity Tracker
  before it has data, and a search that matches nothing.
- **Runnable slash commands on the General tab.** The General tab now
  lists every slash command with a Run button next to it, so you can fire
  a command from the panel without typing it.

### v1.10.6

Housekeeping release: contributor docs and repository hygiene, aligning
BarWarden with the design language and conventions of the sibling addon
EbonClearance. No gameplay or behaviour change.

- **Attribution and licensing.** Added a `LICENSE` (source-available
  attribution license) and a 4-line attribution header to every shipped
  Lua file.
- **Contributor docs.** Added [docs/ADDON_GUIDE.md](docs/ADDON_GUIDE.md)
  (the authoritative architecture + conventions guide), a slimmed
  [CLAUDE.md](CLAUDE.md) agent entry point that points to it, this
  `CHANGELOG.md`, and [NOTICE.md](NOTICE.md).
- **Refactoring-trap markers.** Tagged intentional-but-looks-wrong code
  with grep-able `EC-TRAP:` markers (the optional-library
  graceful-degradation guards, the global-cooldown ignore rule, the
  double `InterfaceOptionsFrame_OpenToCategory` call, the bare
  `GetItemCooldown`, and the 3.3.5a group queries) and indexed them in
  the guide.
- **No em dashes.** Removed every em dash (U+2014) from the repository
  and established the no-em-dash rule as a project convention.

### v1.10.5

Panel byline and provenance fingerprinting: the options panel now shows
an author/source byline, and the addon stamps provenance globals
(`BARWARDEN_*`, `__BarWarden_*`) including a version watermark.

### v1.10.4

Activity Tracker improvements: sortable stats-screen columns (click a
header to sort, click again to flip direction), spell-icon tooltips in
the list, and a richer category filter.

### v1.10.3

Fixes: cancel the glow-on-ready effect when a spell is recast before the
glow finishes, and correct the capitalisation of "Hunger For Blood".

### v1.10.2

LibDBIcon-managed minimap button, drag-reorder wire-up, and a
token-cache leak fix.

### v1.10.1

Performance pass, a DB-migration fix, the standalone test suite, and
live auto-refresh on the Activity Tracker stats panel.

### v1.10.0

LibSharedMedia support (textures and fonts from any LSM-aware addon),
per-group growth direction (up or down), bar copy/paste between groups,
and assorted UI polish.

### v1.9.3

Performance, code-quality, and UI-consistency pass.

### v1.9.2

Bar-pool integrity fixes, performance, an icon fix, and profile guards.

### v1.9.1

Spec-aware starter profiles, spell-icon tooltips, and a first-login
welcome dialog offering to load a starter.

### v1.9.0

Per-group visibility conditions, pulse-on-ready (icon flash at screen
centre when a cooldown completes), the auto-starter prompt, and inline
help tooltips on per-bar and visual settings.

### v1.8.1

Smart visibility conditions (hide while mounted / resting / in a vehicle,
or show only inside instances) and a `showAll` visibility fix.

### v1.8.0

UI polish and a README refresh.

### v1.7.0

Activity Tracker: passive monitoring of every cooldown, buff, debuff,
enchant, and totem on your character, replacing the old bar-driven stats.
Discover what to track, then create bars directly from the stats screen.

### v1.6.0

Code-quality refactor, glow / hide bug fixes, and performance
improvements.

### v1.5.0

Documentation pass (initial contributor guide, root-cause logs) and
README polish.

### v1.4.0

Declarative options schema (the `ns:BuildSettings` walker), a responsive
Bars tab layout fix, and UX polish.

### v1.0.0 - v1.3.0

Initial release series. The first public builds and rapid iteration on
the core feature set: timer bars for cooldowns, buffs, debuffs, procs,
and items; groups with multi-column layouts and sorting; per-bar and
per-group conditions; account-wide profiles with export/import; the
class starter profiles; aura equivalency groups; and the tabbed Interface
Options panel.
