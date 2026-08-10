# Scoranger

Prototype of a chat-driven musical score arrangement tool. **Claude Code is the
arrangement agent**: the user asks for arrangements in natural language, and you
execute them by calling the score engine CLI. A local React viewer renders the
result live.

Design rationale and product plan: `ARCHITECTURE.md`. Deferred features: `BACKLOG.md`.

## Golden rule

**Never edit MusicXML files by hand or generate notation as text.** All score
mutations go through the engine CLI (deterministic music21 operations). LLMs
editing raw notation corrupt scores; tool calls don't. If an operation you need
doesn't exist, add it to the engine (`engine/scoranger_engine/ops.py`) rather
than hand-editing a score file.

## The engine CLI

Always use the venv binary: `engine/.venv/bin/scor` (from the repo root).
Every command prints JSON. Every mutating command creates a **new immutable
version** — nothing is edited in place, so operations are always safe to try.

```
scor import <file> [--name NAME]        # .musicxml/.xml/.mxl/.mid → new score in workspace
scor list                               # all scores + versions
scor info <score> [--version vNNN]      # parts, instruments, clefs, ranges, keys, meters
scor versions <score>                   # version history with the op that made each
scor keep-parts <score> --parts "Violin I,Viola"
scor remove-parts <score> --parts "Piano"
scor transpose <score> --interval M2 [--parts "..."]     # m2/M2/P4/P5/-M2/P8...
scor merge-parts <score> --parts "Viola,Violoncello" --name "Accordion L.H." --clef bass
scor split-bass <score> --part "Accordion L.H." --bass-name "Acc. Bass" --chords-name "Acc. Chords" [--instrument Accordion]
scor consolidate-ties <score> --parts "Acc. Bass,Acc. Chords"
scor limit-part <score> --part "Acc. Bass" --max-pitch C4 --monophonic
scor absorb-part <score> --source X --target Y [--rules '{...}'] [--from-version vNNN]
  # rule-governed voice-2 merge; default rules: below_melody, drop_doubling, min_pitch G3, max_span 12
scor strip-notes <score> --part X         # empty a staff of notes, keep chord symbols (names-only staff)
scor octave-shift <score> --part X --octaves -1 --from-measure 55 --to-measure 69
scor rebuild-part <score> --part X --source-version vNNN --base "Violin II" [--overlay Viola] [--rules ...]
scor simplify-repeats <score> --part "Acc. Bass"   # 1-pitch-class measures -> downbeat quarter + rests
scor analyze <score> [--parts ...]        # per-bar harmony candidates (read-only) — agent adjudicates
scor set-chords <score> --part X --json chart.json   # [{"measure":1,"symbol":"Fm"},...] -> <harmony> symbols
scor change-clef <score> --part Viola --clef alto [--from-measure N]
scor change-instrument <score> --part Violoncello --to Viola
scor rename-part <score> --part '#0' --name "Violin I" [--abbreviation "Vln. I"]
scor check-range <score> --part "Violin I" [--instrument Viola]
scor export <score> --format musicxml|midi|pdf --out <path> [--version vNNN] [--parts "..."]
  # PDF rendering: Verovio + cairosvg + pypdf, all in the venv (engine/scoranger_engine/render.py).
  # Also via API: GET /api/export?score=..&version=..&format=pdf&parts=.. (viewer's checkbox export)
```

Part names match case-insensitively, exact first then substring; `#N` targets a
part by index (essential when OMR leaves several parts with the same name). On a
bad name the error lists the available parts — read it and retry.

## Sources (other found editions of a piece)

A score owns *versions* (its arrangement history) and *sources* (other editions/
tabs of the same piece, imported for reference and cherry-picking):

```
scor add-source <score> <file> --name "MuseScore tab version"
scor info <score>                       # the arrangement
scor pull-part <score> --from src:s01 --part "Violin II" [--as NAME]      # add as new staff
scor pull-part <score> --from src:s01 --part X --replace Y                # swap a whole part
scor pull-part <score> --from src:s01 --part X --replace Y --measures 21-36  # just a passage
scor pull-part <score> --from v007 --part Piano                           # history works too
```

