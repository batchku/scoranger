# Scoranger design system — "instrument panel"

Approved direction: **1A 2B 3A 4B 5C 6A 7A**. This document is the spec; the
combined look is in `scoranger-system.html` and `png/system-*.png`. No app code
has been changed yet.

The direction in one line: *a warm paper-and-clay instrument panel, score-first,
with the arrangement numeral as the app's identity.*

- **Paper & Clay** — warm off-white surfaces, near-black ink, one burnt-clay accent.
- **Space Grotesk** for titles and the `#N` numerals, **Inter** for everything read
  as prose, **IBM Plex Mono** for every machine value.
- **Compressed, weight-driven** ladder: 10–34pt, hierarchy from weight and
  tracked-out caps labels rather than size jumps.
- **Instrument panel** surfaces: flat fills, hard 1pt edges, 2–3pt corners,
  silkscreen band headers, chunky square toggles, the engine state as a real LED.
- **Score first**: the score is the permanent ground; the library and chat slide
  over it; every canvas control collapses into one pill.
- **Light only.** No dark mode, no OS-following palette.

---

## 1. Colour

Three colours, in the sense that matters: one neutral family, one ink family, one
accent. Everything else on this list is a system signal, not part of the palette,
and may never be used decoratively.

### Surfaces

| Token | Hex | Where |
|---|---|---|
| `paper` | `#FFFFFF` | The score page. Nothing else in the app is pure white. |
| `ground` | `#F4F0E8` | The canvas the page sits on; the app's base colour. |
| `panel` | `#FAF7F1` | Overlay panels, sheets, alerts, the pill, cards. |
| `well` | `#EFEAE0` | Inset areas: self-test output, the displayed-version row, stepper cells. |
| `band` | `#F1ECE2` | Section header strips and sheet/alert footers only. |

### Ink

| Token | Hex | Contrast on `panel` | Rule |
|---|---|---|---|
| `ink` | `#1A1917` | 15.0:1 | Titles, body, row names, pen black. |
| `ink2` | `#6B655C` | 5.5:1 | Secondary prose, label column in sheets, mono values. |
| `ink3` | `#8A8378` | 3.5:1 | **Supplementary only** — meta lines ≥11pt, carets, counts, separators. Never the only place information appears. |

### Accent

| Token | Hex | Contrast on `panel` | Rule |
|---|---|---|---|
| `clay` | `#CC5C2E` | 3.9:1 | `#N` numerals, active icons, focus/selection outlines, progress fill. Text only at **≥15pt semibold**. |
| `clayStrong` | `#A8481F` | 5.4:1 | All small accent text: the 10pt caps band labels, inline accent words. |
| `clayPress` | `#B14D22` | 5.3:1 vs white | Fill for primary buttons carrying 13pt labels, and pressed states. |
| `clayTint` | `#F7E7DD` | — | Selected row fill, the user's chat bubble, active pill button. |

`clay` on `clayTint` is 3.3:1 — fine for the numeral, not for 13pt text.

### System status — outside the budget

| Token | Hex | Use |
|---|---|---|
| `ok` | `#3BA05C` | Engine LED, completed op ticks, self-test pass. |
| `warn` | `#C8791B` | Range warnings. Always paired with `ink` text; 3.2:1 makes it an icon colour, not a text colour. |
| `danger` | `#C0392B` | Delete buttons, error bubbles, unreachable LED. |
| `highlight` | `#FFE25A` @ 40% | The passage band over the engraving. |
| pen inks | `#D64B3F` `#2A6BD6` `#2E9159` `#E08A25` `ink` | Pencil markup. Fixed; the user's marks are content. |

Rules:

1. One accent per screen region. If clay is already carrying the numeral, the
   surrounding chrome stays ink and line.
2. Selection is `clayTint` fill **plus** a 1pt `clay` outline inset by 1pt — the
   fill alone is too quiet on a warm ground.
3. Never tint the score page. Engraving colour belongs to Verovio.

---

## 2. Typography

