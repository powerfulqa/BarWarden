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
