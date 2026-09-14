# Backlog

## Shipped 2026-08-15: standalone iPad (engine on-device)

The laptop dependency is gone: CPython 3.14 + music21 embedded in the iOS app
(JSON bridge, workspace in app Documents), Verovio compiled in for rendering
(SVG preprocessed for SwiftDraw), native Swift chat loop over OpenRouter,
share-sheet import, and a Cloud Run Audiveris service for PDF→MusicXML
(`omr-service/`). Cross-device library sync remains a follow-up (iCloud or the
Firebase backend).

## Candidate: portable score-ops kernel (Rust → iOS/Android/WASM)

Idea (2026-08-15): replace the embedded-Python slice of music21 with a small
Rust kernel implementing just our ~20 deterministic ops + MusicXML I/O,
compiled for iOS, Android, and WASM (browser viewer loses its server too).
The de-risking recipe that makes this trustworthy: **differential testing
against music21 as the oracle** — agentically generate thousands of scores,
run both engines, diff canonicalized MusicXML. Coverage alone is not the bar;
music21's 20 years of MusicXML edge-case semantics are (our real bugs were all
spec bugs: voice-padding phantom rests, enharmonic respelling, part ordering).
Sequence after product validation. Do NOT rewrite OMR this way — neural models
(Legato-class) are obsoleting rules-based OMR; portable OMR = shipped weights,
not transpiled Java.

Deferred from the prototype (see ARCHITECTURE.md for the full product design).
The prototype is: local React viewer + Python score engine, driven by Claude Code.

## The release plan after 0.8.1 (set 2026-09-14)

Everything open in this file is assigned to one of two builds. The split is
the renderer: 0.8.3 owns direct vector rendering and what only makes sense on
top of it, because it is the one change that puts the surface Ali reads music
from at risk and must not ship beside feature work. 0.8.2 owns everything
else.

Assumed, absent an answer, and cheap to change before the interaction is
built: a move destination is a tapped bar plus a stepper for the offset inside
it (drag is gone from this app); size is RELATIVE to the engraved default;
the terms gate sits on sharing rather than on first launch; the renderer ships
behind a flag that is OFF by default.

### 0.8.2 -- what 0.8 promised, plus the test debt

In build order. Each step is testable when it lands and later steps stand on
earlier ones.

1. **Engine ops, with the CLI exercised as a process.** Book rename;
   `adjust_element` generalised past `harm` to other added text and marks;
   move and duplicate for the two tractable element classes (offset-anchored,
   note-attached). Spanners stay out -- re-pointing a slur has no answer when
   the rhythms differ. Every new op gets a test that runs the `scor` BINARY,
   which closes the CLI coverage gap with the same work that adds the ops.
2. **`bridge.py` coverage** for what step 1 added and for what it already
   routed.
3. **The four gaps 0.8.0 named for 0.8.1 and 0.8.1 did not carry**: the set
   list's foot strip and the score bar's second row on the phone; the OMR
   offer as a panel state rather than a row in More plus a chip; Rename on a
   book row (now that the engine has it); Settings as a split inside the
   score's 380pt panel.
4. **Added elements in the UI**: size and position for text and marks through
   the adjust row that chord symbols already use, then move and duplicate
   against the destination above.
5. **Chat dispatch against a stubbed model** -- tool-call dispatch and
   argument shaping asserted with no network and no key. The model's own
   judgement stays manual.
6. **Export from the app UI**, end to end through the share sheet.
7. **The gate debt**, late, when the machine is otherwise quiet: the
   `lyricSize` experiment on PaginationAfterAnOp; reproducing the eight
   rotating landscape failures by hand with the pool-then-serial timing; the
   engine-aware lock so `ENGINE_SERIAL` stops growing; the chord adjust row
   UI test on a stripped staff with its rests hidden.
8. **Copyright and terms posture** -- a written position and the gate it
   implies on the sharing path. Mostly Ali's decisions and a document. It
   belongs here because it gets harder the more external testers hold the app.

### 0.8.3 -- the renderer and what stands on it

1. **Direct vector rendering behind a flag**, off by default, compared side by
   side against the bitmap path on Ali's real scores before the flag is
   considered for flipping. Retires the crisp-deep-zoom item outright.
2. **Selection re-based on the vector output.**
3. **Visual/engraving regression tests** -- worth building only once the
   output is vector, which is what can be asserted on.
4. **A real-device lane**: one iPad with a Pencil, run by hand per release
   against a checklist, because the simulator has no Pencil and nothing runs
   on hardware today.
5. **The OMR pipeline through Audiveris**, in its own lane because it needs
   the installed app on the host.
6. **Multi-tenancy: rules, per-user OMR quotas, cost metering.** Firebase
   touches live infrastructure; every deploy waits for Ali's explicit go.

### Tracked as spikes, in neither build

Neither has an acceptance criterion yet, and inventing one to fit a release is
how a research question becomes a missed date. Each needs its go/no-go
question answered first.

- **Generative arrangement (v2)** -- NotaGen or the NeurIPS-2025 unified
  arrangement model behind the same tool interface. Question: what does a
  piano reduction have to get right before Ali would play from it?
- **Portable score-ops kernel (Rust -> iOS/Android/WASM)** -- question: which
  second platform is real enough to pay for the port?

## Deferred to post-prototype

