# After 0.6.1: the twenty items, grouped

Written 2026-09-02, the night 0.6.1 (build 161) went out. Twenty items came in
as one list; they are not twenty pieces of work. They are six, and one of them
is most of the risk.

Status keys: **landed** = committed on a branch tonight, not yet gated or
shipped. **in flight** = being worked now. **queued** = understood, not started.

## A. The notation rendering overhaul — bugs 2, 4, 9, 10, and the continuous view

*The big one, and the only group I would not promise a date for.*

A MusicXML or OMR'd score renders as ONE long unpaginated system, blurry, and
cannot be zoomed out. Continuous view is separately broken: staff lines running
off both edges with no clef or margin, noteheads far too large, opening deep in
the piece. These are one fault family, not five bugs.

Two causes are established:

1. `ContinuousTiles.fittedScale` had no upper clamp. The continuous strip is
   short by design -- Verovio engraves it with `breaks: none` and
   `adjustPageHeight` -- about 540pt for a four-staff system and 150pt for a
   single staff. Fitting that height into a 2000pt portrait viewport is 3.5x
   for a quartet and about 13x for one voice. That is bug 9's "giant notes,
   cannot zoom out" and the oversized continuous view. **A ceiling has landed.**
2. The two Verovio option sets did not both NAME `breaks`. Only the continuous
   set specified it, so the paged set took whatever the toolkit last held --
   which is how a paged score came back as one system with no line breaks and a
   page count of 1. **Both sets name it now.**

Bug 4's blur and the shading flip between page and two-page are consistent with
a strip rasterised for one scale being drawn at another, and bug 10's garbled
thumbnails look like the same seam. Neither is confirmed.

Effort: the rest of this is **1-2 days**, and it is the group most likely to
uncover something underneath. Today the same code produced a confident,
unanimous, wrong diagnosis that only a check caught, which is why every fix here
gets a check before it is believed.

Designer-gated: no.

## B. Playback scrolling and the continuous playhead — bug 6

*A rework, not a bug fix, and it sits on top of A.*

The spec: a line from top staff to bottom staff at the sounding moment, moving
smoothly with tempo, crossing each note as it plays with that note highlighted;
during playback the LINE STANDS STILL and the SCORE SCROLLS PAST IT, DAW-style;
a manual scroll does not stop playback but does stop auto-scroll, and a Sync
button returns to the line-stands-still state.

The paged half of this already exists and shipped in 0.6.0 -- the playhead, the
85% page turn, PageFollow and the Sync chip. Continuous has none of it: no
playhead, and no `pageFollow` gate at all, which is why a scroll during playback
is snapped back. Note highlighting was specified in `design/PLAYBACK_0.6.md` as
a clay overlay over the notehead frame, because the canvas is a rasterised PDF
and a glyph cannot be recoloured in place.

Depends on A: a playhead cannot be placed correctly in a view whose scale and
layout are wrong.

Effort: **1 day** after A. Designer-gated: no -- `PLAYBACK_0.6.md` covers it.

## C. Import, titles, and OMR progress — bugs 1, 3, feature 2

*Mostly landed tonight.*

- **Bug 1, the title.** After OMR the engraved title became `v001.mxl`. music21
  seeds the movement title from the source FILE NAME when a file carries no
  title -- a trap `CLAUDE.md` already documents and `set-metadata` already
  exists to contain; the OMR path simply never called it. **Landed.**
- **Bug 3, Import Book.** A 52MB Real Book PDF imported nothing from either
  iCloud Drive or local storage, and the Books segment showed a SET LIST empty
  state. The cause looks like a missing dependency in the vendored on-device
  packages -- the same class of failure as the vendored-engine staleness that
  bit twice today, where a feature works in the CLI and does nothing in the app.
  **Landed, needs verification against the reader's actual 52MB file.**
- **Feature 2, Make Editable.** Becomes a switch like Performance Mode, with
  in-row OMR progress, since pressing it currently looks like nothing happens.
  Both this and the transport's new "Run OMR to play" button drive the same
  code. **In flight.**

Effort: **half a day** remaining, mostly verification.
Designer-gated: feature 2's progress treatment, lightly.

## D. Ink and selection — bugs 7, 8

Pen selection does not work in scroll view at all, and in page view the ink is
far too thick -- the thin line is gone. Both are small and both touch the canvas
that group A owns, so they wait for A rather than fight it.

Effort: **half a day**. Designer-gated: no, this is restoring a lost look.

## E. Performance — bug 5

The app has grown slow since PDF and MusicXML rendering both landed; the version
dropdown takes about a second. The ask is instrumentation first -- display and
update rates -- and then the cause.

This is the item most likely to be under-served by a rushed fix, and the one
whose value compounds: nobody should optimise this renderer without numbers,
especially while group A is changing it. Instrument early, optimise after A
settles.

Effort: **half a day** to instrument, unknown to fix.
Designer-gated: no.

