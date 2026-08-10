# Scoranger — Architecture

A web product for musicians: drop in a score (PDF, MusicXML, or MIDI) and use a chat
agent to create new arrangements — extract parts, remove parts, transpose, re-clef,
adapt for other instruments — then export a clean new score.

*Last updated: 2026-08-09. Research findings verified as of this date; citations in the appendix.*

> **Prototype pivot (2026-08-09):** this document describes the eventual product.
> The current code is a simplified local prototype — no Firebase, no in-app chat:
> a Python/music21 engine CLI (`engine/`), a local React+OSMD viewer (`viewer/`),
> and **Claude Code as the arrangement agent** (see `CLAUDE.md`). The engine's tool
> layer is the same one a hosted agent loop will call later. Deferred features: `BACKLOG.md`.

---

## Product decisions (locked)

| Decision | Choice | Rationale |
|---|---|---|
| Audience | **Product for other users**, not a personal tool | Justifies in-app OMR correction UX, multi-tenancy, quotas |
| Arrangement ambition (v1) | **Brilliance in the deterministic basics**: part extraction/removal, transposition, clef changes, instrument adaptation | Achievable with near-perfect reliability today; generative arrangement (piano reduction, orchestration) deferred to v2+ behind the same tool interface |
| PDF input (MVP) | **Clean engraved publisher PDFs** | Photos/scans are table stakes for GA but deferred past MVP; handwritten explicitly unsupported (research-only across the industry) |
| Editing | View + chat + export in v1; **no in-browser notation editor** | A notation editor is a product unto itself; export MusicXML for touch-ups in MuseScore/Dorico |
| Canonical format | **MusicXML 4.0** (stored compressed as `.mxl`) | Universal interchange; MNX still an unstable draft in 2026; MEI locks into Verovio's world |

## The core architectural principle

**The LLM never writes notation. It plans; deterministic tools execute.**

Frontier LLMs score only ~47–49% on full-score comprehension benchmarks (MSU-Bench,
2025) and hallucinate bar contents. But an LLM agent calling deterministic
score-editing tools hit **99.6%** on a precise-editing benchmark vs **75.4%** for an
agent editing MusicXML text directly (ScoreSpeak, Cal Poly 2025). Every operation we
care about in v1 — part ops, transposition, clef choice, range checks — is interval
arithmetic and lookup tables that music21 does perfectly.

Corollary: when the agent needs to *read* music (which voice has the melody? where
does the theme return?), it reads **bar-indexed ABC notation** converted on the fly —
~10× fewer tokens than MusicXML and the representation LLMs demonstrably handle best.
It never reads raw MusicXML. Most v1 operations don't require reading notes at all;
part lists and metadata suffice.

## System overview

```
INGEST                              CANONICAL STORE                AGENT LOOP
MusicXML ──(normalize)───────┐
MIDI ──(MuseScore CLI)───────┼──►  MusicXML 4.0 (.mxl)         Chat agent (frontier LLM)
PDF ──(Audiveris headless    │     Cloud Storage,                │ reads: part list, metadata,
       + correction UI)──────┘     immutable versions;           │        bar-indexed ABC on demand
                                   metadata + version graph      │ calls: music21 tools on Cloud Run
                                   in Firestore                  │
RENDER / EXPORT                                                  ▼
OSMD 2.x in React  ◄──────  new immutable .mxl version  ◄──  verify: parse → range-lint → render
PDF / MIDI / parts export via MuseScore CLI
```

### Stack

