# Visual QA — findings queue

Swept on **iPad Pro 13-inch (M5), iOS 26.5**, build `72c77a5` (0.4.5, Home merged
into My Library), landscape **and** portrait, by
`ios/ScorangerUITests/VisualSweep.swift` (untracked harness; `xcodegen generate`
picks it up).

Screenshots: `design/qa/landscape/` (27 states) and `design/qa/portrait/` (11).
Landscape frames are rotated upright — `XCUIScreen.screenshot()` writes the raw
portrait framebuffer.

Numbers are stable across batches; do not renumber.

## Fixed / not reproducing

| # | Was | Now |
|---|---|---|
| 1 | engine chip read "on-device on-device" | reads it once, every frame ✓ |
| — | "ink toolbar floats over the middle" | docks at the canvas bottom, above the strip ✓ (`landscape/L-38`) |
| — | "spread pages render at different heights" | same height; the real problem is #21 ✓ |

## Open — ordered as a fix queue

| # | Screen · element | Problem | Shot | Fix |
|---|---|---|---|---|
| 29 | Score · position counters over chat | `pp. 1–2 / 9` and `bar 1` sit **on top of** the chat header; the model chip is drawn under them | `landscape/L-36` | inset the counters by the chat width while it is open, or move them below the top bar |
| 21 | Score · paged canvas, **landscape only** | page/spread is not fitted to canvas **height**: the top system is sliced and ~250pt of blank paper sits below. Portrait fits correctly | `landscape/L-32`, `L-38`; cf. `portrait/P-30` | fit by `min(fitWidth, fitHeight)`; and drop the stale `bottomChrome: pillHeight` (#9) |
| 22 | Library · Edit mode | per-row `Versions / Set lists / Delete` buttons under the row, duplicating the action bar; the row's `☰` disappears in Edit mode while the chevron stays | `landscape/L-08` | delete `LibraryView.editingActions`; keep `☰` in both modes |
| 31 | Score · chat input | input box ~200pt tall for a one-line placeholder | `landscape/L-36`, `L-37` | one line, growing to a 4-line cap |
| 32 | Score · chat Send | label clipped to "Sen…" by the panel edge | `landscape/L-36` | 34pt icon button; input takes the remaining width |
| 11 | Library · title | count is a bare number: "My library **1**", "My library **0**" | `landscape/L-01`, `L-61` | "1 piece · 2 arrangements"; "No pieces yet" at zero |
| 13 | Library · alphabet header | lowercase "s" in an ~18pt band with no rules | `landscape/L-01`, `L-04`, `L-08` | uppercase, `BandHeader` metrics (§12.6) |
| 14 | Library · row trailing | meta + chevron + **unstyled** `☰`: three affordances, the `☰` a naked glyph while every other icon control is bordered | `landscape/L-01`, `portrait/P-01` | drop the chevron where `☰` exists; give `☰` the 34pt bordered frame; `lineLimit(1)` + `fixedSize` on the meta; restore 20pt trailing padding |
| 34 | Score · Options screen | rows run full-bleed (label ~2600px from its chevron), no separators, most rows show no value | `landscape/L-33` | cap the column ~720pt centred; `line` separators; populate values. Applies to Settings/Details/Move-to-piece too |
| 15 | Library · sort & filter reveal | no `reveal` container (no `well`, no hairlines); options lowercase against sentence case everywhere else | `landscape/L-04`, `L-05` | wrap in `reveal`; sentence-case the labels |
| 12 | Library · empty state | a stray left-aligned sentence in ~1500pt of empty ground — no glyph, title or button, and it is now the **first screen a new user sees** | `landscape/L-61` | use `StateView` with a primary `Import` |
| 33 | Score · Options | stock iOS `Toggle` — the only non-system control in the app | `landscape/L-33` | `PanelToggle` |
| 23 | Library · Edit mode | list lurches right ~75pt when checkboxes appear | `landscape/L-01` vs `L-08` | 44pt leading gutter |
| 19 | Score · top bar subtitle | `… · v003 Pencil: select` — mode text abuts the version with no separator | `landscape/L-30`, `L-31` | own chip, or move beside the pencil button it describes |
| 16 | Score · title switcher band | fixed at ~35% of the canvas (31% in portrait) regardless of content; the score is squashed | `landscape/L-31`, `portrait/P-31` | size to content, cap ~40%, scroll internally |
| 17 | Score · title band, versions column | rows show ids only (`v003 / v002 / v001`) — no prompt or op, so switching is blind | `landscape/L-31` | render the turn prompt, else the op name, one line |
| 30 | Score · chat header | title truncates to `sous-le-ciel-quar…` while space is free | `landscape/L-36` | falls out of #29; then give the title layout priority over the model chip |
| 18 | Score · title, and the engraved page | shows the raw slug `sous-le-ciel-quartet` in the top bar **and** engraved at the top of the page | `landscape/L-30` | set a human title at import (`set-metadata`); never fall back to the slug |
| 20 | Score · thumbnail strip | pages 8–9 render as blank placeholders while 1–7 are real, in both orientations | `landscape/L-30`, `portrait/P-30` | render all strip thumbs at low DPI, or show a distinct "couldn't draw" state |
| 24 | Score · ink bar | leads with an unexplained 4-way move glyph before pen/eraser | `landscape/L-38` | if it drags the bar, remove it (§4B); if it is a tool, label and spec it |
| 8 | Whistle diagrams | octave "+" centres on its own x, not the column anchor — `scaleText` takes `anchorX` and ignores it | code: `FingeringDiagrams.swift:446` | `let centre = (anchorX ?? own) + centreXVsRadius * radius` |
| 9 | Score canvas | `bottomChrome: Theme.Metric.pillHeight` reserves 50pt for a pill that is not in the score view; pushes content 25pt above centre | code: `ScorePagesView.swift:72` | pass the real chrome (0, or ink-bar height when annotating). Likely also fixes #21 |
| 2 | Settings · LED | `LED` prints "on-device" whenever connected, regardless of `useLocalEngine`; used bare in Settings | code: `Components.swift`, `SettingsView.swift:76` | dot only; callers supply the mode word. **Still unverified on screen** |
| 35 | Score · chat divider | the drag grip above the input is a drag affordance (§4B) | `landscape/L-36` | **decision:** keep as resize, or a two-width toggle |

## Not yet covered

- **Piece and arrangement screens, move-to-piece, set-lists-for, versions,
  parts, delete-confirm and undo bar** — with one seeded piece the row opens the
  score directly, so the sweep never lands on them. Next run seeds a second piece.
- **Selection chip and the chord size/position row** — `-seedChordChart` alone
  produced an empty library; now seeded alongside `-seedTestLibrary`.
- **Long-content states** (long titles, many arrangements) — the portrait twin of
  the edge-state sweep has not run. #14's actual *overlap* needs these.
- **iPhone size class** — only iPad so far.