## F. The design cluster — features 1, 3, 4, 5, 6, 7, 8, 9, 10

Nine items, and most are one idea: **the reader cannot tell a PDF from a
MusicXML anywhere in the app**, which is a direct consequence of shipping
PDF-as-is. Features 3, 4 and 5 are that idea in three places -- the lists, a
piece-level tag including set lists, and a marker in the score view.

The rest are placement and reach: the version stamp to top centre (1); the
Score display menu removed and Show transport moved up beside the layout
buttons (6); chord symbols promoted a level with editable sizes, which today
cannot be tapped at all (7); Versions removed from Options, and the top
dropdown showing ONLY versions rather than a split that also lists pieces (8);
spacebar to start and stop the transport (9); the mixer at half height with a
distinct tempo slider, 1-300 bpm (10). **Mixer half-height and tempo have
landed.**

Effort: **1-2 days**, and it parallelises well because it barely touches A or B.
Designer-gated: yes for 3, 4, 5, 6, 7, 8 and 10 -- behaviour is being built to
the written spec and styling kept swappable so the designer's answer drops in
rather than requiring a rewrite.

## Suggested sequence

1. **C and F first** -- they are nearly independent of the hard problem, several
   are already landed, and they are what the reader touches every day.
2. **A next**, on its own, with checks. It is the root of five reported bugs and
   nothing downstream is trustworthy until it settles.
3. **B after A**, because a playhead in a mis-scaled view proves nothing.
4. **D after A**, same reason -- both live on the canvas A is rebuilding.
5. **E alongside**, instrumenting early and optimising once A has stopped moving.

## Quick wins, in order of cheapness

Bug 1 (title) · the Books empty-state copy · feature 1 (version stamp) ·
feature 9 (spacebar) · feature 6 (remove the display menu) · feature 10 (mixer
height and tempo). Four of these are already committed.

## What will not be quick

Bug 4's blur and bug 10's thumbnails, if they turn out not to share A's cause.
Bug 5's slowness, which has no diagnosis yet. Bug 3's verification, which needs
the reader's own 52MB file rather than a fixture.

---

# What happened: all of it shipped as 0.6.3 (build 162), overnight

Written 2026-09-03, after the fact. The plan above was drawn up expecting several
days and two or three builds. Nine branches landed in one night and went out as a
single release, so the C+F / A / B+D / E sequencing below describes the *reasoning*
rather than what the calendar ended up looking like.

**Every group A-F is in build 162 except E's optimisation**, which was deliberately
held: the instrumentation shipped, the optimising did not, because a renderer that
had just been rebuilt is the wrong thing to tune against guesses.

## Verified by looking, not by a green suite

Nine reported items were checked against the running app before anyone was told
they were fixed. The evidence is in `design/screenshots/`.

- **Bugs 2, 4, 10** -- the paged view is now byte-identical before and after a
  visit to continuous; before the fix those two screenshots differed. Plus the
  obvious: `p. 1 / 9`, three systems, crisp, nine good thumbnails.
- **Bug 6** -- photographed mid-playback after a manual scroll: still playing,
  following yielded, "Back to bar 12" offered. The line parks at 30% and the
  score moves past it.
- **Bug 8** -- measured, not eyeballed: 2px at 1x and 7px at 3.55x before; 2px
  and 2px after.
- **Bug 7** -- the lasso selects on the strip and the chip names what it caught.
- **Bug 9** -- the fix is deeper than a smaller opening view. `minimumZoomScale`
  IS the fitted scale, so when a single staff fitted at 13x there was nothing
  below it to zoom out to. Capping the fit lowers the floor itself.
- **Features 1, 3, 4, 5** -- the stamp at top centre, PDF / MUSICXML / UNFILED
  tags across the lists, and `PDF not editable` in the score view.

## The three causes worth remembering

1. **Verovio's `setOptions` MERGES.** The paged option set never named `breaks`,
   so one visit to continuous set `breaks: none` on the shared toolkit and
   nothing set it back. One fault, three reported bugs, and it only appeared
   after you had looked at the strip -- which is why it read as intermittent.
2. **`pypdf` was never vendored.** Every book operation raised
   `ModuleNotFoundError` inside the on-device engine, so Import Book had never
   once worked. Every check passed, because the host had pypdf in its venv.
3. **`lastError` was written 59 times and read almost nowhere.** 57 failures
   were invisible, which is exactly why a `ModuleNotFoundError` looked to a
   reader like nothing happening at all.

Each was invisible to a green test suite, and each was found by running the
thing and looking at it.

## What the plan got wrong

The through-line was right -- bugs 2, 4, 9 and 10 really were one family. The
*cause* guessed at here (continuous options leaking into the paged render) was
half right: not leakage, an omission. Same symptom, different fix. The check
written to confirm the theory is what refuted it, which is the argument for
writing the check before the fix rather than after.
