# Size and position for added score elements — analysis and spec

Not built. For Ali's confirmation. Chord symbols first.

Everything below was measured against the real pipeline rather than assumed.

## What the pipeline actually does

| step | position | size |
|---|---|---|
| music21 → MusicXML | `relative-x` / `relative-y` on `<harmony>` **round-trip exactly** | `font-size` **round-trips exactly** |
| Verovio's MusicXML importer | **drops it** — the MEI has only `staff` and `tstamp` | **drops it** |
| MEI `@ho` / `@vo` on `<harm>` | **works, per element** — `@vo="-6" @ho="4"` moved one chord symbol from x=4129 y=994 to x=4489 y=1540 while its neighbour stayed put | — |
| MEI `@fontsize` on `<harm>` | — | **ignored**, as `200%` and as `large`: the glyph stayed at 405px |
| our own SVG pass | — | **works** — the `<harm>` group carries the MEI id, so one specific symbol can be found and its glyph rescaled |

So the architecture follows from the measurements, and it is the pattern already
in the codebase for whistle fingerings:

- **The notation stores it.** `relative-x`, `relative-y`, `font-size` on
  `<harmony>` — standard MusicXML, portable to any other program.
- **Position is translated to MEI** (`@ho`/`@vo`) in the same round trip that
  already applies chord styling in `render.py`.
- **Size is applied in our own SVG pass**, because Verovio has no per-element
  text size at all. Note the trap: the `<text>` element is `font-size="0px"` and
  the real size lives on the inner `tspan` — the same one that gave every
  fingering circle a radius of zero.

## The thing that has to be fixed first

**The in-app renderer applies no chord styling at all; `render.py` applies the
whole Real Book treatment** (names on the staff via `place="within"`, Helvetica
bold, grey staff lines). Zero references to `harm` in `VerovioRenderer.swift`.

Chord symbols therefore sit in *different places* on screen and in the exported
PDF today. If we ship nudging on top of that, a user's offset means one thing in
the app and another in the PDF, and "move it up a bit" becomes unreproducible.

**Recommendation: reconcile before adding adjustment.** The right fix is not to
port the styling twice but to write it into the notation at op time — the
placement becomes explicit attributes on each `<harmony>`, and both renderers
draw what is there. That is the same rule the rhythm work landed on:
correctness belongs in the op, not in each renderer.

## The three decisions

**1. Relative or absolute size — store absolute, drive relative.**
MusicXML `font-size` is in points and is what every other program reads, so the
file stays portable. The *gesture* is relative: bigger/smaller multiplies the
current value by a step. The user thinks "a bit bigger"; the file records a real
size. This also survives the failure we just had — a global option moving the
absolute size under everyone — because each adjusted element now names its own.

**2. Versioned notation, not per-device view state.**
Consistent with everything else here: the notation is the source of truth, the
adjustment travels with the score, exports correctly, and survives a device
change. The cost is real and worth stating: **each adjustment is a version**. A
drag must therefore commit **one** op when the gesture ends, never per frame,
or a single nudge writes forty versions.

**3. Reset.** Three ways, because an override nobody can undo is a trap: a
`--reset` on the op, a Reset control on the selection chip beside the size
controls, and chat ("put the chord names back where they were"). Plus a
part-wide reset, since a user who nudged ten symbols will not undo them one at
a time.

## Ops and chat

One op, matching how the UI already addresses things:

```
scor adjust-element <score> --part X --measure N --kind harm [--ordinal 0]
                    [--size 14] [--bigger | --smaller]
                    [--offset-x 2.5] [--offset-y -4] [--reset]
scor adjust-element <score> --part X --kind harm --all --size 16   # part-wide
```

`--kind harm --measure N --ordinal K` is exactly `ScoreAddress`, so the UI passes
what the lasso already resolved and no new identity scheme is needed. Chat gets
the same tool, which is what makes "make the chord names bigger" work.

## Gestures — and how they coexist with the lasso we just shipped

The rule is decided at the moment of the hold, by what is under the finger:

| gesture | result |
|---|---|
| hold-then-drag on **empty paper** | lasso (unchanged) |
| hold-then-drag on a **selected element** | **moves that element** |
| tap a selected element | drops it from the selection (unchanged) |
| chip **A⁻ / A⁺ / Reset** | size, in steps |
| two fingers | pinch/zoom (unchanged) |

This matches what iOS does everywhere — hold on an item picks it up, hold on
empty space starts a marquee — and it costs no new gesture.

**On pinch-to-resize, I recommend against it, and this is the one place I am
not doing what was asked.** Two fingers already mean two things: zoom, and
add-to-selection (parked finger plus a dragging one). Making them mean a third
thing on a score people are reading is how zoom becomes unreliable. The chip's
size controls are deterministic, testable, and reachable with one hand. If Ali
still wants pinch after trying the buttons, it can go on top later — but I would
rather ship the reliable thing first than spend a build tuning a three-way
two-finger arbitration.

## Cross-feature implications

- **Lasso selection**: the only real interaction. Resolved above; needs a test
  that a drag starting on empty paper still lassos.
- **Tap-to-drop**: unaffected — a tap has no movement, a drag does.
- **Rhythm**: offsets and sizes touch no duration. `check_rhythm.py` gains a
  case asserting `adjust-element` moves no note, alongside the structural marks.
- **`check_render.py`**: gains cases — an adjusted symbol renders at its size
  and offset; an unadjusted neighbour does not move; and the app and PDF paths
  agree.
- **Two-page spread**: offsets are per element in page coordinates. Unaffected.
- **Whistle fingerings**: also lyric-anchored, and the same mechanism would
  generalize to them. Out of scope for the first increment.
- **Export**: the PDF must honour the same adjustments — which is the
  reconciliation above, and why it comes first.

## Relationship to the deferred move/duplicate spike

That spike was blocked on identity: *"Verovio's element ids are generated during
its own conversion and do not map back to music21 objects, so 'this fermata on
screen' cannot be resolved to 'that fermata in the file'."*

This work solves that for offset-anchored elements, and not by fixing Verovio's
ids: the app already holds a durable `ScoreAddress` for everything it selects,
and `.harm` is already an addressable kind. The op is addressed the same way, so
the round trip is engine-side and never depends on a generated id. When the
spike is picked up, chord symbols and text will already be moveable, and the
remaining question is only the harder one — notes and spanners.

## First increment

**Chord symbols only. Size and position. Nothing else.**

1. Reconcile the in-app and PDF chord styling (prerequisite).
2. `adjust-element` op for `harm`, with reset, TDD.
3. MEI translation for position, SVG pass for size, in both renderers.
4. Chip controls: A⁻ / A⁺ / Reset for the selected element.
5. Drag a selected element to move it, with the arbitration above.
6. Chat wiring, both tool lists.

Deliberately not in it: pinch-to-resize, other element kinds, per-part styling
beyond a part-wide reset, and anything about notes.

## What I need confirmed

1. Store absolute points in the file, drive it relatively in the UI.
2. Versioned notation, accepting one version per completed adjustment.
3. Chip buttons for size rather than pinch, at least to begin with.
4. That reconciling the in-app/PDF chord styling is in scope as the first step
   — without it, an offset means two different things.
