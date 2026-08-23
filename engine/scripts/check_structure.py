"""Regression check for repeats, voltas and navigation marks.

Each kind is written, exported to MusicXML, engraved by Verovio, and checked in
the MEI that comes back — because the only thing that matters is whether the
mark reaches the page. A mark the engine writes and nothing draws is worse than
refusing the request.

Run: engine/.venv/bin/python engine/scripts/check_structure.py
"""

import re
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import verovio  # noqa: E402
from music21 import bar as m21bar, layout, meter, note as m21note, stream  # noqa: E402

from scoranger_engine import ops  # noqa: E402

FAILURES: list[str] = []


def fresh_score(parts: int = 1, bars: int = 4):
    score = stream.Score()
    for _ in range(parts):
        part = stream.Part()
        for i in range(1, bars + 1):
            measure = stream.Measure(number=i)
            if i == 1:
                measure.append(meter.TimeSignature("4/4"))
            for _ in range(4):
                measure.append(m21note.Note("C4", quarterLength=1))
            part.append(measure)
        score.append(part)
    return score


def engrave(score) -> str:
    """The MEI Verovio produces from the exported MusicXML."""
    with tempfile.NamedTemporaryFile(suffix=".musicxml", delete=False) as tmp:
        path = tmp.name
    score.write("musicxml", fp=path)
    toolkit = verovio.toolkit()
    toolkit.setOptions({"scale": 40, "footer": "none", "adjustPageHeight": True})
    if not toolkit.loadFile(path):
        return ""
    return toolkit.getMEI("{}")


def expect_engraved(kind: str, pattern: str, **kwargs):
    """Apply a mark, engrave, and look for it in the MEI."""
    score = fresh_score()
    try:
        ops.set_structure(score, kind, **kwargs)
    except Exception as e:  # noqa: BLE001 — the check is the point
        FAILURES.append(f"{kind}: op raised {type(e).__name__}: {e}")
        return
    mei = engrave(score)
    if not re.search(pattern, mei):
        FAILURES.append(f"{kind}: nothing matching /{pattern}/ reached the engraving")


def expect_gone(kind: str, pattern: str, **kwargs):
    """Apply, then remove, and check the mark is no longer engraved."""
    score = fresh_score()
    ops.set_structure(score, kind, **kwargs)
    ops.set_structure(score, kind, remove=True, **kwargs)
    mei = engrave(score)
    if re.search(pattern, mei):
        FAILURES.append(f"{kind}: still engraved after remove")


# -- repeat barlines --------------------------------------------------------
expect_engraved("repeat-start", r'left="rptstart"', measure=2)
expect_engraved("repeat-end", r'right="rptend"', measure=3)
expect_engraved("repeat-both", r'left="rptstart"', measure=2)
expect_engraved("repeat-both", r'right="rptend"', measure=2)
expect_gone("repeat-start", r'left="rptstart"', measure=2)

# -- voltas -----------------------------------------------------------------
expect_engraved("volta", r'<ending[^>]*n="1"', measure=2, to_measure=3, number=1)
expect_engraved("volta", r'<ending[^>]*n="2"', measure=4, number=2)
expect_gone("volta", r"<ending", measure=2, to_measure=3, number=1)

# -- navigation marks -------------------------------------------------------
# Segno and Coda engrave as glyphs; the rest as directions with real wording.
expect_engraved("segno", r"<dir|<repeatMark", measure=2)
expect_engraved("coda", r"<dir|<repeatMark", measure=3)
expect_engraved("fine", r"(?i)fine", measure=4)
expect_engraved("da-capo", r"(?i)da capo", measure=4)
expect_engraved("da-capo-al-fine", r"(?i)da capo al fine", measure=4)
expect_engraved("da-capo-al-coda", r"(?i)da capo al coda", measure=4)
expect_engraved("dal-segno", r"(?i)dal segno", measure=4)
expect_engraved("dal-segno-al-fine", r"(?i)dal segno al fine", measure=4)
expect_engraved("dal-segno-al-coda", r"(?i)dal segno al coda", measure=4)
expect_gone("fine", r"(?i)fine", measure=4)

# -- a grand staff, which exports as ONE part with two staves ----------------
# The case that caught us out: music21 merges the two PartStaffs of an
# accordion or piano score into a single <part>, and in that merge the second
# staff's barline replaces the first's — taking the volta's <ending> with it.
# The second staff must carry barlines of its own for that to happen, which is
# what every imported score does; a staff with none never showed the bug.
grand = stream.Score()
staves = []
for index in range(2):
    staff = stream.PartStaff()
    for i in range(1, 5):
        bar_ = stream.Measure(number=i)
        if i == 1:
            bar_.append(meter.TimeSignature("4/4"))
        for _ in range(4):
            bar_.append(m21note.Note("C4", quarterLength=1))
        if index == 1:
            bar_.leftBarline = m21bar.Barline("regular")
            bar_.rightBarline = m21bar.Barline("regular")
        staff.append(bar_)
    staves.append(staff)
    grand.insert(0, staff)
grand.insert(0, layout.StaffGroup(staves, symbol="brace"))
ops.set_structure(grand, "volta", measure=2, to_measure=3, number=1)
grand_mei = engrave(grand)
if not re.search(r'<ending[^>]*n="1"', grand_mei):
    FAILURES.append("volta on a grand staff never reached the engraving")
ops.set_structure(grand, "volta", measure=2, to_measure=3, number=1, remove=True)
if re.search(r"<ending", engrave(grand)):
    FAILURES.append("volta on a grand staff survived remove")

# -- a repeat belongs to the system, not to one staff ------------------------
two_staves = fresh_score(parts=2)
report = ops.set_structure(two_staves, "repeat-end", measure=3)
if len(report["parts"]) != 2:
    FAILURES.append("repeat barline was not written to every part: "
                    f"{report['parts']}")

# -- moving ------------------------------------------------------------------
moved = fresh_score()
ops.set_structure(moved, "segno", measure=2)
ops.set_structure(moved, "segno", measure=2, move_to=4)
from music21 import repeat as m21repeat  # noqa: E402

at_two = list(moved.parts[0].measure(2).getElementsByClass(m21repeat.Segno))
at_four = list(moved.parts[0].measure(4).getElementsByClass(m21repeat.Segno))
if at_two or not at_four:
    FAILURES.append(f"move left {len(at_two)} at bar 2 and {len(at_four)} at bar 4")

# -- refusals ----------------------------------------------------------------
for kind, kwargs, why in (
    ("repeat-start", {"measure": 99}, "a measure that does not exist"),
    ("nonsense", {"measure": 1}, "an unknown kind"),
    ("repeat-start", {}, "no measure at all"),
):
    try:
        ops.set_structure(fresh_score(), kind, **kwargs)
        FAILURES.append(f"{kind}: accepted {why}")
    except (ValueError, TypeError):
        pass

if FAILURES:
    print(f"FAIL: {len(FAILURES)} structural mark(s) wrong")
    for line in FAILURES:
        print("   ", line)
    sys.exit(1)
print(f"OK: {len(ops.STRUCTURE_KINDS)} structural marks engrave, remove and move")
