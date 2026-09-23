"""Regression check for staff spacing, and for the whistle fingering band.

Ali: "the app puts too much space above penny whistle tablatures, so scores
that have it end up fitting very few lines on a page." Measured before any of
this was written:

  - Verovio reserves one full lyric line per verse, six for a column's holes;
    the draw pass then packs the holes into 47.5% of that pitch
    (HOLE_PITCH_RATIO), so the top half of the band was empty.
  - `lyricSize` shrinks the band, and is the wrong lever: it is document-wide,
    so it also shrinks every chord symbol and compresses a guitar tab's six
    lines on the OTHER staff.
  - MusicXML's own <staff-layout>/<system-layout> are written by music21 and
    ignored by Verovio at every value.
  - `spacingStaff`/`spacingSystem` are MINIMUMS: they open space and cannot
    take back space the music claims.

So the band is fixed by reserving fewer lines (`render._pack_column`, the
pattern riding in the first verse's label, `_unpack_fingering_columns` putting
the rows back before the draw pass), and staves/systems by Verovio options
carried in a <miscellaneous-field>. What this holds:

  1. the op round-trips, refuses by name, writes nothing at the defaults, and
     survives the next op -- every version is written and read back;
  2. the band shrinks and the page count falls, AND every hole, every fill and
     every octave mark lands at exactly the same height above its own staff;
  3. nothing in the MEI changes but the whistle verses -- the tab, the words
     and every chord symbol are byte-identical;
  4. staff and system spacing reach the page, and are named in every option
     set so one score's spacing cannot leak into the next;
  5. both renderers agree -- the Swift constants are read out of the source,
     and a golden fragment (ios/ScorangerTests/Fixtures/fingering-packed-*)
     holds FingeringDiagrams.swift to the circles render.py draws.

Run: engine/.venv/bin/python engine/scripts/check_staff_spacing.py [--write]
     --write re-cuts the golden fragment after a deliberate change.
"""

import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "engine"))
sys.path.insert(0, str(ROOT / "engine" / "scripts"))

WORK = Path(tempfile.mkdtemp(prefix="spacing-check-"))
os.environ["SCORANGER_WORKSPACE"] = str(WORK / "ws")

import verovio  # noqa: E402
from music21 import converter  # noqa: E402

import fixtures  # noqa: E402
from scoranger_engine import ops, render, workspace  # noqa: E402

FAILURES: list[str] = []
SCOR = str(ROOT / "engine" / ".venv" / "bin" / "scor")
GOLDEN_IN = ROOT / "ios" / "ScorangerTests" / "Fixtures" / "fingering-packed-input.svg"
GOLDEN_OUT = ROOT / "ios" / "ScorangerTests" / "Fixtures" / "fingering-packed-golden.txt"


def check(label, ok, detail=""):
    print(f"    {'ok  ' if ok else 'FAIL'} {label}" + (f": {detail}" if detail and not ok else ""))
    if not ok:
        FAILURES.append(label + (f": {detail}" if detail else ""))


def scor(*args):
    out = subprocess.run([SCOR, *args], capture_output=True, text=True,
                         env={**os.environ})
    if out.returncode != 0:
        raise RuntimeError(out.stderr.strip() or out.stdout.strip())
    import json
    return json.loads(out.stdout)


# --- a whistle tune with a guitar tab under it, like Whiskey In A Jar ---------
ABC = """X:1
T:Spacing Check
M:4/4
L:1/8
K:D
"D"A2 FA d2 fd|"Bm"B2 GB e2 ge|"G"d2 Bd g2 bg|"D"f2 df a2 fa|
"D"A2 FA d2 fd|"Bm"B2 GB e2 ge|"G"d2 Bd g2 bg|"D"f2 df a2 fa|
"A"e2 ce a2 ea|"D"f2 df a2 fa|"G"d2 Bd g2 bg|"D"f2 df a4|
"""
tune = WORK / "tune.abc"
tune.write_text(ABC)
slug = scor("import", str(tune))["score"]
scor("pull-part", slug, "--from", "v001", "--part", "#0", "--as", "Acoustic Guitar")
scor("whistle-fingerings", slug, "--part", "#0")
scor("guitar-tab", slug, "--part", "#1")


