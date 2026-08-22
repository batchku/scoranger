"""Regression check for the penny-whistle fingering chart.

The chart is a table of published fact, so it is checked against the published
fact: the six-hole D whistle's fingerings, the two cross-fingerings every
player knows, the octave boundary that is easy to get wrong (C#5 is the top of
the *first* octave, not the bottom of the second), and the notes the instrument
simply cannot play.

Run: engine/.venv/bin/python engine/scripts/check_whistle.py
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

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

if FAILURES:
    print(f"FAIL: {len(FAILURES)} fingering(s) wrong")
    for line in FAILURES:
        print("   ", line)
    sys.exit(1)
print("OK: whistle fingerings match the published chart")
