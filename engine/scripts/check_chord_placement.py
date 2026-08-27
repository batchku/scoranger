"""Both renderers must draw the chord symbols the NOTATION describes.

The bug this exists to prevent: `render.py` stamped the Real Book treatment
(`place="within"`, names centred in the bar, bold) onto EVERY score that had a
chord symbol, whether or not anyone had asked for a chart; `VerovioRenderer.swift`
stamped nothing at all. So a chord name sat on the staff in the exported PDF and
above the staff in the app -- the same file, two placements.

That is fatal to nudging. "Move it up half a space" has to mean one thing, and
it cannot while the two renderers disagree about where the symbol started.

The rule, which is the same one the rhythm work landed on -- correctness belongs
in the notation, not in each renderer:

    A chord symbol is drawn ON the staff when the notation says so, and above it
    otherwise. `chart_style` is what says so, by writing `placement="below"` and
    `default-y` onto each <harmony>. Neither renderer decides on its own.

The Swift half of this rule is asserted by ChordPlacementTests; both read the
same attributes off the same <harmony> tags.

Run: engine/.venv/bin/python engine/scripts/check_chord_placement.py
"""

import re
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "engine"))

FAILURES: list[str] = []


def check(label: str, ok: bool, detail: str = "") -> None:
    if ok:
        print(f"  ok   {label}")
    else:
        FAILURES.append(f"{label}{': ' + detail if detail else ''}")
        print(f"  FAIL {label}{': ' + detail if detail else ''}")


def build(chart: bool):
    """A two-bar part with a chord symbol in each bar."""
    from music21 import harmony, meter as m21meter, note, stream
    from scoranger_engine import ops

    score = stream.Score()
    part = stream.Part()
    part.partName = "Chords"
    # an explicit meter, because centring in the bar needs one to centre in --
    # and every real score has one
    part.append(m21meter.TimeSignature("4/4"))
    for index, pitch in enumerate(["C4", "D4"]):
        measure = stream.Measure(number=index + 1)
        measure.append(note.Note(pitch, quarterLength=4.0))
        measure.insert(0, harmony.ChordSymbol("Fm"))
        part.append(measure)
    score.append(part)
    if chart:
        ops.chart_style(score, "Chords")
    path = Path(tempfile.mkdtemp(prefix="scoranger-place-")) / "s.musicxml"
    score.write("musicxml", fp=str(path))
    return path


def mei_for(path: Path) -> str:
    """The MEI the PDF renderer would draw from, styling included."""
    import verovio
    from scoranger_engine import render

    toolkit = verovio.toolkit()
    toolkit.setOptions({"scale": 45, "footer": "none", "adjustPageHeight": True})
    if not toolkit.loadFile(str(path)):
        raise RuntimeError(f"Verovio could not load {path}")
    mei = toolkit.getMEI()
    styled = render.mei_with_chart_styling(mei, str(path))
    return styled if styled is not None else mei


def main() -> int:
    print("what the NOTATION carries")
    plain = build(chart=False)
    charted = build(chart=True)
    plain_xml = plain.read_text()
    chart_xml = charted.read_text()

    check("an untouched score's <harmony> carries no placement",
          not re.search(r'<harmony[^>]*placement=', plain_xml),
          re.findall(r"<harmony[^>]*>", plain_xml)[:1])
    check("chart_style writes placement and default-y",
          bool(re.search(r'<harmony[^>]*placement="below"', chart_xml))
          and bool(re.search(r'<harmony[^>]*default-y=', chart_xml)),
          re.findall(r"<harmony[^>]*>", chart_xml)[:1])

    print("\nwhat the PDF renderer draws")
    plain_mei = mei_for(plain)
    chart_mei = mei_for(charted)

    check("an untouched score is NOT forced onto the staff",
          'place="within"' not in plain_mei,
          "render.py stamped place=within on a score nobody asked to chart")
    check("a charted score IS on the staff",
          'place="within"' in chart_mei,
          "chart_style ran but the renderer ignored it")

    print("\nthe centring follows the same rule")
    # Real Book names sit centred in the bar; an untouched score keeps the
    # symbol at the beat it was written on.
    plain_stamps = re.findall(r'<harm\b[^>]*tstamp="([0-9.]+)"', plain_mei)
    chart_stamps = re.findall(r'<harm\b[^>]*tstamp="([0-9.]+)"', chart_mei)
    check("an untouched score keeps its own beat",
          all(float(t) == 1.0 for t in plain_stamps) if plain_stamps else True,
          f"tstamps {plain_stamps}")
    check("a charted score centres in the bar",
          bool(chart_stamps) and all(float(t) > 1.0 for t in chart_stamps),
          f"tstamps {chart_stamps} (4/4 centres at 2.5)")

    print("\nand the weight")
    check("an untouched score is not emboldened",
          "fontweight=\"bold\"" not in plain_mei,
          "render.py bolded a score nobody asked to chart")
    check("a charted score is",
          "fontweight=\"bold\"" in chart_mei)

    print()
    if FAILURES:
        print(f"FAILED: {len(FAILURES)}")
        for f in FAILURES:
            print(f"  - {f}")
        return 1
    print("OK: chord placement follows the notation, so the app and the PDF "
          "agree on where a symbol starts -- which is what makes 'move it up' "
          "mean one thing")
    return 0


if __name__ == "__main__":
    sys.exit(main())
