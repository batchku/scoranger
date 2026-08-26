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

# -- the diagram is small and tightly stacked, and the circles are not --------
#
# Ali asked for the column to lose about half its footprint while each hole got
# BIGGER -- just under a notehead. Those pull against each other, so both are
# measured here, off the drawn output rather than off the constants.

# how the rows are spaced, measured from the circles actually drawn
centres = [(float(x), float(y)) for x, y in
           re.findall(r'<path d="M ([-\d.]+) ([-\d.]+) A', drawn)]
columns: dict[float, list[float]] = {}
for x, y in centres:
    columns.setdefault(round(x, 1), []).append(y)
pitches = sorted({round(b - a)
                  for ys in columns.values()
                  for a, b in zip(sorted(ys), sorted(ys)[1:]) if b > a})

drawn_radii = radii(drawn)
if not drawn_radii:
    FAILURES.append("our pass drew no circles")
if len(drawn_radii) > 1:
    FAILURES.append(f"the holes are not all one size: {drawn_radii}")

# the pitch Verovio laid the verses out at, before we re-placed them
original = [(float(x), float(y)) for x, y in
            re.findall(r'class="verse".{0,400}?<text[^>]*?x="([-\d.]+)"[^>]*?y="([-\d.]+)"',
                       fing_svg, re.S)]
orig_columns: dict[float, list[float]] = {}
for x, y in original:
    orig_columns.setdefault(round(x, 1), []).append(y)
orig_pitches = sorted({round(b - a)
                       for ys in orig_columns.values()
                       for a, b in zip(sorted(ys), sorted(ys)[1:]) if b > a})

if pitches and orig_pitches:
    shrunk = pitches[0] / orig_pitches[0]
    if not 0.40 <= shrunk <= 0.50:
        FAILURES.append(
            f"the column is {shrunk:.0%} of the spacing Verovio laid out "
            f"({pitches[0]} from {orig_pitches[0]}); it was asked to be 40-50%")

# and the holes themselves are just under a notehead, which is what stops
# "smaller overall" from turning into "too small to read"
if drawn_radii and pitches:
    notehead = orig_pitches[0] * render.NOTEHEAD_PER_ROW_PITCH
    fraction = (drawn_radii[0] * 2) / notehead
    if not 0.65 <= fraction < 1.0:
        FAILURES.append(
            f"a hole is {fraction:.0%} of a notehead ({drawn_radii[0]*2:.0f} of "
            f"{notehead:.0f}); it should be a little under one")
    # ...and bigger than the diagrams shipped at, which is the other half of
    # the request and the easy thing to lose while shrinking the column
    was = render.HOLE_RADIUS * render.DIAGRAM_SCALE * (verse_sizes[0] if verse_sizes else 0)
    if was and drawn_radii[0] <= was:
        FAILURES.append(
            f"the holes got smaller, not bigger: {drawn_radii[0]:.1f} vs {was:.1f}")

# A column belongs to ONE note: six holes, plus the octave "+" at most.
#
# Grouping rows by "y keeps increasing" alone merged the last column of a
# system with the first of the next -- whose y is larger still, simply because
# it is further down the page -- and the merged column was re-placed from the
# first system's anchor, leaving a stack of circles floating in the gap between
# the two systems, under no note at all.
oversized = {round(x, 1): len(ys) for x, ys in columns.items() if len(ys) > 6}
if oversized:
    FAILURES.append(
        f"columns with more than six holes: {oversized} -- rows from different "
        "notes have been grouped together")

# the circles must not touch or overlap once the rows are tightened
if drawn_radii and pitches and pitches[0] <= drawn_radii[0] * 2:
    FAILURES.append(
        f"the holes overlap: pitch {pitches[0]} with diameter {drawn_radii[0]*2:.0f}")

# -- the octave "+" is part of the diagram and moves and scales with it --------
plus = sorted({float(s) for s in re.findall(r'<tspan font-size="([\d.]+)px">\+</tspan>', drawn)})
if not plus:
    FAILURES.append("no octave '+' in a fingered second-octave jig -- nothing to check")
elif drawn_radii:
    want_plus = drawn_radii[0] * 2 * render.OCTAVE_MARK_VS_DIAMETER
    if not any(abs(p - want_plus) < 1.0 for p in plus):
        FAILURES.append(f"the octave '+' renders at {plus}; sized from the circles beside it "
                        f"it should be {want_plus:.1f}")

if FAILURES:
    print(f"FAIL: {len(FAILURES)} rendering size check(s) failed")
    for line in FAILURES:
        print("   ", line)
    sys.exit(1)
print(f"OK: chord names are {fing_chords[0]:g}px with or without fingerings; "
      f"the fingering column is stacked at {pitches[0]} where Verovio laid out "
      f"{orig_pitches[0]} ({pitches[0]/orig_pitches[0]:.0%}), and each hole is "
      f"{drawn_radii[0]*2:.0f} across -- "
      f"{(drawn_radii[0]*2)/(orig_pitches[0]*render.NOTEHEAD_PER_ROW_PITCH):.0%} of a notehead")
