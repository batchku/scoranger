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

**Rhythm is preserved by making the transformations correct, not by refusing
to save.** `workspace._write_musicxml` splits notes at the barline (`makeTies`)
before writing, because music21's MusicXML writer emits a note running past its
barline *and* the bars it swallows, duplicating time. It then reads the file
back and RETURNS whatever odd bars it finds as `rhythm_warnings`, recorded on
the version. It never refuses.

A refusal lived here once and was removed: it blocked importing a scanned score
whose bars were imperfect, then blocked adding a repeat to a score that had
inherited such a bar -- a bar the repeat never touched. Detect-and-refuse is a
band-aid over transformations that should not damage anything.

So:

- **Correctness belongs in the op.** An op that cannot rewrite a part without
  changing its rhythm should leave the part alone and say so in its report
  (`consolidate-ties` and `flatten-voices` rehearse `stripTies` on a copy and
  decline if the result would not hold its meter).
- **Material arriving from outside is accepted as it is.** OMR is imperfect by
  nature and the user brings a score in *so they can fix it*.
- **Proof belongs in the checks, which run before a release, not in front of a
  user.** Ten of them, and every fix in them was reverted in turn to confirm
  the check fails without it: `check_rhythm.py` (ops preserve rhythm; structural
  marks move no note), `check_import.py` (release gate: every source imports to
  a usable v001), `check_workflows.py` (ten end-to-end user journeys),
  `check_structure.py` and `check_whistle.py` (notation),
  `check_addresses.py` (a selection-scoped op touches only what was selected),
  `check_chord_diagrams.py` and `check_guitar_tab.py` (the guitar work: the
  shapes against a published chart, the tab against the open strings, and both
  renderers against one golden fragment),
  `check_playback.py` (the MIDI and the bar map describe the same performance),
  and `check_bar_frames.py` (the rectangle the geometry reports for measure N
  IS the Nth bar -- Verovio nests a slur inside the measure it starts in, and a
  group's frame is the union of what it contains, so an unclipped bar can be
  four bars wide and a playhead lands two bars late).

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
scor transpose-elements <score> --interval M2 --elements "s1/m15/l1/note#0,s1/m15/l1/note#1"
  # transpose ONLY those elements. An address is staff/measure/layer/kind#ordinal,
  # as the iPad's lasso produces it from Verovio's MEI. Use this, never a measure
  # range, when the user means a selection: a range moves every note in the bar.
  # The MEI->music21 join is proven in engine/scripts/check_addresses.py, which
  # engraves fixtures with the real Verovio and asserts each address resolves to
  # the pitch the MEI names (226/226). The subtle part: MEI counts a chord's
  # notes individually, music21 holds a chord as ONE object -- resolving by
  # stream position lands on the wrong pitch from the first chord onwards.
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
scor clean-accidentals <score> [--parts "..."]
  # hide accidentals the key signature already implies. Display only -- no
  # pitch, no spelling, no key changes. Each part is judged by the key ON ITS
  # OWN STAFF, so an E-flat alto is judged by its WRITTEN key, not concert.
  # Every op that changes pitches runs this already (see below); this is for
  # material that arrived cluttered.
scor set-accidental <score> --elements "s1/m15/l1/note#0" [--add sharp|flat|natural]
                   [--remove] [--show] [--hide] [--color "#CC4125"|none]
  # the manual override. --add/--remove change the PITCH; --show/--hide/--color
  # change only what is drawn. Colour reaches the page: MusicXML
  # <accidental color=..> -> MEI @color -> the SVG glyph.
