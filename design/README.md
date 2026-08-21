# Scoranger visual revamp

Two phases live here: the A/B/C decision deck (phase 1, answered) and the
combined system built from the answers (phase 2, awaiting final approval).

Prototype/decision phase only. Nothing here touches app code.

## What's here

- `scoranger-design-options.html` — the interactive deck. Seven questions
  (palette, typeface pairing, type scale, mood/surface, iPad layout, signature
  move, light/dark), three options each, every option rendered on the same fake
  Scoranger screen: sidebar (setlists → pieces → `#N` arrangements → nested
  versions), score canvas with the markup bar, chat pane mid-request.
  - Each question changes **one** dimension; everything else sits at a neutral
    baseline (palette A, Inter Tight, compressed scale, instrument-panel mood,
    flush columns, numbers-as-identity, light) and follows your picks as you make
    them.
  - Tap a screen to fill the display and flip A → B → C (arrow keys on desktop).
  - Tap `Pick A/B/C` to lock a choice; the bottom bar builds the answer string
    (`1A 2B 3C …`) with a copy button.
  - Screenshot modes used by the renderer: `?shot=1A` (one frame, exactly
    1180×740) and `?sheet=1` (all three options of a question, stacked, labelled).
- `png/q<N>-<dimension>-<A|B|C>-<name>.png` — 21 single-option frames, 2360×1480.
- `png/sheet-q<N>.png` — 7 comparison sheets, one per question, A/B/C stacked.
- `png/q2-typeface-specimens.png` — the three Q2 pairings at display size (Q2 is
  otherwise decided at 13px, which is unfair to it).
- `artifact.html` — the same deck with the page wrapper stripped, published as a
  private Claude artifact so it can be opened and tapped through on a phone:
  https://claude.ai/code/artifact/849a14ca-c481-4315-9a29-8dd380ec4afa
  (regenerate it from the HTML with the snippet in `shoot.sh`'s sibling comment,
  or by re-deriving: strip doctype/html/head/body, keep the `<title>`.)
- `shoot.sh` — regenerates every PNG from the HTML with headless Chrome.
  `ONLY="2C 7B" SHEETS="2" SKIPSPEC=1 ./shoot.sh` re-renders a subset.

## Regenerating the PNGs

```
./shoot.sh
```

Headless Chrome on this machine writes the screenshot and then does not exit, so
the script backgrounds each run, waits for the file, and kills only the process
it spawned.

## Notes on what the mockups deliberately show

- The green engine LED and the five pen-ink dots are *content*, not palette:
  they stay outside the three-colour budget in every option.
- The score page is white paper in every option, including the dark ones — the
  engraving comes from Verovio and is not ours to re-colour.
- Fonts are loaded from Google Fonts for the mockup. Shipping any of Q2's
  options means bundling the font files in the app (~1–2 MB); only SF Pro is free.


---

# Phase 2 — the chosen system

Picks: **1A 2B 3A 4B 5C 6A 7A** — Paper & Clay, Space Grotesk + Inter + IBM Plex
Mono, compressed weight-driven scale, instrument-panel surfaces, score-first
overlay layout, `#N` as the identity element, light only.

- `DESIGN_SYSTEM.md` — the spec: colour and type tokens with contrast ratios and
  usage rules, spacing/border/elevation/motion ladders, 18 component specs, a
  screen-by-screen table, accessibility rules, non-goals, and the plan for
  applying it to the app.
- `scoranger-system.html` — the combined mockup: 12 screens of the real app
  surfaces in the new system, tap-to-enlarge. `?screen=s4` renders one screen
  full-bleed at 1180x886 for screenshots.
- `artifact-system.html` — wrapper-stripped copy, published at
  https://claude.ai/code/artifact/6a3c32b5-104e-477f-9dee-86d8e90e75ad
- `png/system-01…12-*.png` — the 12 screens at 2360x1772.
- `shoot-system.sh` — regenerates them (`ONLY="s4 s9" ./shoot-system.sh` for a subset).
