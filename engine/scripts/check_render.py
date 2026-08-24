"""Regression check for how things are SIZED on the page.

Verovio has exactly one text-size option, `lyricSize`, and it sizes lyric
verses AND `<harm>` chord symbols. Build 128 halved it to shrink the whistle
fingering diagrams, and chord names came along for the ride: they rendered at
less than half their size for anyone whose score had fingerings, which is
exactly the score a whistle player is looking at.

The rule this file enforces:

    How big a chord name is may not depend on anything else the score happens
    to carry. Our own drawn glyphs are scaled in our own pass, never by moving
    a global option that also sizes someone else's text.

Run: engine/.venv/bin/python engine/scripts/check_render.py
"""

import re
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "engine"))
sys.path.insert(0, str(Path(__file__).resolve().parent))

import verovio  # noqa: E402

import fixtures  # noqa: E402
from scoranger_engine import ops, render  # noqa: E402

FAILURES: list[str] = []

# The app's option set (VerovioRenderer.options), so what is measured here is
# what a user sees.
APP_OPTIONS = {"scale": 45, "footer": "none", "adjustPageHeight": True,
               "pageMarginTop": 100, "pageMarginBottom": 100,
               "pageMarginLeft": 120, "pageMarginRight": 120}

CHORDS = [{"measure": 1, "symbol": "Em"}, {"measure": 5, "symbol": "D"},
          {"measure": 9, "symbol": "G"}]


def engrave(with_fingerings: bool, bars: int = 16):
    """Render a jig with chord symbols, optionally fingered, the app's way."""
    score = fixtures.jig(bars=bars)
    ops.set_chord_symbols(score, "#0", CHORDS)
    if with_fingerings:
        ops.whistle_fingerings(score, score.parts[0], "D")
    src = tempfile.mktemp(suffix=".musicxml")
    score.write("musicxml", fp=src)

    toolkit = verovio.toolkit()
    toolkit.setOptions({**APP_OPTIONS, "lyricSize": render.DEFAULT_LYRIC_SIZE})
    toolkit.loadFile(src)
    mei = toolkit.getMEI()
    above = render.mei_with_fingerings_above(mei)
    if above is not None:
        toolkit.setOptions({**APP_OPTIONS,
                            "lyricSize": render.lyric_size_for(fingerings=True)})
        toolkit.loadData(above)
    svg = toolkit.renderToSVG(1)
    return svg, render._fingering_diagrams(svg)


def sizes(svg: str, css_class: str) -> list[float]:
    """Font sizes of the text inside one class of element."""
    return sorted({float(s) for s in re.findall(
        rf'class="{css_class}".{{0,400}}?<tspan font-size="([\d.]+)px"', svg, re.S)})


def radii(svg: str) -> list[float]:
    """Radii of the arcs our pass drew (the 'A r r' of each circle path)."""
    return sorted({round(float(r), 2) for r in re.findall(r'A ([\d.]+) \1 0 1 0', svg)})


plain_svg, _ = engrave(with_fingerings=False)
fing_svg, drawn = engrave(with_fingerings=True)

# -- the regression itself ----------------------------------------------------
plain_chords, fing_chords = sizes(plain_svg, "harm"), sizes(fing_svg, "harm")
if not plain_chords:
    FAILURES.append("no chord symbols found in the fixture -- the check is not measuring anything")
elif plain_chords != fing_chords:
    FAILURES.append(
        f"chord-name size depends on whether the score has fingerings: "
        f"{plain_chords} without, {fing_chords} with")

# -- and chord names are at the engraving's full text size ---------------------
verse_sizes = sizes(fing_svg, "verse")
if not verse_sizes:
    FAILURES.append("no fingering verses found -- the check is not measuring anything")
elif fing_chords and verse_sizes != fing_chords:
    FAILURES.append(f"chord names ({fing_chords}) and verses ({verse_sizes}) should share the "
                    "engraving's one text size; the diagrams are scaled in our own pass")

# -- the diagrams stay small, in our pass rather than Verovio's option --------
if not 0.4 < render.DIAGRAM_SCALE < 0.6:
    FAILURES.append(f"DIAGRAM_SCALE is {render.DIAGRAM_SCALE}; the diagrams are meant to be "
                    "about half the height of the text they replace")

drawn_radii = radii(drawn)
if not drawn_radii:
    FAILURES.append("our pass drew no circles")
elif verse_sizes:
    want = render.HOLE_RADIUS * render.DIAGRAM_SCALE * verse_sizes[0]
    if not any(abs(r - want) < 1.0 for r in drawn_radii):
        FAILURES.append(f"circle radius {drawn_radii} is not the scaled {want:.1f} -- "
                        "the diagrams no longer match the size they shipped at")

# -- the octave "+" is part of the diagram and scales with it ------------------
plus = sorted({float(s) for s in re.findall(r'<tspan font-size="([\d.]+)px">\+</tspan>', drawn)})
if not plus:
    FAILURES.append("no octave '+' in a fingered second-octave jig -- nothing to check")
elif verse_sizes:
    want_plus = render.DIAGRAM_SCALE * verse_sizes[0]
    if not any(abs(p - want_plus) < 1.0 for p in plus):
        FAILURES.append(f"the octave '+' renders at {plus} but the circles beside it are scaled "
                        f"to {render.DIAGRAM_SCALE:g}x -- it should be {want_plus:.1f}")

if FAILURES:
    print(f"FAIL: {len(FAILURES)} rendering size check(s) failed")
    for line in FAILURES:
        print("   ", line)
    sys.exit(1)
print(f"OK: chord names are {fing_chords[0]:g}px with or without fingerings, "
      f"and the diagrams are scaled {render.DIAGRAM_SCALE:g}x in our own pass")
