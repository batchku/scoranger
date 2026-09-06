# The mixer as a movable window

Supersedes the panel geometry in `PLAYBACK_0.6.md` §1 and the parking rules in
§4. Everything else in that document (materials, LED meaning, playhead, sync
chip, lane order) still stands. Written after reading the shipped code; the
diagnosis in §0 is what the spec is shaped around.

## 0. Why it is broken

Three defects, all structural. None of them is a tuning problem.

**It is not draggable because the drag gesture is attached to the whole panel.**
`MixerLayer` puts `.gesture(DragGesture())` on the entire `MixerPanel`
(`Score/MixerPanel.swift:824`). Every child — six mute buttons, six faders, six
sound chips, the tempo slider, the scrubber, the grip, `All on`, `All off`, `✕` —
carries its own gesture or is a `Button`, and SwiftUI resolves in favour of the
innermost. The draggable surface is whatever pixels are left over, which on a rack
of controls is the gaps between them. The grip *looks* like the handle and is the
one place guaranteed not to work: it is a `Button` (`:88`), so it swallows the
touch and cycles corners instead.

**Text is cut off because every row is a hard-coded height inside a clipped
frame.** The panel takes `.frame(width:height:)` from `MixerLayout` and then
`.clipShape` (`:70`–`:75`), so anything that does not fit is silently trimmed
rather than overflowing where it would be noticed. The row constants were tuned
to one text size. Measured against the shipped font files, at the **default**
content size:

| Row | Constant | Content | Line height | Result |
|---|---|---|---|---|
| value | `valueHeight: 12` | `.data`, IBM Plex Mono 11 | **14.30pt** | **clipped by 2.3pt** |
| tempo readout | `.frame(width: 26)` | `.meta`, Inter 11, up to `300` | ~19pt at 1.0× | clips from xLarge up |
| label | `labelHeight: 16` | `.meta`, Inter 11 | 13.31pt | 2.7pt of slack |
| sound chip | `soundHeight: 16` | `.meta` + chrome | 13.31pt | no slack for the chip border |

Every role is `UIFontMetrics.scaledFont` (`Theme.swift:148`), so these grow with
Dynamic Type while the rows do not. Caption1 runs 12pt at Large to 36pt at AX5 —
**3×** — which puts a 43pt line in a 12pt row.

Horizontally the same: the header packs grip 28 + `MIXER` + summary + `All on` +
`All off` + `✕` 28 into a frame whose width is derived from the *strip count*
(`panelWidth`), so a two-staff arrangement gets a 136pt-wide header holding about
200pt of content. On a 13-inch iPad at normal text this is the cut-off Ali sees.

**A dragged panel can be pushed off the screen.** `MixerLayout.clamp` keeps only
`InkBarPlacement.mustRemainVisible` = 60pt on screen (`MixerLayout.swift:224`).
And the drag is stored as a translation from a *moving* origin: `onEnded` keeps
`value.translation` while `home` is recomputed from corner, lane inset and panel
size, so the panel teleports whenever the sync chip appears or the picker opens.

## 1. The window shell

```
┌──────────────────────────────────────────────────────────┐
│ ≡≡≡   MIXER   3 of 4 voices              ⌄    ▣     ✕    │  header, 44
├────┬─────────────────────────────────────────────────────┤
│ ALL│  ┌──────┬──────┬──────┬──────┐                      │
│ ON │  │  M  7│  M  4│  M  7│  M  0│   ← rack scrolls →   │
│    │  │  ▮   │  ▮   │  ▮   │  ▮   │                      │
│ ALL│  │  │  ●│  │  ○│  │  ●│  │  ○│                      │
│ OFF│  │ Piano│ Piano│ Vln  │ Bass │                      │
│    │  │ Vln I│ Vln II Viola │ Cello│                     │
├────┴─────────────────────────────────────────────────────┤
│ TEMPO  ▬▬▬▬▬▬▮▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬          96   │  28
├──────────────────────────────────────────────────────────┤
│ 0:42  ▬▬▬▬▬▬▬▬▬▮▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬     3:15  │  32
└──────────────────────────────────────────────────────────┘
```

### 1.1 The grab bar — `mixer-grab`

The leading **44×44** of the header, and it is **not a button**. A plain view with
`.contentShape(Rectangle())` carrying `DragGesture(minimumDistance: 0)`. Nothing
else in the header competes with it, and no gesture is attached to the panel body
at any level.

The drag surface extends across the header's inert middle — the rail, `MIXER` and
the voices summary are one region — implemented as a single background layer with
the gesture, with the three trailing buttons drawn *above* it. A touch that lands
on a button is a button press; anywhere else in the header is a drag.

