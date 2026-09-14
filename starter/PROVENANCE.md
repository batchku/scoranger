# The starter library

Five pieces the app ships with, so a new reader has something to open. Every
one of them has to clear **two** independent hurdles, and conflating them is
the mistake this file exists to prevent:

1. **The composition is out of copyright.** In the US a published work enters
   the public domain 95 years after publication, so as of 2026 that means
   published before 1931.
2. **The ENGRAVING is free to redistribute.** A specific encoding of a
   public-domain composition is its own copyrightable work. Somebody's PDF or
   MusicXML of *Für Elise* is theirs, not ours.

Hurdle 2 is what disqualified the obvious source. **music21's corpus cannot be
used here**, and its own `corpus/license.txt` says why in terms:

> Some encodings included in the corpus may not be used for commercial uses or
> have other restrictions … The encodings may be under copyright but have been
> licensed for use, though there may be restrictions on commercial use.

Licensed to *music21*, for possibly non-commercial use, per piece. That is not
a licence this app inherits, and Scoranger ships on the App Store.

So engravings come from the **Mutopia Project**, whose contributors place their
typesetting in the public domain or licence it CC0/CC-BY-SA explicitly, per
file. The licence of each file is recorded below, copied from the file itself
rather than from the project's front page.

## The five

| # | Piece | Composer | Published | Why it is here |
|---|---|---|---|---|
| 1 | Minuet in G, BWV Anh. 114 | J. S. Bach | 1725 | two staves, short, universally known |
| 2 | Für Elise (WoO 59), opening | Beethoven | 1810 | the most recognisable piano page there is |
| 3 | Gymnopédie No. 1 | Erik Satie | 1888 | sparse and slow — good for reading practice |
| 4 | Maple Leaf Rag | Scott Joplin | 1899 | the ragtime root of jazz, unambiguously PD |
| 5 | Greensleeves | traditional | 16th c. | melody only, so the whistle and guitar-tab features have something to work on |

Chosen to exercise different parts of the app, not just to be famous: a
melody-only line, two piano pieces of different density, a rag, and a
two-stave Baroque dance.

**Jazz standards are deliberately absent.** The obvious candidates are all
still in copyright — *Take the A Train* (1939), *Autumn Leaves* (1945),
*Blue Moon* (1934) — so the jazz end of the set is represented by ragtime,
which is genuinely old enough.

## Per-file record

Filled in as each file is added. `check_no_bundled_scores.py` reads this table
and fails on any bundled score that is not in it, so a file cannot be added
without its provenance being written down.

| file | source URL | licence, as stated in the file | verified |
|---|---|---|---|
| bach-minuet-in-g.musicxml | https://www.mutopiaproject.org/ftp/BachJS/BWVAnh114/anna-magdalena-114-115-116/ | `copyright = "Public Domain"` in the .ly | 2026-09-08 |
| bach-prelude-in-c.musicxml | https://www.mutopiaproject.org/ftp/BachJS/BWV846/wtk1-prelude1/ | `<mp:licence>Public Domain</mp:licence>` in the .rdf | 2026-09-08 |
| satie-gymnopedie-1.musicxml | https://www.mutopiaproject.org/ftp/SatieE/gymnopedie_1/ | `license = "Public Domain"`, and the engraved footer reads "Placed in the public domain by the typesetter — free to distribute, modify, and perform" | 2026-09-08 |
| joplin-maple-leaf-rag.musicxml | https://www.mutopiaproject.org/ftp/JoplinS/maple/ | `copyright = "Public Domain"` in the .ly | 2026-09-08 |
| greensleeves.musicxml | https://www.mutopiaproject.org/ftp/Traditional/greensleeves/ | `license = "Public Domain"` in the .ly | 2026-09-08 |

## What is shipped is our own MusicXML, not Mutopia's file

Mutopia publishes LilyPond, PDF and MIDI -- **no MusicXML**, which this app
cannot import from the first two usefully. So each piece was imported from its
MIDI through `scor import` and exported back out as MusicXML by our own engine.
Three consequences, all deliberate:

- The encoding shipped is the engine's output, derived from a Public Domain
  source. Attribution to the Mutopia typesetter is recorded above regardless,
  because it is their work the derivation started from.
- **MIDI-derived notation is thinner than an engraving.** No dynamics, no
  slurs, no articulations, no fingering. Pitches, rhythms, bars, clefs and key
  are right; expression is absent. For a starter library meant to be opened and
  played with, that is an acceptable trade and it is stated here rather than
  discovered.
- Part names came in as MIDI track names -- both staves of the Bach minuet
  arrived called `Viola` -- and were corrected with `rename-part` to
  "Piano (right hand)" / "Piano (left hand)".

**`change-instrument` must not be used on these.** It is a compound op that
also picks an idiomatic clef, and for a left hand ranging G#1-C#5 it picks
TREBLE, which silently destroys the bass staff. That happened on the first
attempt and is why the imports were redone with `rename-part` alone.

## Bar counts, checked against the published works

| piece | bars imported | expected |
|---|---|---|
| Minuet in G BWV Anh. 114 | 32 | 32 |
| Prelude in C BWV 846 | 35 | 35 |
| Gymnopedie No. 1 | 47 | 78 -- SHORT, see below |
| Maple Leaf Rag | 144 | ~90 written, repeats played out |
| Greensleeves | 16 | 16 |

The Satie is the one that does not match, and it is NOT truncated. The Mutopia
source says why in its own comments:

    % The original doesn't use a volta, and thus takes nearly twice as much
    % paper.
    \repeat volta 2 {

47 bars is the piece written WITH A REPEAT; the original writes it out to
about 78. So the notation is complete.

**But MIDI cannot express a repeat sign**, so the file we derive from it has
the 47 bars and no repeat mark -- read or played straight through, it is half
the piece.

Left as 47 bars once through, deliberately, and NOT "fixed" by adding a repeat:
placing a repeat barline requires knowing exactly which bar the volta closes
on, that is not something to infer from LilyPond brace nesting, and a repeat in
the wrong bar corrupts the music in a way a listener notices and a reader
cannot undo. A Gymnopedie played once through is a complete-sounding piece; a
repeat in the wrong place is not. If the repeat is wanted, the span should be
read off the engraved PDF and added with
`set-structure --kind repeat-start/--kind repeat-end`.