Three families, bundled with the app (~1.1 MB total, variable where available).
No serif anywhere. SF Pro is not used.

| Role | Family | Size / weight | Tracking | Where |
|---|---|---|---|---|
| `numeralXL` | Space Grotesk 700 | 34 / lh 0.86 | −0.02em | The numeral on the score page. |
| `numeralL` | Space Grotesk 700 | 21 | −0.02em | Library rows, sheet headers. |
| `numeralM` | Space Grotesk 700 | 17 | −0.01em | Chat header, the pill. |
| `title` | Space Grotesk 600 | 17 | −0.01em | Sheet titles, alert titles, chat subject. |
| `titleS` | Space Grotesk 600 | 15 | −0.01em | Piece names, page title, state titles. |
| `row` | Inter 500 | 13.5 | 0 | Arrangement and piece row names. |
| `body` | Inter 400 | 13 / lh 1.45 | 0 | Chat prose, alert bodies, descriptions. |
| `control` | Inter 600 | 13 | 0 | Buttons, Done, Cancel. |
| `label` | Inter 700 | 10 | +0.11em, uppercase | Band headers, card headers, bubble authorship. |
| `meta` | Inter 400 | 11 | 0 | Part lists, counts, subtitles. |
| `data` | IBM Plex Mono 400/500 | 11 | −0.01em, tabular | Version ids, slugs, ranges, bar numbers, build stamp, keys, hostnames. |
| `dataS` | IBM Plex Mono 400 | 10.5 | 0 | Step counts, footers. |

Rules:

1. **All numerals that are handles are Space Grotesk 700, tabular.** `#2` is a
   handle. `14 versions` is not — that is `meta`.
2. **Every machine value is mono.** Version ids, op names, pitches, measure
   ranges, slugs, model aliases, file names, the build stamp. If the user could
   type it into chat verbatim, it is mono.
3. **Caps labels earn their tracking.** 10pt/700/+0.11em, `clayStrong`, never
   longer than three words, never a sentence.
4. Only one size step exists between adjacent levels; if something needs to
   stand out, change weight, not size. That is the whole point of 3A.
5. Dynamic Type: sizes above are the `.large` values, declared with
   `Font.custom(..., size:, relativeTo:)` — `numeral*` → `.title`, `title*` →
   `.headline`, `row/body/control` → `.body`, `label/meta/data` → `.caption`.
   Rows grow with the text; the pill and the page numeral cap at +2 steps so the
   canvas never loses the score.

---

## 3. Space, size, hit targets

Ladder: **2, 4, 6, 8, 12, 16, 20, 24, 32**. Nothing between.

| Thing | Value |
|---|---|
| Panel padding (horizontal) | 14 |
| Row padding | 7 × 14, `minHeight` 36 |
| Version row | 4 × 14, indent 42; step row indent 64 |
| Band header | 5 × 14 above, 4 below |
| Sheet row | 9 × 14, `minHeight` 40 |
| Gap between sibling controls | 8 |
| Gap between blocks | 12 |
| Library overlay width | 320 |
| Chat overlay width | 380 |
| Score page width | 520; 436 when both overlays are open |
| Pill height | 50 (38pt buttons + 6 padding) |

Every tappable thing gets a **44 × 44** hit area via `contentShape`, even when it
draws at 26 or 34. Rows already do this; icon buttons must.

---

## 4. Line, radius, elevation

| Token | Value | Use |
|---|---|---|
| `line` | 1pt `#E2DBCE` | Separators inside a panel. |
| `line2` | 1pt `#CFC6B6` | Panel edges, control borders, band top/bottom. |
| `rCtl` | 2pt | Buttons, chips, toggles, fields, icon buttons. |
| `rPanel` | 3pt | Panels, sheets, alerts, cards. |
| `rPill` | 999 | The pill and the ink bar — the only round things in the app. |
| `ePanel` | y10 b34 `rgba(26,25,23,.14)` | Library and chat overlays. |
| `ePill` | y6 b20 `rgba(26,25,23,.16)` | Pill, ink bar, highlight chip. |
| `eSheet` | y20 b60 `rgba(26,25,23,.22)` | Sheets and alerts. |
| dim | `rgba(26,25,23,.34)` | Behind sheets and alerts. |

