# Selection gestures — proposal for Ali's decision

Not built. This is the analysis and the recommendation; implementation waits on
your confirmation.

## What is being replaced

Shipped today (builds 124–132): a lasso drawn by **holding a finger and drawing
with the Pencil**. The rule lives in one place (`LassoArbiter`) and reads:
Pencil alone annotates, finger-held + Pencil selects, one finger scrolls, two
fingers pinch. That whole modifier scheme is scratched.

Two things about the current state worth knowing before choosing:

- **The two-finger-tap undo is still in the code** (`ScorePagesView`, a
  two-touch `UITapGestureRecognizer` on the PencilKit canvas). It is gated
  behind markup mode being on, because the canvas only takes touches then —
  which is the likely reason it feels lost. It also competes with the scroll
  view's pinch recognizer for a quick two-finger contact. So "restore" here
  means diagnose and fix, not write from scratch, and it needs a test either way.
- **Selecting every element type needs no new work.** The hit-test model already
  addresses notes, rests, chord symbols, clefs, dynamics and structural marks by
  `(staff, measure, layer, kind, ordinal)`. What changes is only how the lasso
  is drawn and how selections combine.

## The hard constraint

A plain one-finger drag is **scroll**, and that cannot move — it is how the
score is read. So a finger-drawn lasso needs something to distinguish it:
either a mode, or a delay, or a second finger. Every scheme below is a different
answer to that one question.

---

## Scheme 1 — Select mode *(recommended)*

The canvas has one mode at a time, from the pill: **Read** (default), **Markup**,
**Select**. Markup already works this way, so this is the existing pattern
extended, not a new concept.

| gesture | in Select mode |
|---|---|
| one finger drag | draws the lasso; replaces the selection |
| Pencil drag | draws the lasso too (precision, no mode change needed) |
| **one finger held + second finger drag** | **adds to the selection** |
| tap on empty paper | clears the selection |
| tap a selected element | removes just that element |
| two fingers | pinch/zoom, unchanged |
| two-finger tap | clears the selection |

Removal, two ways: tap one element to drop it, or flip the selection chip's
**Add / Subtract** toggle and lasso a region to drop everything in it. The
toggle makes bulk removal explicit and reversible, and it costs no gesture.

- **Good**: no ambiguity anywhere; scroll and pinch keep their meaning
  untouched; a finger-only user can select (no Pencil required); the
  `-lassoWithFinger` test hook disappears entirely, because in Select mode a
  finger genuinely draws the lasso — the tests stop pretending.
- **Cost**: one tap to enter the mode, and the mode has to be visible enough
  that nobody wonders why dragging no longer scrolls.

## Scheme 2 — No mode, long-press then drag

Press and hold about 0.35s, then drag: lasso. A drag that starts moving
immediately: scroll. Works in any mode.

| gesture | result |
|---|---|
| press-hold-drag | lasso, replaces selection |
| one finger held + press-hold-drag | adds |
| press-hold-drag over selected elements | toggles them out (XOR) |

- **Good**: no mode, nothing to discover or exit; selection is always one
  gesture away.
- **Cost**: the 0.35s threshold is a guess that has to feel right on glass —
  too short and a hesitant scroll becomes a lasso, too long and selection feels
  stuck. XOR removal is ambiguous the moment a lasso covers a mix of selected
  and unselected elements, and there is no way to say which the user meant.

## Scheme 3 — Pencil draws, finger modifies

Closest to what exists, listed because it is the smallest change: outside
Markup, a Pencil drag is the lasso; a held finger adds; two held fingers remove.

- **Good**: no mode for Pencil users; the most precise lasso of the three.
- **Cost**: a finger-only user can never select anything, and two-held-fingers
  plus Pencil is exactly the modifier stacking you asked to drop. Recorded for
  completeness; not recommended.

---

## Recommendation

**Scheme 1.** It is the only one where no existing gesture changes meaning, and
it is the only one a person can use without a Pencil. It also removes a test
hook that has been quietly weakening the selection tests: today the simulator
has no Pencil, so the tests exercise a stand-in rule rather than the real one.

Two details worth confirming with the recommendation:

1. **Where the mode lives.** The pill already carries a markup toggle; Select
   becomes a sibling. Read / Markup / Select as three exclusive states, so
   entering one leaves the others.
2. **What the two-finger tap does.** Undo belongs to Markup (it undoes ink). In
   Select mode the same tap is free, and clearing the selection is the natural
   match. If you would rather it always mean undo, say so and Select gets no
   two-finger tap.

## If confirmed, the build order

1. Remove the finger+Pencil scheme: `LassoArbiter`, the `-lassoWithFinger`
   hook, and the arbitration tests that encode the old rule. Clean deletion, no
   dead flags left behind.
2. Fix and test the two-finger-tap undo, on its own, so it is verified before
   anything else moves.
3. Select mode and the plain lasso, with tests that drive a real finger drag.
4. Add-to-selection, then subtract, each with its own tests.
5. The selection chip: count, Add/Subtract, Clear.

Each step is a verified increment, and steps 2 and 3 are independently
shippable if you want them sooner.
