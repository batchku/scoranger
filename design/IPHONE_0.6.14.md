# iPhone compatibility — 0.6.14

Target: iPhone 15 Pro, 393×852pt. Portrait safe area **393×759**; landscape safe
area **734×372** (59pt of Dynamic Island inset each side, 21pt home indicator).
Design only. Steps 1–3 of the loop: the surface, first-pass wireframes for the
five highest-traffic screens, and my own ratings.

## 0. The finding that shapes the effort

**The score view does not exist on iPhone.** `ContentView.scorePane`
(`ContentView.swift:497`) branches on `isCompact` and substitutes
`ScoreZoomView` — a **36-line `PDFView`** with no page model, no ink, no lasso,
no playhead, no geometry:

> `/// Compact-width (iPhone) score view: a pinch-zoomable, vertically scrolling`
> `/// PDFView. No pencil markup here — that stays on the iPad's ScorePagesView.`

Everything *around* it still renders: the top bar, the 96pt thumbnail strip, the
transport, the ink bar, the mixer, the playhead's lane. So on a phone today the
thumbnail strip drives `state.pageIndex` (`ContentView.swift:281`) and the
PDFView ignores it — **tapping a thumbnail does nothing**. The layout control
offers page / spread / continuous over a view with one scroll mode. The ink bar
floats over a canvas that cannot receive ink.

So this is not a re-layout job. Item one is **one canvas everywhere**: retire
`ScoreZoomView`, run `ScorePagesView` at compact width, and let every other
control on this list mean what it says. Nothing below rates above 2 until that
lands, because the chrome is currently honest about an iPad and lying about a
phone.

Second global finding: `openScore`'s compact branch is an **empty `if`**
(`ContentView.swift:696`) — a stub for one-pane-at-a-time navigation that was
never written.

Third: the mixer decides compact by `geo.size.width < 700`
(`MixerPanel.swift:807`). iPhone **landscape is 852pt wide**, so it fails that
test and tries a six-strip floating window on a 372pt-tall screen. Compact must
be decided by size class and container height, never raw width.

## 1. The surface

Status is what a phone gets **today**. ✗ = broken or absent, ~ = renders but
wrong or cramped, ✓ = works.

### A · Library (root)

| # | Screen / interaction | Today |
|---|---|---|
| A1 | My Library: title, count, segment (Pieces/Setlists/Books) | ~ |
| A2 | Action row: Import · New · New set list | ~ |
| A3 | Utility row: Sort · Filter · Edit · Settings · engine chip | ~ |
| A4 | A–Z rail (name sort only) | ✓ |
| A5 | Rows: piece / setlist / book, each with `☰` | ✓ |
| A6 | Row `☰` — push or expand-in-place (`RowMenuBehaviour`) | ✓ |
| A7 | Tap-to-edit inline rename | ~ |
| A8 | Edit mode: selection, bulk action bar | ~ |
| A9 | Two-step delete + undo bar | ✓ |
| A10 | Notice bar | ✓ |
| A11 | Bundle offer bar (import an envelope) | ~ |
| A12 | Import progress rows | ✓ |
| A13 | Empty state | ✓ |

### B · Pieces and arrangements

| # | Screen | Today |
|---|---|---|
| B1 | Piece screen: arrangements, New arrangement, Import into piece, Delete | ✓ |
| B2 | Arrangement screen: Move · Set lists · Duplicate · Versions · Parts · Details · Delete | ✓ |
| B3 | Move to piece (+ New piece, Remove from piece) | ✓ |
| B4 | Set lists for this arrangement | ✓ |
| B5 | Versions list | ✓ |
| B6 | Parts and ranges | ✓ |
| B7 | Details: title, composer, arranger, slug + save | ~ |

### C · Set lists

| # | Screen | Today |
|---|---|---|
| C1 | Set list: running order, steps, Play | ✓ |
| C2 | Add arrangements | ✓ |
| C3 | Reorder (button-driven, no drag) | ✓ |
| C4 | Set list playback context in the transport (prev/next) | ~ |

### D · Books, import, OMR

| # | Screen | Today |
|---|---|---|
| D1 | Books segment | ✓ |
| D2 | Book screen: page thumbnails, from/to page, starts/ends here, extract | ~ |
| D3 | Folder import: the plan, then commit | ✓ |
| D4 | System file importer | ✓ |
| D5 | Make editable / OMR progress chip (bar or canvas) | ✓ |

### E · Score view — the bulk of the work

| # | Screen / control | Today |
|---|---|---|
| E1 | Top bar: ✕ · title block · versions · #N · mode chip · Edit · Ask · layout · performance · transport · OMR · … | ~ |
| E2 | **Canvas: paged / spread / continuous, zoom, pan** | **✗** |
| E3 | Page turn (gesture and zones) | ✗ |
| E4 | Pencil modes: read / edit / performance | ✗ |
| E5 | Ink bar (movable), tools, undo | ✗ |
| E6 | Lasso → selection chip → carry note / place / confirm → chat | ✗ |
| E7 | Thumbnail strip (96pt) | ✗ |
| E8 | Transport: play · rewind · bar · tempo · unavailable / resolve / draft | ~ |
| E9 | Mixer window: strips (mute/fader/LED/sound), tempo, scrubber, picker | ✗ |
| E10 | Playhead + page follow + sync chip | ✗ |
| E11 | Live counters (pages, bar) + artifact marker | ~ |
| E12 | Performance mode bar | ~ |
| E13 | Title menu: arrangement switcher · version switcher · all versions | ~ |
| E14 | Options (…): chord symbols · annotations · selection & chat · transpose · details · share & export · settings · make editable · performance · transport | ✓ |
| E15 | Share & export: formats, send to another iPad | ~ |
| E16 | Chord adjustments: size, bigger / smaller | ~ |
| E17 | Chat panel: input, model, send, grip, dictation | ~ |

### F · Settings

| # | Screen | Today |
|---|---|---|
| F1 | Settings panel — **460pt wide on a 393pt screen** | ✗ |
| F2 | Sections: layout · repair titles · canvas diagnostics · on-device engine + self-test · OMR connection · API key · performance readings · build stamp | ~ |

### G · Cross-cutting

| # | Concern | Today |
|---|---|---|
| G1 | Fixed-width surfaces — `OverlayPanel(width:)`, settings **460pt** | ✗ |
| G2 | Keyboard inset and focus | ~ |
| G3 | Dictation | ✓ |
| G4 | System share sheet | ✓ |
| G5 | Dynamic Type through every screen | ~ |
| G6 | Rotation: state, placement, re-fit | ~ |

## 2. The rules the wireframes obey

1. **One canvas.** `ScorePagesView` at every width. `ScoreZoomView` is deleted.
2. **Chrome ≤ 35% of container height.** Portrait allows 266pt; **landscape
   allows 130pt**, and today's chrome is 204 (52 + 96 + 56). This single number
   drives most of what follows.
3. **The 96pt thumbnail strip becomes a 28pt page scrubber** on compact: a track
   with a tick per page, the current one marked, tap a tick to jump, drag to
   scrub with a page chip. A thumbnail small enough to fit a phone is too small to
   recognise; the feature — go to a page — is kept and improved.
4. **One bottom deck.** Page scrubber 28 + transport 48 = 76pt, both visible.
5. **No Pencil.** iPhone has no Pencil, so the mode is what the *finger* means,
   and it stays a mode rather than a guess (§6 of the navigation spec).
6. **Modal-free holds.** Push screens, anchored panels, inline reveal. No sheets.

## 3. Wireframes and ratings

Rated 1–5: **viability** (does it work at all) and **quality** (is it good).

---

### E-A · Score view, portrait — 393×759

```
┌─────────────────────────────────────┐ ← 59 safe
│ ✕   Sous le ciel de Paris    ⌄  💬 ⋯│ 44   title expands, taps for the menu
├─────────────────────────────────────┤
│                              ⌖ 3/12 │
│                                     │
│         ONE PAGE, fit-width         │ 635
│         pinch to zoom               │
│         swipe / edge tap to turn    │
│                                     │
│                                     │
├─────────────────────────────────────┤
│ ▏▏▎▏▏▏▎▏▏▏▏▏      page 3            │ 28   page scrubber
├─────────────────────────────────────┤
│  ▶   ⏮   bar 21   ♩96      🎚 mixer │ 48   transport
└─────────────────────────────────────┘ ← 34 safe
```

Top bar carries **✕ · title (expands) · versions ⌄ · Ask · …** and nothing else.
Edit, layout, performance and transport toggles move into `…`, which already
carries them at exactly the widths the bar cannot seat
(`ScoreBarLayout.optionsCarriesTransportToggle` — the invariant exists, it just
needs the compact breakpoint). The `#N` numeral and mode chip drop; the subtitle
line stays because it costs width nothing.

**Viability 5 · Quality 4.** One page fit-width at 393pt is 635pt tall — a real
reading view. Loses a point because reaching Edit through `…` is two taps on the
screen where markup is most wanted.

---

### E-B · Score view, landscape — 734×372

```
┌───────────────────────────────────────────────────────────────┐
│ ✕  Sous le ciel de Paris          ⌄   💬  ⋯                   │ 40
├───────────────────────────────────────────────────────────────┤
│                                                               │
│              TWO-PAGE SPREAD, fit-height                      │ 256
│                                                               │
├───────────────────────────────────────────────────────────────┤
│ ▏▏▎▏▏▏▎▏▏▏▏▏  page 3      ▶  ⏮  bar 21  ♩96        🎚         │ 48
└───────────────────────────────────────────────────────────────┘
```

Landscape merges scrubber and transport into **one 48pt deck**: chrome totals 88
of the 130 allowed. 256pt of height at 734 wide is a spread at roughly 1:1.4 —
readable, and the case a phone on a stand actually gets used for.

**Viability 4 · Quality 3.** It works, but 256pt is thin: a dense 4-stave system
will want the reader to zoom, and zooming defeats a spread. The honest
alternative is one page landscape and I want Ali's call — **open question 1**.

---

### E-C · Score view, edit and select

No Pencil, so a mode decides what one finger does. Three modes, same names:

