# Scoranger 0.8 redesign brief

Input for a Claude Design session. Written 2026-09-10 from the owner's words,
against the app as it is on 0.7.4 build 191. Everything in §1 is the owner's
ask; §2–§4 are the grounding a design pass needs and usually does not get.

## 1. The ask, in the owner's words

> The UI is not quite what I want; it's too square; there are too many sharp
> edges. The titles of many of the settings are weird AI-slop phrases instead
> of one or two words labelling a UI element like normal. I like the colour
> scheme but there are many weird inconsistencies and ugly things in the
> settings menus. There is generally too much white space when some menus open
> and take up half the screen. The way that many button clicks result in a
> full-screen-width dropdown that pushes the rest of the UI down is very
> awkward. I want the UI to be more welcoming and friendly — warm and cosy.
> Always clear what you are doing. Lots of attention to detail of alignment
> and UI element centring. I also want the UI to be more distinctive and less
> generic, with sass and uniqueness. Deep consideration of consistency across
> menus, settings and options; the way modals are used — I'm generally
> anti-modal / anti-popup and would prefer permanent homes for things like the
> play transport and mixer, which can go at the bottom and, in performance
> mode, be hidable with a subtle button.

### The deliverable

**Five competing options**, each presented across **the same ten screens and
workflow steps** (§3), so they can be compared like for like. For each option:
a one-paragraph stance, the ten screens, and a components sheet showing how
its rules produce them. One of the ten must be a *sequence* (a workflow, not a
screen), so the transitions and the "always clear what you are doing" claim
can be judged.

### What must survive

- **The colour scheme.** Paper, ink, one clay accent (§2.1). The owner likes it.
- **Score first.** The score is the ground; everything else is over or beside it.
- **The arrangement numeral** (`#1`) as the app's identity mark.
- **No login gate.** Sharing needs an account; nothing else does.
- **Accessibility.** 44pt hit targets, Dynamic Type through AX3, VoiceOver
  labels on every control. The current system honours these; a redesign that
  does not is not a candidate.

### What is explicitly up for grabs

- **Corner radii, edges, weight.** "Instrument panel" chose 2–3pt corners and
  hard 1pt edges (§2.2). The owner now calls that too square. Rounder, softer,
  warmer is the direction; how far is the design's call, per option.
- **Every label.** One or two ordinary words, the way a settings screen
  normally reads (§4 lists the current ones).
- **Every disclosure.** Full-width bands that expand in place and push the
  page down (the current "no modal" answer) are the thing the owner finds
  awkward. Anti-modal still stands — so the options need a *third* way.
- **Where the transport and mixer live.** Permanent home at the bottom; in
  performance mode, hidden behind a subtle affordance.
- **Empty space.** Menus that open to half a screen for three rows.

## 2. What exists today

### 2.1 Tokens (`ios/Scoranger/DesignSystem/Theme.swift`, `design/DESIGN_SYSTEM.md`)

Surfaces: paper `#FFFFFF` (the score page, the only pure white), ground
`#F4F0E8`, panel `#FAF7F1`, well `#EFEAE0`, band `#F1ECE2`. Ink: `#1A1917`,
`#6B655C`, `#8A8378`. One accent: clay, with a `clayStrong` for small text.
Light only, by decision.

Type: Space Grotesk for titles and numerals, Inter for prose, IBM Plex Mono for
machine values. A compressed, weight-driven ladder, 10–34pt.

### 2.2 The current direction, and where it grates

*"A warm paper-and-clay instrument panel, score-first, with the arrangement
numeral as the app's identity."* Flat fills, hard 1pt edges, 2–3pt corners,
silkscreen band headers (tracked-out caps), chunky square toggles, the engine
state as a real LED.

The owner's complaint maps onto this precisely: the instrument-panel metaphor
delivered squareness and hard edges as a *feature*. The warmth is in the
palette and not yet in the forms. The band headers read as machine labels
rather than as a welcome.

### 2.3 Documents worth reading before designing

- `design/DESIGN_SYSTEM.md` — the spec as approved; the components list (§7)
  is the inventory to redesign.
- `design/NAVIGATION_SYSTEM.md`, `design/NAV_MODAL_FREE_0.4.2.md` — why there
  are no modals and what replaced them (the in-place bands the owner now
  finds awkward). The reasoning holds; the form does not.
- `design/MIXER_WINDOW.md` — the mixer as a floating window you can pick up.
  The owner now wants it parked at the bottom instead.