Shadows exist **only** on things that float over the score. Everything anchored
is flat and separated by a line. No gradients, no inner glows, no blur — the one
translucency in the app is the highlight band.

---

## 5. Motion

| Move | Duration | Curve |
|---|---|---|
| Overlay in / out | 220ms | `.spring(response:0.32, dampingFraction:0.86)`, slide + no fade |
| Page re-centring when an overlay opens | same, matched | the page **never resizes mid-animation**; the centring inset animates |
| Pill button state | 120ms | `.snappy` |
| Ink bar appear | 160ms | scale 0.96 → 1 from the pill |
| Row disclosure | 180ms | `.easeOut` |
| Version becoming current | 240ms | `clayTint` flash, then settle |
| Spinner | 1s linear | 2pt ring, clay leading edge |

`prefers-reduced-motion` / Reduce Motion: overlays cross-fade in 120ms, nothing
slides, the spinner stays.

---

## 6. Iconography

SF Symbols, `.medium` weight, `.regular` for row-level 13pt glyphs. Sizes: 16pt
in the pill, 15pt in the ink bar, 13pt in rows and sheets. One glyph per idea and
the same glyph everywhere: `line.3.horizontal` library, `bubble.left.and.text.bubble.right`
chat, `gearshape` options, `pencil.tip` markup, `eraser`, `arrow.uturn.backward`,
`info.circle` details, `plus` add, `xmark` dismiss, `chevron.right` disclosure,
`circle.fill` displayed-version marker, `checkmark`/`exclamationmark.triangle`
op results. The engine LED is a drawn circle with a 3pt halo, not a symbol.

---

## 7. Components

### 7.1 Pill (canvas toolbar) — `png/system-01-resting-score-first.png`
Anatomy, left to right: library toggle · `#N` numeral (17pt, clay) · version chip
(mono 11, 2pt border) · divider · options gear · pencil · divider · chat toggle.
38pt round buttons; active buttons take a `clayTint` circle and `clayStrong`
glyph. Floating bottom-centre, 20 from the bottom edge, `ePill`, radius 999.
On iPhone the pencil is dropped (markup is iPad-only) and the numeral drops to 15.

The pill is the **only** persistent chrome. There is no navigation bar, no title
bar, no tab bar.

### 7.2 Overlay panel
Full-height, opaque `panel`, hard `line2` edge on the score side, `ePanel`.
Header: brand or subject on the left, state on the right, a 30pt bordered dismiss
button at the far end. Dismissed by the dismiss button, by tapping the score, or
by the pill toggle. The library is 320 wide from the left; chat is 380 from the
right. Both may be open at once; the score page narrows to 436 and stays centred
in the gap.

### 7.3 Band header (the silkscreen label)
`band` fill, 1pt `line2` top and bottom, full panel width, 10pt caps
`clayStrong` label, optional 22pt bordered `+` button at the trailing edge.
Used for: sidebar sections, sheet sections, op-card headers, tile captions,
alert footers (fill only, no label).

### 7.4 Row
36pt minimum, 7 × 14 padding. Leading 10pt caret (clay) when the row discloses
something, then the optional numeral, then a two-line stack (name 13.5/500,
meta 11/`ink3`), then a trailing 26pt icon button in a 44pt hit area.
States: **rest** transparent; **selected** `clayTint` + 1pt `clay` inset outline;
**drop target** `clayTint` + 1pt dashed clay; **pressed** `well`.
The meta line truncates with a tail ellipsis and never wraps.

### 7.5 Arrangement row + numeral
`#N` in Space Grotesk 700/21, clay, tabular, 36pt minimum width so #1 through
#99 stay left-aligned. Unfiled arrangements have **no** numeral and no reserved
space — the number only means something inside a piece.

