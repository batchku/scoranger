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

**The rhythm is guarded, and the guard is in the write.** Every version, import
and source goes through `workspace._write_musicxml`, which splits notes at the
barline (`makeTies`), writes to one side, reads the file back, and refuses to
keep it if any bar now holds more music than it is long or two notes sound at
once in one voice (`ops.rhythm_problems`). This exists because music21's
MusicXML writer emits a note running past its barline *and* the bars it
swallows, duplicating time -- which turned an eighth note into a dotted eighth
and pushed the rest of a part a sixteenth later, versions after the op that
caused it. So:

- An op may leave an over-long note behind; the write splits it. What an op may
  never do is move music the user did not ask to move.
- An op that cannot rewrite a part without changing its rhythm should leave the
  part alone and say so in its report (`consolidate-ties` does).
- A `RhythmCorruption` error means the op, not the file, is wrong -- fix the op.
- **Material arriving from outside is accepted as it is.** An import, a source,
  an OMR'd PDF: `_write_musicxml` is called with no baseline, so odd bars come
  in and are reported as `rhythm_warnings` on the version. OMR is imperfect by
  nature and the user brings a score in *so they can fix it* -- refusing the
  write here meant refusing to open their own music. Only EDITS carry a
  baseline (the parent version's faults), and an edit is refused only for
  breaking a bar that was sound before it ran.
- Four checks guard this, and every fix in them was reverted in turn to confirm
  the check fails without it:
  `check_rhythm.py` (ops preserve rhythm), `check_import.py` (release gate:
  every source imports to a usable v001), `check_workflows.py` (nine end-to-end
  user journeys), `check_structure.py` and `check_whistle.py` (notation).

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
scor whistle-fingerings <score> --part X [--whistle D] [--clear]
  # penny-whistle fingerings engraved under the part as stacked lyric verses:
  # six holes top to bottom, a 7th verse "+" for the overblown octave. Notes the
  # whistle cannot play are reported, not faked.
  # The notation stores letters (X covered, O open, / half) and both renderers
  # draw them as circles — filled, hollow, half-filled — keyed on the `wf` lyric
  # tag: render.py::_fingering_diagrams and ios/Scoranger/FingeringDiagrams.swift,
  # which must stay in step. Circle GLYPHS are not an option: the rasterizers'
  # fallback font has none and engraves empty boxes.
  # Chart: engine/scripts/check_whistle.py asserts it against the published one.
scor set-structure <score> --kind KIND --measure N [--to-measure M] [--number N]
                   [--times N] [--remove] [--move-to N]
  # repeats, voltas and navigation marks. KIND is repeat-start / repeat-end /
  # repeat-both / volta / segno / coda / fine / da-capo[-al-fine|-al-coda] /
  # dal-segno[-al-fine|-al-coda]. A repeat barline goes on every part, and a
  # volta on every staff of a grand staff -- music21's grand-staff merge drops
  # a volta written to the top staff alone. --move-to is remove-then-add.
  # engine/scripts/check_structure.py engraves each mark and checks the MEI.
scor set-metadata <score> [--title T] [--composer C] [--arranger A]
  # the ONE title: the arrangement's name in the library and the title engraved
  # at the top of the page are the same value. Versioned, like any notation
  # change. `rename-score` is the same op under its older name.
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

**Titles and credits**: a score has exactly one title. It lives in the notation
(MusicXML `<work-title>` *and* `<movement-title>` — Verovio engraves the
movement title, so both are written to the same value) and the score document's
`title`/`composer`/`arranger` are a *projection* of the latest version's
notation, never independent fields. Edit through `set-metadata`; never set a
title by writing the document. Two music21 behaviours the op exists to contain:
it seeds the movement title with the source *file name* when a file carries no
title (which then engraves as "my-score.mxl"), and it stamps itself in as the
composer on every export when none is set (stripped in `workspace._write_version`).

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
