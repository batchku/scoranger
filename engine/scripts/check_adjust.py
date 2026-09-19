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

# -- and it reaches the page for every kind, THE RIGHT WAY UP -----------------
#
# Step 1 generalised `adjust_element` past chord symbols, and the values went
# into the MusicXML correctly and reached neither engraver: Verovio drops
# relative-x/relative-y from a <dynamics>, a <words>, a <fermata> and an
# articulation exactly as it drops them from a <harmony>, and the renderers
# only carried the <harmony>.
#
# The direction is asserted, not assumed. The old <harm> pass NEGATED its
# offset -- so the app's "up" arrow moved a chord symbol DOWN -- and the check
# that existed only asked whether the symbol had MOVED. `up_is_up` is what
# that check was missing.
def marked():
    """A jig with one of every adjustable mark on it."""
    from music21 import articulations, dynamics, expressions, harmony

    score = fixtures.jig(bars=8)
    ops.set_chord_symbols(score, "#0", [{"measure": 3, "symbol": "Em"}])
    bar = score.parts[0].measure(3)
    bar.insert(0.0, dynamics.Dynamic("mf"))
    bar.insert(1.5, expressions.TextExpression("dolce"))
    note = next(n for n in bar.notes if not isinstance(n, harmony.Harmony))
    note.expressions.append(expressions.Fermata())
    note.articulations.append(articulations.Accent())
    return score


def engrave_marks(path):
    toolkit = verovio.toolkit()
    toolkit.setOptions({"scale": 45, "footer": "none", "adjustPageHeight": True,
                        "lyricSize": render.DEFAULT_LYRIC_SIZE})
    toolkit.loadFile(path)
    mei = render.mei_with_element_adjustments(toolkit.getMEI(), path)
    if mei is not None:
        toolkit.loadData(mei)
    return render.apply_element_sizes(toolkit.renderToSVG(1), path)


def anchors(svg, css, leaf=False):
    """Where each element of one class was drawn, and how big.

    A glyph reports the translate of its <use> and the scale in the same
    transform; a text element reports its <text> x/y and its tspan size.
    """
    out = []
    pattern = (rf'<g[^>]*class="{css}"[^>]*>(?:(?!<g\b).)*?</g>' if leaf
               else rf'<g[^>]*class="{css}".*?</g>\s*</g>')
    for block in re.findall(pattern, svg, re.S):
        # TEXT FIRST. A block's span can reach past its own drawing, so a
        # <use> found inside a chord symbol's block belongs to the note under
        # it; a <text> in there never does.
        pos = re.search(r'<text[^>]*x="([-\d.]+)"[^>]*y="([-\d.]+)"', block)
        size = re.search(r'<tspan font-size="([\d.]+)px"', block)
        if pos:
            out.append((float(pos.group(1)), float(pos.group(2)),
                        float(size.group(1)) if size else None))
            continue
        glyph = re.search(r'translate\(([-\d.]+), ?([-\d.]+)\) '
                          r'scale\(([\d.]+),', block)
        if glyph:
            out.append((float(glyph.group(1)), float(glyph.group(2)),
                        float(glyph.group(3))))
    return out


