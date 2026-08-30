# Open visual defects

**Superseded for 0.4.7 (build 149).** L21–L34 and #40–#53 were fixed in 149 and
re-verified; what remains open there is tracked in `QA_OPEN_149.md`. Kept for
the history of what 147 looked like.

# Open visual defects — verified against build 147 (0.4.6)

Every item below was re-confirmed on **147** (`ca64739`), iPad Pro 13-inch, both
orientations. Frames: `design/qa/147/`. Fixed items are not repeated — see
`QA_FINDINGS.md` for the closed ones.

| # | Defect | Frame | Root-cause fix |
|---|---|---|---|
| **L21** | Landscape two-page spread clips the top of both pages and leaves ~250pt of blank paper below; single-page landscape and all of portrait fit correctly | `L-32-score-two-page-spread.png` (cf. `L-30`, `P-30`) | The canvas sizes the spread from **width** only. Fit by `min(fitWidth, fitHeight)` before centring, so the spread's height is bounded by the canvas |
| **L29** | Page/bar counters are drawn on top of the chat panel header, burying the model chip (`gemini-flash` half-hidden under `pp. 1–2 / 9`) | `L-36-chat-open.png` | `PositionCounters` is pinned `.topTrailing` of the whole canvas stack; inset it by the chat panel's width while chat is open (or move it under the top bar) |
| **L31** | Chat input is a ~200pt-tall box holding a one-line placeholder | `L-36`, `L-37-chat-input-focused.png` | Start at one line and grow to a 4-line cap (`.lineLimit(1...4)`), instead of a fixed-height editor |
| **L32** | The chat Send button is clipped to "Sen…" by the panel edge | `L-36-chat-open.png` | Fixed 34pt icon button (glyph, not the word), input takes the remaining width |
| **L30** | Chat header title truncates ("Sous le ciel quart…") while space is free | `L-36-chat-open.png` | Falls out of L29; then give the title `layoutPriority(1)` over the model chip |
| **L22** | Edit mode still renders per-row `Versions / Set lists / Delete` buttons, duplicating the bottom action bar | `L-08`, `P-08-library-edit-selected-actionbar.png` | Delete `LibraryView.editingActions`; the action bar owns bulk verbs and `☰` owns per-row ones |
| **#40** | In Edit mode the row's `☰` is replaced by a chevron, undoing L14's rule | `P-08-library-edit-selected-actionbar.png` | Keep `RowMenuButton` visible in both modes; never swap it for a chevron |
| **L34** | Options rows run full-bleed (label ~2600px from its chevron), have no separators, and most show no current value | `L-33-score-options.png` | Cap the content column (~720pt, centred), add `Theme.Line.line` separators, populate trailing values. Same for Settings / Details / Move-to-piece |
| **L33** | Performance mode uses a stock iOS `Toggle` — the only non-system control in the app | `L-33-score-options.png` | Swap for `PanelToggle` |
| **L13** | Alphabet section header is a 10pt speck: casing and hairlines are right, but it uses the generic `.label` role instead of the specced 13pt Space Grotesk | `L-01-library-pieces.png`, `L-04` | Give `BandHeader` an index variant at `typeRole(.titleS)` (13pt Space Grotesk 700), or pass a role parameter |
| **#39** | Unfiled arrangements appear to be counted as pieces: header says "2 pieces · 2 arrangements" while both rows are `UNFILED` and their subtitles read "unknown · 9 versions" | `X-remote-mode-library.png` | Decide what an unfiled arrangement is in the count, and make the row subtitle match: a piece row says composer · N arrangements, an arrangement row says parts · N versions |
| **L23** | Entering Edit mode shifts the whole list right by ~75pt | `L-01` vs `L-08` | Put the checkbox in a fixed 44pt leading gutter so content moves by 44, not 75 |
| **#41 / L18 nit** | The score subtitle ends with a dangling "·" before the mode chip ("… · v003 ·") — one item, listed twice in earlier batches | `L-30-score-reading.png`, `L-31` | Build the subtitle by joining non-nil parts; the chip is not a joined component |
| **L24** | The ink bar leads with an unexplained 4-way move glyph before pen/eraser | `L-38-edit-ink-mode.png` | If it drags the bar, remove it (§4B no-drag); if it is a tool, label it and add it to the spec |
| **L12 nit** | The empty-state `Import` button is a plain bordered button, not the specced primary | `L-61-library-empty.png` | `PanelButton(kind: .primary)` |
| **L35** | *Decision, not a defect:* the chat pane's drag grip is the one drag affordance left | `L-36-chat-open.png` | Keep as a resize, or replace with a two-width toggle in the chat header — Ali's call |

## Suggested fix order

1. **L21** — the reading surface is clipped; nothing else is more visible.
2. **L29** — hard text-on-text collision.
3. **L22 + #40** — one change to the row/Edit-mode rules, closes both.
4. **L31, L32** — chat input and Send; small and adjacent.
5. **L34, L33** — the pushed-screen family reads as unfinished; both live in the same views.
6. **L13** — one type role.
7. **#39** — needs a product decision on counting before the code.
8. **L23, #41, L24, L12 nit** — small, independent.
9. **L35** — decide, then it is either nothing or a five-line change.

## Not covered by this run

Piece and arrangement screens, move-to-piece, set-lists-for, versions, parts,
delete-confirm, the undo bar, Settings itself, long-title states, and the
selection chip's size/position row. The harness has been fixed for the next run
(two-piece seed made through the UI, plus an asserted return to the library
before Settings and before each section) but **not yet run**.
