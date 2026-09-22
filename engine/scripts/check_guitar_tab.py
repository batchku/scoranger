"""Regression check for guitar tablature.

The fret arithmetic is published fact -- a string's pitch plus a fret is a
note, and every guitarist knows where the open strings are -- so it is checked
against the published fact, the way check_whistle.py checks the whistle's
fingerings. Beyond the arithmetic, four things that are easy to get plausibly
wrong:

  - THE HAND. Not the lowest fret that plays each note, which is the one on
    the thinnest string and writes a melody as a single line climbing the top
    string to the twelfth fret. A hand covers four frets, stretches one more,
    crosses strings freely and SHIFTS only where the line leaves its reach, so
    the choice is made for the whole line at once. The cases here are tabs a
    guitarist reads without thinking -- a C scale in fifth position, Twinkle in
    first with the pinky stretch, open strings at the nut and none reached back
    for from the eighth fret -- and the lowest-fret rule got every one of them
    wrong. Every shift is in the report with the bar it lands in.
  - THE CHORD THAT CLIMBED. A chord is laid out as a whole -- one string per
    note, inside four frets -- so it can force the hand higher than any of its
    notes would alone, and the report has to SAY SO rather than leave a reader
    wondering why bar 12 climbed the neck.
  - THE CAPO. It shortens every string by its own number of frets, so a note
    keeps its pitch and loses that many fret numbers, and nothing below the
    capo can be played at all.
  - WHAT CANNOT BE PLAYED. Reported with its bar and its pitch, never
    transposed into range and never dropped.
  - THE TWO RENDERERS. render.py draws the PDF and TabStaff.swift draws the
    page on the iPad, and both are held to one golden fragment in
    ios/ScorangerTests/Fixtures/guitar-tab-golden.txt.

Run: engine/.venv/bin/python engine/scripts/check_guitar_tab.py
     ... --write   to re-cut the golden fragment after a deliberate change
"""

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "engine"))

from music21 import chord as m21chord  # noqa: E402
from music21 import harmony as m21harmony  # noqa: E402
from music21 import meter as m21meter  # noqa: E402
from music21 import note as m21note  # noqa: E402
from music21 import stream as m21stream  # noqa: E402

from scoranger_engine import ops, render  # noqa: E402

GOLDEN = ROOT / "ios" / "ScorangerTests" / "Fixtures" / "guitar-tab-golden.txt"
SWIFT = ROOT / "ios" / "Scoranger" / "ScoreModel" / "TabStaff.swift"

FAILURES: list[str] = []


def check(label: str, ok: bool, detail: str = "") -> None:
    if not ok:
        FAILURES.append(f"{label}{': ' + detail if detail else ''}")


def tabbed(pitches, tuning: str = "EADGBE", capo: int = 0, chords: list | None = None,
           position: int | None = None):
    """(report, [column]) for a bar of notes. A column is six strings, high
    first, as the verses under that note read."""
    score = m21stream.Score()
    part = m21stream.Part()
    part.partName = "Guitar"
    measure = m21stream.Measure(number=1)
    measure.append(m21meter.TimeSignature("4/4"))
    for name in chords or []:
        measure.insert(0.0, m21harmony.ChordSymbol(name))
    for entry in pitches:
        measure.append(m21chord.Chord(entry, quarterLength=1) if isinstance(entry, list)
                       else m21note.Note(entry, quarterLength=1))
    part.append(measure)
    score.append(part)
    report = ops.guitar_tab(score, part, tuning, capo=capo, position=position)
    columns = []
    for n in part.recurse().notes:
        if isinstance(n, m21harmony.Harmony):
            continue
        verses = sorted([ly for ly in n.lyrics
                         if ops.parse_tab_label(str(ly.identifier or "")) is not None],
                        key=lambda ly: ly.number)
        if verses:
            columns.append([ly.text for ly in verses])
    return report, columns


def column(*rows: str) -> list:
    """Six strings, HIGH first, the way the verses stack."""
    return list(rows)