- **Drawn:** three 20×2pt bars, 3pt apart, `ink3`, centred in the 44pt square.
- **Pressed:** the 32×32 rounded square behind the bars fills `well`, radius
  `rCtl`. It is the only pressed state in the header, so "I have hold of it" is
  unambiguous.
- **Accessibility:** `.accessibilityHidden(true)`. It duplicates the park button,
  and VoiceOver cannot drag anyway — the park button is that path, which is
  exactly why the two must be separate controls.

### 1.2 Park — `mixer-park`

44×44, trailing group, cycles the four corners as today. **A drawn glyph, not a
grip:** a 16×12pt rounded rectangle stroked 1pt `line2`, with a 6×5pt `clay` block
in the corner it will move to **next**. The affordance previews its destination.

- Label "Park the mixer", value the current corner, hint "Moves it to the next
  corner".
- Tapping it sets placement to `.corner(next)` and discards any free position.

### 1.3 Collapse — `mixer-collapse`

44×44, `chevron.down` / `chevron.up`, `ink2`. Collapsed the panel is **header +
scrubber only** — 76pt at normal text. This is the answer to "it covers my
score", and it is what buys the height §2 costs. Remembered per device; the
panel opens in whichever state it was left.

### 1.4 Close — `mixer-close`

44×44, trailing-most, unchanged.

### 1.5 The master column — `mixer-master`

`All on` / `All off` leave the header. They become a 45pt column pinned at the
**leading edge of the rack**, outside the horizontal scroll: two stacked text
buttons, `.label` caps in `clayStrong`, min 22pt each, separated from the strips
by a 1pt `line` divider.

They are moved because the header cannot hold them at every width, and this is
where they belong anyway: beside the mutes they operate, in the same place a
mixer keeps its master. Same identifiers, `voices-all-on` / `voices-all-off`.

## 2. Sizing that scales

**The rule the whole section reduces to: no view in the mixer takes a fixed
`.frame(height:)` or `.frame(width:)` around text.** Rows take
`.frame(minHeight:)`, text takes `.fixedSize(horizontal: false, vertical: true)`,
and the panel takes `.fixedSize()` on its own body so it measures what it
contains. `MixerLayout` exposes **minimums**, never heights.

| Row | Minimum | Grows with |
|---|---|---|
| Header | 44 | text, never below 44 |
| Mute + value | 24 | `.data` line height + 6 |
| Fader | 44 ideal, **32 floor**, 120 ceiling | absorbs slack; first to give |
| Sound chip | 24 | `.meta` line height + 8 |
| Label | 20 | `.meta` line height + 4 |
| Rack padding | 8 | — |
| Tempo | 28 | `.meta` line height + 10 |
| Scrubber | 32 | `.data` line height + 12 |

At normal text that is **44 + 128 + 28 + 32 = 232pt** expanded, **76pt**
collapsed. Say the cost plainly: the shipped panel is 170pt and it clips; a panel
that does not clip and has a real handle is 232, **+36%**. The collapse control is
the trade — 76pt is less than half of what it replaces.

**Widths.** The strip scales too: `stripWidth = clamp(64 × textScale, 64, 96)`,
where `textScale` comes from `@ScaledMetric(relativeTo: .caption1)`. The panel is

```
width  = max(headerFloor, padding·2 + master 45 + 1 + n·stripWidth + (n−1))
       clamped to freeRect.width − 16
```

with **`headerFloor` measured, never below 280** — this is what kills the
horizontal clipping: panel width stops being derived from the strip count alone.
The tempo readout gets `minWidth` for `"300"` at the current text size, not 26pt.

**Six strips** visible before the rack scrolls (four when compact), as today.

## 3. Scrolling

- The rack is always a horizontal `ScrollView`, `.scrollBounceBehavior(.basedOnSize)`.
  Header, master column, tempo and scrubber never scroll with it: they belong to
  the performance, not to whichever strips are in view.
- Vertical scrolling exists **only in the list tier** (§4.3). In the other tiers
  the rows are small enough that the panel cannot exceed its ceiling; if a
  computed height ever would, the panel opens **collapsed** rather than clipping.
  That is the whole fallback — deterministic, and there is no state in which
  something is drawn outside the frame that clips it.

## 4. Three tiers, chosen by the container and the text size

Chosen from the *container*, not the device: a resized window and a Slide Over
get the right tier for free.

### 4.1 Window — regular width, text ≤ xxxLarge

The floating window above. Free placement, ceiling 60% of the free rect.

### 4.2 Anchored — compact width (`< 700pt`), or container height `< 500pt`