| Layer | Choice | Notes |
|---|---|---|
| Frontend | React + **OpenSheetMusicDisplay 2.x** | BSD-3, native MusicXML rendering, note-level interactivity (cursor API, click/highlight). Verovio (LGPL) is the fallback if engraving quality becomes a differentiator, at the cost of MusicXML→MEI conversion on every render |
| App backend | **Firebase**: Auth, Firestore, Cloud Storage, Hosting | Firestore holds score metadata, chat history, job docs, version graph |
| Score engine | **Python on Cloud Run**: music21 + MuseScore 4 CLI (xvfb) + Audiveris | One service (or a small set), custom Dockerfile. Cloud Functions can't host this |
| Job orchestration | Firestore job docs + **Cloud Tasks** → Cloud Run | Client gets realtime job progress free via Firestore listeners. Cloud Run allows 60-min requests; OMR jobs fit comfortably |
| Agent runtime | Server-side agent loop (Cloud Run) calling Claude API with tool definitions | Tools dispatch to the score engine. Claude was the strongest frontier model on the music-theory and visual-score benchmarks surveyed |

### Data model (Firestore + Storage)

- `scores/{scoreId}` — title, owner, source type, current version pointer, part list
- `scores/{scoreId}/versions/{versionId}` — immutable; parent version, operation log
  (the tool calls that produced it), Storage path to `.mxl`. Undo = repoint; compare
  arrangements = render two versions side by side
- `scores/{scoreId}/chats/{chatId}/messages` — conversation, with tool calls recorded
- `jobs/{jobId}` — status: queued → processing → done/failed; client subscribes

Every mutation creates a new version. Nothing is edited in place.

## Ingestion pipelines (by increasing difficulty)

1. **MusicXML** — parse with music21, normalize (validate parts, fix common exporter
   quirks), store. Nearly free.
2. **MIDI** — `mscore in.mid -o out.musicxml` headless (best OSS MIDI import;
   quantizer + voice separation), music21 post-processing. Lossy by nature: no clefs,
   enharmonics, articulations, or dynamics in MIDI. Label the result as inferred.
3. **PDF (MVP: clean engraved only)** — **Audiveris 5.9+ headless** in the container
   (`-batch -export`), 300 dpi rasterization. Output is a *draft*: even best-case OMR
   needs a per-page correction pass (systematic residual errors: tuplets, grace notes,
   dynamics, transposing instruments, ties, multi-voice rhythms).
   - **Correction UX (modeled on Soundslice, the industry best):** render recognized
     MusicXML in OSMD side-by-side with the source PDF page; surface low-confidence
     regions first (mine per-symbol confidence from the Audiveris `.omr` project
     file); support measure-level re-entry. This is a first-class product surface,
     not an afterthought.
   - **Post-MVP:** add `homr` (transformer OMR, AGPL, Python) as a second engine
     routed to photo/scan uploads, where Audiveris is weak. If OSS accuracy caps out,
     the only commercial engine licensable for self-hosting is PlayScore's
     ReadScoreLib (C library). Soundslice/Newzik/ScanScore/SmartScore have no APIs.
   - **Never:** handwritten (decline explicitly), VLM-based reading of score images
     (frontier VLMs score ~20–24% on score QA).

## The agent

### Tool inventory (v1 — the "brilliant basics")

Score structure:
- `get_score_info()` — parts, instruments, key/time signatures, measure count, tempo map
- `keep_parts(part_ids)` / `remove_parts(part_ids)`
- `extract_measures(start, end)`
- `merge_scores(...)` (post-v1 candidate)

Pitch and notation:
- `transpose(interval, part_ids?, written_or_sounding)` — key-signature-aware,
  correct enharmonic spelling
- `change_instrument(part_id, new_instrument)` — the flagship compound tool:
  applies the instrument's transposition, picks the idiomatic clef, octave-shifts
  to fit range, renames the part, flags unplayable passages instead of silently
  mangling them
- `change_clef(part_id, clef, measure_range?)`
- `respell_enharmonics(part_id?)`
- `octave_shift(part_id, direction, measure_range?)`

Reading (returns text to the LLM, never mutates):
- `read_as_abc(part_ids?, measure_range?)` — bar-indexed ABC (`%1, %2 …` markers to
  counter the bar-localization failure mode)
- `check_range(part_id, instrument)` — out-of-range notes with measure numbers
- `analyze(kind, ...)` — key, melody-vs-accompaniment heuristics, voice density