scor change-clef <score> --part Viola --clef alto [--from-measure N]
scor change-instrument <score> --part Violoncello --to Viola
scor rename-part <score> --part '#0' --name "Violin I" [--abbreviation "Vln. I"]
scor adjust-element <score> --part X [--kind harm|diagram|tab]
                    [--measure N] [--ordinal N] [--all] [--size PT]
                    [--offset-x TENTHS] [--offset-y TENTHS] [--reset]
  # how big an added element is and where it sits, stored in the notation
  # (MusicXML font-size / relative-x / relative-y) so it travels with the
  # score. `harm` is a chord symbol, `diagram` a chord diagram, `tab` a tab
  # column -- addressed by the same measure + ordinal, because the reader is
  # pointing at one thing on the page. Verovio honours none of the three, so
  # each renderer carries them across itself.
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
scor guitar-tab <score> --part X [--tuning EADGBE] [--capo N] [--clear]
  # guitar tablature under a part: a fret number per note on a six-line tab
  # staff, at the LOWEST position that plays it -- the one a player reaches for
  # first. A chord is laid out whole (one string per note, inside four frets),
  # so it can force the hand higher than any of its notes would alone, and the
  # report says which bar that happened in. Notes the tuning cannot play are
  # reported, never transposed into range and never dropped.
  # Engraved the way the whistle's fingerings are: six lyric verses per note,
  # tagged `gt`, verse 1 the HIGHEST string, because a tab staff's top line is
  # the string nearest the floor. A fret number where a string is played, a
  # DASH where it is not -- and the dash is the meaning while the LINE is the
  # drawing: render.py::_tab_staff and ios/Scoranger/ScoreModel/TabStaff.swift
  # run the six lines through the dashes and leave the numbers standing in gaps
  # cut in them. Left as text a column of dashes is six loose hyphens per note.
  # Tunings: EADGBE, DADGAD, DADGBE (drop D). A capo shortens every string by
  # its own number of frets; nothing under it can be played at all.
  # Size and position are adjust-element's business, with --kind tab.
scor chord-diagrams <score> --part X [--tuning EADGBE] [--clear]
                    [--shape "A7=x02020"]
  # a guitar chord diagram over every chord symbol the part ALREADY carries --
  # `set-chords` writes them and `chart_style` places them, and a second notion
  # of where a chord sits would fall out of step with the first one the moment
  # either moved.
  # What goes in the notation is the shape, in the shorthand a player writes:
  # [x,3,2,0,1,0], one entry per string from the low E up, `x` for a string not
  # sounded. The window of the neck, the thick NUT line, the barre and the
  # "5 fr." label all follow from those six numbers, by rules both renderers
  # apply and neither invents.
  # And after them, when there is one to say, the FINGERING:
  # [3,2,0,0,0,3](3,2,0,0,0,4) is a G. The row above the grid is the HAND, not
  # the frets -- ring and middle low and the PINKY on the top E -- and no
  # arithmetic over six fret numbers produces that, which is why it is a table
  # (ops.OPEN_FINGERINGS) and rides in the notation. A movable shape derives
  # from the open one it is a barre of, by the rule a method book teaches: the
  # index bars the fret the nut used to be and every other finger steps up one,
  # so E 023100 becomes F 134211. Where neither knows the hand, the row shows
  # the frets, as it always did -- an invented fingering would be a lie.
  # It rides as a <direction><words> at the symbol's own offset, and that is a
  # deliberate second choice: MusicXML's <frame> is where a diagram belongs and
  # music21 WRITES one, but it drops the frame notes on the way back in, so a
  # diagram would survive exactly one op -- every version is written and read
  # back. The shorthand survives, and exports as a line a player can read.
  # GLYPHS ARE NOT AN OPTION for the grid, the dots or the barre, the same
  # lesson the whistle's circles taught: render.py::_chord_diagrams and
  # ios/Scoranger/ScoreModel/ChordDiagrams.swift draw them as paths, and must
  # stay in step -- check_chord_diagrams.py holds both to one golden fragment.
  # A curated chart of CONVENTIONAL shapes first, a search up the neck second:
  # the search finds a voicing for anything, but it does not know that x32010
  # is *the* C. The two rules disagree, and the chart wins: A7 and Dm7 can both
  # be played open and are both written as fifth-fret barres, so that is what
  # the op draws. --shape "A7=x02020" pins any chord to a shape of your own,
  # ahead of both. Chords with no playable shape are reported, not faked.
  # Transposing the music CLEARS the diagrams (six frets are one chord, and a C
  # grid over a D is worse than nothing); run the op again after.
  # Size and position are adjust-element's business, with --kind diagram.
