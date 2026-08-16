# Notice - third-party material, shared conventions and prior art

This file documents BarWarden's design lineage honestly, so that any
future "they copied us" or "you copied them" claim has a record to refer
to. Convergence on similar shapes is acknowledged where it exists, and
originality is not claimed where a pattern is shared with a sibling
project or with the broader WoW 3.3.5a addon ecosystem.

---

## X-Perl UnitFrames artwork (GNU GPL v3)

BarWarden's unit frames are drawn with artwork taken from **X-Perl
UnitFrames**, Copyright (C) Zek (zeksie@gmail.com), licensed under the GNU
General Public License version 3. The files were taken from the
[Xperl-Grimfall](https://github.com/Valdstuff/Xperl-Grimfall) fork, which
carries X-Perl's GPL v3 licence and its `## X-License` and `## Author`
metadata intact.

**This is why BarWarden is GPL v3.** The GPL is a copyleft licence: a work
that incorporates GPL-licensed material must itself be distributed under
the GPL. BarWarden shipped under a bespoke source-available attribution
licence through v2.6.0 and relicensed at v2.7.0 as the condition of using
this artwork. See [LICENSE](LICENSE) for what that changed.

Files taken, all from `XPerl/Images/` and unmodified, now in
`Textures/XPerl/`:

| File | Used for |
| --- | --- |
| `XPerl_FrameBack.blp` | The frame and portrait backdrop tile |
| `XPerl_ThinEdge.blp` | Border artwork |
| `XPerl_Highlight.blp` | Highlight overlay |
| `XPerl_Elite.blp`, `XPerl_Rare.blp` | Target classification overlays |
| `XPerl_EyeBall.blp` | Targeting indicator |
| `XPerl_StatusBar.blp` and `XPerl_StatusBar2..10.blp` | Bar skins, offered as "XP Perl v2" and "XP Perl 2".."XP Perl 10" |

The frame geometry (a 16px tooltip-bordered backdrop over a 32px tile with
a 4px inset, and a portrait inset 5px inside its own bordered frame) is
reproduced from X-Perl's `XPerl_BorderStyleTemplate` and
`XPerl_Portrait_Template` so the artwork sits the way its author drew it
to sit.

**No X-Perl code was copied.** `UnitFrames.lua` is BarWarden's own, written
against the same Blizzard 3.3.5a API. X-Perl's XML was read to learn how
its artwork is assembled, which is what the table above records.

A separate reference copy of **DragonUI-Grimfall** was consulted for layout
ideas only. It carries no licence file, so nothing from it - code or art -
is used or shipped. Both reference checkouts are gitignored and never
packaged.

---

## Shared design language with EbonClearance

BarWarden and [EbonClearance](https://github.com/powerfulqa/EbonClearance)
are written by the same author for the same WoW 3.3.5a server. They
deliberately share a design language so the two read as one product
family. BarWarden adopted the following conventions from EbonClearance
rather than claiming them as original:

- **The attribution model.** The source-available attribution license,
  the `## Author:` TOC line, the in-game options-panel byline, and the
  provenance globals (`BARWARDEN_IDENT` / `BARWARDEN_AUTHOR` /
  `BARWARDEN_ORIGIN` and the `__BarWarden_origin` / `__BarWarden_author`
  / `__BarWarden_watermark` form) mirror EbonClearance's
  `EBONCLEARANCE_*` / `__EbonClearance_*` set. This is the prior art the
  [LICENSE](LICENSE) refers to.
- **The option-UI style.** The widget-factory primitives
  ([Widgets.lua](Widgets.lua)) and the declarative settings-schema walker
  ([Options_Builder.lua](Options_Builder.lua), `ns:BuildSettings`) follow
  the same pattern EbonClearance uses for its panels.
- **The `EC-TRAP:` convention.** The grep-able marker that flags
  intentional-but-looks-wrong code carries EbonClearance's `EC-` prefix
  on purpose, so a contributor moving between the two addons recognises
  it. See the trap index in [docs/ADDON_GUIDE.md](docs/ADDON_GUIDE.md).
- **The no-em-dash rule** and the **brief, jargon-free player-facing
  text** discipline are shared house style, applied to both addons.

Where the two addons diverge, it is on purpose and for cause:

- BarWarden **keeps external libraries** (LibStub, LibSharedMedia-3.0,
  LibDataBroker-1.1, LibDBIcon-1.0); EbonClearance ships with none. The
  libraries earn their place here (LSM media value, the standard minimap
  stack) and degrade gracefully when absent. Rationale in the guide.
- BarWarden uses a **versioned `MigrateDB()` / `CURRENT_SCHEMA`**
  migration; EbonClearance uses a nil-default `EnsureDB` style. Both are
  downgrade-safe; BarWarden's is kept for its explicit, testable
  migration path.

---

## Convergent patterns in the 3.3.5a niche

A WoW 3.3.5a addon shares a small, fixed Blizzard API surface with every
other addon on the client. Several shapes in BarWarden are common across
the niche because that API forces them, not because of copying in either
direction:

- A hand-wired event-frame dispatcher mapping events to handler methods.
- An OnUpdate accumulator loop in place of `C_Timer.After` (which does
  not exist on 3.3.5a).
- Aura scans that walk buff/debuff indices 1..40 and break on the first
  nil name.
- The double `InterfaceOptionsFrame_OpenToCategory` call to work around
  the first-call-only-scrolls quirk.
- A LibDataBroker + LibDBIcon minimap button (the de facto standard for
  the period).

Convergence on these shapes is not, in itself, evidence of copying. The
implementations here are BarWarden's own, written against the same
Blizzard 3.3.5a API as everyone else.