| Mode | One finger | Two fingers | Reached by |
|---|---|---|---|
| Read | pan | pinch zoom | default |
| Ink | **draws** | pan and zoom | ink bar opening |
| Performance | taps turn pages | pinch zoom | `…` → Performance |

Lasso is not a fourth mode. **Ask arms it for one gesture**: tapping `💬` opens
the chat panel with a `Select music` control in its header; tapping that arms
the lasso, the next finger drag draws it, and the selection lands in the chat
input where it was going anyway. One gesture, then back to Read.

Ink bar on compact: **anchored above the deck, full width**, not floating —
there is no room to float it and nowhere to put it that is not over the music.

**Viability 4 · Quality 2.** Finger ink at phone scale is imprecise, and a
lasso drawn with a fingertip around one notehead is worse. It is the honest
ceiling of the hardware, not a layout failure, but I will not rate it higher
than "works". **Open question 2**: is view-only markup on iPhone acceptable for
0.6.14, with drawing deferred?

---

### E-D · Mixer, compact

Per `MIXER_WINDOW.md` §4.2, and it needs the `< 700` width test replaced first.

```
PORTRAIT, anchored, above the deck        LANDSCAPE, collapsed by default
┌───────────────────────────────────┐     ┌──────────────────────────────┐
│  MIXER  3 of 4 voices     ⌄    ✕  │ 44  │ MIXER  3 of 4      ⌃    ✕    │ 44
├────┬──────────────────────────────┤     ├──────────────────────────────┤
│ALL │ ┌────┬────┬────┬────┐        │     │ 0:42 ▬▬▬▬▮▬▬▬▬▬▬▬▬▬   3:15   │ 32
│ ON │ │M  7│M  4│M  7│M  0│  scroll│128  └──────────────────────────────┘
│ALL │ │ ▮  │ ▮  │ ▮  │ ▮  │   →    │      expand → 45% ceiling, body scrolls
│OFF │ │Vln │Vln │Vla │Vc  │        │
├────┴──────────────────────────────┤
│ TEMPO ▬▬▬▮▬▬▬▬▬▬▬▬▬▬▬▬▬▬     96   │ 28
├───────────────────────────────────┤
│ 0:42 ▬▬▬▬▮▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬  3:15  │ 32
└───────────────────────────────────┘
```

Four strips visible at 393 wide (8 + 45 master + 4×64 + 3 = 312). No grab bar,
no park button — an anchored panel has nowhere to go. Collapse and close stay.
The sound-chip row drops in landscape; tapping the strip label opens the picker,
which is true in every tier anyway.

**Viability 4 · Quality 3 portrait, 2 landscape.** Portrait is a real mixer.
Landscape at 372pt tall can show the panel or the music, not both — collapsed by
default is a mitigation, not a fix. **Open question 3**: should the mixer in
landscape be a push screen instead of an anchored panel?

---

### E-E · Transport, compact

```
│  ▶   ⏮   bar 21   ♩96                        🎚 mixer  │ 48
```

Play · rewind · bar readout · tempo · mixer. The set-list prev/next arrows drop
on compact and move to the title menu, which already lists the running order —
two ways to step a set list is one more than a phone has width for. Unavailable
and draft-warning states keep their inline treatment; `transport-resolve` pushes
to Settings as it does now.

**Viability 5 · Quality 4.** Loses a point only for the set-list step moving.

---

### A-A · Library, portrait

```
┌─────────────────────────────────────┐
│ My library                       ⚙  │ 44
│ 14 pieces · 3 set lists             │ 20
├─────────────────────────────────────┤
│ ▐ Pieces ▌│ Setlists │ Books        │ 36   full-width segment
├─────────────────────────────────────┤
│  Import   │   New    │  New set list│ 44   three equal buttons
├─────────────────────────────────────┤
│ Sort: name    Filter    Edit        │ 36   utility row, left-aligned
├─────────────────────────────────────┤
│ Sous le ciel de Paris          ☰   A│
│ 3 arrangements · Louiguy            │B
│─────────────────────────────────────│C
│ Autumn Leaves                  ☰   ·│ rows, A–Z rail 16pt
│ 1 arrangement · Kosma               │·
└─────────────────────────────────────┘
```

The engine chip leaves the utility row for Settings — it is a status, it was
already the first thing to squeeze, and on a phone the row is exactly full
without it. Everything else keeps its place and its identifier.

**Viability 5 · Quality 4.** Four stacked rows of chrome before the first piece
is 180pt of a 759pt screen. Acceptable, not lovely. If Ali wants it tighter the
lever is folding the utility row behind a single `Sort & filter` control —
**open question 4**.

---

### A-B · Library, landscape — 734×372

Same single column, capped at **560pt wide and centred**; a 734pt-wide row with
a 20-character title is a stripe of whitespace with text at one end. Chrome is
the same 180pt against 372 of height, which leaves **two rows visible**, so the
action and utility rows collapse into one 44pt row: `Import · New · Set list ·
Sort · Filter · Edit`, icons with labels dropping first.

**Viability 4 · Quality 3.** Two visible rows is a poor list. It is the standard
phone-landscape compromise and I would not spend more on it than this.

---

### E-F · Chat panel, compact

Already full width (`ContentView.swift:575`). Needs: a header naming the
arrangement with `✕`, the `Select music` control from E-C, and the keyboard
inset it currently gets from the score screen's `.ignoresSafeArea(.keyboard)`
which is the *opposite* of what this panel wants.

```
┌─────────────────────────────────────┐
│ Ask · Sous le ciel        Select  ✕ │ 44
├─────────────────────────────────────┤
│  … conversation, scrolls            │
│                                     │
├─────────────────────────────────────┤
│ [ selection: 4 notes, bar 21    ✕ ] │ 32  when armed
│ ┌─────────────────────────────┐  ▶  │ 44
│ │ ask…                        │     │
└─────────────────────────────────────┘
        keyboard raises the input, not the canvas
```

**Viability 5 · Quality 4.**

## 4. Ratings, all together

| Area | Viability | Quality | Note |
|---|---|---|---|
| Library portrait | 5 | 4 | 180pt of chrome before row one |
| Library landscape | 4 | 3 | two rows visible |
| Piece / arrangement / management pushes (B, C) | 5 | 4 | full-screen pushes already |
| Book screen (D2) | 3 | 2 | **flagged** — a page-thumbnail grid at 393pt |
| Score view portrait | 5 | 4 | after one-canvas |
| Score view landscape | 4 | 3 | 256pt of music |
| Page navigation (scrubber) | 5 | 4 | better than thumbnails on a phone |
| Transport | 5 | 4 | set-list step moves |
| Mixer portrait | 4 | 3 | real, but half the screen |
| Mixer landscape | 3 | 2 | **flagged** |
| Ink | 4 | 2 | **flagged** — finger, no Pencil |
| Lasso / selection | 3 | 2 | **flagged** — fingertip precision |
| Chat | 5 | 4 | |
| Options `…` and sub-screens | 5 | 4 | pushes, already fine |
| Share & export | 4 | 4 | |
| Settings (F1) | 2 | 2 | **flagged** — 460pt panel |
| Panel dialogs (G1) | 1 | 1 | **flagged** — 620pt sheet |
| Performance mode | 4 | 3 | tap zones on a small page |
| Dynamic Type everywhere | 2 | 2 | **flagged** — same class of bug as the mixer |

**Nothing rates well yet in six places**: the book screen, the mixer in
landscape, ink, lasso, settings, and fixed-width surfaces — plus Dynamic Type as
a cross-cutting failure the mixer already proved is systemic. §6 solves the last
three as rules; §7 first-passes the rest of the surface; §8 says which of them a
decision cannot lift.

## 5. Open questions for Ali

1. **Landscape score**: spread at 256pt tall, or single page? I lean single page
   with the spread offered — a phone on a stand is one page at a time.
2. **Ink on iPhone**: finger drawing, or view-only markup for 0.6.14? Finger ink
   works and is imprecise; view-only is honest but drops a feature.
3. **Mixer in landscape**: anchored collapsed panel, or a push screen?
4. **Library chrome**: keep the four stacked rows, or fold sort/filter/edit
   behind one control?
5. **Scope**: is the book screen (D2) in 0.6.14, or does the phone open books
   read-only and leave page extraction to the iPad?

---

# Second pass

## 5A. Two corrections to the first pass

**`sheetWidth: 620` is a dead constant.** Nothing reads it — `grep` finds one
definition (`Theme.swift:247`) and no consumer. The same is true of
`libraryWidth: 320`. I rated "panel dialogs 1/1" off a number that no screen
uses, and that rating is withdrawn. The app is genuinely modal-free: what looks
like a dropdown is a *band* (`TitleSwitcherBand`, height-capped by the score
height already passed to it), what looks like a sheet is a pushed screen, and
push screens cap at `readingColumn: 720` as a **maxWidth** (`Screen.swift:60`),
so they degrade to 393pt correctly on their own. That is why groups B and C rate
4 without work.

The real fixed-width surface is **one**: `OverlayPanel`, which takes a hard
`.frame(width:)` (`Components.swift:266`) and is used once — Settings at 460pt
(`RootView.swift:68`). Smaller than I reported, and still broken on a phone.

**Landscape paged is arithmetically dead, and that answers question 1.** A page
is 1.414 tall per unit wide. Landscape gives 284pt of height after chrome, so a
page fits at **201pt wide**; a spread at **two** of those. Portrait gives 393pt
of width and needs 556 of the 635pt available — **a whole page, full width, no
zoom**. So landscape paged shows the music at half the size portrait shows it
at, and a spread is not a reading view on this device at any setting.

The honest landscape view is **continuous**: 284pt of height holds two or three
systems at portrait's engraving size, scrolling sideways. Landscape should
*default* to continuous and offer paged rather than the other way round. This
supersedes wireframe E-B, and it does not need Ali's answer — the page geometry
decides it. What still needs his answer is whether paged stays *offered* in
landscape at all.

## 6. The three systemic rules

### 6.1 One rule for every surface that is not a pushed screen

> **At compact width nothing has a fixed width. A surface either fills the
> width, or it becomes a screen.**

