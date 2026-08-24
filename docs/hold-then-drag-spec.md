# Touch-and-hold-then-drag as the primary interaction — analysis and spec

Not built. For Ali's confirmation.

Ali: *"I'm trying to replace the touch-and-hold that opens a contextual menu
with a touch-and-hold-then-drag that lets me achieve all of the same
interactions as what we have in the contextual menus."*

## The finding that decides half of this

**On the sidebar, hold-then-drag already works exactly as Ali describes, and it
is the platform's own behaviour.** Our rows carry both `.onDrag` and
`.contextMenu`. iOS resolves that pairing itself: hold and the row lifts; move
and it becomes a drag; hold still and the menu opens instead.

We know this from the inside. When the reorder drag looked broken, the cause was
a test pressing *still* for a second — which opened the menu rather than lifting
the drag. The comment is still in the test suite. That was not a bug; it was
this exact model, working.

So Ali's candidate resolution — hold begins a pick-up, drag gives the spatial
action, release in place gives the menu — **is not something to build. It is
what the sidebar does now.** What is missing is that nobody can tell, and the
menu still offers the same spatial actions, so there is no reason to learn the
drag.

That reframes the sidebar work from "replace the menu" to "make the drag the
obvious path". The canvas is the genuinely new work.

## 1. Rename, delete and info — how the non-spatial actions stay reachable

Recommendation: **the menu keeps every action, including the spatial ones.**
Drag becomes the fast path, not the only path.

Three reasons, in order of weight:

- **Accessibility.** A drag-only action is unreachable with VoiceOver, with
  Switch Control, and for anyone whose hands do not do a precise 0.35s hold and
  a controlled drag. Removing "Move to piece" from the menu removes the only
  way some people can file an arrangement. This is a regression we would not
  see and could not test for.
- **It contradicts a directive you already gave**, for good reason: in 0.1.2
  you asked that a drag target which cannot be made to work keeps its
  context-menu action as fallback. Dropping onto the Unfiled band, for one,
  only exists when something is already unfiled — so "Remove from piece" has no
  drag target much of the time.
- **iOS does not force the choice.** Because hold-still and hold-then-move are
  already distinct, keeping both costs nothing in gesture budget.

What changes instead, to make the drag primary:

- **Order the menu by what has no drag**: rename, duplicate, delete, details
  first; the spatial actions below a separator, as the slower route.
- **Discoverability.** On lift, the drop targets that can accept the row
  highlight immediately — piece headings, set list headings, row insertion
  lines. Today the highlight only appears once the finger is over a target, so
  a user who does not already know where to drop learns nothing by lifting.
  This is the single highest-value change in the sidebar half.
- Optionally a one-time hint the first time a row is lifted. Cheap; say if you
  want it.

**If Ali still wants the spatial items gone from the menu**, the safe version is
to hide them only when the device reports no accessibility assistive technology
active, keeping them for VoiceOver and Switch Control users. I would rather not:
two different menus is a thing nobody can reason about later.

## 2. The canvas — hold-then-drag lasso

New work. There is no context menu on the canvas, so there is no tension here,
only the scroll gesture to respect.

| gesture | result |
|---|---|
| one finger, moves immediately | scroll (unchanged, no delay) |
| one finger, held 0.35s, then drag | **lasso** — replaces the selection |
| Pencil, held then drag (markup off) | lasso, same as a finger |
| Pencil drag (markup on) | ink, unchanged |
| **one finger held + second finger drags** | **adds to the selection** |
| two fingers moving | pinch/zoom, unchanged |
| two-finger tap | undo the last annotation stroke |
| tap empty paper | clear the selection |

**Scrolling is never delayed.** The pan recognizer is not made to wait for the
long press. A finger held still produces no pan movement, so when the long
press fires at 0.35s it cancels the pan with nothing scrolled and nothing
jumping. This is the pattern iOS itself uses for hold-to-reorder inside a
scrolling list.