def path():
    return str(workspace.resolve_notation_path(slug))


def engrave(rows=None, extra=None):
    """(pages, raw svgs, drawn svgs, mei) the way render_pdf engraves."""
    text = Path(path()).read_text(encoding="utf-8")
    spacing = render.spacing_from_musicxml(text)
    if rows is not None:
        spacing = {**spacing, "rows": rows}
    tk = verovio.toolkit()
    tk.setOptions({**render.page_options(), **render.spacing_options(spacing), **(extra or {})})
    tk.loadFile(path())
    mei = render.mei_with_fingerings_above(tk.getMEI(), rows=spacing["rows"])
    tk.loadData(mei)
    raw = [tk.renderToSVG(p) for p in range(1, tk.getPageCount() + 1)]
    drawn = [render._fingering_diagrams(s) for s in raw]
    return tk.getPageCount(), raw, drawn, mei


HOLE = re.compile(r'<path d="M (-?[\d.]+) (-?[\d.]+) A ([\d.]+) [\d.]+ 0 1 0 [^"]*"'
                  r'[^>]*fill="(currentColor|none)"')
LINE = re.compile(r'<path d="M(-?[\d.]+) (-?[\d.]+) L(-?[\d.]+) (-?[\d.]+)"')
OCT = re.compile(r'<text[^>]*\by="(-?[\d.]+)"[^>]*>(?:(?!</text>).)*?>\+</tspan>', re.S)


def marks_by_staff(svgs):
    """Every hole and octave mark, as a height above its OWN staff's top line."""
    holes, octaves = [], []
    for svg in svgs:
        for staff in re.split(r'(?=<g[^>]*class="staff")', svg)[1:]:
            flat = [float(m.group(2)) for m in LINE.finditer(staff) if m.group(2) == m.group(4)]
            if not flat:
                continue
            top = min(flat)
            holes += [(round(top - float(m.group(2))), round(float(m.group(3)), 1), m.group(4))
                      for m in HOLE.finditer(staff)]
            octaves += [round(top - float(y)) for y in OCT.findall(staff)]
    return holes, octaves


def first_system_height(svg):
    block = re.split(r'(?=<g[^>]*class="system")', svg)[1]
    ys = [float(y) for y in re.findall(r'[" ]y="(-?[\d.]+)"', block)]
    return round(max(ys) - min(ys))


# --- 1. the op ---------------------------------------------------------------
print("the op: round trip, refusals, nothing written at the defaults")

score = converter.parse(path(), forceSource=True)
report = ops.staff_spacing(score, staff=20, fingering_rows=5)
check("it reports what it set", report["staff"] == 20 and report["fingering_rows"] == 5
      and report["system"] == render.DEFAULT_SPACING_SYSTEM, str(report))
check("and says which values changed", report["changed"] == ["fingering_rows", "staff"],
      str(report["changed"]))
field = score.metadata.getCustom(render.SPACING_FIELD)
check("only the values that differ from the defaults are written",
      field and str(field[0]) == "staff=20;rows=5", str(field))

again = ops.staff_spacing(score, system=10)
check("a second call changes only what it names",
      again["staff"] == 20 and again["system"] == 10 and again["fingering_rows"] == 5,
      str(again))

back = ops.staff_spacing(score, reset=True)
check("reset puts every value back",
      (back["staff"], back["system"], back["fingering_rows"]) ==
      (render.DEFAULT_SPACING_STAFF, render.DEFAULT_SPACING_SYSTEM, render.DEFAULT_FINGERING_ROWS),
      str(back))
check("...and leaves no field behind", not score.metadata.getCustom(render.SPACING_FIELD),
      str(score.metadata.getCustom(render.SPACING_FIELD)))