# --- the arithmetic, against the open strings every player knows -------------
_, cols = tabbed(["E4", "F4", "G4", "B3", "G3", "D3", "A2", "E2"])
for expected, got, name in zip([
    column("0", "-", "-", "-", "-", "-"),   # E4 is the open first string
    column("1", "-", "-", "-", "-", "-"),
    column("3", "-", "-", "-", "-", "-"),
    column("-", "0", "-", "-", "-", "-"),   # B3 is the open second
    column("-", "-", "0", "-", "-", "-"),   # G3 the open third
    column("-", "-", "-", "0", "-", "-"),   # D3 the open fourth
    column("-", "-", "-", "-", "0", "-"),   # A2 the open fifth
    column("-", "-", "-", "-", "-", "0"),   # E2 the open sixth
], cols, ["E4", "F4", "G4", "B3", "G3", "D3", "A2", "E2"]):
    check(f"{name} is where the tuning puts it", expected == got, str(got))

# one note on its own goes where an unconstrained hand goes: as low on the neck
# as it can. C5 is the eighth fret of the first string, not the thirteenth of
# the second
_, cols = tabbed(["C5"])
check("a note on its own sits low", cols[0] == column("8", "-", "-", "-", "-", "-"),
      str(cols[0]))

# --- the hand stays where it is ---------------------------------------------
#
# The one thing a fret number per note does not say. Every note has three or
# four frets that play it, and taking the lowest of them every time -- the one
# on the THINNEST string -- writes a melody as a single line climbing the top
# string to the eighth and twelfth frets, on a neck where a player would have
# spread it over two strings and never moved. Each case below is a tab a
# guitarist reads without thinking, and the old rule got every one of them
# wrong.


def frets(cols):
    """The tab as a player reads it: (string, fret) per note, string 1 on top."""
    out = []
    for c in cols:
        out.append(next(((i + 1, int(t)) for i, t in enumerate(c) if t != "-"), None))
    return out


# A C major scale is played in fifth position, three strings, no shift -- and
# it was played on one string from fret 0 to fret 8.
report, cols = tabbed(["C4", "D4", "E4", "F4", "G4", "A4", "B4", "C5"])
check("a C scale is the fifth-position fingering",
      frets(cols) == [(3, 5), (3, 7), (2, 5), (2, 6), (2, 8), (1, 5), (1, 7), (1, 8)],
      str(frets(cols)))
check("...with the hand never moving", report["shift_count"] == 0, str(report["shifts"]))
check("...and the report says where it sat", report["position"] == 5, str(report))

# Twinkle in C is first position, and it is the case a hand held to exactly
# four frets cannot play there at all: the A is the fifth fret, reached by
# stretching the little finger rather than by moving the whole hand.
report, cols = tabbed(["C4", "C4", "G4", "G4", "A4", "A4", "G4",
                       "F4", "F4", "E4", "E4", "D4", "D4", "C4"])
check("Twinkle is first position, with the stretch to the A",
      frets(cols) == [(2, 1), (2, 1), (1, 3), (1, 3), (1, 5), (1, 5), (1, 3),
                      (1, 1), (1, 1), (1, 0), (1, 0), (2, 3), (2, 3), (2, 1)],
      str(frets(cols)))
check("...and no shift is claimed for a stretch", report["shift_count"] == 0,
      str(report["shifts"]))

# A line that genuinely leaves the hand shifts, and the report says which bar
# it lands in -- the one thing a player has to see coming.
report, _ = tabbed(["E4", "F4", "G4", "A5"])
check("a line that leaves the hand shifts", report["shift_count"] >= 1, str(report))
check("...and the report gives the bar and both positions",
      bool(report["shifts"]) and report["shifts"][0]["bar"] == "1"
      and report["shifts"][0]["from"] != report["shifts"][0]["to"],
      str(report["shifts"]))

# An open string is what a player takes at the nut and a reach back to it from
# the eighth fret, so it is preferred in one place and not in the other.
_, cols = tabbed(["E4", "F4", "G4", "B3", "G3", "D3", "A2", "E2"])
check("at the nut the open strings win",
      frets(cols) == [(1, 0), (1, 1), (1, 3), (2, 0), (3, 0), (4, 0), (5, 0), (6, 0)],
      str(frets(cols)))
