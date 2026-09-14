"""Generate the fixture for how MARKS are drawn: tempo, directions, dynamics.

The app draws Verovio's SVG through SwiftDraw, and SwiftDraw reads neither
Verovio's stylesheet nor nested tspans. Two faults lived there unseen for
months and both are properties of ONE engraved page:

  - a tempo mark is three runs in one `<text>` -- a music glyph at 720px, then
    " = " and "138" at 405px -- and flattening took the size of the FIRST run,
    so the digits printed at nearly double their engraved size;
  - Verovio's own stylesheet sets `g.dir`, `g.dynam` and `g.mNum` italic and
    `g.tempo` bold, and none of it reached the page.

So the fixture is a real engraving carrying all of them, committed next to the
score-model fixtures and read by `SVGForSwiftDrawTests` and `MarksOnThePage`.
It is engraved with the APP's options (EngravingOptions), because what is being
pinned is the page a reader gets.

Synthetic on purpose: the repository is public, so no committed fixture may
carry copyrighted music.

    engine/.venv/bin/python engine/scripts/make_marks_fixture.py
"""
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "engine"))
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

import verovio  # noqa: E402
from music21 import (articulations, duration, dynamics,  # noqa: E402
                     expressions, metadata, tempo)

import fixtures  # noqa: E402
from scoranger_engine import render  # noqa: E402

OUT = ROOT / "ios/ScorangerTests/Fixtures"

# the app's own set (EngravingOptions.json), plus measure numbers on every bar
# so `g.mNum` -- the third italic class -- is on the page to be looked at
APP_OPTIONS = {"scale": 45, "footer": "none", "breaks": "auto",
               "adjustPageHeight": False,
               "pageWidth": 2159, "pageHeight": 2794,
               "pageMarginTop": 100, "pageMarginBottom": 100,
               "pageMarginLeft": 120, "pageMarginRight": 120,
               "lyricSize": render.DEFAULT_LYRIC_SIZE,
               "mnumInterval": 1}


def build():
    """A jig with a tempo mark, an expression, a dynamic and a fingering."""
    score = fixtures.jig(bars=8)
    # music21 stamps "Music21 Fragment" at the top of anything it writes with
    # no title of its own, and that would engrave into the committed fixture.
    score.insert(0, metadata.Metadata(title="Marks", movementName="Marks"))
    part = score.parts[0]
    first = part.measure(1)
    # dotted quarter = 138: the mark whose digits printed twice their size
    first.insert(0.0, tempo.MetronomeMark(number=138,
                                          referent=duration.Duration(1.5)))
    first.insert(0.0, dynamics.Dynamic("mf"))
    first.insert(1.5, expressions.TextExpression("dolce"))
    part.measure(3).insert(0.0, expressions.TextExpression("rit."))
    # a fingering mark: `g.fing` is the fourth class the stylesheet styles
    notes = [n for n in part.measure(2).notes]
    if notes:
        notes[0].articulations.append(articulations.Fingering("m"))
    return score


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    tmp = OUT / "_marks.musicxml"
    build().write("musicxml", fp=str(tmp))
    toolkit = verovio.toolkit()
    toolkit.setOptions(APP_OPTIONS)
    if not toolkit.loadFile(str(tmp)):
        raise SystemExit("verovio failed to load the generated score")
    (OUT / "marks.svg").write_text(toolkit.renderToSVG(1))
    tmp.unlink()
    written = OUT / "marks.svg"
    print(f"  {written.name:18} {written.stat().st_size:>7} bytes")


if __name__ == "__main__":
    main()