Every tool call: **parse → execute → range/sanity lint → re-render → diff shown to
user**. The agent's plan is visible ("I'll extract Violin I and Viola, transpose the
viola line up an octave where it sits below C3, and set alto clef") and each step is
individually undoable via the version graph.

"Brilliance in the basics" bar: the output of `change_instrument` +
`extract_parts` should look like a professionally prepared part — correct clef,
sensible page turns eventually, proper part naming, transposed vs. concert pitch
handled correctly. That polish, not model magic, is the v1 differentiator. No
incumbent (Sibelius, Dorico, MuseScore, Flat) ships chat-driven arrangement as of
mid-2026 — we'd be first, and the deterministic core is what makes it trustworthy.

### v2+ generative tools (behind the same interface)

Piano reduction, accompaniment filling, re-orchestration — wire in specialized models
as *draft generators* whose output passes through the same lint/verify pipeline:
- NotaGen (MIT-licensed weights, ABC, score-quality classical generation)
- The NeurIPS 2025 unified arrangement model (band arrangement / piano reduction /
  drum arrangement, any-to-any instrumentation)
- music21's `chordify()` / `PartReduction` as the deterministic baseline for reduction

No fine-tuning needed for v1. Revisit only if v2 generative quality demands it.

## Product-grade concerns

- **Licensing isolation:** Audiveris and homr are AGPL — run unmodified as separate
  services/containers; if we modify them, we must publish those modifications (fine).
  MuseScore is GPLv3 — invoked strictly as a CLI subprocess, never linked; server-side
  use is not distribution, so no copyleft obligation on our code. music21 is
  BSD-compatible (dual license). OSMD is BSD-3.
- **Copyright of uploaded scores:** users will upload publisher PDFs. Private,
  user-scoped storage + processing (format-shifting for personal use) is standard for
  this product category (Soundslice, Newzik operate this way), but ToS must prohibit
  public redistribution, and any future "share/publish" feature needs a rights
  gate. Get real legal review before launch.