scor set-structure <score> --kind KIND --measure N [--to-measure M] [--number N]
                   [--times N] [--remove] [--move-to N]
  # repeats, voltas and navigation marks. KIND is repeat-start / repeat-end /
  # repeat-both / volta / segno / coda / fine / da-capo[-al-fine|-al-coda] /
  # dal-segno[-al-fine|-al-coda]. A repeat barline goes on every part, and a
  # volta on every staff of a grand staff -- music21's grand-staff merge drops
  # a volta written to the top staff alone. --move-to is remove-then-add.
  # engine/scripts/check_structure.py engraves each mark and checks the MEI.
scor set-rehearsal <score> [--measure N] [--mark A] [--remove] [--move-to M] [--reletter]
  # rehearsal marks, written to EVERY part -- the workflow is parts-first and a
  # mark on the top staff alone is missing from every part but the first. The
  # cost: Verovio anchors one direction per part to the SAME staff of a
  # combined score, so the render dedupes them (render.mei_with_deduped_rehearsals
  # and ios/Scoranger/ScoreModel/RehearsalMarks.swift, which must stay in step).
  # No --mark takes the next free letter; --reletter re-labels in bar order,
  # A-Z then AA, BB, CC. Size and position are adjust-element's business.
scor set-metadata <score> [--title T] [--composer C] [--arranger A]
  # the ONE title: the arrangement's name in the library and the title engraved
  # at the top of the page are the same value. Versioned, like any notation
  # change. `rename-score` is the same op under its older name.
scor check-range <score> --part "Violin I" [--instrument Viola]
scor export <score> --format musicxml|midi|pdf --out <path> [--version vNNN] [--parts "..."]
  # PDF rendering: Verovio + cairosvg + pypdf, all in the venv (engine/scoranger_engine/render.py).
  # Also via API: GET /api/export?score=..&version=..&format=pdf&parts=.. (viewer's checkbox export)
scor playback <score> --out <path.mid> [--version vNNN]
  # the score AS PERFORMED, plus the map from its beats back to the page. NOT
  # a version: playback is a reading of the arrangement, like `info`.
  # The performed score differs from the engraved one three ways, and both the
  # MIDI and the map come from ONE object so they cannot drift apart:
  #   - repeats and voltas are PLAYED OUT, so the beat->bar map is one-to-MANY
  #     (bar 1 sounds at beat 0 and again at beat 8) -- which is why the map is
  #     a list of spans and never a dict keyed by bar;
  #   - written pitch becomes SOUNDING pitch, or a B-flat clarinet plays a tone
  #     sharp against every other part;
  #   - the click grid is emitted, not the rule for it: 6/8 gets two clicks a
  #     bar, and a pickup's click is not a downbeat.
  # Beats are quarter notes, the unit iOS's AVAudioSequencer reports its play
  # head in. Proof: engine/scripts/check_playback.py.
```

### Accidentals are normalised by the ops, not patched afterwards

Any op that changes pitches or spelling recomputes which accidentals PRINT,
against each part's own written key (`ops.normalize_accidentals`, wired into
transpose, transpose-elements, respell, change-instrument, octave-shift,
merge/split/absorb/pull/rebuild/limit/flatten/simplify). The report carries
`redundant_accidentals_hidden`.

This exists because a user was handed an alto sax part full of sharps that were
already in its key signature. Two music21 behaviours combine to cause it: a
respelled pitch gets a NEW `Accidental` whose `displayStatus` is None, and None
prints; and music21 runs `makeAccidentals` at most once per stream
(`streamStatus`), so a score that has been written and read back -- which is
every version in the workspace -- is never normalised again. `overrideStatus=True`
is what makes it recompute. A fixture built in memory cannot show the bug, so
`check_accidentals.py` round-trips every fixture through a real write first.

### Adding to the toolset

**A tool that CREATES an element ships with the tools that MANIPULATE it** --
adjust, move, resize, remove -- and with the agent's description of them. A
create-only op leaves the user asking for something the agent then cannot undo
or nudge, which is worse than not having offered it. `set-structure` is the
shape to copy: one op that adds a mark also takes `--remove` and `--move-to`.

The same rule governs replacing an affordance: **keep the current access path
until its replacement exists.** Do not remove the old way of reaching a feature
in the build that introduces the new one; never drop the feature.

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
