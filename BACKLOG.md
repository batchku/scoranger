# Backlog

## In progress: standalone iPad (engine on-device)

Decision 2026-08-15: eliminate the laptop dependency by embedding the engine in
the iOS app. Verified: the engine is pure-Python end to end (numpy/matplotlib
optional) → embed the official Python.xcframework + music21 + scoranger_engine
behind a JSON bridge; Verovio-iOS for native rendering; Swift chat loop with
the OpenRouter key in the Keychain; workspace in app Documents. OMR remains
off-device (JVM). Cross-device library sync becomes a follow-up (iCloud or the
Firebase backend).

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
