# 0.6 playback — mixer, playhead, sync chip

Design spec. The engineer builds to this; every value below is a token from
`DESIGN_SYSTEM.md`, not a new invention.

## 0. The material rule

The mixer is laid out like a mixer and **rendered like Scoranger**. A DAW's dark
chassis, chrome caps, gradient meters and channel colours are that software's
brand, not a functional requirement — every one of them has an equivalent in the
instrument-panel language this app already uses. **Light only** (§7A): do not
invert the panel to dark because mixers are usually dark.

| DAW convention | Scoranger rendering |
|---|---|
| Dark chassis | `panel` #FAF7F1 on `ground`, 1pt `line2` border, radius 3 (`rPanel`), `ePill` shadow |
| Recessed metal fader slot | `well` #EFEAE0 track, 1pt `line2`, radius 2 — the same well as the self-test output and the displayed-version row |
| Chrome / plastic fader cap | flat `panel` cap, 1pt `line2`, radius 2. **No bevel, no gradient, no drop shadow** — the same object as the seek handle and the `PanelToggle` knob |
| Glowing green LED | the app's existing `LED`: dot in `ok` #3BA05C with a 3pt halo at 22% — identical to the engine LED, so "lit means live" stays one idea |
| Illuminated red mute | square button language: radius 2, 1pt `line2`, letter **M**. Muted = `ink` fill, paper-white M. **Never `danger` red** — muting is not destructive |
| Level meter (green→amber→red gradient) | **omitted.** We have no calibrated scale; a gradient meter would imply one. The LED says sounding / not |
| Per-channel colour coding | **omitted.** Three-colour budget. Channel identity is the label, which mirrors the staff label exactly |
| Neon numeric readout | 11pt IBM Plex Mono, `ink3` |
| Dark gutters between strips | 1pt `line` hairlines |
| dB scale with unity detent | linear **0–10**, default 7, with a single 1pt `line2` tick silkscreened at the 7 position |

## 1. Mixer panel

### Strip — 64pt wide, top to bottom

| Element | Treatment |
|---|---|
| Mute | 28×24pt, radius 2, 1pt `line2`, `panel` fill, **M** in 11pt/700 `ink2`. Muted: `ink` fill, paper-white M, and the strip's fader, LED, value and label drop to 42% |
| Fader | 150pt tall. Track 6pt wide, `well`, 1pt `line2`, radius 2, filled from the **bottom** in `clay`. Cap 20×12pt, `panel`, 1pt `line2`, radius 2. Tap the track to jump, drag the cap, `.adjustable` for VoiceOver. A 1pt `line2` tick marks 7 |
| LED | 8pt column immediately right of the fader, 6pt inset, vertically centred on the cap's travel. Off: `well` fill, 1pt `line2` hairline. Active: `ok` + 3pt halo at 22% |
| Value | 11pt mono `ink3`, centred beneath the fader, 0–10 |
| Label | Bottom, ≤2 lines, 11pt/500 `ink`, centred, tail-truncated. Duplicate names take a mono `ink3` index (`Voice 2`) — this app makes several "Voice" staves from OMR. Full name in the accessibility label |

**Activity means sounding, not amplitude.** The LED is on while any note in that
staff sounds, off in rests, whatever the fader says. A muted channel's LED still
lights, at the strip's 42% — the staff *is* playing and you simply cannot hear
it, which is how a reader confirms the mute is working.

### Panel

- Height 268pt: 32 header · 24 mute · 150 fader · 18 value · 28 label · padding
- Width: 8pt padding + n×64 + 1pt dividers. **Six strips visible (~400pt); horizontal scroll beyond**, header and footer fixed while strips scroll. iPhone: four strips, width minus 32pt
- Header 32pt: grip · `MIXER` (10pt caps, `clayStrong`) · `✕`
- Footer 40pt — the seek scrubber, full width, 1pt `line` above it: `0:42` (11pt mono `ink2`) · 4pt `well` track with 1pt `line2`, elapsed in `clay`, handle = the 20×12pt cap · `3:15`. While scrubbing, a `panel` chip above the handle reads **`bar 21`**: musicians seek by bar
- Move: drag anywhere in the header; the grip (three 2pt `ink3` lines, leading edge) is the cue. **Tap the grip to cycle four parked corners** — the path for VoiceOver and Switch Control, which cannot drag. Clamped on-screen, persisted per device

