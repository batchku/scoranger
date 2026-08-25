# Selection gesture (superseded: hold-then-drag)

**This scheme is no longer implemented.** It shipped in 0.2.3–0.2.4 and never
worked on a real iPad. Kept for the record; the current model is below.

## What replaced it (0.2.5)

The split is by instrument, not by gesture:

| annotation | what is touching | what happens               |
|------------|------------------|----------------------------|
| off        | Pencil, dragging | lasso selection, at once   |
| off        | Pencil, tapped   | drop that element          |
| on         | Pencil           | ink                        |
| either     | fingers          | pan and zoom, nothing else |

There is no hold, no modifier finger, no timer, and nothing to arbitrate: a
Pencil cannot pan (`panGestureRecognizer.allowedTouchTypes = [.direct]`) and a
finger cannot select. Adding to or subtracting from a selection is the chip's
Replace/Add/Subtract mode, set before the next lasso.

While a Pencil is down with annotation off, pan AND zoom are disabled. That is
the palm rejection: outside markup mode the PencilKit canvas takes no touches,
so *its* palm rejection is not running, and the hand resting beside the Pencil
reaches the scroll view as an ordinary finger. Disabling scrolling also cancels
a pan already in flight, so a palm that landed first stops dragging the page the
moment the Pencil arrives.

## Why the old scheme failed

Three gates, none of them visible in a simulator with no Pencil and no palm:

1. Both lasso gates required exactly one touch down. The resting palm was a
   second touch, so the lasso could never begin. Fatal on its own.
2. The Pencil was made to wait out a 0.35s hold it had no need of.
3. The scroll view panned with the Pencil by default, so a Pencil drag raced a
   scroll it could not win.

Before that, `LassoArbiter` wanted a finger held while the Pencil drew, and
could only be tested through a stand-in that let a finger pretend to be a
Pencil — so the tests exercised the pretence.

## What the tests can and cannot prove

`LassoGateTests` covers the rules. The UI tests relaunch with `-uiTestPencil`,
which makes a finger classify as a Pencil, and drive everything downstream of
touch classification: page, unit points, hit test, selection, chip, chat
handoff. They do not exercise Pencil input — no simulator can produce it. That
last step is a person holding an iPad, with the touch diagnostics readout on
(Settings → Diagnostics).