An **anchored bottom panel**, full width minus 16pt, sitting in lane 3 directly
above whatever chrome is showing. Not movable — there is nowhere to move it — so
the grab bar and the park button are both absent; collapse and close remain. This
is the anchored-bar pattern from `NAV_MODAL_FREE_0.4.2`, so it costs the app no
new concept and it is not a sheet.

On **short** containers (iPhone landscape) the strip also drops its sound chip
row; tapping the strip's label opens the picker instead. Ceiling 45%, and the
panel opens collapsed the first time.

*Tapping the label opens the picker in every tier* — the chip is the visible
affordance, the label is the larger target.

### 4.3 List — text at AX1 or larger, any width

A vertical fader with 33pt labels is not an object anyone can use. At
accessibility sizes the panel anchors to the bottom, full width, and each channel
becomes a **row**: `M` 44×44 · name (up to 2 lines) · sound chip · a *horizontal*
fader, min 100pt · value. Rows min 44pt, the body scrolls vertically, header and
scrubber pinned.

The DAW layout is a rendering of the model, not the model. It is allowed to
change when it stops being legible.

## 5. Placement, clamping, persistence

Replace the stored translation with a placement value:

```swift
enum MixerPlacement: Codable {
    case corner(MixerLayout.Corner)
    case free(CGPoint)   // panel CENTRE as a unit point of the free rect
}
```

- **freeRect** = container inset by its safe-area insets, then by 8pt.
- **Fully on screen, always.** The origin is clamped so the panel rect is
  contained in `freeRect`. No `mustRemainVisible` — that rule is the ink bar's,
  and the ink bar is a 60pt object the reader is deliberately shoving aside. A
  window whose header can leave the screen is a window that cannot be dragged
  back.
- If the panel is somehow larger than `freeRect` in a dimension, pin to that
  edge; §2 and §3 exist so this cannot happen.
- **Drag:** `onChanged` applies a live translation on top of the resolved origin;
  `onEnded` converts the final rect's centre to a unit point and stores
  `.free(unit)`, zeroing the translation. This is the fix for the teleport — a
  unit point does not care that `home` moved.
- **Rotation and resize** map the same unit point into the new `freeRect`, so the
  panel keeps its relative position and is inside by construction.
- **Recompute on:** container size, safe-area change, `dynamicTypeSize`, strip
  count, picker open/close, collapse toggle. Never per frame.
- Persist placement and the collapsed flag per device.

**Lanes.** A *parked* corner still respects `lanesInset` so it never lands on the
ink bar or the sync chip. A *freely dragged* panel may go anywhere in `freeRect`
— the reader moved it there, the same latitude the ink bar got in #46. Z-order is
unchanged: fixed chrome < ink bar < sync chip < mixer.

## 6. The sound picker

It stops resizing the window. While picking, the panel keeps the width it already
had (floor 280) and swaps its **body** for the picker; only the height changes,
clamped by §5. Below 380pt the two columns become one — families, then
instruments, pushed within the panel with a back control — rather than a 300pt
fixed width the panel has to grow to.

## 7. Materials

Nothing new. Panel `panel` on 1pt `line2`, radius `rPanel`, `ePanel` shadow.
Grab bars `ink3` on `well` when pressed. Park glyph stroked `line2` with a `clay`
corner block. Master column text `clayStrong` on `panel`, divider `line`. Tempo
stays graphite on `band`; faders stay clay on `well`; the flat `panel` cap with
1pt `line2` is the same object everywhere it appears. Light only.

## 8. Acceptance

Each of these fails against the shipped build. That is the point of listing them.

1. **`rowsFitTheirText`** — for every `DynamicTypeSize` and every row, the row's
   minimum ≥ the scaled line height of the role it carries plus its padding.
   Fails today at `.large` on the value row.
2. **`clampKeepsThePanelWhole`** — fuzz origins, panel sizes and bounds; the
   result is contained in `freeRect` every time. Fails today by 60pt.
3. **`placementSurvivesRotation`** — a `.free` unit point resolves inside the free
   rect in both orientations and across a Dynamic Type change.
4. **`dragMovesTheMixer`** (UI) — drag `mixer-grab` by (+160, −120); the `mixer`
   frame moves by that, and stays inside the window. Fails today.
5. **`aFaderDragDoesNotMoveTheWindow`** (UI) — drag `mixer-fader-0` vertically;
   the fader value changes and the `mixer` frame does not move.
6. **`nothingClipsAtXXXL`** (UI) — launch with
   `-UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityMedium`
   and again at xxxLarge; assert the frames of `mixer-value-0`, `mixer-label-0`,
   `mixer-sound-0` and `mixer-tempo-value` are each contained in the `mixer`
   frame. This is the mechanical form of "nothing is cut off".
7. **`theHeaderHoldsItsContent`** — with a two-staff arrangement, the panel is at
   least 280pt wide and `mixer-close` is inside it.