high_report, high = tabbed(["E4", "G4", "C5", "G4", "A4", "C5", "E5", "C5"])
check("up the neck a lone open string is not reached back for",
      all(fret > 0 for _, fret in frets(high)), str(frets(high)))
# The bar the owner's own reference page opens with, and the one the lowest
# fret rule wrote as 0-3-8-3-5-8-12-8, every note on the top string, jumping
# nine frets between two of them. It is two strings and one shift.
check("the reference line is spread over the strings, not stacked on one",
      len({string for string, _ in frets(high)}) > 1, str(frets(high)))
check("...and the hand moves at most once",
      high_report["shift_count"] <= 1, str(high_report["shifts"]))
check("...by a fret or two, not by nine",
      all(abs(s["to"] - s["from"]) <= ops.TAB_HAND_SPAN
          for s in high_report["shifts"]), str(high_report["shifts"]))

# The arranger's own say over where it is read.
pinned, pinned_cols = tabbed(["C4", "D4", "E4", "F4"], position=7)
check("--position pins the hand", pinned["position"] == 7, str(pinned))
check("...and the frets follow it",
      all(fret >= 6 for _, fret in frets(pinned_cols)), str(frets(pinned_cols)))
try:
    tabbed(["C4"], position=40)
    check("a position off the neck is refused", False)
except ValueError:
    check("a position off the neck is refused", True)

# --- a chord is laid out whole, and says when it climbed ---------------------
report, cols = tabbed([["E3", "B3", "E4"]])
check("a chord takes one string per note",
      cols[0] == column("0", "0", "-", "2", "-", "-"), str(cols[0]))
report, cols = tabbed([["E4", "G4"]])
stopped = [int(f) for f in cols[0] if f != "-"]
check("a chord fits inside four frets",
      stopped and max(stopped) - min(stopped) < ops.TAB_CHORD_SPAN, str(cols[0]))
check("a chord that climbed says so",
      report["positions_raised_count"] >= 1
      and report["positions_raised"][0]["to_fret"]
      > report["positions_raised"][0]["lowest_alone"],
      str(report["positions_raised"]))
# ...and one that did not, does not
report, _ = tabbed(["E4", "G4"])
check("a line that stayed put claims nothing",
      report["positions_raised_count"] == 0, str(report["positions_raised"]))

# --- the capo ---------------------------------------------------------------
#
# A capo at the second fret shortens every string by two: the same note keeps
# its pitch and loses two fret numbers.
plain, plain_cols = tabbed(["F#4"])
capoed, capo_cols = tabbed(["F#4"], capo=2)
check("a capo takes its own number of frets off",
      plain_cols[0][0] == "2" and capo_cols[0][0] == "0",
      f"{plain_cols[0][0]} without, {capo_cols[0][0]} with")
check("the capo is in the report", capoed["capo"] == 2)
# The lowest note a capo at the second fret leaves is F#2: everything under it
# is gone, and the reason says which.
below, _ = tabbed(["F2"], capo=2)
check("nothing below the capo can be played",
      below["unplayable_count"] == 1
      and "below the capo at fret 2" in below["unplayable"][0]["why"],
      str(below["unplayable"]))
open_string, _ = tabbed(["E2"], capo=0)
check("...and without one the same note is the open sixth",
      open_string["unplayable_count"] == 0)

# --- what cannot be played is reported, not faked ---------------------------
report, cols = tabbed(["C2", "A6", "E4"])
check("two notes outside the neck are reported", report["unplayable_count"] == 2,
      str(report["unplayable"]))
check("...with the bar and the pitch",
      report["unplayable"][0]["bar"] == "1"
      and report["unplayable"][0]["pitch"] == "C2", str(report["unplayable"][0]))
check("...and nothing is written for them", len(cols) == 1,
      f"{len(cols)} notes tabbed")
check("the one that can be played still is",
      cols[0] == column("0", "-", "-", "-", "-", "-"), str(cols))