for kwargs, words in (({"fingering_rows": 3}, "tightest a whistle column fits"),
                      ({"fingering_rows": 7}, "between 4 and 6"),
                      ({"staff": 99}, "between 0 and 48"),
                      ({"system": -1}, "between 0 and 48")):
    try:
        ops.staff_spacing(score, **kwargs)
        check(f"{kwargs} is refused", False)
    except ValueError as exc:
        check(f"{kwargs} is refused by name", words in str(exc), str(exc))

# through the binary, and across the NEXT op: every version is written and read back
scor("staff-spacing", slug, "--staff", "20", "--fingering-rows", "5")
scor("transpose", slug, "--interval", "M2")
scor("transpose", slug, "--interval=-M2")
kept = render.spacing_from_musicxml(Path(path()).read_text(encoding="utf-8"))
check("the spacing survives the ops that come after it",
      kept == {"staff": 20, "system": render.DEFAULT_SPACING_SYSTEM, "rows": 5}, str(kept))
scor("staff-spacing", slug, "--reset")
check("and a reset through the binary clears it",
      render.SPACING_FIELD not in Path(path()).read_text(encoding="utf-8"))

# --- 2. the band -------------------------------------------------------------
print("\nthe fingering band: smaller, with every hole where it was")

old_pages, _, old_drawn, old_mei = engrave(rows=6)
new_pages, new_raw, new_drawn, new_mei = engrave()        # the default, 3
check(f"the default reserves {render.DEFAULT_FINGERING_ROWS} rows, not 6",
      render.DEFAULT_FINGERING_ROWS == 4)
check(f"fewer pages: {old_pages} -> {new_pages}", new_pages < old_pages)
check(f"a shorter first system: {first_system_height(old_drawn[0])} -> "
      f"{first_system_height(new_drawn[0])}",
      first_system_height(new_drawn[0]) < first_system_height(old_drawn[0]))

(old_holes, old_oct), (new_holes, new_oct) = marks_by_staff(old_drawn), marks_by_staff(new_drawn)
check(f"every hole is still drawn: {len(old_holes)} -> {len(new_holes)}",
      len(old_holes) == len(new_holes) > 0)
check("with the same fill, the same radius, at the same height above its staff",
      old_holes == new_holes,
      f"first difference at {next((i for i, (a, b) in enumerate(zip(old_holes, new_holes)) if a != b), None)}")
check(f"every octave mark likewise: {len(old_oct)}", old_oct == new_oct and len(old_oct) > 0)
leftover = sum(len(re.findall(r'>[XO/]</tspan>', s)) for s in new_drawn)
check("no hole is left on the page as a letter", leftover == 0, f"{leftover} letters")

# --- 3. nothing else moved ---------------------------------------------------
print("\nnothing changes in the MEI but the whistle verses")

# ONE load, both transforms. Two separate loads are never byte-identical --
# Verovio mints fresh xml:ids, and the startid/plist references to them, every
# time -- so comparing two engraves would measure Verovio, not the transform.
tk = verovio.toolkit()
tk.setOptions(render.page_options())
tk.loadFile(path())
source_mei = tk.getMEI()
six = render.mei_with_fingerings_above(source_mei, rows=6)
three = render.mei_with_fingerings_above(source_mei, rows=render.DEFAULT_FINGERING_ROWS)
strip = lambda m: re.sub(r'<verse\b[^>]*label="wf[^"]*"[^>]*>.*?</verse>', "", m, flags=re.S)
check("tab, words, chord symbols and every note are byte-identical",
      strip(six) == strip(three))
others = lambda m: [v for v in render._MEI_VERSE_RE.findall(m) if 'label="wf' not in v]
check(f"including all {len(others(six))} tab verses",
      others(six) == others(three) and len(others(six)) > 0)
check("while the whistle verses DID change -- the band is what moved",
      six != three)

# --- 4. staves and systems reach the page ------------------------------------
print("\nstaff and system spacing reach the page, and never leak")