- **Firebase backend** — Auth, Firestore (metadata/jobs/chat), Cloud Storage, Hosting
- **Hosted agent loop** — server-side chat agent calling the Anthropic API with the
  same tool set the CLI exposes; in-app chat UI; API key / billing management
- **PDF ingestion (OMR)** — Audiveris headless container + side-by-side correction UI
  (clean engraved PDFs first; photos/scans via homr later; handwritten never)
- **MIDI ingestion** — MuseScore CLI conversion (music21's basic MIDI import may land
  earlier since it's nearly free)
- **PDF/parts export** — MuseScore CLI in a container (engine currently exports
  MusicXML/MIDI only)
- **Multi-tenancy** — security rules, per-user quotas on OMR/conversion jobs, cost metering
- **Copyright/ToS review** — users uploading publisher PDFs; sharing features need a rights gate
- **Playback** — OSMD cursor + soundfont
- **Generative arrangement (v2)** — piano reduction / orchestration via NotaGen or the
  NeurIPS-2025 unified arrangement model behind the same tool interface
- **In-browser notation editing** — explicitly out of scope for v1

## Prototype polish (nice-to-haves)

- Live reload via websocket instead of manifest polling
- Measure-range support on more ops (transpose, octave shift)
- `merge_scores`, `extract_measures` tools
- Part extraction to separate printable parts (one part per page/file)

## Build 115 — score canvas polish (from Ali, after build 114)

Queued, not started. Verbatim asks with implementation notes:

- **Drop the title and number from the canvas header.** "The title of the piece
  that's on the canvas doesn't need to be there because the title of the piece is
  also written in the score. So remove that title. And also remove the number, so
  I don't want to see 'number four arrangement' or something too."
  → the principal toolbar item added in `ContentView.detailTitle`. Note the
  sidebar and chat header still carry piece / #N, so the hierarchy stays legible
  once the canvas header goes.

- **Annotation toggle icon should read as locked vs editing.** "Change the icon so
  that it goes between a pencil with a line across it (like 'no edit' or locked)
  and a pencil with no line (means you're in edit mode right now)."
  → `pencil.slash` when off, `pencil` when on, in `ScorePagesView`'s toolbar
  (currently `pencil.tip.crop.circle` / `.fill`).

- **Colour selection is not clear enough.** "The color change is not clear enough."
  → the selected swatch in `AnnotationBar` is a thin ring; needs a much stronger
  selected state (size bump, checkmark, or a filled surround), and the active
  colour should probably show on the toggle itself.

- **Two-finger zoom is broken: it does not anchor.** "As I do it the canvas — the
  point in the center of my fingers should not move, that should be the center of
  zooming, but right now the canvas moves as I zoom and that makes for a very
  glitchy experience."
  → `ScorePagesView` applies `MagnifyGesture` magnification to the page *width*
  inside a ScrollView, so content reflows around the scroll origin rather than
  scaling about the gesture anchor. Needs real anchored zoom: scale a container
  about `MagnifyGesture.Value.startAnchor` and adjust the scroll offset to keep
  that point fixed, or move the paged view into a `UIScrollView` with
  `zoomScale`/`viewForZooming`, which gives anchored pinch for free.

## Next major bucket — a selectable vector score (not a page bitmap)

Awaiting Ali's go-ahead: a UI design revamp is being explored in parallel and
may reshape the interaction. Do not start without it.

### The vision, in Ali's framing

The score should be a real vector representation, the way Finale, Sibelius,
Encore and Dorico render engraved music — "almost like a font", where every
note, every bar, every clef, every sign is an individually selectable object.
Today it is a flattened bitmap, which is why nothing on the page can be
pointed at. Lasso selection is not the goal; it is the first thing the
foundation makes possible.

### Why the current pipeline blocks it

`MusicXML -> Verovio SVG -> SwiftDraw -> PDF page bitmap`
(`ios/Scoranger/VerovioRenderer.swift`). Every coordinate and id is discarded
at render, so the app knows only "here is a picture of page 3".

The existing bar selection (`HighlightCaptureOverlay` in
`ios/Scoranger/ScorePagesView.swift`) maps a drag's horizontal span *linearly*
onto the measure count. That is why its chip reads "≈ bars 12–15": it is an
estimate, not hit-testing.

The material is already there before flattening. Page 1 of the sample quartet
carries 74 `g.note`, 19 `g.measure`, 19 `g.harm` (chord symbols), plus
`g.staff`, `g.layer`, `g.tie`, `g.rest`, `g.barLine`, `g.accid`, `g.stem` —
each with an SVG id. CORRECTION (measured in the spike, see
ios/VECTOR_SCORE.md): those ids are NOT stable — a fresh load of the same file
produces entirely different ones, and the source MusicXML carries no xml:id for
Verovio to adopt. Durable addressing must come from joining the SVG to
Verovio's MEI/getElementAttr output, which does expose measure and staff
numbers.

### Foundation: keep the geometry

1. Stop treating the SVG as an intermediate to be thrown away. Retain the
   parsed per-page document alongside (or instead of) the rasterised page.
2. Build a per-page spatial index of musical elements in page coordinates:
   id, kind (note / measure / harm / clef / articulation / spanner), rect,
   and the staff + measure it belongs to.
3. Map view coordinates into page coordinates through the zoom transform
   (`ZoomableScroll` owns it) so hit-testing is correct at every zoom level.
4. Render selection as an overlay keyed on element ids, so it survives zoom,
   scroll and re-render the way the highlight band already does.

Open question worth settling early: keep rasterising for display and use the
SVG purely as a hit-test model, or render the vectors directly and drop the
bitmap. The second is closer to Ali's "like a font" framing and gives crisp
zoom for free, but it is a bigger change to the drawing path and would need
its own performance work on multi-page scores.

### The interaction that rides on it

Decided with Ali: a **selection mode** (like annotation mode) with a **single
one-finger lasso** plus a **notes / bars / other picker**. The earlier
one/two/three-finger scheme is dropped: finger-count switching collides with
pinch zoom (which Ali specifically praised in build 116), with two-finger-tap
undo in annotation mode, and with iPad system three-finger gestures.

Selection then feeds chat as real context — parts and bar numbers rather than
an estimate — extending what `chatContextWithHighlight` already does.

`HighlightCaptureOverlay` is deleted only when this lands. Removing it first
would leave no way to select bars at all.

### Separate research spike — move/duplicate non-note elements

Selecting a fermata, slur or chord symbol falls out of the index above. Editing
one does not, and this should not be scheduled until two questions are answered:

- **No engine ops exist** for relocating or duplicating an expression or a
  spanner. They must be written as deterministic music21 operations (golden
  rule: notation is never hand-edited).
- **Identity does not round-trip.** Verovio's element ids are generated during
  its own MusicXML->MEI conversion and do not map back to music21 objects, so
  "this fermata on screen" cannot currently be resolved to "that fermata in the
  file". Candidate approaches: match on (part, measure, offset, element type)
  derived from SVG ancestry, or have the engine write a stable id into the
  MusicXML that survives Verovio's conversion. Settle this before designing any
  move/duplicate toolbar.

## Next build (collecting — Ali is still listing items)

### ~~Drag to reorder arrangements within a piece~~ — REMOVED in 0.4.2

Struck. Dragging is gone from the app entirely (NAV_MODAL_FREE_0.4.2 §9: "and
**every drag path**"), so there is no gesture left to design. Reordering inside
a piece is `Move up` / `Move down` on the piece screen, which calls the same
`reorder-piece` op the drag would have. The numbering analysis this section
carried was correct and is now moot: `#N` is derived from `piece.arrangements`,
so the badges and the chat refs follow the buttons the way they would have
followed a drop.

Also queued for this build: penny-whistle fingering notation (see below).

## Penny-whistle fingering notation

Requested by Echo, Ali's son, who plays penny whistle: an option to put
penny-whistle fingerings into a staff — ask for a part to be translated into
fingerings and have them render under the notes to play from, the way guitar
tab does. Not started; here is the shape of it.

Three pieces, in order:

1. **Note → fingering.** A standard six-hole D whistle has a well-defined
   mapping, including the second-octave overblown fingerings and the common
   half-holed accidentals. Look for an existing library or published table
   first; the mapping is small enough to encode directly in the engine if
   nothing suitable exists. It belongs in `ops.py` as a deterministic op like
   every other notation change — never generated by a model.
2. **Rendering.** Fingering diagrams (six dots, filled/open/half) aligned under
   the noteheads they belong to. Verovio has no whistle tab, so this is either
   a new layer drawn from the score model's per-note geometry (the Phase A
   address + spatial index already locate every note on the page) or an
   engraved annotation staff written into the MusicXML.
3. **The ask.** A chat tool so "show penny whistle fingerings for the melody"
   maps to the op on a named part, plus whatever the sheet needs to turn it
   off again.

Open questions: which whistle key to assume (D by default, but the part may be
in any key — transposing whistles are the norm), what to do with notes outside
the instrument's range, and whether fingerings live in the notation (versioned,
exportable) or as a view layer (cheap, disposable). The range question overlaps
with `check-range`, which already knows how to report notes an instrument
cannot play.

## Assessed for build 125, deferred with reasons

### ~~Drag to reorder — the numbering shipped, the drag did not~~ — MOOT

Struck. This section proposed a `List` + `.onMove` rewrite, or hoisting the
drop target to the section, to make the drop land. Neither will be built:
dragging was removed in 0.4.2. Kept only as the reason the `reorder-piece` op
is proven end to end.

### Move/duplicate of lasso-selected elements — tractable, but not free

More feasible than when it was first deferred, and worth stating precisely
what changed. Phase A addresses are (staff, measure, layer, kind, ordinal),
which resolve to music21 objects deterministically. The elements split three
ways:

1. **Offset-anchored** (dynamics, text, chord symbols) carry their own offset
   in a measure. Moving or duplicating is a deepcopy and an insert at a new
   (measure, offset) — deterministic, and an engine op could land in an hour.
2. **Note-attached** (fermatas, articulations) live on a note's `expressions`
   or `articulations`. Moving is remove-from-A, append-to-B — also fine once
   both ends are addressed.
3. **Spanners** (slurs, hairpins) reference their endpoints. Re-pointing them
   is deterministic only when the destination has an unambiguous anchor; "move
   this slur four bars later" has no answer when the rhythms differ.

So the *ops* are largely tractable. What is missing is the interaction: move
and duplicate need a destination, and there is no way yet to express one — the
selection has no drag, and the sidebar work above says dragging in this app is
its own problem. Design the destination first (drag the selection? tap a target
bar? a bar-offset stepper?), then the ops follow quickly for classes 1 and 2.

### Phase B, direct vector rendering — a renderer, not a feature

Still the right direction and still large. The current path is Verovio → SVG →
SwiftDraw → PDF → PDFKit raster, re-rasterized at the settled zoom. Drawing the
score directly means owning glyph rendering: Verovio's SVG places SMuFL glyphs
by reference (`<use xlink:href="#E0A4">`), so direct drawing needs the Bravura
font, the codepoint mapping, and path rendering for everything that is not a
glyph — beams, slurs, staff lines, hairpins. `SVGGeometryParser` gives element
*bounds* today, not draw instructions, so this is new work rather than a
rewiring.

It is also the one change that would put the thing Ali reads music from at
risk, and the problem it was meant to solve — pinch redraw — is currently
adequate (the page re-rasterizes at the settled zoom and stays sharp). Worth
doing behind a flag, in a session where it can be compared side by side against
the bitmap path on real scores, and not in a build that also carries features.

## Sequencing decided by Ali (for the build after the whistle build)

1. **Direct vector rendering (Phase B) first.** Promoted from "deferred, not
   recommended yet" to the next major build. Ali's rationale: he wants vector
   rendering to underpin the selection work.
2. **Then re-base the finger+Pencil selection interactions on it.**

Recorded as decided. One technical note for whoever picks this up, because the
plan reads as though selection is blocked on vectors and it is not:

Selection does NOT depend on the drawing path. The hit-test model is built by
parsing Verovio's SVG and MEI at engrave time (`ScoreModelBuilder`), which
yields per-element frames in page coordinates and durable addresses. The lasso
maps its points into those page coordinates and queries that model. How the
pixels reach the screen — PDF raster today, drawn vectors tomorrow — is not
part of that path. Build 124 ships working selection on the bitmap.

What Phase B genuinely adds, in order of real value:

- **Showing what is selected.** Today the page is one flat image, so the only
  feedback is the lasso outline and the chip's "8 elements in bars 1-4". The
  selected noteheads themselves cannot be tinted. Per-element drawing fixes
  that properly. (A halfway option exists: draw highlight boxes over the bitmap
  from the model's frames — the geometry is already there. Boxes, not tinted
  glyphs.)
- **Direct manipulation.** Dragging a selected element wants that element drawn
  on its own. This is the move/duplicate spike's real dependency.
- **Fidelity of odd shapes.** Curved spanners are indexed by bounding box, so a
  slur's "centre" can sit off the curve. Vector geometry would make lasso hits
  on those exact.

What Phase B does NOT fix, and should not be expected to:

- Precision at zoom — hit-testing is already in resolution-independent page
  coordinates.
- Which element kinds are selectable — that is the parser's class list, not the
  renderer.
- Selection on the remote-engine path — the model is built where the engrave
  happens, which is on-device only.

Risk worth pricing in: re-basing the selection interactions means replacing
code that ships and works today with code on an unproven renderer. If Phase B
is done first, keep the bitmap path behind a flag until the vector path renders
every score in the library correctly at every zoom level.

## Shipped in 0.1.2 — dragging, repeat signs, two pages side by side

All three of what were logged as 0.1.2, 0.1.3 and 0.1.4 went out together.
What is worth keeping from the write-ups:

### Dragging — the earlier diagnosis was wrong (SUPERSEDED: drag removed in 0.4.2)

**Read this as history only.** Every drag path described below was deleted in
0.4.2 on Ali's direction ("remove ALL drag-and-drop interactions entirely").
The diagnosis is preserved because it is a good lesson about blaming the wrong
layer, not because any of it still runs.

Three reorder designs were abandoned in build 125 on the conclusion that "a row
carrying `.onDrag` does not receive drops". That was not the cause. **A still
press of a second opens the row's context menu instead of lifting the drag**,
so under XCUITest the drop was never delivered — while dropping on a piece
*heading* worked, which is what made the row look guilty. Driving it with
`press(forDuration: 0.6, thenDragTo:, withVelocity: .slow,
thenHoldForDuration: 1.2)` delivers the drop to a sibling row in the same
piece, and the `List` + `.onMove` rewrite the backlog called for is unnecessary.

Shipped: a piece heading files an arrangement, a row inside a piece takes its
place in the order, a set list heading adds to the running order, the Unfiled
band unfiles. Every one also stays in the context menu.

~~Still open, if anyone wants them as drags: duplicate, and dragging out of a
set list.~~ Struck — there are no drags. Duplicate and Remove from piece are
buttons on the arrangement screen.

### Repeat signs — what the engine now has

`scor set-structure <score> --kind K --measure N [--to-measure M] [--number N]
[--times N] [--remove] [--move-to N]`, wired to the CLI, the app bridge and
both chat tool lists. Kinds: `repeat-start`, `repeat-end`, `repeat-both`,
`volta`, and the navigation marks (`segno`, `coda`, `fine`, `da-capo`,
`da-capo-al-fine`, `da-capo-al-coda`, `dal-segno`, `dal-segno-al-fine`,
`dal-segno-al-coda`). One op with a `kind`, as the write-up recommended, to
keep the chat tool list short.

`engine/scripts/check_structure.py` engraves every mark and looks for it in the
MEI Verovio returns. It caught the one that mattered: **music21 merges the two
staves of a grand staff into a single MusicXML `<part>`, and in that merge the
second staff's barline replaces the first's — taking the volta's `<ending>`
with it.** A volta now goes on every staff of the joined group. Repeats already
went to every part.

`repeat.Expander` is still unused and still the tool for a future "play this
through as written".

**Ali still owes a screenshot and the exact prompt that failed**, to confirm
that specific case reaches the new op.

### Two pages side by side

`SpreadLayout` (in `Scoranger/ScoreModel`, so the unit tests compile it in)
decides page width and which pages share a row; `ScorePagesView` lays out rows
of one or two. Off by default, under a Reading band in Settings.

Decisions taken, against the questions the write-up left open:

- **No automatic fallback when a panel opens.** The pages shrink and zoom is
  the answer. A setting that silently stops applying is worse than a narrow
  spread the user can see and close a panel to fix.
- **A spread is not capped at 1100pt** the way a single page is, or a wide
  display leaves a band of ground down the middle.
- **The odd last page sits alone**, in the left-hand slot.
- No orientation special-casing: the layout is width-driven.
- The pill still says nothing about which pages are showing. Nobody asked.

The flagged risk — a lasso on the right-hand page selecting from its neighbour
— did not materialise: each page carries its own `LassoAnchor` and the
recognizer picks the anchor under the touch.
`testALassoOnTheRightHandPageSelectsFromThatPage` draws on both halves and
checks the right one gives later bars.

## Shipped in 0.1.2 (bug-fix build) — rhythm integrity, single version highlight

### The rhythm bug, and what it actually was

Reported as "a prompt that had nothing to do with durations made an eighth note
dotted and pushed everything after it a sixteenth later". Three wrong suspects
were ruled out by measurement before the real one turned up:

- **Round-trip rounding: no.** Six consecutive parse/serialize cycles over 6/8
  with dotted-eighth + sixteenth pairs and triplets came back identical.
- **The op named in the version history (`pull-part`): no.** Its whole-part
  branch is a `deepcopy`; it tests clean from clean sources. It faithfully
  copies whatever the source holds, which is why the damage *appeared* there.
- **The other ops in the ladder** (`change-instrument`, `whistle-fingerings`,
  `set-chords`, `limit-part`, `rebuild-part`): all clean, tested.

The fault was the **write**, shared by every entry point including
`add-source` — which is how a corrupt source file got into the library in the
first place, before any arrangement op ran.

Two ops were also breaking scores on their own: `absorb_part` read each note's
offset *after* detaching it (music21 reports 0 for a detached element, so the
melody piled onto the downbeat) and assumed the target staff had no voices;
`consolidate_ties` and `_flatten_copy` handed `stripTies` results straight on.

### Worth knowing next time

- **Measure the file, not the intention.** Several hours went into in-memory
  comparisons that showed nothing, because the score was correct in memory and
  the writer was the problem. `check_rhythm.py` writes and reads back.
- **A duration sum is not a length.** Summing a container's durations treats
  simultaneous notes as sequential, which made a collapsed measure look
  correct. Compare each voice's END TIME against the bar.
- **Diffing two event lists by index lies** once an op adds or removes an
  event: every later pair misaligns and reads as "everything moved". Compare by
  position, or compare sets.
- Under-filled bars are legitimate (pickup, partial bar before a repeat, last
  bar of a piece). Only overflow is corruption; an exact-fill assertion would
  refuse honest scores.

### Version highlight

A prompt group's steps include the group's own face version, so with the steps
open both the group row and a step row claimed the highlight. Open groups let
their step rows own it; collapsed groups stand in for whichever version shows.


## Next build — chord symbols shrank (regression, root-caused)

Ali: chord names used to render much bigger and legible; now they are small
and hard to read. **Found: build 128 did it, and it is a coupling in Verovio's
options, not anything to do with the chord op.**

Verovio has exactly one text-size option, `lyricSize` (default 4.5), and it
governs BOTH lyric verses and `<harm>` chord-symbol text. Build 128 ("whistle
diagrams above the staff, at half size") set `lyricSize` to 2.2 to halve the
fingering diagrams -- in `render.py` (`WHISTLE_LYRIC_SIZE`) and in
`VerovioRenderer.swift` (`FingeringDiagrams.lyricSize`) -- and chord symbols
came along for the ride. Measured on a jig with three chord symbols:

    lyricSize 4.5  ->  chord symbol font-size 405
    lyricSize 2.2  ->  chord symbol font-size 198     (less than half)

It applies whenever the score carries fingerings, which is exactly Ali's
Morrison's Jig: whistle fingerings AND chord names, so the names halved. A
score without fingerings still renders them at 405.

There is no independent harm-size option. `harmDist` and `topMarginHarm` move
chord symbols; they do not size them. `fingeringScale` (0.75) applies to `<fing>`
elements, which is not how these fingerings are encoded.

### The fix, and why this one rather than the alternatives

**Stop shrinking `lyricSize`; scale the diagrams ourselves.** Both renderers
already rewrite each tagged verse glyph into circle paths
(`render.py::_fingering_diagrams`, `FingeringDiagrams.swift`), and the circle
radius is a proportion of the verse font-size. Put `lyricSize` back to 4.5 and
apply the ~0.49 factor inside that pass, so the diagrams stay the size Ali
approved in 128 while chord symbols go back to full size. Our own drawn glyph
should not ride on a global text option that also sizes someone else's text.

Watch: Verovio reserves vertical space from `lyricSize`, so at 4.5 there will
be more room above the staff than the small diagrams need. `lyricTopMinMargin`
and `lyricHeightFactor` are the knobs for that; check it visually.

Rejected: scaling `g.harm` font-size back up in our SVG pass (a compensation
layered on the coupling rather than removing it), and re-encoding fingerings as
`<fing>` elements to use `fingeringScale` (a much larger rewrite).

**A check to add with the fix**: chord-symbol font size must not depend on
whether the score has fingerings. That is a one-line assertion over two renders
and it would have caught this.

Ali is resending a screenshot of the small rendering; it may show he wants them
larger than the 4.5 default, in which case the target size changes but the
decoupling above does not.

## Next release — size and position for things added to a score (Ali)

When Ali adds something to a score he wants to change its SIZE and its
LOCATION. Starting with chord symbols, extending to other added text and marks.

This is the other half of the chord-size regression: the reason a global option
could shrink his chord names is that nothing owns the size of an added element.
Per-element size and offset would make that impossible by construction.

### Shape of the work

- **Model.** A chord symbol is a `music21.harmony.ChordSymbol` at an offset in a
  measure. MusicXML `<harmony>` carries `default-x`/`default-y` (and
  `relative-x`/`relative-y`) for position, and MEI has `@ho`/`@vo` offsets --
  so both a size and an offset can be stored in the notation rather than in
  app-side state, which is the rule this project holds to.
- **Ops.** Something like `scor style-element <score> --part X --measure N
  [--kind harmony] [--size 1.4] [--offset-x 0 --offset-y -2]`, and a
  score-or-part-wide default (`chart-style` already exists and is the natural
  home for "all chord symbols this big").
- **Verovio.** Per-element size needs the size to reach the engraving. Check
  early whether Verovio honours `@fontsize` on `<harm>`, or whether it has to
  be a post-pass in `_fingering_diagrams`' neighbour -- the answer decides
  whether this is an op-only change or an op plus renderer change.
- **UI.** This is where it meets the deferred move/duplicate spike. Offset-
  anchored elements (chord symbols, text) are the tractable case: the lasso
  already resolves an element to a `ScoreAddress`, so a drag of a selected
  chord symbol becomes an offset write, and a pinch or a stepper becomes a size
  write. Notes are the hard case and stay out of scope.
- **Chat.** "make the chord names bigger", "move that Em up a bit" should reach
  the same op, so the tool wants a size/offset argument rather than a new verb
  per adjustment.

### Worth deciding before building

- Whether size is absolute (points) or relative (a multiplier on the engraved
  default). Relative survives a page-size change; absolute is what a user
  means when they say "14pt". Lean relative, and say so in the UI.
- Whether an adjustment belongs to the arrangement (versioned, travels with
  the score, which is this project's model) or to the view (per-device, not in
  the notation). Versioned is consistent with everything else here; it does
  mean an adjustment costs a version.
- Reset. Any per-element override needs a way back to the default, or scores
  accumulate nudges nobody can undo.


## Order of work, set by Ali (2026-08-23)

1. **Chord-name fix** — shipped, 0.2.2 build 133, VALID.
2. **Selection rework** — in progress. 0.2.3 carries steps 1–3 (the
   finger+Pencil scheme scratched, two-finger-tap undo restored, hold-then-drag
   lasso); 0.2.4 carries steps 4–5 (Replace/Add/Subtract chip with
   tap-to-drop-one, and sidebar drop targets that show themselves on lift plus
   the reordered menu). Per the confirmed spec in
   `docs/hold-then-drag-spec.md`.
3. **Size and position for added elements** — chord names first, then other
   added text and marks, adjustable by drag/pinch and by chat. Analysis first,
   then TDD. Scoped earlier in this file.
4. **Awaiting Ali's explicit go-ahead — do NOT start without it**: direct vector
   rendering (Phase B), then re-basing selection on it; and move/duplicate of
   non-note elements, which shares the offset/identity problem with item 3 and
   should be tackled alongside it.
5. **The testing push — AFTER the feature work above, not before.**

## Near-term queue after 0.4.2 (set by Ali, 2026-08-27)

In order. Each ships as its own verified increment.

1. **Share & export.** The score's `Share & export` row pushes to a section
   with no `case`, so it lands on a note saying export lives in the engine.
   `scor export --format musicxml|midi|pdf` already exists and is already
   reachable from the app bridge. Wire the row to it and hand the file to the
   system share sheet — Apple's own sheet is exempt from the no-modal rule.
2. **Bar-position counter.** The `bar 21` readout in the score's top bar. No
   `visibleBar`/`barCounter` exists yet. Cheaper since 0.4.2: the paged canvas
   keeps the viewport inside one page's coordinate space, and
   `ScoreModelBuilder` already indexes every measure's frame in page
   coordinates, so this is a visible-rect query against an index that exists.
3. **Size and position for added elements** (chord symbols first). See the
   section above for the model and the ops. **The UI half of that spec is
   stale** — it assumed drag-and-pinch to reposition, and 0.4.2 removed drag
   while pinch means zoom. The engine op and the storage are unaffected and can
   proceed; the interaction is with the designer.
4. **Crisp deep zoom.** 0.4.2 raised the zoom ceiling to 12x but the page is
   still one bitmap capped at `maxRasterWidth` (5200px), so it softens past
   roughly 3-4x. Assess tiling / re-raster-at-depth against simply waiting for
   Phase B vector rendering, which supersedes it.

## Known coverage gap — the chip's adjust row has no end-to-end test

0.4.3 shipped position and size for chord symbols. Everything about the row is
covered EXCEPT driving it through the UI:

- `ChordAdjustSessionTests` -- 28 cases over the step, the clamps counted
  against what the notation already carries, the ladder, pending, revert, reset,
  and what commits.
- `check_adjust_journey.py` -- chords on a score, nudged, resized, exported, and
  the size and offset read back out of the exported file.
- Two UI tests: that the fixture really adds chord symbols, and that the Chord
  symbols screen carries the default and the two-step reset-all.

What is missing is a UI test that lassos a chord symbol and taps the row. Three
attempts were deleted rather than left flaky: the lasso has to land on a small
target whose position depends on the engraving, and a sweep across 6%-46% of the
page caught notes and rests but never an all-chord-symbol selection. A mixed
selection is deliberately not adjustable, which is correct behaviour and also
what makes the target hard to hit.

Worth trying when someone picks this up: seed a score whose chord staff has been
through `strip-notes` AND has its rests hidden (`chart-style` does that), so a
lasso over the staff can only catch chord symbols. `strip-notes` alone was tried
and the staff's rests were still caught.

## After feature work — the dedicated testing push

Queued deliberately at the end. These are the gaps in the honest coverage
audit: everything below is covered by nothing today, and each is a place a
user-visible failure has either already happened or would go unnoticed.

- **Chat / the LLM path.** Zero automated coverage, on a chat-driven app. The
  headless hook exists (`inbox-chat` / `outbox-chat`, `scripts/test_chat_e2e.sh`)
  and needs a network and a key, so the work is deciding what can be asserted
  without one: tool-call dispatch and argument shaping can be tested against a
  stubbed model; only the model's judgement needs the real thing.
- **OMR / Audiveris.** Zero. `PDFPreflightTests` covers the step *before* OMR
  with synthetic PDFs. The pipeline that produced Ali's Morrison's Jig has never
  been exercised by a test.
- **The `scor` CLI binary.** Zero. Every engine check calls Python functions
  directly, never the process. This gap has already cost us:
  `scor whistle-fingerings` was completely dead with a NameError and no test
  noticed — it was found by hand, twice, months apart.
- **`bridge.py`**, the app's dispatch layer: only exercised incidentally through
  UI tests.
- **Apple Pencil, and any real device.** The simulator has no Pencil; annotation
  tests use a finger stand-in. Nothing runs on hardware.
- **Visual/engraving regression.** `check_render.py` measures font sizes and
  radii; nothing asserts the page *looks* right, so a layout could break with
  every test green.
- **Export from the app UI** (the engine-side export is covered).

## Continuous view: follow does not consult pageFollow -- DONE, and this entry
## was stale

Paged view answers a manual page turn with the Sync chip -- the music keeps
playing, the page stays where the reader put it, and following resumes only when
they ask. This said continuous view had no such gate.

**It has had one since 6db130a2 ("The play head's handle can be dragged"), which
shipped in 0.6.19 build 179.** `ContinuousPlayheadLayer.follow()` guards on
`isFollowing`, and `readerScrolled()` -- wired to the canvas's `onUserScroll`,
which carries the continuous strip as well as the paged canvas -- calls
`state.readerTurnedPage()` and forgets the scroller's target. A hand on the
strip during playback yields following and raises the Sync chip, the same state
and the same rule as a paged turn.

Checked before writing a second fix for it, which is the only reason this note
exists: the entry outlived the work, and the next reader would have implemented
it twice.

WHAT IS STILL MISSING is a test, and it is view-level: `PageFollowTests` covers
the model, so `readerTurnedPage()` clearing `isFollowing` is asserted, but
nothing asserts that a scroll of the CONTINUOUS strip reaches it. That wants a
UI test -- scroll the strip mid-performance, assert the Sync chip appears and
the strip stays where it was put.

## PaginationAfterAnOp's system count passes and fails for reasons nobody chose

`PaginationAfterAnOp.testTheSystemCountAgreesWithTheEngine` compares the app's
per-page system count against a hard-coded 25 that the engine reports for the
accordion solo. Measured, three ways, and the results do not agree with each
other:

- **Run alone, it fails 3 times out of 3**, deterministically, in ~22s:
  `pages=5 systems=5,6,6,6,3` -- 26.
- **In the sharded gate it PASSED**, in ~70s: `pages=9 systems=3,3,3,2,3,3,3,3,2`
  -- 25. Same binary, same xctestrun, same simulator UDID.
- **The engine, re-measured**, reports 25 both on the raw `.mxl` (5 pages,
  `5,6,6,6,2`) and on the imported v001 (5 pages, `5,6,6,5,3`).

So the hard-coded 25 is current, and the app produces EITHER 25 or 26 depending
on something the test does not control.

**It is not the viewport, and this is worth writing down because it is the
obvious wrong answer.** `EngravingOptions` fixes every page-setup value --
width 2159, height 2794, scale 45, all four margins -- and `adjustPageHeight`
is true only for the continuous strip. Paged engraving cannot vary with the
window, so 9 pages and 5 pages are not two fits of one engraving. They are two
different engravings, which means **the music differed**: the library state the
test found was not the same in the two runs, despite
`-resetLibrary -seedTestLibrary`.

That makes this a TEST ISOLATION problem before it is a pagination problem, and
the consequence is the part that matters: **the gate's green on this test is not
evidence.** It passed with a pagination nobody expected, on a library nobody
intended, and a run alone fails. A test that passes under load and fails idle is
reporting on the harness.

**Ruled out on the 0.6.21 line (2026-09-08), so nobody spends the time twice:**

- *A leftover fixture from an earlier test.* `-resetLibrary` does a real
  `FileManager.removeItem` on `Documents/workspace` inside
  `PythonEngine.start()`, BEFORE the engine is configured -- so nothing an
  earlier test did to the accordion solo survives into this one. This was the
  leading hypothesis and it is wrong.

Where to look, in order:
1. Whether `-resetLibrary -seedTestLibrary` actually completed before the probe
   was read, or whether the 240s waits let a partially seeded library through.
   The seeding path already has form here: `seedOutcome` exists because a
   `pull-part` that failed was invisible and three preconditions were written
   before one of them noticed.
2. `lyricSize`. `EngravingOptions.json(lyricSize:continuous:)` takes it as a
   parameter and `render.lyric_size_for(fingerings:)` returns a larger value
   when fingerings are present. A bigger lyric size makes every system taller,
   which is exactly how 25 systems land 3-to-a-page over 9 pages instead of
   5-6 over 5. If the two runs engraved at different lyric sizes, that is the
   difference, and the question becomes why.
3. Only then the app's own inference, `BarPosition.systems(of:)`.
   `check_bar_frames.py` records the hazard -- Verovio nests a slur inside the
   measure it starts in and a group's frame is the union of what it contains --
   so one over-wide bar frame straddling two rows would split one system into
   two, which is an over-count of exactly one. The fragility is worse at 5-6
   systems per page than at 3, which fits both observations.

The 0.6.21 line SKIPPED this test in its gate for the reasons above. The 0.8
line did not: it runs in the pool and passed in the build 196 gate (79s). A
green here is still not evidence until the two engravings are explained.

**Not a 0.6.20 regression.** Every file feeding that number is byte-identical to
`afa0c572`, which is 0.6.19 build 179 and already on the phone:
`ScoreGeometry.swift` (which computes `systemsPerPage`), `ContentView.swift`
(which surfaces the probe), `ScoreBarLayout.swift`, `EngravingOptions.swift`,
and the test itself.

Worth doing because this test is the observable for issue #4 (pagination
collapse). While it can pass for the wrong reason, nothing it says about #4 can
be believed either way.

## The gate's four workers are over-subscribed for engine-backed UI tests

`ENGINE_SERIAL` in `ios/scripts/gate.sh` grew three times on 2026-09-08, and
every addition had the same shape: a UI test that WAITS ON A CALL INTO THE
EMBEDDED PYTHON ENGINE, timing out under four workers and passing solo in
roughly half the time it was allowed.

- the deletion class -- a delete through the engine; 25-32s solo, past 210s
  under load (the original entries)
- `testTheChordSymbolsScreenCarriesTheDefaultAndTheLadder` -- waits for the
  piece screen to list its arrangements, a manifest read; 36s solo, 117s and a
  timeout under load
- `testEachStripsControlsBelongToThePartItNames` -- waits for mixer strips,
  which come from a playback timeline; 27s solo, found ZERO strips under load

**It is one contention class, not three flakes**, and serialising each is a
targeted remedy that works but lengthens the serial tail every time. Two
structural fixes, neither attempted:

1. **An engine-aware scheduler.** Let at most one engine call be in flight
   across the whole gate -- a lock the test host takes around the ops that
   contend -- so everything else stays parallel. This is the right shape,
   because the contended resource is the engine and not the host.
2. **Fewer workers**, which costs every run to fix a subset of tests, and
   would have to be measured against the ~29 minute wall clock before being
   worth it.

Worth doing when the serial phase starts dominating the gate, or the next time
a test is added to `ENGINE_SERIAL`. Not urgent while the tail is six tests.

## The eight rotating UI tests fail only inside the gate (2026-09-10)

`LandscapeFits` (4), `MixerOnAlisCase` (2 landscape), `MixerTwoChannel` (2
landscape) fail in `gate.sh` -- in the four-worker pool and in the serial phase
-- and pass in every configuration tried by hand on the same build: alone on an
idle device (15-25s), under four workers running only those eight (22-205s),
and the serial phase's own 15-test command on the same device with the same
result bundle (13-27s, 15/15, at load 7.2, while the gate's run of it failed at
load 5.4). The failure is always the same: the window never leaves portrait,
for the whole budget, and the tests immediately after rotate fine.

Six causes asserted and disproved by measurement: a dirty pool, the budget
(20 -> 120 -> 240s, re-asking every 8s), foreign booted simulators, load, the
unit-test target running first, `-resultBundlePath`. The seventh candidate --
the phase begins the instant four workers stop -- is untested. Five gates went
into this on 2026-09-09, on tests of the mixer's landscape layout, while the
sharing feature waited.

**Skipped in `gate.sh` with this record beside them.** Not serialised (they
fail serialised too) and not deleted (they pass by hand and assert real
things). To close this: reproduce the failure by hand -- run the pool, then the
serial command within a minute -- and if that reproduces, capture
`simctl io <udid> screenshot` and the SpringBoard orientation at the moment the
budget expires. Until it reproduces by hand, nothing else is worth trying.
