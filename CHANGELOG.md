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