- **Cost control:** OMR and conversion jobs are the expensive path — per-user quotas
  (pages/month, mirroring Soundslice's 100 scan-pages/mo model), Cloud Tasks rate
  limiting, and job-size caps from day one. LLM chat costs metered per user.
- **Multi-tenancy:** Firestore security rules scoping everything by `ownerUid`;
  Cloud Run verifies Firebase Auth ID tokens via `firebase-admin`.

## Build phases

**Phase 0 — walking skeleton (the novel part first, OMR last):**
MusicXML upload only → OSMD rendering → chat agent with 5 tools (`get_score_info`,
`keep_parts`, `remove_parts`, `transpose`, `change_clef`) → versioned output →
MusicXML export. End-to-end on clean input. This proves the product thesis.

**Phase 1 — the flagship tool + export polish:**
`change_instrument` with range/clef/octave intelligence, `read_as_abc`,
`check_range`; PDF and MIDI *export* via MuseScore CLI; part-extraction formatting
quality.

**Phase 2 — MIDI ingestion.** Cheap; reuses the MuseScore container.

**Phase 3 — PDF ingestion (MVP-complete):**
Audiveris pipeline + the side-by-side correction UI. Biggest single lift in the app.

**Phase 4 — GA hardening:** photo/scan support (homr routing), quotas/billing,
sharing, playback (OSMD cursor + soundfont).

---

## Appendix: research summary (verified Aug 2026)

### Why not let the LLM edit notation directly
- MSU-Bench (arXiv 2511.20697): best frontier models 47–49% on full-score QA (ABC
  input); ~20–24% from PDF images; failure modes = bar misalignment + hallucination.
- ScoreSpeak (Cal Poly thesis 3338, 2025): 80+ MusicXML tools; tool-calling agent
  99.6% vs 75.4% for direct-text editing on a 752-case benchmark. Open-source.
- ABC-Eval (arXiv 2509.23350), ZIQI-Eval (2406.15885), MusicTheoryBench (2402.16153):
  consistent limitations across models and tasks.
- Format for LLM reading: ABC (compact, well-represented in training data; used by
  ChatMusician/MuPT/NotaGen and as MSU-Bench's textual upper bound).

### Specialized models (none does chat-driven arrangement; all candidates for v2 draft generators)
- NotaGen (IJCAI 2025, MIT weights) — score-quality classical generation, ABC.
- MuPT (ICLR 2025) — multitrack ABC generation.
- Unified arrangement model (NeurIPS 2025, arXiv 2408.15176) — band arrangement,
  piano reduction, drum arrangement; MIDI-proxy domain, needs notation cleanup.
- Structured accompaniment arrangement (NeurIPS 2024, arXiv 2310.16334); piano
  reduction via BERT (arXiv 2512.21324).
- Anticipatory Music Transformer, Moonbeam, Aria, MIDI-RWKV — MIDI-domain
  infilling/continuation.
- Industry: Sibelius shipped AI chord autocomplete only; Dorico none; MuseScore's AI
  is OMR (NoteVision) + playback vocals; Magenta pivoted to realtime audio; Microsoft
  Muzic dormant. **No shipped chat-driven arrangement product exists (mid-2026).**

### OMR
- Audiveris (AGPL, 5.9.0 Dec 2025 / 5.10.x 2026): standard OSS engine, headless
  `-batch -export`, MusicXML 4.0 out, Dockerable; good on clean 300 dpi engraved
  scores, weak on photos.
- homr (AGPL): TrOMR-style transformer, better on camera photos, pitch/rhythm only.
- Academic end-to-end (SMT/SMT++/Zeus): 31–66% symbol error out-of-domain (Sheet
  Music Benchmark, ISMIR 2025) — not production-ready.
- Commercial APIs: effectively none. Soundslice scanner has no API (explicit);
  Newzik/ScanScore/SmartScore no APIs; Klangio's self-serve API is audio-transcription;
  ReadScoreLib (PlayScore) is the sole licensable self-host engine.
- Human-in-the-loop correction is mandatory in every credible product; Soundslice's
  review flow is the UX benchmark; Newzik's lack of one is its top criticism.

### Tooling
- OSMD 2.x (BSD-3): v2.0 June 2026 ~2× render speedup; native MusicXML; cursor +
  note-level interaction. Verovio 6.x (LGPL): best engraving, MEI-native, converts
  MusicXML on import.
- music21 9.x: maintenance mode but mature; the only serious manipulation library.
  **No production-grade JS MusicXML manipulation library exists** — semantics stay
  server-side in Python.
- MNX: still an unstable draft (explicitly "work in progress" 2026) — watch, don't build on.
- MuseScore 4 CLI headless needs `xvfb-run` in Docker (MS4 regression; some pin
  MS 3.6.2 for cleaner headless conversion).
- Firebase + Python: Cloud Run custom container; Firestore job docs + Cloud Tasks is
  the established long-job pattern.

Full citation URLs live in the research reports that produced this doc; key ones:
MSU-Bench https://arxiv.org/abs/2511.20697 · ScoreSpeak
https://digitalcommons.calpoly.edu/theses/3338/ · NotaGen
https://github.com/ElectricAlexis/NotaGen · Unified arrangement
https://arxiv.org/abs/2408.15176 · Audiveris https://github.com/audiveris/audiveris ·
homr https://github.com/liebharc/homr · Sheet Music Benchmark
https://arxiv.org/abs/2506.10488 · OSMD
https://github.com/opensheetmusicdisplay/opensheetmusicdisplay · music21
https://github.com/cuthbertLab/music21 · MNX https://w3c-cg.github.io/mnx/docs/ ·
music21 MCP server https://github.com/brightlikethelight/music21-mcp-server ·
Scoring Notes OMR landscape
https://www.scoringnotes.com/reviews/scanning-the-current-omr-landscape/
