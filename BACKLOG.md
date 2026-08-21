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