## 2. Playhead

**1pt** `clay` line spanning topmost to bottom staff, 6pt overshoot each end.
Clay despite selection also being clay: a moving hairline and a tinted outlined
box cannot be confused. Weight is in **view space** — 1pt on screen at any zoom,
or at 3× it becomes a slab over the noteheads. **No glow** (§4 forbids gradients
and blur); if direction needs reinforcing, a flat 8pt `clayTint` trailing band at
12%. Top handle: 10×10pt `clay` square, radius 2, centred on the line at the top
staff's upper edge; hidden in performance mode.

> **1pt, revised from the 2pt drawn here (0.6.6).** The owner marked the shipped
> 2pt line "thin" on a screenshot. 1pt is not a new number: it is the hairline
> every rule, border and divider in the app is drawn at, so the cursor now
> weighs the same as the lines it crosses and is told apart by its colour, which
> is what `clay` on a black-and-white engraving is for. The view-space rule is
> unchanged and is now asserted arithmetically as well as photographed
> (`PlayheadTests`, and the pair of pictures at 1× and 3×).
>
> **The handle is draggable (0.6.6).** A finger on the square scrubs the
> transport to the bar under it, through the seek the mixer's scrubber already
> uses. Stopped and playing behave identically: the play head moves and the
> transport is neither started nor stopped. The handle keeps its 10pt and takes
> a 32pt touch target; it is the only part of the cursor layer that accepts a
> touch, so the lasso and the Pencil are untouched everywhere else, and the
> Pencil is not accepted even on the handle — a Pencil over it still lassos and
> still inks.

- **Paged / spread:** sweeps left→right; the page turns at **85% of page width**, so the next page arrives before the music does
- **Continuous:** the line **parks at 30% from the left** and the score scrolls under it; before that point the line travels and the score is still
- **Note highlight:** recolour the **notehead glyph** to `clay` for the note's duration — no box, no fill, no outline, so it cannot be read as selection. Needs a time→element map from the geometry layer; if that is not ready, ship the playhead alone
- The playhead runs on the transport clock: **muting a channel must not stop it**

## 3. Sync-to-playback chip

Pill (`rPill`), 36pt, 14pt padding, **`clayPress` fill, paper-white label** — the
only solid-clay object on the canvas, so it reads as an interruption without a
new colour. `arrow.uturn.left` + **"Back to bar 34"**, bar number in mono;
"Back to playback" where there is no geometry. Appears 400ms after the playhead's
page leaves view, fades in over 160ms, hides itself when the playhead returns —
no `✕`. Hidden in performance mode. Post `.layoutChanged` on appearance, or a
non-visual reader never learns they have drifted.

Its visibility predicate is *"is the playhead's unit index in the visible set"* —
the same one the thumbnail strip uses for its current outline. Reuse it; two
sources for one truth is how the strip and the counters drifted apart in 0.4.

## 4. The bottom of the canvas — lanes and z-order

```
│                        ┌───── MIXER ─────┐   │  lane 3  movable, parks bottom-right
│         [ Back to bar 34 ]                │   │  lane 2  centred, transient
│              ┌── ink bar ──┐              │   │  lane 1  centred, fixed position
├──────────────────────────────────────────┤
│  thumbnail strip                          │  fixed chrome
│  transport                                │  fixed chrome
```

1. Fixed chrome owns the bottom; every lane measures its inset from whichever of strip/transport is showing
2. Lane 1, ink bar, centred, 12pt clear — never moves, so muscle memory holds
3. Lane 2, sync chip, centred, 12pt above lane 1
4. Lane 3, mixer, 12pt above the highest occupied lane, parked bottom-right by default. Dragged into a lane, **the fixed lanes win** and the mixer nudges up on the next layout pass
5. Z-order: fixed chrome < ink bar < sync chip < mixer
6. **Performance mode empties every lane** — that mode exists to remove exactly this

Recompute the mixer's parked position only when a lane appears or disappears,
never per frame, or the panel drifts under the reader's hand.