**Feel**: 0.35s, with a light haptic and the lasso's first point appearing at
the moment of lift, so the user learns the threshold from feedback rather than
from guessing. 0.35s is the number to start at and tune on the device — below
about 0.3 a hesitant scroll becomes a lasso; above about 0.45 selection feels
stuck.

### The one real ambiguity, and what to do about it

Ali's add gesture — one finger held, second finger drags — is two fingers on
the glass, and so is a pinch. They are distinguishable (in a pinch both fingers
move; here the first stays put) but only after watching for 100–150ms.

Proposal: implement Ali's gesture with that short arbitration window — if the
first finger has moved less than a few points when the second finger starts
dragging, it is an add; otherwise it is a pinch. **And build the fallback at the
same time**: the selection chip carries **Replace / Add / Subtract**, so the
combine mode can be set explicitly and every hold-then-drag obeys it. If the
two-finger reading proves unreliable in the hand, the chip already covers it and
nothing has to be redesigned.

## 3. Remove from selection

The chip's **Subtract** mode is the mechanism: set it, then hold-then-drag over
anything to drop those elements. Plus **tap a selected element to drop just
that one**, for single corrections.

Not XOR-by-re-lasso: over a region holding both selected and unselected
elements, there is no way to know which the user meant, and the result is
different depending on what was already caught. A mode is legible; a toggle
whose meaning depends on prior state is not.

While Subtract is active the lasso outline draws in a different colour, so the
gesture looks different from the one that adds.

## 4. Two-finger-tap undo — restore

It is in the code (`ScorePagesView`, a two-touch tap recognizer on the PencilKit
canvas). Two things stop it working:

- The canvas only takes touches while markup mode is on
  (`isUserInteractionEnabled = controller.isOn`), so outside markup the tap
  never arrives.
- On the canvas it competes with the scroll view's pinch for a two-finger
  contact.

Fix: move the recognizer onto the scroll view, where it sees the touches
whatever the mode, with `cancelsTouchesInView = false` so pinch is unaffected —
a tap has no movement, so it can never be read as a pinch.

**Decision needed**: should it undo only in markup mode, or whenever there is
ink on the page? Recommendation: whenever there is ink. Undo of a stroke you can
see is never surprising, and requiring a mode to undo the thing you just drew is
the reason it felt missing.

## 5. Scratching the Pencil-modifier scheme

Removed cleanly: `LassoArbiter`, the `-lassoWithFinger` launch argument, the
finger-held branch of `LassoGestureRecognizer`, and the arbitration tests that
encode the old rule.

Worth stating plainly: this **strengthens** the tests. The simulator has no
Pencil, so today's selection tests drive a stand-in rule rather than the real
gesture. A finger-drawn hold-then-drag lasso is something a test can perform
exactly as a person does.

## Build order, if confirmed

1. **Scratch** the finger+Pencil scheme and its test hook. No behaviour to
   replace yet — selection is briefly unavailable, which is why this ships with 2 and 3.
2. **Two-finger-tap undo**, fixed and tested on its own.
3. **Hold-then-drag lasso** (replace-mode only) with tests that drive a real
   finger hold-and-drag, plus a test that scrolling is not delayed.
4. **Add and Subtract**: the chip modes first (deterministic, testable), then
   the two-finger add gesture on top.
5. **Sidebar**: menu reordering, and drop targets highlighting on lift.

Steps 2 and 3 are the smallest shippable increment that leaves the app better
than it is now. Step 5 is independent of all of it and could go first if Ali
wants the sidebar discoverability sooner.

## What I need confirmed

1. Menu keeps every action, with drag as the fast path — or Ali insists the
   spatial actions leave the menu (and accepts the accessibility cost).
2. Two-finger-tap undo works whenever there is ink, not only in markup mode.
3. The chip carries Replace / Add / Subtract, with the two-finger add gesture
   layered on as the shortcut.