### 7.6 Version rows
Group row: caret · `vNNN` (mono 11, `ink2`) · prompt text (12) · step count
(mono 10.5, `ink3`) · displayed marker (`circle.fill`, clay). The currently
displayed version's row takes the `well` fill. Step rows indent to 64, drop the
prompt for the op name in `ink2`, and keep the same marker rule.

### 7.7 Chat bubble
Bordered `panel` card, radius 3, 9 × 11 padding, max width 86%. A 10pt caps
author label (`AGENT` / `YOU`) sits above the text — cheaper than tails and it
survives having no colour to spare. The user's bubble is `clayTint` with a
`#E7C4B1` border, right-aligned. Errors use a `#FBEEEC` fill and `#E3B4AE`
border with the failing value in mono.

### 7.8 Op card (live progress)
Bordered card with a band header stating the count (`WORKING · 3 OPS`), then one
step row per op: 13pt status glyph (`ok` tick / `warn` triangle / `ink3` circle),
the op name in Inter, its arguments in mono `ink2`. The tail row is the 11pt clay
spinner plus `thinking…`. When the turn completes the card keeps its final state
and the header changes to `DONE · 3 OPS`.

### 7.9 Ink bar (pencil markup)
Pill language, 74 from the bottom so it stacks above the toolbar. Pen · eraser ·
divider · five ink dots · divider · undo · exit. The live ink grows 16 → 24, gains
a 2pt ink ring and a white tick. Pencil draws, fingers scroll — unchanged.

### 7.10 Highlight chip
Top-centre panel chip: `PASSAGE` caps label, a bordered stepper group with the
bar numbers in mono on `well` cells, the sentence `handed to chat`, and a
dismiss. The band on the page is `highlight` at 40%.

### 7.11 Buttons
13pt/600 label, 2pt radius, 8 × 12 padding, 1pt `line2` border on `panel`.
Primary: `clayPress` fill, white label. Destructive: `danger` fill, white label.
Disabled: 42% opacity, no colour change. Pressed: `well` (default) or 12% darker
fill (primary/destructive). Icon buttons are 34pt squares with the same border.

### 7.12 Toggle
44 × 26, 2pt radius, `well` track with a 20pt square knob on `panel`. On: track
`clayTint` with a `clay` border, knob `clay` with a `clayPress` border. It reads
as a panel switch, not an iOS capsule. Never animate the knob more than 120ms.

### 7.13 Field
`paper` fill inside a panel, 1pt `line2`, 2pt radius, 9 × 10 padding, 13pt.
Placeholder `ink3`. Focus: 1pt `clay` border, no glow. Secure fields show a mono
mask with the last four characters visible.

### 7.14 LED
9pt circle with a 3pt halo at 22% of its own colour. `ok` connected, `danger`
unreachable. It sits next to a mono word (`on-device`, `unreachable`) — colour is
never the only carrier.

### 7.15 Sheet
620 wide, inset 64 top and bottom, `panel`, radius 3, `eSheet`, over a 34% dim.
Header: title (17 SG 600), optional numeral, `Done` at the trailing edge. Body is
band headers plus 40pt label/value rows separated by `line`; values right-aligned,
machine values in mono. Destructive actions sit in the body, last, never in the header.

### 7.16 Alert
420 wide, `panel`, radius 3, `eSheet`. Title 16 SG 600, body 12.5 `ink2`, and a
`band` footer with right-aligned buttons: cancel first, then the verb. The verb
names the action (`Delete`, `Create`, `Rename`) — never `OK`. Naming alerts put a
`paper` field in the body.

### 7.17 State view
Centred: 30pt `ink3` glyph, 17pt SG title, 12.5pt body no wider than 44
characters, and at most one button. Every state keeps the pill visible so the app
never looks dead. Failure states name the cause in mono and the fix in prose.

### 7.18 Import progress
A row inside the library: file name, a 4pt `well` track with a `clay` fill and a
1pt border, and the stage in mono (`OMR 62%`). Indeterminate work shows the ring
spinner instead of a track.

---

## 8. Screens

