# BarWarden -> EbonClearance design-language alignment (plan of attack)

> Hand-off note for a fresh agent: execute this plan with the BarWarden repo
> (`C:\Users\chris\Wow Addons\barwarden`, branch `main`) as your working
> directory. Use EbonClearance at `c:\Users\chris\Wow Addons\EbonClearance`
> as the read-only reference for the design language / conventions. Deploy to
> the `G:\Project Ebonhold\Ebonhold\Interface\AddOns\BarWarden` copy for
> in-game testing. Do NOT commit until a change is confirmed in-game. There
> is a pre-existing uncommitted change to `Widgets.lua` in this repo (the
> owner's WIP) - leave it alone unless told otherwise.

## Context

We want a singular design language and contributor discipline across our addons. An audit of **BarWarden** (a mature, same-author WoW 3.3.5a bar/cooldown tracker) against **EbonClearance** (EC) found it is already **~85% aligned**: it lives in Blizzard Interface Options, uses an EC-style widget factory + declarative option schema, matching design tokens (even EC's olive-grey byline colour), brief jargon-free text, live-reactive settings, a near-identical event hub, and the same minimap / bug-report patterns. Zero em dashes exist in its Lua.

The real gaps are **process/docs/hygiene plus one UX feature**, not the shipped code. Scope is **Tier A only**: design language + docs + hygiene. Explicitly OUT of scope for now: lint/format configs, CI, test suites (Tier B/C), external-library removal, and DB-migration-style conversion (all deferred or not recommended - the libs add real value and BarWarden's versioned DB migration is arguably better than EC's).

**Source of truth:** work in this git working tree (`C:\Users\chris\Wow Addons\barwarden`); the `G:\...\AddOns\BarWarden` folder is the deployed install copy. First step: confirm the working tree matches the deployed copy the audit was based on.

**Reference templates in EC** (`c:\Users\chris\Wow Addons\EbonClearance`): `EbonClearance_HelpPanel.lua` + `EbonClearance_PanelWidgets.lua` (MakeHelpIcon / AddHelpIcon, NS.OpenHelpEntry), the v2.41.3 empty-state work in `EbonClearance_ListWidget.lua`, `CLAUDE.md`, `docs/ADDON_GUIDE.md`, `NOTICE.md`, the per-file attribution header block, and the `EC-TRAP:` convention.

## Guiding principle

EC is the reference; BarWarden adopts EC's conventions so the two read as one product family. Keep BarWarden's tabbed options shell (correct for a bar editor) and its libraries (LSM/LDB/LibDBIcon) - "design language" here means look, wording, help affordances, hygiene, and contributor docs, not internal re-architecture.

## Phase 1 - Hygiene & conventions (quick, low-risk, do first)

1. **Em dashes -> zero.** Replace the 24 U+2014 in `README.md` with hyphens / commas / parens. Repo-wide grep for U+2014 must return zero. Establish the no-em-dash rule (carried into the docs in Phase 2).
2. **Attribution headers.** Add EC's 4-line header (`-- <File> - <purpose>.` / `-- Author:  Serv` / `-- Source:  https://github.com/powerfulqa/BarWarden` / `-- License: see LICENSE; attribution preservation is required.`) to every `.lua` file that lacks it (~30 files). Confirm a `LICENSE` exists; add EC's if missing.
3. **EC-TRAP convention.** Sweep for intentional-but-looks-wrong code (library graceful-degradation fallbacks in `MinimapButton.lua` / `SharedMedia.lua`, the GCD-ignore-under-1.5s cooldown rule, any forced flags, 3.3.5a-specific APIs) and mark each with a grep-able `-- EC-TRAP:` line pointing to its reason. Document the convention in the Phase-2 docs.

## Phase 2 - Contributor docs (mirror EC's set)

4. **`CLAUDE.md`** - agent entry point: one-paragraph what-it-is, the file inventory + load order (read `BarWarden.toc`), conventions (namespace, libs-are-intentional, chat via `ns:Print`, no em dashes, brief player-facing text, EC-TRAP), and a short "read docs/ADDON_GUIDE.md first" pointer.
5. **`docs/ADDON_GUIDE.md`** - prescriptive guide: architecture (Core/DB/Events hub/Bar engine/FrameManager/Options-tabs), the bar lifecycle + conditions engine, the library rationale (why LSM/LDB/LibDBIcon are kept), 3.3.5a gotchas, naming, and a "Gotchas and refactoring traps" section indexing the EC-TRAP sites.
6. **`CHANGELOG.md`** - start a per-release stanza format (current `.toc` version is 1.10.5); backfill notable past versions if feasible, otherwise begin going forward with the next change.
7. **`NOTICE.md`** - acknowledge the shared design language / conventions with EC so the family relationship is documented.

## Phase 3 - Design-language UX parity (the one real feature gap)

8. **Help / FAQ panel + `[?]` deep-links.** BarWarden has tooltip-only help today. Add a **Help tab** to the existing options window (natural fit for its tabbed shell, vs EC's separate sub-panel) populated with ~20-30 FAQ entries (Getting Started, Tracking Modes, Conditions, Profiles, Troubleshooting - much can be lifted from the already-excellent README). Add a `ns:OpenHelpEntry(id)` deep-link and a `MakeHelpIcon`-equivalent `[?]` button (reuse `Widgets.lua`) on the major section headers, deep-linking into the Help tab. This is the largest single item.
9. **Empty-state messaging pass.** Mirror EC's v2.41.3 work: add instructive empty-state lines where lists render nothing - Bars/Groups ("No groups yet. Click Add to create one."), the Activity Tracker stats list ("Activate bars and play to see tracking data here."), and any no-search-match case. Greyed, brief, lead-with-what-to-do.

## Critical files (BarWarden working tree)

- Phase 1: `README.md`, all `*.lua` (headers), trap sites in `MinimapButton.lua` / `SharedMedia.lua` / `BarEngine.lua` / `Trackers.lua`.
- Phase 2: new `CLAUDE.md`, `docs/ADDON_GUIDE.md`, `CHANGELOG.md`, `NOTICE.md`.
- Phase 3: new `Options_Help.lua` (or a Help section in `Options.lua`), `Widgets.lua` (the `[?]` button), `Options.lua` (tab registration), `Options_Bars.lua` + `Options_Stats.lua` (empty states).

## Out of scope (deferred / not recommended)

- Tier B (`.luacheckrc`, `stylua.toml`, Test + Release GitHub workflows, version-injection pipeline) and Tier C (static test suites) - revisit later.
- Removing LibStub/LDB/LibDBIcon/LibSharedMedia (deep, low ROI, LSM adds real media value).
- Converting the versioned DB migration to EC's nil-default style (BarWarden's is arguably better).
- Splitting the tabbed options into separate Interface Options sub-panels (the tabbed shell is correct for a bar editor).

## Verification

- Per phase: `luac -p <changed>.lua` (local syntax). No test suites exist in BarWarden (out of scope), so correctness rides on `luac` + in-game smoke.
- Repo-wide grep for U+2014 returns zero after Phase 1.
- In-game smoke after Phase 3: deploy to the `G:\` copy, `/reload`, confirm the Help tab opens, `[?]` icons deep-link correctly, and empty-state lines show on empty Groups / Stats.
- Standing rule: do not commit until confirmed in-game; then commit to this working tree (branch `main`).
- Each phase is independently shippable; recommended order is 1 -> 2 -> 3 (hygiene and docs are fast and low-risk; the Help panel is the big build).
