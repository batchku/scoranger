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
from scoranger_engine import ops, render  # noqa: E402

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


def adjusted():
    """The same marks, each one nudged right and UP and made half again.

    The numbers are the fixture: +8 tenths right, +12 tenths up, 18pt against
    the 12pt default. What the app's side has to do with them is turn them into
    MEI @ho/@vo of the RIGHT SIGN and a scale on the drawn glyph.
    """
    score = build()
    # the two note-attached kinds, which the page above does not carry in bar 1
    first = next(n for n in score.parts[0].measure(1).notes)
    first.expressions.append(expressions.Fermata())
    first.articulations.append(articulations.Accent())
    for kind in ("dynamic", "text", "fermata", "articulation"):
        ops.adjust_element(score, "#0", kind=kind, measure=1,
                           offset_x=8, offset_y=12, size=18)
    return score


def engrave(score, stem: str) -> None:
    tmp = OUT / f"_{stem}.musicxml"
    score.write("musicxml", fp=str(tmp))
    toolkit = verovio.toolkit()
    toolkit.setOptions(APP_OPTIONS)
    if not toolkit.loadFile(str(tmp)):
        raise SystemExit("verovio failed to load the generated score")
    (OUT / f"{stem}.svg").write_text(toolkit.renderToSVG(1))
    if stem != "marks":
        (OUT / f"{stem}.mei").write_text(toolkit.getMEI())
        (OUT / f"{stem}.musicxml").write_text(tmp.read_text(encoding="utf-8"))
    tmp.unlink()


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    engrave(build(), "marks")
    # ...and the same page with every mark adjusted, plus the MusicXML and the
    # MEI it came from, so the app's half of the translation can be pinned to
    # real artifacts in a bundle that has no Verovio in it.
    engrave(adjusted(), "marks-adjusted")
    for name in sorted(f.name for f in OUT.iterdir() if f.name.startswith("marks")):
        f = OUT / name
        print(f"  {name:24} {f.stat().st_size:>7} bytes")


if __name__ == "__main__":
    main()