Which one it becomes follows from a single question: *must it coexist with the
canvas?*

| Surface | Regular | Compact | Because |
|---|---|---|---|
| `OverlayPanel` — Settings | trailing panel, 460 | **pushed screen** (`Route.settings` exists) | nothing on the canvas is being read while settings are changed |
| Chat | side panel, 380 | full-width anchored panel, canvas above | the answer is about the music on screen |
| Mixer | movable window | anchored bottom panel (`MIXER_WINDOW` §4.2) | it is played *with*, not read |
| Ink bar | movable | anchored above the deck | nowhere to float that is not over the music |
| Title switcher band | band under the bar | same, height cap 45% | already width-flexible |
| Layout control | 3 cells | 2 cells (`ScoreLayout.available(isCompact:)`) | already right |
| Notice · undo · selection · bundle bars | full width | unchanged | already right |
| Push screens | `readingColumn` 720 max | fills | already right |

Implementation is two lines and one move: `OverlayPanel`'s `width` becomes
`.frame(maxWidth: width)`, and at compact `RootView` routes Settings to the
stack instead of the panel. Everything else in the table is already true or is
specced in `MIXER_WINDOW.md`.

**Test:** no `.frame(width:` with a constant survives in a view that renders at
compact width, and a UI test at 393pt asserts every top-level surface's frame is
within the window.

### 6.2 Settings

Falls out of 6.1: at compact, Settings is a push screen with the same content,
the same sections and the same identifiers. `settingsWidth` becomes a maximum.
No per-section work — every section is a `PanelToggle`, `PanelButton`,
`LabeledField` or `WellBlock` in a vertical stack, and those are width-flexible
already. The one thing to check is the API-key field and the self-test output
`WellBlock`, which hold long unbroken strings: both need
`.lineLimit(nil)` and a horizontal scroll, not truncation.

### 6.3 Dynamic Type — the same bug the mixer proved, everywhere

Every type role is `UIFontMetrics.scaledFont` (`Theme.swift:148`) and caption1
runs 12pt at Large to 36pt at AX5, a **3×** range. Every fixed row height in the
app is a 1.0× number. Five rules:

1. **No `.frame(height:)` or `.frame(width:)` around text.** Rows take
   `minHeight`; text takes `.fixedSize(horizontal: false, vertical: true)`.
   Layout enums expose **minimums**, never heights.
2. **Constants that sit under text become `@ScaledMetric`** — including
   `scoreTopBar: 52`, `transportHeight: 56`, `thumbStripHeight: 96`,
   `hitTarget`, and every row height in `Screen.swift`.
3. **Measured-fit arithmetic must measure at the current text size.**
   `ScoreBarLayout`'s `closeWidth: 34`, `actionWidth: 34`, `versionsWidth: 110`
   and `titleMinimum: 90` are all 1.0× numbers, so the bar that was carefully
   fitted for #60 mis-fits at every size above Large — it will seat controls it
   cannot draw.
4. **At AX1 or larger, a horizontal row of more than three controls becomes a
   vertical list.** Established by the mixer's list tier; applies to the library
   action row, the utility row, the transport and the options rows.