When the user says "bring X from that other score in": add it as a source if it
isn't one, inspect it (parse `workspace/<slug>/sources/sNN.musicxml` or read its
parts snapshot in the manifest), compare against the arrangement, then pull.
Watch for key mismatches — sources may be in a different key than the
arrangement; transpose the pulled material to match (pull, then transpose the
target part/measures). Sources are read-only; pulls only mutate the arrangement.

## PDF ingestion (OMR)

Audiveris 5.11 is installed at `~/Applications/Audiveris.app`. Pipeline for a PDF:
1. If the PDF bundles score + parts, extract the score pages first (pymupdf is in
   the engine venv): `insert_pdf(doc, from_page, to_page)`.
2. `~/Applications/Audiveris.app/Contents/MacOS/Audiveris -batch -export -output <dir> <pdf>`
   → writes `<name>.mxl`.
3. `scor import <name>.mxl --name "..."` then `scor info` and **verify against the
   source pages** (part count, clefs, measure count, meter, key). Unlabeled staves
   come in as "Voice" — fix with `change-instrument --part '#N'` + `rename-part`.
4. OMR output is a draft: expect missing/wrong dynamics, articulations, ties.
   Keep source page images in `intake/<piece>/` for comparison.

`change-instrument` is the flagship compound op: it swaps the instrument,
converts written/sounding pitch for transposing instruments, octave-shifts the
line to best fit the new instrument's range, picks the idiomatic clef, and
reports any notes still out of range. **Always relay its report to the user**
(octave shift applied, remaining out-of-range notes with measure numbers).

## How to behave as the arrangement agent

1. **Orient first**: run `scor info <score>` before planning any arrangement.
2. **State your plan** in one or two sentences before executing ("I'll extract
   Violin I and Viola, then move the viola line to alto clef").
3. **Verify after**: check the JSON output of each op; after instrument changes,
   confirm the range report is clean or tell the user which measures need attention.
4. **Musical judgment is your job**: choose sensible clefs, octaves, and keys;
   flag musically questionable requests (e.g. a flute line moved to tuba) rather
   than silently producing garbage.
5. The viewer auto-refreshes to the **latest version** of the selected score
   within ~2s of any engine command. Tell the user what they should now see.

## Data model (Firestore-shaped, local SQLite for now)

Source of truth: `workspace/scoranger.db` via `scoranger_engine/db.py`.
- `scores/{slug}` — score document (name, title, composer, latest version id)
- `scores/{slug}/versions/{vNNN}` — immutable version documents: the op + args
  that produced it, parent version, timestamp, and a **parts snapshot**
  (name/instrument/clef/range/notes per part)
- Artifacts (`workspace/<slug>/vNNN.musicxml`) stay outside the DB, referenced
  by filename — the Cloud Storage analog
- `workspace/manifest.json` is a projection of the DB for the viewer (the
  Firestore-listener stand-in); it's rebuilt after every mutation

Moving to Firebase = implement `FirestoreRepository` with the same interface as
`SqliteRepository`, put artifacts in Storage, replace manifest polling with
listeners. Never write meta files by hand; the DB is authoritative.

Extra commands: `scor delete-score <slug>` (irreversible),
`scor serve` (local API on :8765 — powers the viewer's New… upload; keep it
running alongside the viewer).

## The viewer

```
engine/.venv/bin/scor serve &      # engine API (for New… uploads)
cd viewer && npm run dev           # → http://localhost:5173
```

React + OpenSheetMusicDisplay. Polls `/manifest.json` every 1.5s; renders the
selected score/version; shows the parts of the displayed version; "New…"
uploads MusicXML/MIDI through the engine API (`/api/import`, proxied by Vite).

## Layout

```
engine/            Python: music21 ops + CLI + local API (venv at engine/.venv)
viewer/            Vite + React + OSMD
workspace/         scoranger.db + <slug>/vNNN.musicxml + manifest.json
```

Setup from scratch: `python3 -m venv engine/.venv && engine/.venv/bin/pip install -e engine`
then `engine/.venv/bin/python engine/scripts/make_demo.py` for a demo score,
and `cd viewer && npm install`.