# --- the tuning is real -----------------------------------------------------
#
# DADGAD is not standard tuning with different letters. Its sixth string is a
# D, so a low D is an OPEN string where standard has to reach the tenth fret.
standard, standard_cols = tabbed(["D2"])
dadgad, dadgad_cols = tabbed(["D2"], tuning="DADGAD")
check("standard tuning cannot reach a low D", standard["unplayable_count"] == 1)
check("DADGAD plays it open",
      dadgad["unplayable_count"] == 0
      and dadgad_cols[0] == column("-", "-", "-", "-", "-", "0"), str(dadgad_cols))
_, drop_cols = tabbed(["D2"], tuning="DADGBE")
check("and so does drop D", drop_cols[0] == column("-", "-", "-", "-", "-", "0"))

# --- the chart on the same staff as the tab ---------------------------------
#
# A chord SYMBOL is a Chord in music21, so `recurse().notes` hands the op the
# chart as well as the music. Tab hung on a chord symbol is six verses on an
# element that is not on the staff at all.
report, cols = tabbed(["E4", "G4"], chords=["C"])
check("a chord symbol is not a note to be tabbed",
      report["notes_tabbed"] == 2 and len(cols) == 2, str(report))

# --- both features on one part ----------------------------------------------
#
# The case an arranger actually uses, and the one most likely to look broken:
# grids above the staff, tab below it, neither standing where the other is.
score = m21stream.Score()
part = m21stream.Part()
part.partName = "Guitar"
measure = m21stream.Measure(number=1)
measure.append(m21meter.TimeSignature("4/4"))
measure.insert(0.0, m21harmony.ChordSymbol("C"))
for name in ["E4", "G4", "A4", "B4"]:
    measure.append(m21note.Note(name, quarterLength=1))
part.append(measure)
score.append(part)
tab_report = ops.guitar_tab(score, part, "EADGBE")
diagram_report = ops.chord_diagrams(score, part, "EADGBE")
check("tab and diagrams coexist on one part",
      tab_report["notes_tabbed"] == 4 and diagram_report["diagrams"] == 1,
      f"{tab_report['notes_tabbed']} tabbed, {diagram_report['diagrams']} drawn")
# and one does not eat the other: clearing the tab leaves the diagrams alone
cleared = ops.guitar_tab(score, part, "EADGBE", clear=True)
check("clearing the tab leaves the diagrams", cleared["cleared"] == 4
      and len(ops.chord_diagrams(score, part, "EADGBE", clear=True)) > 0)

# --- the reader's own nudge -------------------------------------------------
score = m21stream.Score()
part = m21stream.Part()
part.partName = "Guitar"
measure = m21stream.Measure(number=1)
measure.append(m21meter.TimeSignature("4/4"))
measure.append(m21note.Note("E4", quarterLength=4))
part.append(measure)
score.append(part)
ops.guitar_tab(score, part, "EADGBE")
nudged = ops.adjust_element(score, "Guitar", kind="tab", measure=1,
                            size=18.0, offset_x=15.0, offset_y=-20.0)
check("a tab column is addressable by adjust-element", nudged["adjusted"] == 1, str(nudged))
labels = {str(ly.identifier) for n in part.recurse().notes for ly in n.lyrics}
check("the nudge rides in the name, where Verovio carries it",
      labels == {"gt@1.5,15,-20"}, str(labels))
check("...and in the notation's own fields too",
      all(ly.style.relativeX == 15.0 and ly.style.relativeY == -20.0
          for n in part.recurse().notes for ly in n.lyrics))
check("the label round-trips", ops.parse_tab_label("gt@1.5,15,-20") == (1.5, 15.0, -20.0))
check("a plain tag carries no adjustment", ops.parse_tab_label("gt") == (None, None, None))
check("a whistle verse is not a tab verse", ops.parse_tab_label("wf") is None)
back = ops.adjust_element(score, "Guitar", kind="tab", measure=1, reset=True)
check("...and reset puts it back",
      {str(ly.identifier) for n in part.recurse().notes for ly in n.lyrics} == {"gt"},
      str(back))

