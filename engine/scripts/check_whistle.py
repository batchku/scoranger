"""Regression check for the penny-whistle fingering chart, and what it writes on.

The chart is a table of published fact, so it is checked against the published
fact: the six-hole D whistle's fingerings, the two cross-fingerings every
player knows, the octave boundary that is easy to get wrong (C#5 is the top of
the *first* octave, not the bottom of the second), and the notes the instrument
simply cannot play.

Then WHERE the fingerings land, which is a separate way to be wrong and was:

  - A chord SYMBOL is a Chord in music21, so `recurse().notes` hands the op the
    chart along with the music. A part carrying chord symbols had six holes and
    an octave mark written onto every symbol -- a fingering for a chord, on an
    element that is not on the staff at all. `guitar_tab` was written knowing
    this and this was not, so the same iteration is now asserted for both.
  - A whistle's fingerings are verses 1-7 and a guitar tab's frets are verses
    1-6, so one note cannot carry both. `addLyric` writes the TEXT of the verse
    at a number and leaves its NAME alone, which put fret numbers under a `wf`
    label -- and the renderers key on that label, so "3" engraved as a row of
    circles. Whichever op runs last takes those verses outright and says how
    many notes it took them from; and CLEARING one leaves the other alone,
    which is not the same rule and had to be checked separately.

Run: engine/.venv/bin/python engine/scripts/check_whistle.py
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from music21 import harmony as m21harmony  # noqa: E402
from music21 import meter, note as m21note, stream  # noqa: E402

from scoranger_engine import ops  # noqa: E402


def fingering(pitch: str, whistle: str = "D"):
    """(holes, overblown, playable) for one pitch on one whistle."""
    score = stream.Score()
    part = stream.Part()
    measure = stream.Measure(number=1)
    measure.append(meter.TimeSignature("4/4"))
    measure.append(m21note.Note(pitch, quarterLength=1))
    part.append(measure)
    score.append(part)
    report = ops.whistle_fingerings(score, part, whistle)
    note = next(iter(part.recurse().notes))
    holes = "".join(l.text for l in sorted(note.lyrics, key=lambda l: l.number)
                    if l.number <= 6)
    overblown = any(l.number == 7 for l in note.lyrics)
    return holes, overblown, report["unplayable_count"] == 0


FAILURES = []


def expect(pitch, holes, overblown=False, whistle="D"):
    got_holes, got_over, playable = fingering(pitch, whistle)
    if not playable or got_holes != holes or got_over != overblown:
        FAILURES.append(
            f"{whistle} whistle, {pitch}: expected {holes}"
            f"{' +' if overblown else ''}, got {got_holes or '(none)'}"
            f"{' +' if got_over else ''}")


def expect_unplayable(pitch, whistle="D"):
    holes, _, playable = fingering(pitch, whistle)
    if playable:
        FAILURES.append(f"{whistle} whistle, {pitch}: expected unplayable, got {holes}")


# the D-major scale, first octave: one hole lifts at a time
expect("D4",  "XXXXXX")
expect("E4",  "XXXXXO")
expect("F#4", "XXXXOO")
expect("G4",  "XXXOOO")
expect("A4",  "XXOOOO")
expect("B4",  "XOOOOO")
expect("C#5", "OOOOOO")            # top of the FIRST octave: not overblown

# the same fingerings an octave up, overblown
expect("D5",  "XXXXXX", overblown=True)
expect("G5",  "XXXOOO", overblown=True)
expect("C#6", "OOOOOO", overblown=True)

# the cross-fingerings every whistle player knows
expect("C5",  "OXXOOO")            # C natural: "oxx ooo"
expect("F5",  "XXXOXX", overblown=True)   # F natural: "xxx oxx"
expect("F4",  "XXXOXX")
expect("B-4", "XOXXXO")

# half-holed accidentals
expect("E-4", "XXXXX/")
expect("G#4", "XXX/OO")

# outside the instrument
expect_unplayable("C4")            # below the low D
expect_unplayable("D6")            # above the second octave
expect_unplayable("A3")

# A C whistle is the same chart transposed down a tone, so its home scale is
# C major: all covered is C, and the flattened seventh (B flat) takes the same
# cross-fingering that C natural takes on a D whistle.
expect("C4",  "XXXXXX", whistle="C")
expect("D4",  "XXXXXO", whistle="C")
expect("B4",  "OOOOOO", whistle="C")
expect("B-4", "OXXOOO", whistle="C")
expect("C5",  "XXXXXX", overblown=True, whistle="C")



# --- where the fingerings land ----------------------------------------------

def charted_part(pitches=("D4", "E4", "D5"), symbols=("D", "G")):
    """A whistle part that also carries a chord chart, which is ordinary: a
    tune is written with its changes over it."""
    score = stream.Score()
    part = stream.Part()
    part.partName = "Whistle"
    measure = stream.Measure(number=1)
    measure.append(meter.TimeSignature("4/4"))
    for name in symbols:
        measure.insert(0.0, m21harmony.ChordSymbol(name))
    for name in pitches:
        measure.append(m21note.Note(name, quarterLength=1))
    part.append(measure)
    score.append(part)
    return score, part


def note(msg, ok):
    if not ok:
        FAILURES.append(msg)


score, part = charted_part()
report = ops.whistle_fingerings(score, part, "D")
symbols = [n for n in part.recurse().notes if isinstance(n, m21harmony.Harmony)]
tunes = [n for n in part.recurse().notes if not isinstance(n, m21harmony.Harmony)]
note(f"a chord symbol is not a note to be fingered: {[len(s.lyrics) for s in symbols]}",
     len(symbols) == 2 and all(not s.lyrics for s in symbols))
note(f"and the notes still are: {report}",
     report["notes_fingered"] == 3 and all(n.lyrics for n in tunes))

# tab over fingerings: the tab takes the verses, correctly named, and says so
tab = ops.guitar_tab(score, part, "EADGBE")
labels = {str(ly.identifier or "") for n in tunes for ly in n.lyrics}
note(f"tab written over fingerings takes the verses cleanly: {labels}",
     labels == {ops.TAB_LYRIC_TAG})
note(f"...and says how many notes it took them from: {tab}",
     tab["whistle_fingerings_replaced"] == 3)

# and back the other way, including the overblown seventh verse
again = ops.whistle_fingerings(score, part, "D")
labels = {str(ly.identifier or "") for n in tunes for ly in n.lyrics}
note(f"fingerings written over tab take the verses cleanly: {labels}",
     labels == {ops.WHISTLE_LYRIC_TAG})
note(f"...and say how many notes they took them from: {again}",
     again["guitar_tab_replaced"] == 3)
note("the overblown mark is back on the note that needs it",
     any(ly.number == 7 for ly in tunes[2].lyrics))

# clearing one leaves the other alone -- a different rule from writing over it
ops.guitar_tab(score, part, "EADGBE")
cleared = ops.whistle_fingerings(score, part, "D", clear=True)
note(f"clearing fingerings that are not there takes nothing: {cleared}",
     cleared["cleared"] == 0 and all(n.lyrics for n in tunes))
ops.whistle_fingerings(score, part, "D")
tab_cleared = ops.guitar_tab(score, part, "EADGBE", clear=True)
note(f"and clearing a tab that is not there takes nothing either: {tab_cleared}",
     tab_cleared["cleared"] == 0 and all(n.lyrics for n in tunes))
mine = ops.whistle_fingerings(score, part, "D", clear=True)
note(f"clearing its own fingerings takes them: {mine}",
     mine["cleared"] == 3 and not any(n.lyrics for n in tunes))

if FAILURES:
    print(f"FAIL: {len(FAILURES)} fingering(s) wrong")
    for line in FAILURES:
        print("   ", line)
    sys.exit(1)
print("OK: whistle fingerings match the published chart, and land on the notes")