- `design/PLAYBACK.md`, `design/CONTINUOUS_VIEW.md` — the transport and the
  scroll-mode strip, including the follow rule (line parked a quarter in).
- `design/IPHONE_0.6.14.md` — the phone layout and its metrics rules.
- `design/FIREBASE.md` §6A — sharing as a field on a set list: one kind of set
  list, a share button on its row, a two-people glyph once shared.

### 2.4 Photographs of the app as it stands

`ScorangerUITests/DesignerSweep` photographs every screen at several widths and
Dynamic Type sizes. Run it once and hand the folder to the design session:

    cd ios && TEST_RUNNER_SCORANGER_SHOT_DIR=/path/to/shots \
      xcodebuild test -project Scoranger.xcodeproj -scheme Scoranger \
      -destination "platform=iOS Simulator,name=iPad Pro 11-inch (M4)" \
      -only-testing:ScorangerUITests/DesignerSweep

Draw the five options against these, not against memory.

## 3. The ten screens and steps

Chosen to cover every surface and every kind of interaction, and to include
the places the owner named.

| # | Screen or step | Why it is in the ten |
|---|---|---|
| 1 | **Library — Pieces** (list, search, sort/filter, edit) | The home. Full-width rows, the numeral, the bands. |
| 2 | **Library — Set lists** with a shared row | The share glyph, the two-people glyph, the `+`, the `☰`. |
| 3 | **A set list's own screen** | Running order, rename-in-place, people, leave/delete. Half-screen disclosures live here. |
| 4 | **Score, reading, paged** | The permanent ground. Top bar, page chip, thumbnails rail. |
| 5 | **Score, playing, scroll mode** with the transport and mixer | The owner's stated home for both: bottom, permanent, hidable in performance. |
| 6 | **Performance mode** | Everything hidden but the score; the subtle way back. |
| 7 | **Settings** and one section (Account) | The labels, the whitespace, the sign-in. |
| 8 | **The arrangement `☰` screen** (versions, parts, details) | Deep disclosure; the current expand-in-place pattern at its worst. |
| 9 | **Sequence: share a set list** — tap share → progress → share sheet → recipient taps link → "Add to my set lists" → row appears | The workflow; "always clear what you are doing". |
| 10 | **Sequence: import a PDF and open it** — Import → progress → the scan opens → OMR offered | The other workflow; progress and state. |

Each option shows all ten at iPad width; options may add a phone variant of
1, 4 and 5 where the answer differs.

## 4. The labels as they stand

Every band header, row and button title currently shown in settings and the
management screens, verbatim, so the rewrite has the real list. The owner's
rule: one or two words, the way a settings screen normally reads.

**Settings:** Account · Send my address · Sign out · "Signing out keeps your
library on this iPad. Nothing is deleted." · Paste an invitation · Reading ·
Titles · About · Diagnostics · On-device engine · Remote engine · PDF
conversion (OMR) · Chat model · Save · Clear

**Piece and set list screens:** Pieces · Or · New piece · Remove from piece ·
In these set lists · New set list · Play from the top · Running order · This set
list · Add arrangements · People in this set list · In this set list · History ·
Parts · "No parts recorded for this version."

Some of these are fine. The ones the owner means are the sentences, the "Or",
and the headers that describe rather than name.

## 5. Constraints on the options

- **Anti-modal is a principle, not a style.** No sheets or popups as the
  primary pattern. But in-place expansion that shoves the page is out too.
  Each option must state its disclosure pattern in one sentence.
- **The transport and the mixer have a home**, at the bottom, together or
  adjacent; performance mode hides them behind one subtle control.
- **Alignment and centring are first-class.** Every option's components sheet
  states its grid and its rule for centring a label in a control.
- **Warm and cosy, distinctive, with sass.** Not generic iOS, not a Material
  clone, not the current instrument panel. Five genuinely different stances.
- **Everything in the ten screens is real.** No invented features; every
  control shown exists today or is in `design/FIREBASE.md`'s 0.7 plan.

## 6. What to hand back

For each of the five options: the stance, the ten screens, the components
sheet, and a short note on what it would cost to build against the current
SwiftUI code (which components change shape, which change only tokens). The
owner picks one, or a combination; then `design/DESIGN_SYSTEM.md` is rewritten
as the spec for 0.8 and the tokens in `Theme.swift` follow it.