_, _, wide_drawn, _ = engrave(extra={"spacingStaff": 40, "spacingSystem": 40})
check(f"wider staves and systems make a taller system: "
      f"{first_system_height(new_drawn[0])} -> {first_system_height(wide_drawn[0])}",
      first_system_height(wide_drawn[0]) > first_system_height(new_drawn[0]))
opts = render.page_options()
check("the base option set names both, at the defaults",
      opts.get("spacingStaff") == render.DEFAULT_SPACING_STAFF
      and opts.get("spacingSystem") == render.DEFAULT_SPACING_SYSTEM, str(opts))

# --- 5. the two renderers agree ----------------------------------------------
print("\nthe two renderers agree")

swift = (ROOT / "ios/Scoranger/ScoreModel/StaffSpacing.swift").read_text()


def swift_value(name):
    m = re.search(rf"static let {name}\s*=\s*([^\s/]+)", swift)
    return m.group(1).strip('"') if m else None


check("the field name", swift_value("field") == render.SPACING_FIELD, str(swift_value("field")))
check("the default staff spacing", swift_value("defaultStaff") == str(render.DEFAULT_SPACING_STAFF))
check("the default system spacing", swift_value("defaultSystem") == str(render.DEFAULT_SPACING_SYSTEM))
check("the default fingering rows", swift_value("defaultRows") == str(render.DEFAULT_FINGERING_ROWS))
lo, hi = render.FINGERING_ROWS_RANGE
check("the fingering rows range", swift_value("rowsRange") == f"{lo}...{hi}", str(swift_value("rowsRange")))
lo, hi = render.SPACING_RANGE
check("the spacing range", swift_value("spacingRange") == f"{lo}...{hi}", str(swift_value("spacingRange")))
engraving = (ROOT / "ios/Scoranger/ScoreModel/EngravingOptions.swift").read_text()
check("EngravingOptions names both spacing keys in every option set",
      '"spacingStaff": \\(spacing.staff)' in engraving and '"spacingSystem": \\(spacing.system)' in engraving)
fingering = (ROOT / "ios/Scoranger/FingeringDiagrams.swift").read_text()
check("FingeringDiagrams packs with the same prefix",
      'static let packedPrefix = tag + "|"' in fingering and render.PACKED_PREFIX == "wf|")

# The golden fragment: the packed page Verovio drew, and the circles render.py
# drew from it. FingeringDiagramTests feeds the SAME page through
# FingeringDiagrams.draw and must get the same circles.
page = new_raw[0]
circles = [f"{float(m.group(1)):.3f}|{float(m.group(2)):.3f}|{float(m.group(3)):.3f}|{m.group(4)}"
           for m in HOLE.finditer(new_drawn[0])]
golden = "\n".join(circles) + "\n"
if "--write" in sys.argv:
    GOLDEN_IN.write_text(page, encoding="utf-8")
    GOLDEN_OUT.write_text(golden, encoding="utf-8")
    print(f"    wrote {GOLDEN_IN.name} and {GOLDEN_OUT.name} ({len(circles)} circles)")
check("the golden page carries packed columns", render.PACKED_PREFIX in
      (GOLDEN_IN.read_text(encoding="utf-8") if GOLDEN_IN.exists() else ""))
if GOLDEN_IN.exists() and GOLDEN_OUT.exists():
    have = [f"{float(m.group(1)):.3f}|{float(m.group(2)):.3f}|{float(m.group(3)):.3f}|{m.group(4)}"
            for m in HOLE.finditer(render._fingering_diagrams(GOLDEN_IN.read_text(encoding="utf-8")))]
    check(f"the golden circles are what render.py draws from the golden page ({len(have)})",
          "\n".join(have) + "\n" == GOLDEN_OUT.read_text(encoding="utf-8"))
else:
    check("the golden fragment exists -- run with --write", False)

shutil.rmtree(WORK, ignore_errors=True)
if FAILURES:
    print(f"\nFAIL: {len(FAILURES)} spacing check(s) failed")
    for line in FAILURES:
        print("   ", line)
    sys.exit(1)
print("\nOK: the whistle band is smaller, every hole is where it was, and both renderers agree")