---

# 12. Compact amendment — the panel floats and is sized to its channels

**§4.2 is withdrawn.** Both reported bugs are that section being implemented
correctly, so this is my correction and not a misreading of the spec.

§4.2 said: *"full width minus 16pt … not movable — there is nowhere to move it —
so the grab bar and the park button are both absent"*. That is the empty right
two-thirds, and it is the dead drag surface. The two are one mistake: **I
anchored it because it was full-width, and it was full-width because I anchored
it.** Fix the width and the reason for anchoring disappears.

**Ruling: option (a).** One model everywhere — a floating window, sized to its
channel count, draggable within the score area, on iPhone exactly as on iPad.
Narrower, and with one height rule of its own.

## 12.1 Width is a function of the channel count

```
rack   = 8 padding + 45 master + 1 + n·stripWidth + (n−1) dividers
floor  = 4 × 44 + 8            = 184     grab · collapse · park · close
width  = min( max(floor, rack), rack at visibleStripsCompact )
```

`stripWidth` is `clamp(64 × textScale, 64, 96)` as §2 — computed, never a
literal. At default text size:

| Channels | Rack | Panel | |
|---|---|---|---|
| 1 | 118 | **184** | rack centred, 66pt slack |
| 2 | 183 | **184** | the reported case — 47% of a 393pt screen |
| 3 | 248 | **248** | |
| 4 | 313 | **313** | the compact maximum |
| 5+ | — | **313** | rack scrolls horizontally |

**Two channels is a 184pt panel, not a 393pt one.** The blank right-hand
two-thirds and the LED floating in the void both go.

The floor is four 44pt controls and their padding, and at that width the header
carries *nothing else*: **`MIXER` and the voices summary appear only at 248pt
and above** (three channels or more). A two-channel panel is labelled by its own
strips; a title on it would be the thing that forced it wider.

Never below the floor. Four controls at 44pt is not negotiable — the grab bar
and the park button are how the panel is moved by hand and by VoiceOver, and
they are the controls this amendment exists to restore.

## 12.2 The grab surface at the floor width

At 184pt the header is exactly its four controls: **there is no inert middle,
so the grab bar is the leading 44×44 and nothing else.**

Which makes §1.1's rule load-bearing rather than stylistic: **the grab bar is
not a `Button`.** A plain view with `.contentShape(Rectangle())` carrying
`DragGesture(minimumDistance: 0)`, with no gesture anywhere on the panel body.
If the grab bar is a button at this width, the panel has no draggable pixels at
all — which is how the drag died the first time.

## 12.3 Drag bounds and height

Unchanged from §5, which already covers this: placement is `.corner` or
`.free(unit point)`, clamped so the panel is **fully inside** the free rect
(container minus safe area minus 8pt), remapped on rotation and Dynamic Type.
Parked corners respect `lanesInset`; a panel the reader dragged goes anywhere.

One rule added for phone height: **the panel opens collapsed when its natural
height exceeds 60% of the canvas.** In landscape the canvas is about 284pt, so
that is where it bites; collapsed is header + scrubber, and `mixer-collapse`
expands it. Portrait at 635pt of canvas opens expanded.

## 12.4 Check the width test first — it may be the whole bug

`MixerLayer` decides compact with `geo.size.width < 700`
(`MixerPanel.swift:807`), and **iPhone landscape is 852pt wide**. So by that
test the phone is compact in portrait and *regular* in landscape.

If that is what shipped, the panel is **draggable in landscape and pinned in
portrait**, and one rotation confirms the diagnosis before any code changes.
Either way the test is wrong: compact is a size class and a container height,
never a raw width. It is the same defect noted in `IPHONE_0.6.14.md` §0.

## 12.5 Acceptance

The drag has now died twice from two unrelated causes — competing gesture
recognisers in 0.6.11, a layout branch in 0.6.14 — so the test has to be
behavioural rather than structural:

1. **`theMixerDragsAtEveryWidth`** — drag `mixer-grab` by (+120, −80) and assert
   the `mixer` frame moved by that and stayed inside the window. Run it at
   **compact portrait, compact landscape and regular**. A version of this that
   only runs at regular width is what let 0.6.14 ship pinned.
2. **`theMixerIsNoWiderThanItsChannels`** — with a two-channel arrangement the
   `mixer` frame is ≤ 200pt wide at a 393pt window, and it is wider with four
   channels than with two.
3. **`theHeaderSeatsItsControls`** — `mixer-grab`, `mixer-collapse`,
   `mixer-park` and `mixer-close` all have frames inside the `mixer` frame at
   the floor width. The window-relative clip test from the selection chip,
   pointed at four more identifiers.