UP_TENTHS = 12.0
RIGHT_TENTHS = 8.0
for kind, css, leaf in (("harm", "harm", False), ("dynamic", "dynam", True),
                        ("text", "dir", False), ("fermata", "fermata", True),
                        ("articulation", "artic", True)):
    plain_marks = anchors(engrave_marks(written(marked())), css, leaf)
    nudged_score = marked()
    ops.adjust_element(nudged_score, "#0", kind=kind, measure=3,
                       offset_x=RIGHT_TENTHS, offset_y=UP_TENTHS)
    nudged = anchors(engrave_marks(written(nudged_score)), css, leaf)
    if not plain_marks or len(plain_marks) != len(nudged):
        FAILURES.append(f"{kind}: engraved {len(plain_marks)} then {len(nudged)} "
                        "-- nothing to measure")
        continue
    before_x, before_y, before_size = plain_marks[0]
    after_x, after_y, after_size = nudged[0]
    if after_x <= before_x:
        FAILURES.append(
            f"{kind}: a positive relative-x did not move it RIGHT "
            f"({before_x} -> {after_x}) -- the renderer is not carrying @ho")
    if after_y >= before_y:
        # SVG y grows downwards, so up is a SMALLER y
        FAILURES.append(
            f"{kind}: a positive relative-y did not move it UP "
            f"({before_y} -> {after_y}) -- MusicXML and MEI both measure up, "
            "so a negated @vo sends the reader's 'up' arrow down")

    bigger_score = marked()
    ops.adjust_element(bigger_score, "#0", kind=kind, measure=3, scale=2.0)
    bigger = anchors(engrave_marks(written(bigger_score)), css, leaf)
    if not bigger or bigger[0][2] is None or before_size is None:
        FAILURES.append(f"{kind}: could not read the engraved size")
    elif bigger[0][2] <= before_size:
        FAILURES.append(
            f"{kind}: --scale 2 did not make it bigger "
            f"({before_size} -> {bigger[0][2]})")

# -- a word's size reaches the page too, by a different road ------------------
#
# A lyric is not sized the way the five above are. MusicXML has no font on a
# <lyric> -- the font belongs on the <text> inside it, which music21 neither
# writes nor reads -- so the size rides in the verse NAME, and Verovio carries
# that name onto the page as a labelAttr title. `apply_lyric_sizes` reads the
# page rather than the file and so needs no nth-element alignment, which is
# what a page break would break on a score with four hundred syllables.
def sung(word="la"):
    from music21 import harmony

    score = fixtures.jig(bars=4)
    bar = score.parts[0].measure(2)
    note = next(n for n in bar.notes if not isinstance(n, harmony.Harmony))
    note.lyric = word
    return score


def engrave_words(path):
    toolkit = verovio.toolkit()
    toolkit.setOptions({"scale": 45, "footer": "none", "adjustPageHeight": True,
                        "lyricSize": render.DEFAULT_LYRIC_SIZE})
    toolkit.loadFile(path)
    return render.apply_lyric_sizes(toolkit.renderToSVG(1))


def verse_sizes(svg):
    return [float(m) for block in re.findall(
                r'<g[^>]*class="verse">.*?</g>\s*</g>', svg, re.S)
            for m in re.findall(r'<tspan font-size="([\d.]+)px"', block)[:1]]


plain_words = verse_sizes(engrave_words(written(sung())))
bigger_score = sung()
ops.adjust_element(bigger_score, "#0", kind="lyric", measure=2, scale=2.0)
bigger_words = verse_sizes(engrave_words(written(bigger_score)))
if len(plain_words) != 1 or len(bigger_words) != 1:
    FAILURES.append(f"lyric: engraved {len(plain_words)} then "
                    f"{len(bigger_words)} verses -- nothing to measure")
elif bigger_words[0] <= plain_words[0]:
    FAILURES.append(f"lyric: --scale 2 did not make the word bigger "
                    f"({plain_words[0]} -> {bigger_words[0]})")

# And an offset is REFUSED rather than written into a file nothing honours.
try:
    ops.adjust_element(sung(), "#0", kind="lyric", measure=2, offset_y=8)
    FAILURES.append("lyric: an offset was accepted, and nothing draws one")
except ValueError as e:
    if "cannot be nudged" not in str(e):
        FAILURES.append(f"lyric: the offset refusal does not say why: {e}")

if FAILURES:
    print(f"FAIL: {len(FAILURES)} adjustment check(s) failed")
    for line in FAILURES:
        print("   ", line)
    sys.exit(1)
print("OK: size and position are written to the notation, survive the file, "
      "and reach the page -- right is right and up is up, for a chord symbol, "
      "a dynamic, a text mark, a fermata and an articulation alike; and a "
      "word grows by its verse name, or refuses the nudge nothing would draw")
