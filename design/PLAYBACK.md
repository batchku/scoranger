# Playback, the mixer, and the playhead (0.6)

Approved 2026-08-31. This is the reference; where it and a memory disagree, this
wins.

Playback exists on `feat/playback` already: an `AVAudioSequencer` graph over the
MIDI the engine exports, a transport, per-voice mutes, and a metronome. What
follows is what 0.6 adds around it.

## The rule that shapes everything else

**All voices off gives you the metronome. All voices off AND the metronome off
gives you silence, and that is allowed.**

Silence is only tolerable because you can still see where you are, which is why
the playhead is not a nicety in this release. It is the thing that makes a
silent transport legible. The two ship together.

## The playhead is driven by (measure, beat), never by wall-clock x

The single most important decision here, and the one that is easy to get wrong.

Playback expands repeats -- `ops.playback_timeline` calls music21's
`expandRepeats()` -- and produces a flat stream. The engraved page does not: it
carries repeat barlines and voltas, and bar 5 is drawn once. So playback time
maps to page position MANY-to-one, and bar 9 of the audio is bar 5 on the page.

The tempting implementation is to take Verovio's timemap, convert the current
playback time to an x, and draw there. It works until the first repeat. After
that it requires Verovio's expansion and music21's expansion to agree exactly,
in every score, forever -- and when they drift the playhead desyncs silently,
which looks like working software.

So: the timeline is asked what MEASURE and BEAT is sounding, and the geometry is
asked where that measure is on the page. A second pass through bar 5 resolves to
bar 5's frame again and the cursor jumps back, which is what a reader expects.
No agreement between two libraries is required, and the failure mode -- a bar
with no frame -- is visible rather than silent.

`BarPosition.bars(onPage:)` already returns each bar's frame in page
coordinates, one element per staff, so the union of the frames sharing a measure
number gives the vertical span the cursor draws across.

## What is being built

- **Per-channel gain.** The mixer needs volume, not just mute. `AVMusicTrack`
  has no gain property; the intended route is per-track `destinationAudioUnit`
  into its own sampler, controlling that node's mixer input. NOT YET PROVEN --
  spike this first and report before building on it. The fallback is CC7 volume
  events, which is coarser and fights any volume data already in the file.
- **A movable mixer panel.** One channel strip per staff: volume, mute, and the
  seek scrubber. Movable by drag, using the ink bar's pattern
  (`InkBarPlacement.clamp`), including the tap-the-handle-to-redock escape so a
  panel dragged somewhere silly is never a trap.
- **Channel labels mirror the staff labels exactly.** Whatever the staff is
  called on the page is what the strip is called. A scanned quartet reads
  "Voice" four times, and the fix for that is renaming the parts with the tools
  that already exist -- not inventing a different name in the mixer. This means
  channels key on part INDEX, not on name, because duplicate labels are legal.
- **The playhead**, in the paged canvas: a vertical line across all staves,
  moving in real time, moving even in silence.
- **Page-follow.** When playback leaves the visible page, the page follows.
- **Offline audio assertions.** See below.
- **Seek**, as a scrubber in the mixer panel.

Follow-up, deliberately not 0.6: note highlighting (cheap once the playhead
lands -- same time source, overlay rectangles over `.note`/`.chord` frames from
`ScoreGeometry`, because the canvas draws a rasterised PDF and glyphs cannot be
recoloured at runtime), and the playhead in continuous view.

## Seek is a scrubber, not a canvas tap

A tap on the canvas already means lasso, and the canvas already carries Pencil.
`seek(toBar:)` exists and is tested; what it lacked was a way to reach it that
did not overload a gesture. It goes in the mixer panel, where the transport
already lives.

## Turning a page during playback hands control over, and a button hands it back

Revised 2026-08-31, replacing an earlier rule that resumed following
automatically once the playhead came back into view.

Following is on during playback and turns the page at 85% of its width. A
MANUAL page turn yields it: the music KEEPS PLAYING, the page stays where the
reader put it, and following does NOT come back on its own.

Instead a **Sync** button appears, and tapping it jumps the view to whatever
page the playhead is on now and resumes following. When the visible page
already holds the playhead, the button is not there.

Automatic resumption is what this replaces, and the reason is that it makes the
same gesture mean two different things depending on where the music happens to
be. A reader who pages ahead to read what is coming would be snatched back the
moment the playhead wandered into view -- not because they asked, but because
the music arrived. An explicit tap is a reader saying "take me back", which is
the only moment it is right to move the page under them.

Consequences to get right:
- The button belongs to PLAYBACK, so it is absent when nothing is playing.
- On a two-page spread, "the visible page holds the playhead" means EITHER page
  of the spread.
- Performance mode hides chrome, and this is chrome.
- Continuous view has no pages; when the playhead lands there, the same shape
  applies to a manual SCROLL. Not 0.6.

## Five ways this breaks other things

Each of these is a regression this release must not ship.

1. **The cursor layer must not take input.** It sits over the canvas, where
   Pencil and the lasso live. `allowsHitTesting(false)`, and a test that a lasso
   still selects while the transport is running.
2. **Two movable panels.** The mixer and the ink bar share the clamp logic and
   can be dragged over each other. Distinct docks, a settled z-order, and the
   mixer is suppressed in markup mode rather than left to fight.
3. **Page-follow versus manual paging.** The rule above.
4. **Mutes keyed on name break the moment labels may repeat.** They are keyed on
   part index now. This is a change to code that is already tested on
   `feat/playback`; update those tests, do not weaken them.
5. **A timemap is per-engraving.** If one is used at all, it shares the render
   key (`slug/version/layout`) or it goes stale on a version switch -- the same
   failure the stale-selection fix already covers for selections.

## Nobody has heard it, and a test can

The synth path has been asserted structurally and never once produced a sound
anybody checked. `AVAudioEngine.enableManualRenderingMode` renders offline into
a buffer, so this is testable rather than anecdotal. Four assertions:

- voices on -> RMS above silence
- all voices muted, metronome on -> click transients only
- everything off -> true silence
- channel gain changed -> RMS changes with it

That last one is what stops per-channel volume from being a slider wired to
nothing.
