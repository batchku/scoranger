"""Regression check for where the LINES break, and for the Verovio option
that decides whether any of it is drawn at all.

`ops.paginate` writes MusicXML `<print new-system="yes"/>`. Whether a reader
ever sees one is a RENDERER setting, and the three modes do genuinely
different things -- measured here rather than believed:

    breaks=auto      lays the music out itself and IGNORES encoded breaks
    breaks=encoded   breaks ONLY where the notation says, and nowhere else
    breaks=smart     honours some and re-flows the rest

The paged renderers were `auto` until 0.12.2, so every line the op wrote would
have been invisible on the page while the op reported success. That is the
first thing asserted here, on BOTH renderers, because render.py and
EngravingOptions.swift each carry their own copy of the answer.

The second is the trap in `encoded`: because it breaks only where told, ONE
break on a long piece means one short line and then everything else crushed
onto a single system. So the op always writes a COMPLETE pagination, and that
is asserted against the drawn page, not against the op's own report.

Run: engine/.venv/bin/python engine/scripts/check_pagination.py
"""

import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import verovio  # noqa: E402
from music21 import layout, meter, note as m21note, stream  # noqa: E402

from scoranger_engine import ops, render  # noqa: E402

FAILURES: list[str] = []
SCRATCH = Path(__file__).resolve().parents[2] / "workspace" / ".pagination-check"


def check(label, ok, detail=""):
    print(f"    {'ok  ' if ok else 'FAIL'} {label}" + (f": {detail}" if detail and not ok else ""))
    if not ok:
        FAILURES.append(f"{label}{': ' + detail if detail else ''}")


def a_score(bars: int = 16, parts: int = 1):
    score = stream.Score()
    for _ in range(parts):
        part = stream.Part()
        for i in range(1, bars + 1):
            m = stream.Measure(number=i)
            if i == 1:
                m.append(meter.TimeSignature("4/4"))
            m.append(m21note.Note("G4", quarterLength=4))
            part.append(m)
        score.append(part)
    return score


def drawn_systems(score, tag: str, breaks: str = "encoded") -> list[int]:
    """Measures per system, off the page Verovio actually draws."""
    SCRATCH.mkdir(parents=True, exist_ok=True)
    path = SCRATCH / f"{tag}.musicxml"
    score.write("musicxml", fp=str(path))
    tk = verovio.toolkit()                 # fresh: Verovio's options are sticky
    options = dict(render.page_options())
    options["breaks"] = breaks
    tk.setOptions(options)
    tk.loadFile(str(path))
    out = []
    for page in range(1, tk.getPageCount() + 1):
        svg = tk.renderToSVG(page)
        blocks = re.split(r'(?=<g[^>]*class="system")', svg)[1:]
        out += [b.count('class="measure"') for b in blocks]
    return out


# --- the renderers ask for encoded breaks, or none of this is drawn ---------
print("both renderers ask Verovio for the breaks the notation carries")

check("render.py exports with breaks=encoded",
      render.page_options().get("breaks") == "encoded",
      str(render.page_options().get("breaks")))

swift = (Path(__file__).resolve().parents[2]
         / "ios/Scoranger/ScoreModel/EngravingOptions.swift").read_text()
match = re.search(r'static func breaks\(continuous: Bool\) -> String \{([^}]*)\}', swift)
check("EngravingOptions.swift agrees, and the strip still refuses to break",
      bool(match) and '"encoded"' in match.group(1) and '"none"' in match.group(1),
      match.group(1).strip() if match else "breaks(continuous:) not found")

# --- and the three modes are not interchangeable ---------------------------
print("\nthe three modes do different things, which is why it has to be encoded")

paged = a_score(16)
ops.paginate(paged, measures_per_line=4)
check("encoded draws the four-bar lines the notation asks for",
      drawn_systems(paged, "encoded", "encoded") == [4, 4, 4, 4],
      str(drawn_systems(paged, "encoded", "encoded")))
auto = drawn_systems(paged, "auto", "auto")
check("auto ignores them outright -- the bug this would have shipped",
      auto != [4, 4, 4, 4], f"auto gave {auto}")

# --- a complete layout, never a lone break ---------------------------------
print("\nevery pagination is complete, because a lone break crushes the rest")

one = a_score(16)
ops.paginate(one, measures_per_line=4)
report = ops.paginate(one, break_at=[7])
check("a forced break keeps its bar at the head of a line",
      7 in report["line_starts"], str(report["line_starts"]))
check("...and no line is longer than the score's own length",
      max(report["bars_per_line"]) <= report["measures_per_line"],
      str(report["bars_per_line"]))
check("...which is what the page actually shows",
      drawn_systems(one, "forced") == report["bars_per_line"],
      f"drawn {drawn_systems(one, 'forced')} vs reported {report['bars_per_line']}")

# --- the round trip, which is where chord diagrams died --------------------
print("\nbreaks survive being written and read back, every version is")

from music21 import converter  # noqa: E402

SCRATCH.mkdir(parents=True, exist_ok=True)
trip = SCRATCH / "roundtrip.musicxml"
rt = a_score(16)
ops.paginate(rt, measures_per_line=4)
rt.write("musicxml", fp=str(trip))
back = converter.parse(str(trip), forceSource=True)
check("a break read back is still a break",
      ops.system_break_bars(back) == [5, 9, 13],
      str(ops.system_break_bars(back)))
again = SCRATCH / "roundtrip2.musicxml"
back.write("musicxml", fp=str(again))
check("and survives a second write, which every op performs",
      again.read_text().count('new-system="yes"') == 3,
      str(again.read_text().count('new-system="yes"')))

# --- clearing hands it back ------------------------------------------------
print("\nclearing gives the layout back to the engraver")

cleared = a_score(16)
ops.paginate(cleared, measures_per_line=4)
gone = ops.paginate(cleared, clear=True)
check("every break is removed and counted",
      gone["breaks_removed"] == 3, str(gone))
check("and a score with none falls back to the engraver's own layout",
      drawn_systems(cleared, "cleared") == drawn_systems(a_score(16), "plain", "auto"),
      f"{drawn_systems(cleared, 'cleared')} vs auto {drawn_systems(a_score(16), 'plain', 'auto')}")

# --- a break is a property of the SYSTEM, so every staff carries one -------
print("\na break goes on every staff, as a volta has to")

grand = a_score(8, parts=3)
ops.paginate(grand, measures_per_line=4)
per_part = [[m.number for m in p.getElementsByClass(stream.Measure)
             if any(sl.isNew for sl in m.getElementsByClass(layout.SystemLayout))]
            for p in grand.parts]
check("all three staves break at the same bar",
      per_part == [[5], [5], [5]], str(per_part))

# --- refusals --------------------------------------------------------------
print("\nit refuses rather than guessing")

bare = a_score(16)
try:
    ops.paginate(bare, break_at=[9])
    check(False, "a score with no line length must refuse a bare break")
except ValueError as exc:
    check("with no length written or given, it says so by name",
          "measures_per_line" in str(exc), str(exc))

try:
    ops.paginate(a_score(8), break_at=[99])
    check(False, "a bar that does not exist must be refused")
except ValueError as exc:
    check("a bar outside the score is refused with the range",
          "99" in str(exc) and "1-8" in str(exc), str(exc))

import shutil  # noqa: E402
shutil.rmtree(SCRATCH, ignore_errors=True)

if FAILURES:
    print(f"\nFAIL: {len(FAILURES)} pagination check(s) failed")
    for line in FAILURES:
        print("   ", line)
    sys.exit(1)
print("\nOK: the lines break where the notation says, and both renderers ask for it")