5. **Chrome yields before content.** When scaled chrome would exceed the 35%
   budget, chrome collapses (deck merges, then the scrubber hides behind the
   transport's page chip) — the music is never the thing that shrinks.

**Test, per screen:** launch at `UICTContentSizeCategoryExtraExtraExtraLarge`
and again at `…AccessibilityLarge`; assert every labelled element's frame is
contained in its container's frame. That is the mechanical form of "nothing is
cut off", and it is the single check that would have caught the mixer.

## 7. First pass on the rest of the surface

Ratings are **viability · quality**, 1–5, of the *adapted* design.

### A · Library

| # | Adaptation | V·Q |
|---|---|---|
| A4 | A–Z rail: keep, 16pt, name sort only. Already narrow enough. | 5·4 |
| A5 | Rows: title, meta line, `☰`. Unchanged; the row is already a column. | 5·5 |
| A6 | Row `☰`: `RowMenuBehaviour` unchanged — push where an action needs a target, expand where every action is one tap. Expansion is vertical, so it costs width nothing. | 5·5 |
| A7 | Inline rename: field replaces the title in place, keyboard raises, Save/Cancel inline beneath. Needs the field kept above the keyboard — the score screen's `.ignoresSafeArea(.keyboard)` must not apply here. | 4·4 |
| A8 | Edit mode: checkboxes on rows, bulk bar anchored at the bottom, 44pt, verbs collapsing to icons below 4 selected verbs. | 4·4 |
| A9 | Two-step delete + undo bar: anchored, full width, unchanged. | 5·5 |
| A10 | Notice bar: unchanged, wraps to 2 lines. | 5·4 |
| A11 | Bundle offer: bar with summary; `detail` pushes rather than expanding — the detail is a list of what is in the envelope and it does not fit under a bar on a phone. | 4·4 |
| A12 | Import progress rows: unchanged. | 5·4 |
| A13 | Empty state: unchanged, `readingColumn` capped. | 5·5 |

### B · Pieces and arrangements

| # | Adaptation | V·Q |
|---|---|---|
| B1 | Piece screen: unchanged. Rows + three actions, all vertical. | 5·5 |
| B2 | Arrangement screen: unchanged. Seven rows with values on the right; at AX sizes value drops under title (rule 6.3.1). | 5·4 |
| B3 | Move to piece: unchanged list. | 5·5 |
| B4 | Set lists for X: checklist, unchanged. | 5·5 |
| B5 | Versions: unchanged; the version label and op summary stack on a narrow row. | 5·4 |
| B6 | Parts and ranges: a part per row with range as the value. Range notation (`C3–A5`) is short; no adaptation. | 5·4 |
| B7 | Details: title / composer / arranger / slug fields, one per row, labels above fields at compact rather than beside. Save is an anchored bar so it survives the keyboard. | 4·4 |

### C · Set lists

| # | Adaptation | V·Q |
|---|---|---|
| C1 | Set list screen: running order rows, `Play` as an anchored primary bar rather than a row, so it is reachable without scrolling a long order. | 5·4 |
| C2 | Add arrangements: checklist, unchanged. | 5·5 |
| C3 | Reorder: the existing up/down buttons per row. No drag — the standing principle, and it happens to be the right phone answer. | 5·4 |
| C4 | Set-list context in the transport: prev/next drop from the 48pt deck; the running order in the title menu becomes the way to step. Deck shows `3 of 7` as a chip. | 4·3 |

### D · Books, import, OMR

| # | Adaptation | V·Q |
|---|---|---|
| D1 | Books segment: rows, unchanged. | 5·5 |
| D2 | Book screen: **two-column thumbnail grid** at ~180pt each — a page thumbnail at 180pt is legible enough to recognise a title or a first system. `from`/`to` become an anchored range bar reading `pages 4–11 · Extract`; `starts here` / `ends here` stay per-thumbnail. | 4·3 |
| D3 | Folder import plan: rows, unchanged; `commit` anchored. | 5·4 |
| D4 | System importer: system-provided. | 5·5 |
| D5 | OMR chip: the bar cannot seat 142pt on a phone, and `ContentView` already draws it over the canvas instead — that path becomes the only one at compact. | 5·5 |

### E · Score view, the rest

| # | Adaptation | V·Q |
|---|---|---|
| E3 | Page turn: swipe anywhere, plus 44pt edge zones. Zones matter more on a phone because the thumb rests at the edge. | 5·4 |
| E10 | Playhead + follow + sync chip: unchanged; the chip is centred above the deck. Follow matters *more* on a phone — one page is one page. | 5·4 |
| E11 | Live counters + artifact marker: the two counters merge into one chip `3/12 · bar 21` at the trailing top corner; the artifact marker keeps the leading corner. Two chips at 393pt crowd the music. | 4·4 |
| E12 | Performance mode: bar shrinks to 38pt as it already does; tap zones are the whole left/right halves. The one mode that is *better* on a phone — no chrome, whole screen, one page. | 5·5 |
| E13 | Title switcher band: already a band, already height-capped by `available: scoreHeight`. Cap at 45% and scroll within. | 5·4 |
| E14 | Options `…`: pushed screen, already `readingColumn`-capped. Carries Edit, layout, performance and transport at compact — the `optionsCarries…` invariant, extended to a compact breakpoint. | 5·5 |
| E15 | Share & export: format rows, then the system share sheet. "Send to another iPad" keeps its name and works phone-to-iPad. | 5·4 |
| E16 | Chord adjustments: `size` with bigger/smaller steppers — three controls in a row, fine at 393. | 5·4 |

### F · Settings — resolved by 6.1/6.2

| # | Adaptation | V·Q |
|---|---|---|
| F1 | Push screen at compact. | 5·5 |
| F2 | Sections unchanged; `WellBlock` output and the API-key field scroll horizontally rather than truncate. | 4·4 |

### G · Cross-cutting

| # | Adaptation | V·Q |
|---|---|---|
| G1 | Fixed widths: §6.1. | 5·5 |
| G2 | Keyboard: the score screen's `.ignoresSafeArea(.keyboard)` is right for the canvas and wrong for chat, rename and Details. Each of those raises its own input. | 4·4 |
| G3 | Dictation: unchanged. | 5·5 |
| G4 | System share sheet: unchanged. | 5·5 |
| G5 | Dynamic Type: §6.3. | 4·4 |
| G6 | Rotation: placement as a unit point (`MIXER_WINDOW` §5); layout re-fit on size change; the canvas keeps its page index and zoom fraction, not its zoom scale. | 4·4 |

## 8. What a decision cannot lift

Four of the flagged items are **engineering constraints**, not layout choices. No
answer from Ali raises them; each needs a different feature or is capped by the
hardware.

1. **Fingertip lasso — 3·2, ceiling ~3.** A finger's contact patch is about 9mm,
   roughly 25pt. At fit-width portrait a notehead is about 4pt. Selecting *this
   note and not its neighbour* is below the input's resolution, at any zoom the
   reader will actually use. Lasso is not portable to a phone.
   **The engineering answer is different granularity**: tap a bar to select the
   bar, tap again to cycle within it. Bar-level selection is a real feature and
   most chat asks ("transpose bars 21–24") are bar-level anyway. That is a new
   op path, not a layout.
2. **Finger ink — 4·2, ceiling ~3** with decision (2). Ink at 2× zoom is usable
   for a circle round a bar; it is not usable for a fingering above one note.
   Same physics, less severe, because ink is inherently coarse.
3. **Notation does not respond to Dynamic Type — 2·2, no ceiling change.** The
   score is engraved and rasterised; a reader who needs AX5 text gets AX5 chrome
   around notation at whatever size the page is. The only lever is zoom, which is
   already there. Worth stating plainly to Ali rather than implying the app is
   accessible at large text: **the chrome will be, the music will not.** If that
   matters, the engineering answer is an engraving scale setting that re-renders
   at a larger staff size — a Verovio option, not a layout rule.
4. **Continuous view at 393pt — unrated until measured.** Continuous re-engraves
   with no system breaks. At 393pt of width, a four-stave system may fit two or
   three measures, which is a ribbon nobody can read in tempo. Landscape (734pt)
   is fine. **I want a measurement before I rate portrait continuous**, and it
   is the one item on this list I would put a spike on: render `Sous le ciel` at
   393pt continuous and count measures per system.

Everything else rated ≤2 is lifted by a decision: mixer landscape by (3), book
screen by scoping (5), settings and fixed widths by §6.1, and the score canvas
by one-canvas-everywhere.

---

# Third pass — selection is first class on the phone

Ali's ruling: precision comes from zoom. The contact-patch ceiling I put on
lasso and ink is withdrawn, and **note selection and measure selection are both
first-class iPhone interactions**. This section replaces wireframe E-C and the
first two items of §8.

## 9. The ruling is supported by the canvas that already exists

The zoom ceiling is **12×**, and it was put there for exactly this
(`ScorePagesView.swift:74`):

> *The ceiling stays 12 so a notehead can be inspected; the page re-rasters at
> the settled scale.*

The arithmetic, so the design is sized to something real. An A4 page is about
120 staff spaces across, so at fit-width portrait one staff space is 3.3pt and a
notehead is **3.9pt**. A fingertip contact patch is about 25pt. Zoom closes it:

| Zoom | Notehead | Page width in view | What is selectable |
|---|---|---|---|
| fit (1×) | 3.9pt | whole page | measures, systems |
| 2× | 7.8pt | half a page | measures, a beat |
| 4× | 15.6pt | ~98pt, about a measure | notes, a chord |
| 6× | 23pt — a fingertip | ~65pt | notes, comfortably |
| 12× | 47pt | ~33pt | one notehead, inspected |

So the ruling holds, and it comes with its own consequence: **at the zoom where
a note is hittable, you can see about a measure.** That is not a problem to
solve, it is the shape of the interaction — and it produces the rule below
rather than fighting it.

## 9.1 Granularity follows the zoom

> **Below 2×, a tap selects a measure. At 2× and above, a tap selects a note.**

Not arbitrary: it is precisely the granularity that is both legible and hittable
at that scale. It needs no mode, no second control, no hold, and no toolbar. The
reader who wants a note does what they would do anyway — zoom in — and the tap
means what the view already implies.

Three overrides so the rule is never a trap:

- **Tap an already-selected measure** → drills in and selects the note nearest
  the tap, at any zoom. The way to a note without zooming.
- **The selection chip names the granularity and offers the other one**:
  `bar 21 selected · notes` / `4 notes · whole bar`. The rule is visible and
  reversible in one tap.
- **Tap the page away from any element** → clears.

Taps **accumulate** in a selection: tap two notes and both are selected, which
is what the chat asks are actually about ("swap these two"). A phone has no
modifier key, so accumulate-by-default with a visible `clear` in the chip is the
only honest option.

## 9.2 The loupe — occlusion is a separate problem from resolution

Zoom fixes resolution. It does **not** fix the finger covering the thing being
selected, and no amount of zoom will: the fingertip occludes whatever is under
it at every scale.

So, the pattern every iOS reader already knows from text selection: while a
finger is down in a selecting gesture, a **96pt circular loupe** appears offset
88pt above the touch, showing the page under the finger at 2× the current scale
with a crosshair at the exact hit point. Release commits what the crosshair is
on, not what the finger is on.

- Paper & Clay: `paper` fill, 1pt `line2` ring, `ePanel` shadow, crosshair in
  `clay`. No magnifier chrome, no bevel.
- It flips *below* the touch within 100pt of the top safe area.
- Suppressed under VoiceOver, which selects by element and not by point.

This is what makes tap-a-note reliable at 4× instead of demanding 8×, and it is
the single control that most decides whether phone selection feels precise or
approximate.

## 9.3 Lasso

Tapping needs no mode. A lasso does, because a one-finger drag is already pan
and page-turn, and the app's standing rule is that inputs are separated by mode
rather than by a guess at timing or distance.

**`Select` is armed from the top bar** (`⌖`, beside Ask), and the mode chip says
`Select` while it is. While armed, one finger draws the loop and two fingers
still pan and pinch, so the reader can reposition mid-selection. The loop closes
on release, the selection lands, and the mode **disarms after one gesture** —
tap the control twice to latch it for several.

The loupe follows the path head while drawing, so the leading edge of the loop
is never under the finger.

Lasso is for *several* elements, and several elements have to be on screen, so
in practice it lives between fit and 4×. That is fine: it is the multi-select
tool, and the tap is the precision tool. Neither is a substitute for the other,
which is why both ship.

## 9.4 Selection survives zoom, page and rotation

Select a note at 8×, zoom out, and it stays highlighted in context — that is the
loop the reader needs before asking a question about it, and it is what makes
"zoom for precision" cost nothing. Selection is held in score addresses
(`ScoreAddress`, `staff/measure/layer/kind#ordinal`) and not in view
coordinates, so this is a rendering concern and not a model one.

## 9.5 Ink, under the same ruling

Ink takes the ruling too: you draw at the zoom the mark needs. A circle round a
bar at fit, a fingering above one note at 6×. `InkSharpness` already re-rasters
at the settled scale, so a stroke drawn at 6× stays crisp when zoomed out.

Ink stays a mode entered by the ink bar, unchanged. The loupe does **not** apply
— a stroke is a path, not a point, and a loupe chasing a drawing hand is noise.

## 9.6 Score view, iPhone portrait — revised

```
┌─────────────────────────────────────┐
│ ✕  Sous le ciel de Paris  ⌄ ⌖ 💬 ⋯ │ 44   ⌖ arms Select
├─────────────────────────────────────┤
│  Select                      ⌖ 3/12 │      mode chip while armed
│                                     │
│        ╭────────╮                   │
│        │  ◉  ← loupe, 2× under      │ 635
│        ╰────────╯     the finger    │
│         ●                           │
│      ╭──────────╮  ← lasso path     │
│      ╰──────────╯                   │
├─────────────────────────────────────┤
│ [ bar 21 · 4 notes    notes ⌄   ✕ ] │ 36   selection chip
├─────────────────────────────────────┤
│ ▏▏▎▏▏▏▎▏▏▏▏▏      page 3            │ 28
├─────────────────────────────────────┤
│  ▶   ⏮   bar 21   ♩96      🎚 mixer │ 48
└─────────────────────────────────────┘
```

The selection chip sits **above the deck**, not over the music, and only while
something is selected. Tapping it opens chat with the selection already carried,
which is the path it was always for.

Chrome with a selection: 44 + 36 + 28 + 48 = 156 of the 266pt portrait budget.

## 9.7 Revised ratings

| Interaction | Was | Now | Why |
|---|---|---|---|
| Measure selection (tap at fit) | — | **5 · 5** | a measure at 393pt is a 30×80pt target |
| Note selection (tap at 2×+, loupe) | 3 · 2 | **5 · 4** | 15.6pt at 4×, crosshair not fingertip |
| Lasso (armed, at the zoom that shows the targets) | 3 · 2 | **4 · 4** | mode-separated, loupe on the path head |
| Ink (finger, at the zoom the mark needs) | 4 · 2 | **5 · 4** | same ruling, and already re-rasters |
| Chat with a carried selection | 5 · 4 | **5 · 5** | the chip is now the route in |

Quality stays at 4 rather than 5 for note-tap and lasso for one reason each,
both worth Ali knowing: a note tap at 4× shows about a measure, so *finding* the
note costs a pan the iPad does not need; and an armed mode is a state the reader
can be in without noticing, which is why the mode chip is not optional.

## 9.8 §8 amended

Constraints 1 and 2 are **withdrawn** — the ruling and the loupe lift both, and
the arithmetic supports it.

Two remain, unchanged:

- **Engraved notation does not answer Dynamic Type.** The chrome scales, the
  music does not; the lever is a staff-size engraving setting, not layout.
- **Portrait continuous is unrated** until someone renders `Sous le ciel` at
  393pt continuous and counts measures per system. Still the one spike I would
  ask for.

And one new item, from this pass: **selection must be held as addresses, not
points** (§9.4). If it is not already, that is model work and it belongs in the
estimate.

---

# Fourth pass — engineer validation answered

## 10.1 Portrait continuous: it does not reflow, and neither does paged

**Decision: nothing re-engraves to the viewport. The engraved width stays
fixed at US Letter, at every size class, in both layouts.**

The spike measured the right thing and it settles the question against reflow:
1.1–1.2 bars per system, 141 systems for the accordion solo, 47 paged portrait
pages of one bar each. That is not a reading view at any zoom.

But reflow is also the wrong lever, and the codebase already says why. Paged
uses `breaks: "auto"` because *"a page on the iPad and a page in an exported PDF
are broken the same way"* (`EngravingOptions.swift:64`). Reflowing to 393pt
would mean **the phone's page 12 is not the iPad's page 12 and neither is the
PDF's** — bar numbers still agree, but "turn to page 4" stops meaning one thing,
the thumbnail rail indexes a different document per device, and a set list built
on one device paginates differently on another. Reflow does not cost a bit of
legibility here; it costs page identity across the product.

So paged portrait stays exactly as rated: the fixed 972×1258 page scaled to
393pt wide (0.404), a whole page in view, ~3.9pt noteheads, zoom to read
one. **5 · 4, unchanged.**

### Continuous, and what it actually does today

Continuous is not reflowed music — it is `breaks: "none"`, one system, height
trimmed to it (`EngravingOptions.swift:62`, `adjustPageHeight`). A quartet comes
back about **21000 × 540pt**, and `ContinuousTiles` fits it by **height** with a
ceiling of `maximumMagnification: 2` times the fitted-page scale
(`ContinuousTiles.swift:104`). On the phone that resolves to:

```
pageScale   393 / 972                  = 0.404
ceiling     2 × 0.404                  = 0.81
strip       540 × 0.81                 = 437pt tall in a 635pt canvas
in view     393 / 0.81                 = 485 engraved pt ≈ 2 bars
```

So portrait continuous already works without touching the engraving — it is a
horizontal ribbon showing about two bars at a time, scrolled sideways. The 141
systems only appear if someone reflows, and nothing here asks for that.

Its real defect on a phone is different and smaller: **a 437pt ribbon in a 635pt
portrait canvas wastes a third of the screen**, and a single-voice strip (about
150pt engraved) wastes three quarters of it.

### The fix, which is canvas work and not engraving work

**Portrait continuous wraps the strip into rows.** Take the one-system strip
that is already rasterised in tiles, cut it at barlines, and stack the pieces as
393pt-wide rows scrolled vertically. Same engraving, same tiles, same scale
rules — only the arrangement of tiles on the surface changes.

- Cuts land on barlines, never mid-bar: `ScoreGeometry` already reports bar
  extents (`ScoreGeometry.swift:263`), which is the same source the bar frames
  check (`check_bar_frames.py`) holds to account.
- Row height is the strip's height at the chosen scale, plus 8pt of air.
- Scale keeps its existing floor and its `maximumMagnification: 2` ceiling — the
  rule is unchanged, it simply now spends the height on **more rows** rather
  than on one over-magnified system.
- Landscape keeps the single ribbon: 734pt of width shows four or five bars, the
  height is not going spare, and there is nothing to wrap.

This turns portrait continuous into the one mode where a phone beats an iPad:
the whole score as stacked rows of music, one thumb, no page turns.

### Ratings, and the fallback

| Portrait continuous | V·Q | |
|---|---|---|
| **Wrapped rows (recommended)** | **5 · 4** | new canvas layout, no engraving change |
| Unwrapped ribbon (ships today) | 4 · 3 | works, wastes a third of the screen |
| Reflowed to 393pt | **2 · 1** | **rejected** — 141 systems, and page identity lost |

If wrapping does not fit 0.6.14, **ship the unwrapped ribbon**: it is viable
today, it needs no work, and it is not a trap to improve later. Reflow is
rejected in both cases, and I would like that recorded as a decision rather than
a deferral — it is the option that looks like the obvious fix and is not one.

## 10.2 Address-driven highlighting — required, and smaller than reported

Accepted as a prerequisite for §9.1: **tap selection is invisible without it**,
so it is a build item, not polish.

One refinement to the finding. The *drawing* already exists and is already
zoom-corrected — `SelectionInk` defines `highlightWeight`, `highlightPad` and
states the rule that every constant is divided by the zoom (`SelectionInk.swift`
header), and `LassoOverlay` draws "the boxes over what it caught". What does not
exist is the path that feeds it **without a lasso having just run**:

```
[ScoreAddress]  →  ScoreGeometry.element(at:)  →  ScoreElement.frame  →  the
                                                  existing highlight layer
```

`element(at:)` is there (`ScoreGeometry.swift:226`), frames are there in page
coordinates (`:19`). The work is holding the selection as `[ScoreAddress]` on
the canvas, mapping it through on every render, and letting the lasso *write* to
that set instead of owning its own. Three consequences worth stating so they are
built in rather than discovered:

1. **The lasso becomes one writer, not the owner.** Tap, lasso and any future
   route all append addresses to the same set.
2. **§9.4 falls out for free.** A selection held as addresses survives zoom,
   page change and rotation because it was never in view coordinates.
3. **Highlight treatment**, in Paper & Clay, distinct from the playhead
   (`PLAYBACK_0.6.md` §2 recolours a notehead to `clay` for a sounding note):
   selection is a **box, not a recolour** — `clayTint` fill at 40% with a 1pt
   `clay` border, `rCtl` radius, `SelectionInk.highlightPad` of padding, drawn
   *behind* the glyph. A note that is both selected and sounding shows a clay
   notehead inside a tinted box, which is legible and correct.
4. A **measure** selection uses the same box over the bar's extent. Same
   treatment at both granularities — the chip says which one you have, the
   drawing does not need to.

## 10.3 Loupe caveat accepted

The loupe **freezes during a pinch**: it holds its last sampled content, dims to
70%, and re-samples on the first frame after the scale settles. A loupe showing
stale music at a changing scale is worse than one that visibly pauses, and the
raster is already re-cut on settle — the same moment
`ScorePagesView` re-rasters at.

VoiceOver: suppressed, as specced. Two fingers down: suppressed, because a pinch
is not a selection.

## 10.4 Build order

1. One canvas everywhere — `ScorePagesView` at compact width, delete
   `ScoreZoomView` (§0). Nothing else is testable until this lands.
2. Address-driven highlighting (§10.2). Prerequisite for 3.
3. Tap selection with granularity from zoom (§9.1) and the loupe (§9.2).
4. Armed-mode lasso (§9.3), writing to the same address set.
5. Compact chrome: 44pt bar re-fit, 28pt page scrubber, merged landscape deck
   (§2, §3).
6. §6.1 fixed-width surfaces, then §6.3 Dynamic Type with its per-screen test.
7. Portrait continuous wrapped rows (§10.1) — the one item that can be dropped
   from 0.6.14 without stranding anything else.

Steps 1–4 are the release. Steps 5–6 are what make it good on the device. Step 7
is what makes the phone worth preferring for practice.

---

# 11. Selection highlight — settled

Both engineer questions are correct. §10.2 item 3 is superseded by this section.

## 11.1 Colour: unchanged, and my token was wrong

`clayTint` at 40% composites to **#FCF5F1 — 1.08:1 against paper**. It is not a
highlight, it is nothing. Withdrawn.

**The shipped values are right. Do not repaint them.**

| | Token | Opacity | Composite over paper | Ink on it |
|---|---|---|---|---|
| Fill, note | `clay` #CC5C2E | **22%** | #F4DBD1 · 1.32:1 | 13.3:1 |
| Fill, **measure** | `clay` | **12%** | #FBF2EE · 1.15:1 | — |
| Border, both | `clayStrong` #A8481F | **65%**, 1pt | — | — |

The only change is the **measure** fill. A bar's box is fifty times the area of
a notehead's, and 22% across a whole bar is a wash rather than a highlight;
area does the work that opacity does on a small patch, and the border carries
the definition at both granularities. That one is a judgement call — show me a
frame with a bar selected on a dense page and I will confirm or move it.

Nothing else changes. The release adds a selection *route*; it should not
repaint a working visual on the way past.

## 11.2 Layer order: stay an overlay, and multiply

**"Behind the glyph" is withdrawn as a build instruction.** You are right that it
means compositing under the tiles, and that is not worth a structural change.

**Keep `SelectionHighlight` as an `.overlay`. Give the fill
`.blendMode(.multiply)`. The border keeps normal blending, drawn on top.**

Multiply over white paper leaves the tint exactly as it is now; multiply over a
black notehead leaves the notehead black. That is the whole of what "behind the
glyph" was asking for, with no layer-order change.

And it is not only cheaper — it fixes a live defect. Today's normal-blend fill
**lightens every notehead it selects**:

| Notehead #1A1917 under a clay@22% box | Result | Contrast vs paper |
|---|---|---|
| normal blend (today) | #41281C | **13.6:1** |
| multiply | #191513 | **18.1:1** |

Selecting a note currently washes it out to a brown. Multiply leaves it at the
contrast it had unselected, a hair darker. So the answer to "which looks similar
on paper" is that they do not: the current one is quietly degrading the thing
being selected, and nobody would notice from a static mockup.

**Sounding and selected together**, which was the constraint: a `clay` notehead
under a multiplied clay@22% box composites to **#C34F26** against `clay`'s
#CC5C2E — unmistakably the same clay note, marginally deeper. It still reads as
a clay notehead inside a tinted box, which is what §10.2 asked for.

Three notes for the build:

- **Fill multiplies, border does not.** A multiplied border crossing a stem or a
  ledger line darkens it unevenly; the border is an edge and wants its own
  colour, source-over.
- Multiply over a **grey scan** darkens slightly more than normal blend does.
  That is the right direction — a light overlay is what washes out on grey paper.
- `SelectionInk`'s divide-by-zoom rule is untouched; a blend mode has no size.

## 11.3 What this leaves to build

Nothing new. The route (`[ScoreAddress]` → `element(at:)` → frame → highlight)
is already there per your finding; this section changes **one blend mode, one
opacity for measure-granularity boxes, and nothing else**.

---

# 12. Single-finger tap arbitration — ruling

## 12.1 Amend, not confirm — and the premise that just became false

`PageTurn` already carries the arbitration table and it is explicit about why a
finger tap was free (`PageTurn.swift:52`):

> *A finger never selects and never inks, so its tap is free in every mode — a
> single-finger tap on the page did nothing at all before this.*

§9.1 invalidates exactly that sentence, so the table changes rather than gains a
row. Update the comment with the rule; a premise that has quietly stopped being
true is how the mixer's drag died.

**The proposed rule is amended on one point**, because checking the code moved
my answer: I was about to gate turn zones on zoom, and `PagedCanvas.afterTurn`
forbids it — *"Zoom PERSISTS — a violinist reading at 180% stays at 180%"*
(`PagedCanvas.swift:76`). Turning pages while zoomed is designed behaviour, so
zoom cannot be the separator. It has to be position.

And "keep the outer margins" does not survive measurement. The engraved margin
is `pageMarginLeft: 120` tenths-mm → 54 engraved points → **21.8pt on screen at
fit-width portrait**. Half a thumb. There is no margin to keep: at fit the page
fills the canvas.

## 12.2 The ruling: bottom-anchored corner zones

**Turn zones stop being full-height columns and become bottom-anchored corners.
Everything else on the canvas selects.**

```
static let zoneFraction: CGFloat = 0.22          // unchanged
static let zoneHeightFraction: CGFloat = 0.30    // new
static let zoneMinHeight: CGFloat = 88           // two hit targets
static let zoneMinWidth: CGFloat = 64            // narrow split views
```

| Canvas | Corner zone | Selectable |
|---|---|---|
| iPhone portrait 393×635 | 86 × 190 | 86.8% |
| iPhone landscape 734×284 | 161 × 88 | 86.4% |
| iPad 13" landscape 1366×820 | 301 × 246 | 86.8% |
| iPad 11" portrait 834×950 | 183 × 285 | 86.8% |
| iPad split, narrow 320×700 | 70 × 210 | 86.8% |

Bottom-anchored because that is where a thumb rests on every one of those
devices, and because it hands back the upper 70% of the outer columns — which
at fit is the first and last bar of every system except the last.

**Why not hit-test arbitration** (tap an element selects, tap blank paper in the
outer zone turns), which is the more elegant rule and uses the spatial index
that already exists: it makes a page turn *conditional on what is engraved under
the thumb*. A performer's page turn must be reliable in a fixed, learnable
place, and a rule that works over a rest and fails over a chord is not that.

## 12.3 The hole, stated

At fit, the **last system's outer bars** fall inside the corner zones and cannot
be tap-selected. Three existing routes reach them, so nothing is stranded:

- zoom past 2× and pan — the bar leaves the corner, and §9.1 wants a note
  selected at that zoom anyway;
- lasso, which is armed and positional;
- tap the measure before it, then the chip's granularity control.

I would rather have that hole than a conditional page turn. If Ali disagrees
after using it, the lever is `zoneHeightFraction`, not the structure.

## 12.4 The structural instruction — this is the mixer lesson

**One recogniser owns the single-finger tap for the whole canvas, and it
decides.** Not a turn recogniser and a select recogniser racing, not
`.simultaneousGesture`, not innermost-wins. That arrangement is exactly what
left the mixer undraggable for a release, in an arena less crowded than this one.

The decision is a pure function beside the ones already there, testable without
a screen:

```swift
enum TapOutcome: Equatable {
    case turn(Zone)
    case select(CGPoint)   // canvas point, for the geometry to resolve
    case clear
    case none
}

static func tap(isPencil: Bool, mode: ScoreMode, touchCount: Int,
                point: CGPoint, canvas: CGSize,
                movement: CGFloat, elapsed: TimeInterval) -> TapOutcome
```

Order inside it, and nowhere else:

1. `touchCount > 1` at any moment during the gesture → `.none`. The two-finger
   undo tap and every pinch must not leave a stray selection behind, and a
   pinch that began as one finger is the case that will actually happen.
2. Not `isTap(movement:elapsed:)` → `.none`. Unchanged: 10pt slop, 0.3s.
3. `mode == .performance` → `.turn` **anywhere on the canvas**. Selection is off
   in performance, so the whole page is the turn target. This is the escape
   valve that makes 12.3's hole affordable.
4. `isPencil` → the existing table, untouched.
5. Point inside a corner zone → `.turn`.
6. Otherwise → `.select(point)`; the geometry decides measure or note by zoom
   (§9.1), and a miss on any addressable element returns `.clear`.

Two checks that fail if this drifts:

- **Disjoint and total**: over a fuzz of canvas sizes and points, every point
  resolves to exactly one outcome, and the union of the zones plus the
  selectable region is the whole canvas. This is the test the mixer never had.
- **No stray selection from a pinch**: a synthesised two-finger sequence whose
  first touch lands in the centre produces `.none`, not `.select`.

## 12.5 What changes on iPad

This is a behaviour change there too — full-height columns become corners — and
it should not arrive unannounced. It is unavoidable: Ali's ruling puts finger
tap-select on iPad as well, so the same arena is crowded on both. The Pencil
table is untouched, and performance mode still turns from anywhere.

## 12.6 The 12% measure fill

Understood that the frame comes with this wiring. When it lands, send **a bar
selected in the middle of a dense system at fit, portrait** — density is what
the 12% call turns on, and a sparse bar will make any value look fine.

---

# 13. Two rulings after steps 3–4

## 13.1 Measure fill: renderer-only, confirmed — and it is the only safe option

**Confirmed.** Do it in the renderer. Do not put a measure address into the
selection.

The recommendation is stronger than "cheaper". `ScoreModelBuilder.selectable`
excludes bar-like kinds as a *fix*, and the comment names the two bugs it
closed (`ScoreModelBuilder.swift:96`):

> *A `<measure>` element's frame spans the whole bar across every staff, so
> lassoing three notes caught the measure too and lit up the entire bar (#9),
> and tapping empty space caught the measure alone and selected the whole bar
> out of nowhere (#10a). One cause, two symptoms.*

Putting `.measure` back into a selection reopens both. The renderer is not a
shortcut here, it is the only route that does not regress a shipped fix.

The problem being solved is real and worth stating in the code: **22% fills
compound where boxes stack.** Two layers composite to 39%, three to 53%. A bar
of ten notes with overlapping boxes is a mottled patch that is darkest wherever
the engraving is densest — the opposite of what a highlight should do.

### The rule, precisely

**Per measure, per staff.** For each measure represented in the selection, if
every selectable address of that measure *on the staves represented* is
selected, replace those member boxes with **one rectangle: the union of those
members' own frames**, padded by `SelectionInk.highlightPad`.

Three things that rule is deliberately not:

- **Never the measure element's frame.** `element(at:)` on a bar address returns
  a rect spanning every staff, and drawing that is #9 again. The union is of the
  members that are actually selected.
- **Never one rect across bars.** Several bars selected draw several rects, one
  each, because the bar is the unit the reader asked for.
- **Never additive.** The union replaces the member boxes; it does not sit over
  them, or the compounding comes straight back.

Partial bars keep individual boxes — nine of ten notes is not a bar. Selections
that accumulate a bar plus a stray note elsewhere draw a rect for the bar and a
box for the note, which falls out of evaluating per measure.

Border on the union rect (`clayStrong` 65%, 1pt); no border on the members it
replaced. Fill still multiplies, border still does not (§11.2).

### The value

**12%, and it ships as 12%** — with the frame still owed. It is now a single
flat layer rather than a compound, so 12% is genuinely 12% (#FBF2EE, 1.15:1
against paper), and it should read *lighter* than the 22% note boxes beside it:
same visual weight, larger area. The border carries the definition.

Provisional in one direction only. If the frame says it is too faint, the lever
is the value; the structure does not change.

## 13.2 Press versus tap: confirmed, with three amendments

**Confirmed.** 0.25s against a 0.3s tap window is a clean split with no
ambiguous band, and claiming the touch is right — a loupe you cannot slide is a
loupe that cannot correct the thing it exists to correct.

Three amendments, each closing a case that would otherwise be found on a device:

1. **No press in performance mode.** §12 rule 3 gives the whole canvas to
   turning there, because selection is off. A performer resting a finger for a
   quarter-second and getting nothing — no turn, no loupe, since there is
   nothing to select — is the one failure that mode exists to prevent. In
   performance, a still finger past 0.25s still turns.
2. **A finger that has already moved cannot become a press.** If movement
   exceeds `PageTurn.tapSlop` (10pt) before `pressDelay`, the touch is a pan for
   the rest of its life. Without this, a slow deliberate pan — finger down,
   settle, drag — becomes a loupe drag, and slow deliberate panning is what
   reading a zoomed score is made of.
3. **No press where the loupe is already suppressed**: more than one touch, ink
   mode (a stroke is a drag from the first frame), or VoiceOver (§9.2). One
   predicate for both, so they cannot drift apart.

And one behaviour to define rather than discover: **release outside the page
cancels** — no commit, no clear. A finger dragged off the paper is a reader
backing out.

`pressDelay` at 0.25s is snappier than the system's 0.5s long-press and than
iOS's own text loupe. With amendment 2 in place I would ship it and watch;
if it proves twitchy on a device the lever is the constant, not the design.

## 13.3 The chip clipping

Good catch, and the right fix: a control sized to its longest line, 1.5pt over
the window, is exactly the class §6.3 rule 1 names. **The window-relative clip
test is the general form of that section's per-screen check** — if it is written
so other screens can adopt it, point §6.3's acceptance test at it rather than
letting a second one grow beside it.

---

# 14. The library toolbar at compact width — ruling

## 14.1 Measured

Window 393, `sidePadding: 20` each side, so the row has **353pt**. At compact,
`LibraryActionRow.isCompact` strips labels from the five quick actions but does
not reduce their number.

| Row | Needs | |
|---|---|---|
| 5 icons + `Sort: name` + filter + edit | **407pt** | over by 54 |
| the same under the *recently changed* sort | **491pt** | over by 138 |

`.frame(width: geo.size.width)` then holds the HStack at 353 while its content
measures 407, and SwiftUI centres the overflow — **27pt off each edge**, which
is the reported symptom exactly: the import icon clipped on the left, sort,
filter and select running off the right. Any fix has to hold for the **longest**
sort label, not the one that happens to be selected.

## 14.2 None of the three options, because the row is the wrong shape

Horizontal scroll and an overflow menu are both rejected, and two rows is a last
resort rather than the fix:

- **Horizontal scroll** hides controls behind an invisible affordance, against
  the 0.4.1 directive, and the first thing off the right is `Edit` — the row's
  only mode switch.
- **An overflow `…`** that opens a floating menu is forbidden outright
  (`NAV_MODAL_FREE_0.4.2`). It could push a screen, but two taps for `Import`
  is a worse trade than the bug.
- **Two rows** costs 44pt on a screen where library chrome is already 180 of
  759pt, and it fixes the symptom while leaving the cause.

The cause is that **five of the seven controls are two verbs**. `importScore`,
`importFolder` and `importBook` are three flavours of Import; `new` and
`newSetlist` are two flavours of New. At compact they render as five unlabelled
squares — and two of those glyphs are `square` and `line.3.horizontal`, which
name nothing at all.

## 14.3 Ruling: collapse five into two, using the band this row already has

**`[Import ▾] [New ▾] · · · [Sort: …] [Filter] [✓]`**

Import and New each open a `RevealBand` beneath the row listing their variants —
Score · Folder · Book, and Arrangement · Set list. That is the pattern Sort and
Filter already use **in this row**, mutually exclusive with them, so it costs no
new concept, no scroll, no permanent second row and no menu. It also gives the
three imports readable names instead of three glyphs a reader has to guess.

The variants keep their identifiers (`library-import-folder`,
`library-import-book`, `library-new-setlist`) so nothing that addresses them
breaks.

Applies at **every width**. Five occasional actions in a permanent row was
always a lot of toolbar for what they are; the phone is where it stopped fitting.

## 14.4 Then fit by measurement, with a stated yield order

Collapsing is not sufficient on its own — the long sort label still overflows:

| Row | Needs | |
|---|---|---|
| Import/New labelled, short sort | 396pt | over by 43 |
| **Import/New icons, short sort** | **315pt** | fits, 38 spare |
| Import/New icons, *recently changed* | 371pt | over by 18 |
| everything yielded | 245pt | fits, 108 spare |

So it needs the same treatment as the score bar: **a pure `LibraryBarLayout`
beside `ScoreBarLayout`**, taking the row width and returning what it seats,
unit-testable without a screen.

**Yield order, first to go:**

1. `Edit` label → icon
2. `Filter` label → icon
3. `New` label → icon
4. `Import` label → icon
5. `Sort` **short form** — `name · composer · recent · count`, added to
   `LibrarySort` beside `buttonLabel`. It is still the answer, just said shortly.
6. `Sort` loses its value entirely: glyph plus `Sort`. Last, because that label
   being an answer rather than a name is the reason it is written that way.

**Nothing is ever removed.** All seven controls stay present and one tap from
their action at every width. Only labels yield.

**Two rows is the floor, not the fix:** if step 6 has run and the row still does
not fit — accessibility text sizes will do this — it wraps to two rows, and at
AX1 or larger it becomes the vertical list that §6.3 rule 4 already requires of
every row of more than three controls. That is where two rows belongs: as what
happens when measurement says nothing else is left, not as the first answer.

## 14.5 Acceptance

Mirror what the score bar's fix needed, since this is the same failure in a
different row:

1. **`seatsWhatItDraws`** — for every width from 320 to 1366 and every
   `DynamicTypeSize`, the sum of what `LibraryBarLayout` seats is ≤ the row
   width. Fails today at 393 by 54pt, and by 138 under the *recently changed*
   sort.
2. **`nothingLeavesTheWindow`** — the same window-relative clip test the
   selection chip just got, pointed at `library-import` and `library-edit`. If
   that test is written to take any identifier, this costs a line.
3. **`everyActionSurvives`** — all seven identifiers are reachable at 320pt,
   through a band where they have moved into one.

One caution from the mixer and the score bar both: `ScoreBarLayout`'s constants
are 1.0× numbers, which §6.3 rule 3 already flags as mis-fitting above Large.
Do not copy that mistake here — `LibraryBarLayout` should take the scaled label
widths, not literals measured at default text size.

---

# 15. Photos as a source — Import band amendment

## 15.1 The premise is half right, and the half that is wrong decides it

> *a "Score" import today already accepts PDF/MusicXML/image from Files*

It accepts PDF and MusicXML. **It does not accept images**
(`ImportIntent.swift:10`):

```swift
static let scoreTypes: [UTType] = ([
    "musicxml", "mxl", "xml", "mid", "midi"
].compactMap { UTType(filenameExtension: $0) }) + [.pdf]
```

No image type is in that list, which is exactly *why* pictures are greyed out in
the Files picker. So bug (1) is not a menu problem at all — it is that array,
and the fix is adding the image types to it.

That settles the structure: **an image from Files is a score file like a PDF is,
and needs no entry of its own. Photos is a different picker, not a different
kind of thing, and it is the only addition the band needs.**

## 15.2 The band

```
Import
  Score      MusicXML, MIDI, PDF, or a picture — from Files
  Photos     a picture of the music, from your photo library
  ───────
  Folder     a whole exported library
  Book       a collection to take arrangements out of
```

Four rows, each with the one-line description `ScreenRow(title:value:)` already
carries elsewhere. The subtitle is what makes the labels work: neither `Score`
nor `Photos` has to disambiguate on its own, so a reader whose picture is in
Files still finds it under `Score`.

**Rejected, and why:**

- *`Score from Files` / `Score from Photos`* — consistent, but it makes the
  common case read as a technicality. Nobody importing a MusicXML file is
  choosing a filesystem.
- *`Image` opening a second band of Files vs Photos* — two taps for Import, which
  §14.3 already refused, and it would be the only nested band in the app.
- *`Image` as a fourth object* — it would sit beside `Score` meaning the same
  thing through a different door, which is the confusion §15.1 removes.

`Photos` names the app the picture comes out of, which is the only thing the
reader is actually choosing between. It sits **second**, next to `Score`: the
first two rows each make one arrangement from one thing, the last two bring in a
collection — hence the divider, which the band already supports.

Applies at **every width**, like the rest of §14. Identifier
`library-import-photos`, beside the three that exist.

## 15.3 Two rulings the build needs before it starts

**Both image routes end in the same pipeline.** An image from Files and an image
from Photos are the same import once it has a file: written to the inbox,
OMR'd through make-editable exactly as a scanned PDF is. One path, not two —
the picker is the only thing that differs.

**Several photos are one arrangement's pages, not several arrangements.** Files
and Photos diverge here deliberately:

| Picker | Multiple selection means |
|---|---|
| Files | *n* documents → *n* arrangements (unchanged: `for url in urls`) |
| Photos | *n* pictures → **one** arrangement of *n* pages, in selection order |

Photographing a three-page piece gives three pictures of one piece, and PHPicker
preserves selection order, which is page order. Treating them as three
arrangements would be wrong every time the feature is used as intended.

The escape hatch for the reader who selected pictures of three *different*
pieces already exists and needs no new UI: the result is one multi-page draft,
and the **Book screen** is the tool for taking arrangements out of one of those.
Say so in the import's own notice rather than asking a question up front.

## 15.4 Acceptance

1. **`filesOfferPictures`** — `ImportKind.scoreTypes` contains the image types,
   so a `.png`, `.jpeg` and `.heic` are selectable. Fails today; it is bug (1)
   in one assertion.
2. **`everyImportRouteSurvives`** — §14.5's identifier check, now four:
   `library-import`, `library-import-photos`, `library-import-folder`,
   `library-import-book`, all reachable at 320pt.
3. **`photosBecomeOneArrangement`** — three pictures selected in the Photos
   picker produce one arrangement with three pages, in the order chosen.
4. **`anImageImportsLikeAScan`** — an image from either route reaches
   make-editable, so the two routes cannot drift into two pipelines.

---

# 16. Set lists from the score view — placement ruling

## 16.1 It is not a popover, and that answers the compact question

The pieces-list version is a **pushed screen**, not a checklist popover:
`Route.setlistsFor(slug)` → `SetlistsForScreen` with `navigationBarHidden`
(`RootView.swift:256`), reached from a row on the arrangement screen
(`PieceScreen.swift:289`). `SetlistChooserView` is band-styled content *inside*
that screen — `BandHeader`, `PanelNote` — not a floating surface.

So there is nothing to adapt. The Options screen behind `⋯` is itself a pushed
screen that pushes further (`push("Chord symbols")`), a push fills the width on
a phone and caps at `readingColumn` on an iPad (§6.1), and rows are already
44pt. **Compact needs no special treatment, no reveal band and no sheet.**

**Do not build a popover for this.** It would be the only one in the app, and
`NAV_MODAL_FREE_0.4.2` exists to keep it that way.

## 16.2 Where it sits

The Options rows group by subject: view toggles, then things that change the
notation, then where the arrangement *sits*, then outbound, then the app. Set
list membership is filing, so it goes with details:

```
Chord symbols                 14 pt
Annotations                   on
Selection & chat              4 selected
Transpose                     by interval
Piece & arrangement details   Sous le ciel de Paris
Set lists                     2 set lists            ← new
Share & export                MusicXML · MIDI · PDF
Settings                      on-device
```

Immediately after `Piece & arrangement details`, before `Share & export`:
filing, then sharing, then the app. Identifier **`more-setlists`**, matching
`more-details` and `more-export`.

## 16.3 The label is `Set lists`, not `Add to setlist…`

Three reasons, each of which the codebase already argues somewhere:

1. **The screen toggles membership — it removes as well as adds.** "Add to"
   mislabels half of what it does, and a reader wanting to take a piece *out*
   of tonight's set would not look under it.
2. **That screen already has a name.** `PieceScreen` calls the identical
   destination `Set lists`. Two labels for one screen is the thing this codebase
   keeps warning about — *"a switch belongs in exactly one place"*, *"two
   independent notions of what fits"*. Whichever label is better, there must be
   one.
3. **`…` means a dialog, and there are none.** A `ScreenRow` with `leads: true`
   draws a chevron; that is the affordance, and it is honest about arriving at a
   screen rather than a pop-up.

**The value carries the answer**, per the rule stated in this very screen — *"A
screen of bare labels is a menu; the answers are what make it a summary of where
the score stands (L34)"*. Reuse `PieceScreen`'s `setlistSummary`: `2 set lists`,
`Tonight` when it is one and the name fits, `none` when it is in none.

Spelling: `Set lists`, two words, matching `New set list` and the back labels.

## 16.4 Reuse the screen, including the way out of empty

Push the same `SetlistsForScreen` the library pushes — not a second chooser.
`SetlistChooserView` takes `onNewSetlist`, and that closure is not decoration:
without it, a reader with **no set lists yet** lands on `"No set lists yet."`
with nothing to press. From the library they can back out and make one; from the
score view there is no list behind them to back out to.

So the score view's route must wire `onNewSetlist` to the same seeded-create
flow, which is an inline name field — already the pattern, no new surface.

If the score screen's stack is string-keyed rather than `Route`-keyed, add a
case that renders `SetlistsForScreen(slug:onBack:)`. One screen, one behaviour,
two entrances.

## 16.5 Acceptance

1. **`setlistsReachableFromTheScore`** — `score-options` → `more-setlists`
   reaches the chooser, and toggling a row changes membership as the library's
   route does. Run at compact and regular.
2. **`oneChooserNotTwo`** — the score view's destination is
   `SetlistsForScreen`; a grep for a second chooser type finds nothing.
3. **`emptyHasAnExit`** — with zero set lists, the score view's chooser offers
   `chooser-new-setlist`. This is the case that would ship broken.
4. **`theRowStatesItsAnswer`** — the row's value is `none` for an unfiled
   arrangement and names the count otherwise; it is never blank.

---

# 17. Landscape — the whole surface at 874×402

Consolidates §3 E-B, §2's merged deck and §12's landscape leg, all of which have
been dead code while landscape was disabled. Everything here supersedes those.

## 17.1 Spec against the narrower phone

| Device | Window | Safe rect | Chrome | Canvas |
|---|---|---|---|---|
| iPhone 15 Pro | 852×393 | **734×372** | 100 (27%) | **734×272** |
| iPhone 17 Pro | 874×402 | 756×381 | 100 (26%) | 756×281 |

Lateral safe insets are **59pt each side** (the Dynamic Island edge) and the home
indicator takes **21** off the bottom. **Every number below is computed for
734×372**, the binding case; the 17 Pro has 22pt more width and 9pt more height
and needs no separate treatment.

**The top bar stays 52pt.** §3 E-B proposed 40. Withdrawn: a second bar height
means a second `ScoreBarLayout` fit case, and that layout has already mis-fitted
twice (#60, and §6.3 rule 3's 1.0× constants). 12pt of canvas is not worth a new
breakpoint in the one piece of layout arithmetic that keeps breaking.

## 17.2 Score view

**Chrome: top bar 52 + merged deck 48 = 100pt.** The 96pt thumbnail strip and
the 56pt transport do not both appear; landscape has one deck carrying both
jobs, at 48pt:

```
│ ✕  Sous le ciel de Paris          ⌄  ⌖  💬  ⋯              │ 52
├────────────────────────────────────────────────────────────┤
│                                                            │
│                     canvas 734 × 272                       │
│                                                            │
├────────────────────────────────────────────────────────────┤
│ ▏▏▎▏▏▏▎▏▏▏  page 3    ▶  ⏮  bar 21  ♩120          🎚      │ 48
└────────────────────────────────────────────────────────────┘
```

The deck row has **694pt** after padding and its contents measure **620pt** —
fits with 74pt spare. Heights are `minHeight`, not `frame(height:)` (§6.3
rule 1); the transport's 56pt constant does not apply here.

**Paged in landscape stays what §5A settled:** a page fits at 201pt wide against
portrait's 393, so paged is offered and is not the default. Landscape defaults
to continuous.

## 17.3 Continuous in landscape — correcting the number and the rule

Asked to confirm "single ribbon, ~4–5 bars, no wrap". **Two corrections.**

The strip is fitted by height with a ceiling of `2 × pageScale`
(`ContinuousTiles.swift:104`). In landscape `pageScale` is bound by the page's
**height** — 272/1258 = 0.216 — so the ceiling is 0.432, and **the ceiling binds
for every score**:

| Strip | Scale | Drawn | Bars in view | Rows that fit |
|---|---|---|---|---|
| 4-staff quartet, 540pt | 0.432 | 234pt | **7.0** | 1 |
| 2-staff piano, 300pt | 0.432 | 130pt | **7.0** | 1 |
| single voice, 150pt | 0.432 | 65pt | **7.0** | **3** |

1. **It is ~7 bars, not 4–5**, and the number is the same for every score
   because the ceiling — not the strip's height — sets the scale.
2. **"No wrap" is right for two staves and denser, and wrong for a single
   voice.** A 150pt strip draws at 65pt in a 272pt canvas: one ribbon wastes
   three quarters of the height, which is the exact defect §10.1 wraps to fix in
   portrait.

So **the wrap rule is row-count-driven, not orientation-driven**:

```
rows = floor(canvasHeight / (stripHeight × scale + 8))
```

One row for a dense score, several for a thin one, in either orientation, with
no orientation branch anywhere. §10.1's wrapping is amended to this; it was
framed as a portrait fix and it is a *height* fix.

Cuts land on barlines, as §10.1 already requires.

## 17.4 Mixer

§12's landscape leg, now with numbers. Against a **272pt** canvas and the 60%
gate of §12.3:

| Panel | Height | of canvas | |
|---|---|---|---|
| Knob strip, sound row kept (§13) | 172 | 63.2% | **opens collapsed** |
| Knob strip, sound row dropped | **156** | **57.4%** | **opens expanded** |
| Collapsed | 48 | 17.6% | — |

**So landscape takes §13.1's lever: the sound-chip row is dropped and the picker
opens by tapping the part label** — which is already §4.2's rule for short
screens, so this is that rule doing its job rather than a new one. 156pt clears
the gate on both devices and the mixer opens usable instead of collapsed.

Width is unchanged: §12's `f(channel count)` — 184pt for two channels, 313 for
four — out of 718pt of free width, so 26–44%. Drag bounds are §5's free rect,
which in landscape is inset by the 59pt lateral safe areas; **the panel must
never be placed under the Dynamic Island edge**, which is what makes the safe
inset part of the clamp rather than decoration.

## 17.5 Library — a yield ladder, because the stack does not fit

The portrait chrome stack costs **216pt of 372**, leaving 156pt: **2.1 rows.**
That is not a library.

| | Chrome | List | Rows at 76pt |
|---|---|---|---|
| As built | 216 | 156 | 2.1 |
| Count folded into the header | 196 | 176 | 2.3 |
| **+ search and toolbar share one row** | **140** | **232** | **3.1** |
| + segment becomes a header control | 104 | 268 | 3.5 |

**Rule: landscape must show at least three rows.** Apply the levers in order
until it does — which on the 15 Pro means the first two:

1. **Count into the header line**: `My library · 14 pieces · 3 set lists`.
2. **Search and toolbar share one row.** Search takes the slack on the left, the
   §14 toolbar sits right. At 716pt: search 240 + gap 16 + toolbar 396
   (Import/New labelled, short sort) = 652, fits with 64pt spare — so landscape
   gets **labels on Import and New**, where portrait does not. `LibraryBarLayout`
   arrives at that by measurement; there is no landscape special case in it.
3. Segment as a header control, held in reserve — it is the one that costs a
   reader the ability to see which half of the library they are in.

**The 35% chrome rule does not govern list screens.** It was written for the
score canvas, where the music is the content. A list's test is *how many rows
are visible*, and three is the floor — enough to show that the list continues.

**Rows cap at 560pt and centre.** At 734–756 of width a full-bleed row puts a
title and its own chevron half a screen apart, which is L34 again at a smaller
scale.

## 17.6 Bands, pushes and the import menu

- **Reveal bands** (§14 sort/filter, §15 Import/New): four rows at 44 = 176pt,
  against a **223pt** cap (60% of 372). Fits. Rule: **a band caps at 60% of the
  container and scrolls within it** — needed at accessibility sizes, not at
  default.
- **Import band unchanged in landscape**: Score · Photos · ─ · Folder · Book.
  Four rows, same labels, same identifiers (§15.2).
- **Push screens** — Options, Set lists, Move to piece, Versions, Parts,
  Details, Book, Setlist — are header 52 + 320pt of scroll ≈ **7 rows at 44pt**.
  These are the screens landscape costs nothing: no change, `readingColumn`
  already caps them, and they were rated 5·4 in §7.

## 17.7 The one thing that only works in portrait

**Anything with a focused text field.** The landscape keyboard is about 200pt,
which leaves **172pt** of the 372 — and after a 52pt header, **120pt of
content.** That is the genuine landscape hazard and it touches: inline rename
(A7), Details (B7), new set list and new piece names, library search, and chat
(E17).

Rules, since a screen that cannot show its own field is broken rather than
cramped:

1. `.ignoresSafeArea(.keyboard)` is right for the score canvas and **wrong for
   every one of these** (§G2). Each raises its own input.
2. The focused field scrolls to sit **immediately above** the keyboard, and any
   anchored Save bar rides above it — never behind it.
3. **Chat in landscape shows its input and one line of conversation.** That is
   the honest ceiling at 120pt; it is not a layout to improve, it is what the
   device leaves. Flagged rather than smoothed over.
4. Bands and pickers **do not open while a keyboard is up** in landscape — 176pt
   of band into 120pt of space cannot be shown. Dismiss the field first, which
   the toolbar's own controls already do elsewhere.

## 17.8 Acceptance

1. **`landscapeChromeFitsTheWindow`** — at 852×393 and 874×402, the score
   chrome is ≤ 35% of the safe height and the deck's contents are inside the
   deck's frame.
2. **`theLibraryShowsThreeRows`** — at 852×393, at least three library rows have
   frames inside the window.
3. **`continuousWrapsByRowsNotOrientation`** — a single-voice score wraps to 3
   rows in landscape and a quartet to 1, from the same function, with no
   orientation input.
4. **`theMixerOpensExpandedInLandscape`** — with the sound row dropped the panel
   is 156pt and its `expanded` state is the one it opens in; and it drags, per
   `MIXER_WINDOW` §12.5's compact-landscape leg.
5. **`aFocusedFieldIsAboveTheKeyboard`** — for inline rename, Details, new set
   list and chat, the focused field's frame is above the keyboard's top at
   852×393. This is the test that catches 17.7 regressing.
6. **`nothingUnderTheIsland`** — no draggable panel's clamped frame extends into
   the 59pt lateral safe insets.
