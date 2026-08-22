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

### Drag to reorder arrangements within a piece

Let the user drag an arrangement up and down inside its piece, and have the
numbers follow. #N is not decoration: it is how Ali refers to an arrangement in
chat ("take the violin part from #3"), so a reorder has to move the badge and
the '#N = ... (ref arr:<slug>)' mapping the chat context is built from, in the
same breath. Anything that renumbers silently, or renumbers the badge but not
the refs, is worse than not reordering at all.

Most of the machinery is already there:

- `reorder-piece` (engine op, `workspace.set_piece_order`) takes the piece and
  the full ordered list of slugs, and validates that every slug belongs to the
  piece. It is already exposed through the bridge and through
  `AppState.reorderPiece(piece:order:)`.
- The context menu already drives it — "Move up (become #2)" / "Move down" in
  `arrangementMenu` — so the op is proven end to end. This is about the gesture,
  not the plumbing.
- Rows already carry `.onDrag` (that is how an arrangement is dragged into a
  piece), and `pieceRow` already has an `.onDrop`. What is missing is a drop
  target *between* rows within a piece.
- `#N` is derived, not stored: `piecesSection` numbers by position and
  `AppState.placement(of:)` reads the index out of `piece.arrangements`. So a
  correct reorder needs no numbering code at all — the badge follows the list.
  The chat refs come from the same list (`AppState`'s numbered context), so they
  follow too. Worth an assertion in the UI test rather than an assumption.

Watch for: the row-identity trap that bit build 123. Rows keyed by slug alone
get matched against the row they replace when they move between sections, and
SwiftUI reuses the old one — which is how a moved arrangement kept a numeral it
should not have had. The identities are section-scoped now; a reorder inside one
section will need the same care so a dragged row does not inherit its
neighbour's number.

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

### Drag to reorder arrangements — the numbering shipped, the drag did not

Reordering works and is covered: "Move up (become #1)" / "Move down" in an
arrangement's context menu call `reorder-piece`, and two tests now assert that
the #N badges AND the chat refs follow the new order (they are both derived
from `piece.arrangements`, so neither needs renumbering code).

What did not work is the *gesture*. Three shapes were tried and none received
the drop: the row itself as a target, a background layer behind the row, and a
dedicated insertion strip between rows (via both `onDrop` and
`dropDestination`). Instrumenting the handler showed it never runs.

This is NOT a test-harness limit, which was checked rather than assumed: a
control test dragged an unfiled arrangement onto a piece heading — the gesture
that shipped in an earlier build — and it worked under XCUITest. That control
is now a permanent test. So SwiftUI is declining to deliver drops somewhere in
the arrangement-row hierarchy, and the row being a drag source (`.onDrag`) is
the likeliest reason: a view that is dragging cannot also be dropped on, and
the neighbouring strips inherit something from that context.

Next things to try, in order: move the whole per-piece list into a `List` with
`.onMove` (which owns reordering natively and sidesteps drag sources entirely —
the cost is fitting a List into the overlay sidebar's styling); or hoist the
drop target to the *section* and compute the insertion index from the drop
location. Budget it as a session, not a patch.

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
