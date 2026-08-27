# Size and position for added score elements — analysis and spec

Not built. For Ali's confirmation. Chord symbols first.

**Revised 2026-08-27** for the two app-wide rules that landed after the first
draft: **no drag anywhere** and **no modals**. Everything about the pipeline, the
storage decisions and the op is unchanged; §"Gestures" is replaced by
§"Interaction — no drag, no modal" below, and `docs/hold-then-drag-spec.md` is
superseded by it.

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

## Interaction — no drag, no modal

Selection is unchanged: the Pencil lassos, a tap adds or drops one element, a
held finger of the other hand adds. What changes is what happens *after* — the
first draft moved a selected element by holding and dragging it, and there is no
dragging in the app any more.

### The control surface: the selection chip, extended

The chip already is the right thing — it appears only when something is selected,
it is anchored at the top of the canvas, it blocks nothing, it needs no
dismissal, and it already carries `Use in chat` and a clear button. It gains one
row, shown only when every selected element is adjustable (today: chord symbols):

```
┌────────────────────────────────────────────────────────────────┐
│ Dm · bar 21 · Acc. Chords                                  ✕   │
│ POSITION  ◀  ▲  ▼  ▶   │   SIZE  A⁻  14 pt  A⁺   │   Reset     │
│ pending: 0.5 sp up · 14 pt                          Revert     │
│ [ Use in chat ]                                                │
│ Hold a finger down to add · tap an element to drop it          │
└────────────────────────────────────────────────────────────────┘
```

**Docked, not floating beside the element.** A control cluster that follows the
selection would sit on top of the music, land off the page for a symbol near an
edge, and move under the thumb as the element moves. The chip is in one place,
always, and the element stays visible while you nudge it — which is the thing you
actually need to watch.

### Position — four buttons, one step each

| | |
|---|---|
| step | **0.5 staff space** per tap — 5 MusicXML tenths, exactly 1 MEI half-space, so no rounding anywhere in the chain |
| repeat | press and hold auto-repeats after 400ms at 8/s. A tap alone always works; this is a press, not a drag, and not a hidden affordance |
| bounds | clamped to ±4 staff spaces vertically, ±2 horizontally; the button disables and dims at the limit, exactly like `▲▼` on an ordered row |
| multiple selection | all selected symbols move by the same delta — the chip says `3 chord symbols` |

### Size — a ladder, not a multiplier

Points are what the file stores (`font-size` on `<harmony>`), so the UI steps
through a ladder of clean values rather than multiplying: **8, 9, 10, 11, 12,
14, 16, 18, 20, 24**. `A⁻`/`A⁺` move one rung and the current value is shown
between them; the buttons disable at the ends. 12 pt is
`ChordAdjustments.defaultChordPoints`, i.e. the untouched size, so the ladder
always has a home. A multiplier would have written 13.5 pt and then 15.19 pt into
the notation and made "put it back" impossible to hit exactly.

**No pinch-to-resize.** Unchanged from the first draft and now doubly true:
two fingers mean zoom, and one of them parked means add-to-selection. A third
meaning would make zoom unreliable on a score someone is reading.

### Committing — one version per element per session

Each tap must *not* be an op. Taps accumulate as a **pending adjustment**, shown
in the chip, and commit as a single `adjust-element` when you leave the element:
deselect it, select another, leave the score, or after 3s of no further taps.
That is exactly the tap-to-edit rule from `NAV_MODAL_FREE_0.4.2.md` §4A —
commit on leaving — applied to a numeric value instead of a name.

Preview costs no round trip: the app already applies size and offset itself in
`ChordAdjustments` (MEI `@ho`/`@vo` for position, its own SVG pass for size),
so pending values are drawn locally and only the commit reaches the engine.

`Revert` in the pending line discards the uncommitted change. Once committed,
the version history is the undo — and consecutive `adjust-element` versions
should be grouped in the version list the way a chat turn's steps already are
(`AppState.VersionGroup`), with a synthetic turn id per adjustment session, or
nudging four symbols reads as four unrelated versions.

### Reset — four levels, because an override nobody can undo is a trap

| level | where |
|---|---|
| discard the pending change | `Revert` in the chip |
| this element back to inherited size and zero offset | `Reset` in the chip |
| every chord symbol in this part | `… → Score display → Chord symbols ›` → *Reset all adjustments*, with the two-step inline confirm (no dialog) |
| by voice | chat: "put the chord names back where they were" |

### Per-element or chart-wide — both, and they are different controls

- **Per element**: the chip. Writes `font-size` / `relative-x` / `relative-y` on
  that one `<harmony>`.
- **Chart-wide**: a new `… → Score display → Chord symbols ›` screen, carrying
  the part's default size (same ladder) and the reset-all. This is the value new
  symbols inherit; per-element values override it and survive it changing, which
  is the point of storing absolute points per adjusted element.
- **Chat** reaches both: "make the chords bigger" (chart-wide, one step) versus
  "make the Dm in bar 21 bigger" (that element). The agent should say which it
  did.

### Accessibility — a strict improvement on dragging

Every control is a real button with a spoken label ("Move Dm up half a space").
The size control carries the VoiceOver `.adjustable` trait, so a swipe up or down
steps the ladder. All of it is reachable by Switch Control and full keyboard
access, none of which could ever perform the drag this replaces.

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
4. Chip row: position pad, size ladder, Reset, and the pending line with Revert.
5. Commit-on-leave with session grouping in the version list.
6. `… → Score display → Chord symbols ›` screen: part default size, reset all.
7. Chat wiring, both tool lists.

Deliberately not in it: pinch-to-resize, dragging of any kind, other element
kinds, per-part styling beyond the default size and the reset, and anything
about notes.

## What I need confirmed

1. Store absolute points in the file, drive it relatively in the UI.
2. Versioned notation, one version per **adjustment session** (not per tap),
   committed when you leave the element.
3. Buttons for both size and position — no pinch, no drag.
4. The step sizes: 0.5 staff space per nudge, and the 8→24 pt ladder.
5. Size lives in two places on purpose: a part default on the Chord symbols
   screen, per-element overrides from the chip.
6. That reconciling the in-app/PDF chord styling is in scope as the first step
   — without it, an offset means two different things. **Still the one real
   blocker**, unchanged from the first draft.

## Flags

- **Selection must survive the op.** Nudge, commit, re-render — if the selection
  is lost the next nudge has nothing to act on. `selectionKey` /
  `selectionCarryNote` already carry a selection across ops; this needs a test
  that says so for `adjust-element`.
- **Paged canvas**: an element belongs to one page, offsets are page
  coordinates, and the clamp keeps a symbol from wandering into the system above.
  Nothing about paging changes the mechanism.
- **"A bit" in chat** is one step. "A lot" is ambiguous — the agent should pick
  three and say what it did rather than guess silently.
- **`docs/hold-then-drag-spec.md` is superseded** by the interaction section
  above and should be deleted or banner-marked before anyone builds from it.