| # | Screen | Notes |
|---|---|---|
| 01 | Resting | Score edge-to-edge, page centred, pill only. The page carries `#2` and `ARRANGEMENT` at 34/8.5pt. |
| 02 | Library overlay | 320 from the left over the score; page re-centres. Status → Setlists → Pieces → Unfiled → build stamp. |
| 03 | Chat overlay | 380 from the right; header repeats the numeral, piece and version count; model alias in mono. |
| 04 | Working | Both overlays, page at 436, op card live. The everyday state. |
| 05 | Pencil markup | Ink bar above the pill; markup drawn over the engraving. |
| 06 | Highlight a passage | Chip with mono steppers; band at 40%; chat open to receive it. |
| 07 | Arrangement details | Sheet: arrangement, scored-for (per part: instrument, clef, range, bars), sources, delete last. |
| 08 | Settings | Sheet: on-device engine toggle + LED + self-test output in a `well` row, OMR service, keys masked in mono. |
| 09 | Alerts | Delete confirmation and a naming alert, same width and footer. |
| 10 | States | No arrangement open · engraving · render failed · engine unreachable. |
| 11 | iPhone | One pane at a time; overlays go full width; pill drops the pencil. |
| 12 | Tokens and controls | The board: surfaces, ink, accent, status, type ladder, every control state. |

---

## 9. Accessibility

- Contrast: `ink`, `ink2`, `clayStrong` and white-on-`clayPress` all clear 4.5:1
  on their surfaces. `clay`, `ink3`, `warn` and `ok` clear 3:1 and are therefore
  restricted to ≥15pt semibold text, numerals, icons and borders — the tables
  above state which is which. Nothing carries meaning by colour alone.
- Hit targets: 44 × 44 minimum, including the pill's 38pt buttons and the ink dots.
- Dynamic Type as specified in §2; the library and chat panels scroll rather than
  clip, and rows grow.
- VoiceOver: the labels already in the app stay. New ones needed for the pill
  ("Library", "Chat", "Version v014, pick another"), the numeral ("Arrangement
  number 2"), the LED ("Engine connected / unreachable"), and the ink dots.
- Reduce Motion and Reduce Transparency both fall back to the flat, non-sliding
  variants described in §5.

---

## 10. Non-goals

Dark mode. A second accent. Serif type. SF Pro. Rounded cards. Gradients.
Translucent chrome. Icons in the score page. Restyling the engraving.

---

## 11. Applying it (next step, once approved)

1. `Theme.swift` becomes the token file: `Theme.Color` (the tables in §1),
   `Theme.Font` (§2, custom faces with `relativeTo:`), `Theme.Metric` (§3–4).
   Bundle Space Grotesk, Inter and IBM Plex Mono; register them in `Info.plist`.
2. New view components, one per §7 entry, in a `DesignSystem/` group: `Pill`,
   `OverlayPanel`, `BandHeader`, `Row`, `NumeralBadge`, `VersionRow`, `Bubble`,
   `OpCard`, `InkBar`, `HighlightChip`, `PanelButton`, `PanelToggle`, `PanelField`,
   `LED`, `PanelSheet`, `PanelAlert`, `StateView`.
3. `ContentView` loses `NavigationSplitView`: the detail canvas becomes the root,
   with the library and chat as overlays driven by two booleans. The existing
   toolbar items move into the pill; the versions menu keeps its behaviour behind
   the version chip. This is the largest change and the one to review first.
4. `ChatView`, `ScorePagesView`, `AnnotationTools`, `SettingsView`, `ScoreInfoView`
   restyle onto the new components; the six alerts become `PanelAlert`.
5. Risks worth naming before starting: the split-view removal touches every
   navigation path including compact width; `AnnotationController.Ink.black`
   becomes `ink` (`#1A1917`), so previously drawn strokes stay pure black while
   new ones do not; and `Theme.arrangementNumber` (currently system purple) is
   replaced by `clay`, which is also the accent — the numeral now shares a hue
   with the chrome and depends on size and weight to stay distinct.
