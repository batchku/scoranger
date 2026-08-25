"""Regression check for adjusting the size and position of added elements.

Chord symbols first. What a user means by "make that chord name bigger" or
"nudge it up" has to survive three hops: into the notation, out through
music21's writer, and onto the page. Each hop was measured before this was
built, and each is checked here:

  - music21 round-trips `font-size`, `relative-x` and `relative-y` on
    <harmony> exactly. So the notation is where the adjustment lives, in
    standard MusicXML that any other program can read.
  - Verovio's MusicXML importer DROPS all three, so position has to be
    translated into MEI (@ho/@vo, which Verovio honours per element) and size
    applied in our own SVG pass (Verovio ignores @fontsize entirely, as a
    percentage and as a keyword).

Run: engine/.venv/bin/python engine/scripts/check_adjust.py
"""

import re
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "engine"))
sys.path.insert(0, str(Path(__file__).resolve().parent))

import verovio  # noqa: E402
from music21 import converter  # noqa: E402

import fixtures  # noqa: E402
from scoranger_engine import ops, render  # noqa: E402

FAILURES: list[str] = []

CHORDS = [{"measure": 1, "symbol": "Em"}, {"measure": 3, "symbol": "G"},
          {"measure": 5, "symbol": "D"}]


def charted(bars: int = 8):
    score = fixtures.jig(bars=bars)
    ops.set_chord_symbols(score, "#0", CHORDS)
    return score


def symbols(score):
    return list(score.recurse().getElementsByClass("ChordSymbol"))


def written(score):
    path = tempfile.mktemp(suffix=".musicxml")
    score.write("musicxml", fp=path)
    return path


# -- the op writes into the notation ------------------------------------------
score = charted()
ops.adjust_element(score, "#0", kind="harm", measure=3, size=18, offset_y=-4)
adjusted = symbols(score)[1]
if adjusted.style.fontSize != 18:
    FAILURES.append(f"size not written: fontSize is {adjusted.style.fontSize}")
if adjusted.style.relativeY != -4:
    FAILURES.append(f"offset not written: relativeY is {adjusted.style.relativeY}")
for other in (symbols(score)[0], symbols(score)[2]):
    if other.style.fontSize is not None or other.style.relativeY is not None:
        FAILURES.append("adjusting one chord symbol changed its neighbours")

# -- and it survives the notation round trip ----------------------------------
back = converter.parse(written(score), forceSource=True)
b = symbols(back)[1]
if b.style.fontSize != 18 or b.style.relativeY != -4:
    FAILURES.append(f"the adjustment did not survive the file: "
                    f"size={b.style.fontSize} offsetY={b.style.relativeY}")

# -- reset puts it back -------------------------------------------------------
ops.adjust_element(score, "#0", kind="harm", measure=3, reset=True)
r = symbols(score)[1]
if r.style.fontSize is not None or r.style.relativeY is not None:
    FAILURES.append(f"reset left size={r.style.fontSize} offsetY={r.style.relativeY}")

# -- a part-wide adjustment reaches every symbol ------------------------------
whole = charted()
ops.adjust_element(whole, "#0", kind="harm", all_elements=True, size=20)
if any(c.style.fontSize != 20 for c in symbols(whole)):
    FAILURES.append("--all did not reach every chord symbol")
ops.adjust_element(whole, "#0", kind="harm", all_elements=True, reset=True)
if any(c.style.fontSize is not None for c in symbols(whole)):
    FAILURES.append("--all --reset did not clear every chord symbol")

# -- refusals a person can act on ---------------------------------------------
for kwargs, why in (
    ({"kind": "harm", "measure": 99, "size": 12}, "a measure with no chord symbol"),
    ({"kind": "note", "measure": 1, "size": 12}, "a kind that is not supported yet"),
    ({"kind": "harm", "measure": 1}, "nothing to change"),
):
    try:
        ops.adjust_element(charted(), "#0", **kwargs)
        FAILURES.append(f"accepted {why}")
    except ValueError:
        pass

# -- position reaches the page ------------------------------------------------
# Verovio drops relative-x/y from MusicXML, so the renderer translates them into
# MEI @ho/@vo. Without that step this assertion fails, which is the point.
def engrave(path):
    toolkit = verovio.toolkit()
    toolkit.setOptions({"scale": 45, "footer": "none", "adjustPageHeight": True,
                        "lyricSize": render.DEFAULT_LYRIC_SIZE})
    toolkit.loadFile(path)
    mei = render.mei_with_chord_adjustments(toolkit.getMEI(), path)
    if mei is not None:
        toolkit.loadData(mei)
    svg = toolkit.renderToSVG(1)
    return render.apply_chord_sizes(svg, path)


def harm_boxes(svg):
    out = []
    for block in re.findall(r'<g[^>]*class="harm".*?</g>\s*</g>', svg, re.S):
        pos = re.search(r'<text[^>]*x="([-\d.]+)"[^>]*y="([-\d.]+)"', block)
        size = re.search(r'<tspan font-size="([\d.]+)px"', block)
        out.append((float(pos.group(1)) if pos else None,
                    float(pos.group(2)) if pos else None,
                    float(size.group(1)) if size else None))
    return out

plain = harm_boxes(engrave(written(charted())))

moved_score = charted()
ops.adjust_element(moved_score, "#0", kind="harm", measure=3, offset_y=-6, offset_x=4)
moved = harm_boxes(engrave(written(moved_score)))

if len(plain) != 3 or len(moved) != 3:
    FAILURES.append(f"expected three chord symbols, engraved {len(plain)} and {len(moved)}")
else:
    if moved[1][:2] == plain[1][:2]:
        FAILURES.append(f"the adjusted symbol did not move: {plain[1][:2]} -> {moved[1][:2]}")
    for i in (0, 2):
        if moved[i][:2] != plain[i][:2]:
            FAILURES.append(f"symbol {i} moved when its neighbour was adjusted: "
                            f"{plain[i][:2]} -> {moved[i][:2]}")

# -- size reaches the page ----------------------------------------------------
big_score = charted()
ops.adjust_element(big_score, "#0", kind="harm", measure=3, size=30)
big = harm_boxes(engrave(written(big_score)))
if len(big) == 3 and plain:
    if big[1][2] is None or plain[1][2] is None:
        FAILURES.append("could not read the engraved chord-symbol size")
    elif big[1][2] <= plain[1][2]:
        FAILURES.append(f"the adjusted symbol did not grow: {plain[1][2]} -> {big[1][2]}")
    elif big[0][2] != plain[0][2]:
        FAILURES.append(f"a neighbour changed size: {plain[0][2]} -> {big[0][2]}")

# -- and none of it touches a note --------------------------------------------
rhythm_before = ops.rhythm_faults(charted())
after = charted()
ops.adjust_element(after, "#0", kind="harm", measure=3, size=22, offset_y=-3)
if ops.rhythm_faults(after) != rhythm_before:
    FAILURES.append("adjusting a chord symbol changed the rhythm")

if FAILURES:
    print(f"FAIL: {len(FAILURES)} adjustment check(s) failed")
    for line in FAILURES:
        print("   ", line)
    sys.exit(1)
print("OK: size and position are written to the notation, survive the file, "
      "and reach the page without disturbing anything else")