# --- the two renderers draw the same picture --------------------------------
CASES = [
    # a plain column, mid-system
    (["0", "-", "-", "-", "-", "-"], 638.0, 2547.0, 390.0, 1200.0, 1800.0, 1.0),
    # a two-digit fret, which needs a wider gap in its line
    (["-", "10", "-", "-", "-", "-"], 2421.0, 2547.0, 390.0, 2000.0, 2800.0, 1.0),
    # a chord: three strings stopped at once
    (["0", "0", "-", "2", "-", "-"], 4204.0, 2547.0, 390.0, 3800.0, 4600.0, 1.0),
    # and one the reader made bigger
    (["3", "-", "-", "-", "-", "-"], 638.0, 2547.0, 390.0, 300.0, 1000.0, 1.5),
]
lines = []
for texts, x, top, pitch, left, right, scale in CASES:
    drawn = render.tab_column_svg(texts, x, top, pitch, left, right, scale)
    lines.append(f"{','.join(texts)}|{x:g}|{top:g}|{pitch:g}|{left:g}|{right:g}|{scale:g}"
                 f"\t{drawn}")
golden = "\n".join(lines) + "\n"

if "--write" in sys.argv:
    GOLDEN.parent.mkdir(parents=True, exist_ok=True)
    GOLDEN.write_text(golden, encoding="utf-8")
    print(f"wrote {GOLDEN.relative_to(ROOT)}")
else:
    have = GOLDEN.read_text(encoding="utf-8") if GOLDEN.exists() else ""
    check("the golden fragment is what render.py draws", have == golden,
          "run check_guitar_tab.py --write if the change was deliberate")

# a column with a number in it has its line broken around the number, which is
# what makes it a tab staff rather than a number sitting on a line
plain = render.tab_column_svg(["-"] * 6, 500, 0, 100, 0, 1000)
fretted = render.tab_column_svg(["7", "-", "-", "-", "-", "-"], 500, 0, 100, 0, 1000)
check("a fret number breaks its line",
      plain.count("<path") == 6 and fretted.count("<path") == 7
      and "<text" in fretted and "<text" not in plain,
      f"{plain.count('<path')} paths plain, {fretted.count('<path')} fretted")
# and the break is a GAP: two segments that meet at the number are not a break
import re as _re  # noqa: E402
ends = [float(m) for m in _re.findall(r'L ([-\d.]+) 0"', fretted)]
check("...and the break is a gap, not a seam",
      bool(ends) and ends[0] < 500 - 1, str(ends))
wide = render.tab_column_svg(["10", "-", "-", "-", "-", "-"], 500, 0, 100, 0, 1000)
wide_ends = [float(m) for m in _re.findall(r'L ([-\d.]+) 0"', wide)]
check("...and a two-digit fret gets a wider one",
      bool(wide_ends) and wide_ends[0] < ends[0], f"{wide_ends[:1]} vs {ends[:1]}")

# The Swift half cannot be run from here; TabStaffTests does the drawing
# comparison. What is asserted is that it is still holding itself to the same
# numbers.
swift = SWIFT.read_text(encoding="utf-8") if SWIFT.exists() else ""
for name, value in [("pitchRatio", render.TAB_PITCH_RATIO),
                    ("digitVsPitch", render.TAB_DIGIT_VS_PITCH),
                    ("lineVsPitch", render.TAB_LINE_VS_PITCH),
                    ("breakVsPitch", render.TAB_BREAK_VS_PITCH),
                    ("endAdvance", render.TAB_END_ADVANCE),
                    ("baselineVsPitch", render.TAB_BASELINE_VS_PITCH),
                    ("tenthVsRowPitch", render.TAB_TENTH_VS_ROW_PITCH)]:
    check(f"TabStaff.swift keeps {name} = {value:g}",
          f"static let {name} = {value:g}" in swift)
check("TabStaff.swift reads the same tag",
      f'static let tag = "{ops.TAB_LYRIC_TAG}"' in swift
      and f'static let rest = "{ops.TAB_REST}"' in swift)

if FAILURES:
    print(f"FAIL: {len(FAILURES)} guitar-tab check(s)")
    for line in FAILURES:
        print("   ", line)
    sys.exit(1)
print("OK: tablature matches the tuning, the rules and the other renderer")
