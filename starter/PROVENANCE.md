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
| maple_leaf_rag.mxl | https://www.mutopiaproject.org/ftp/JoplinS/maple_leaf_rag/ | Public Domain | 2026-09-08 |
