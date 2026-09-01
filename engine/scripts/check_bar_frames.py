#!/usr/bin/env python3
"""Prove the bar-frame join: the frame for measure N IS the Nth bar.

The playhead is placed by asking the timeline which MEASURE is sounding and
how far through it, then asking the geometry where that measure is. That design
exists so playback time never has to be converted to an x -- repeats make that
many-to-one and it desyncs silently. But it moves the whole weight of the
feature onto one assumption nobody had tested: **that the rectangle the
geometry reports for measure N is the bar the reader sees as measure N.**

It was not. Measured on the scanned quartet, the playhead sat in the THIRD
drawn bar while the transport correctly said bar 1.

The cause is not the numbering. Verovio's MEI `@n` and music21's measure
numbers agree exactly on that score, 136 measures, 1..136 -- that was the first
guess and it was wrong. The cause is the FRAME. Verovio nests a spanner inside
the measure where it STARTS:

    <measure n="1"> <staff/>x4 <dynam/>x3 <slur startid=.. endid=..(measure 4)/>

and `SVGGeometryParser` gives every group the union of everything drawn inside
it, which is the right rule for a note (bounding its notehead, stem, dots and
accidental) and the wrong one for a bar. A cello slur running from measure 1
into measure 4 makes measure 1's rectangle four bars wide, and a cursor asked
to stand a third of the way through it lands two bars late.

The left edge is sound -- a spanner is a child of the measure it starts in, so
nothing is drawn left of the barline -- so the fix takes each bar's right edge
from where the NEXT bar begins. `BarPosition.clippedToNeighbours` does it, and
this asserts the property that fix must hold: **consecutive bars on a system do
not overlap.**

This mirrors SVGGeometryParser's union rule in Python rather than testing the
resolver against itself, the same way check_addresses.py mirrors the MEI parser.
The bbox arithmetic here is approximate; the defect it catches is bars OVERLAPPING
BY WHOLE BARS, which no amount of approximation error could invent.

Run: engine/.venv/bin/python engine/scripts/check_bar_frames.py
"""
import re
import sys
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "ios" / "PythonApp" / "app"))
sys.path.insert(0, str(ROOT / "engine" / "scripts"))
sys.path.insert(0, str(ROOT / "engine"))

FAILURES: list[str] = []
NUMBER = re.compile(r"-?\d+\.?\d*(?:e-?\d+)?")


def check(label: str, ok: bool, detail: str = "") -> None:
    if ok:
        print(f"  ok   {label}")
    else:
        FAILURES.append(f"{label}{': ' + detail if detail else ''}")
        print(f"  FAIL {label}{': ' + detail if detail else ''}")


def _x_range(element) -> tuple[float, float] | None:
    """The horizontal extent of one drawn thing, in SVG user units.

    Mirrors what SVGGeometryParser unions: glyph placements (`<use x=>`), path
    geometry, and rects. Coarse on purpose -- this is here to catch a bar that
    is three bars wide.
    """
    tag = element.tag.split("}")[-1]
    if tag == "use" and element.get("x") is not None:
        x = float(element.get("x"))
        return (x, x)
    if tag == "path" and element.get("d"):
        # Verovio writes absolute commands, so every other number is an x.
        values = [float(v) for v in NUMBER.findall(element.get("d"))]
        xs = values[0::2]
        return (min(xs), max(xs)) if xs else None
    if tag == "rect" and element.get("x") is not None:
        x = float(element.get("x"))
        return (x, x + float(element.get("width") or 0))
    return None


def _group_range(group) -> tuple[float, float] | None:
    """A group's frame is the union of everything drawn inside it."""
    lows, highs = [], []
    for node in group.iter():
        span = _x_range(node)
        if span:
            lows.append(span[0])
            highs.append(span[1])
    return (min(lows), max(highs)) if lows else None


def _system_of(group) -> str:
    """Which system a measure is on, so bars are only compared with their
    neighbours. Read from the enclosing <g class="system"> id."""
    return group.get("data-system", "")


def measures_from_svg(svg: str) -> list[dict]:
    root = ET.fromstring(svg)
    out = []
    for system_index, system in enumerate(
            g for g in root.iter() if "system" in (g.get("class") or "").split()):
        for group in (g for g in system.iter()
                      if "measure" in (g.get("class") or "").split()):
            span = _group_range(group)
            if not span:
                continue
            # the notes actually inside this bar, for the containment assertion
            notes = []
            for note in (n for n in group.iter()
                         if "note" in (n.get("class") or "").split()):
                place = _group_range(note)
                if place:
                    notes.append(place[0])
            out.append({"id": group.get("id"), "system": system_index,
                        "min": span[0], "max": span[1], "notes": notes})
    return out


def main() -> int:
    from music21 import converter
    from scoranger_engine import render
    import fixtures

    sources = [("a quartet with slurs running between bars",
                ROOT / "testdata/app-samples/sous-le-ciel-quartet.mxl"),
               ("a built fixture", None)]

    for label, path in sources:
        print(f"\n{label}")
        if path is None:
            score = fixtures.quartet(bars=8)
        elif not path.exists():
            print(f"  --   skipped, {path.name} is not in this checkout")
            continue
        else:
            score = converter.parse(str(path), forceSource=True)

        with tempfile.NamedTemporaryFile(suffix=".musicxml", delete=False) as f:
            score.write("musicxml", fp=f.name)
            xml = Path(f.name).read_text()
        tk = render._toolkit()
        if not tk.loadData(xml):
            check("Verovio engraved it", False, "loadData refused")
            continue
        tk.setOptions(render.page_options())
        tk.redoLayout()
        svg = tk.renderToSVG(1)

        bars = measures_from_svg(svg)
        check("the page has bars", len(bars) > 1, str(len(bars)))
        if len(bars) < 2:
            continue

        # Verovio's RAW frames overlap, and that is not a bug in Verovio: a
        # slur belongs to the measure it starts in, and a group's frame is the
        # union of what it contains. It is only wrong as a BAR rectangle.
        raw_overlaps = []
        for first, second in zip(bars, bars[1:]):
            if first["system"] != second["system"]:
                continue
            if first["max"] > second["min"] + 1.0:
                overrun = first["max"] - second["min"]
                width = max(second["min"] - first["min"], 1.0)
                raw_overlaps.append((first["id"], overrun / width))

        # The clip the app applies: BarPosition.clippedToNeighbours. The LEFT
        # edge is trustworthy, so each bar's right edge is taken from where the
        # next bar on the same system begins.
        clipped = []
        for index, bar in enumerate(bars):
            nexts = [other["min"] for other in bars[index + 1:]
                     if other["system"] == bar["system"]
                     and other["min"] > bar["min"] + 0.5]
            edge = min(nexts) if nexts else bar["max"]
            clipped.append({**bar, "max": min(bar["max"], edge)})

        check("after the clip, no bar reaches into the bar after it",
              all(first["max"] <= second["min"] + 1.0
                  for first, second in zip(clipped, clipped[1:])
                  if first["system"] == second["system"]),
              "the clip did not separate them")

        # THE ASSERTION the playhead rests on: the span used for measure N
        # holds measure N's own notes and none of measure N+1's. This is what
        # "the frame for measure N IS the Nth bar" means operationally.
        wrong = []
        for index, bar in enumerate(clipped):
            for x in bar["notes"]:
                if not (bar["min"] - 1.0 <= x <= bar["max"] + 1.0):
                    wrong.append(f"{bar['id']} does not contain its own note at {x:.0f}")
            if index + 1 < len(clipped) and clipped[index + 1]["system"] == bar["system"]:
                for x in clipped[index + 1]["notes"]:
                    if bar["min"] <= x <= bar["max"] - 1.0:
                        wrong.append(f"{bar['id']} swallows a note of the next bar")
        check("the span for measure N holds measure N's notes and no others",
              not wrong, "; ".join(sorted(set(wrong))[:4]))

        # And the clip is LOAD-BEARING, said out loud rather than assumed: on
        # material with cross-bar spanners the unclipped frames fail the very
        # assertion above, which is why this check exists at all.
        if raw_overlaps:
            worst = max(raw_overlaps, key=lambda pair: pair[1])
            print(f"       (unclipped, {len(raw_overlaps)} bars overlap their "
                  f"neighbour; worst {worst[0]} by {worst[1]:.1f} bars -- "
                  f"this is what the clip removes)")
            swallowed = any(
                bar["min"] <= x <= bar["max"] - 1.0
                for index, bar in enumerate(bars[:-1])
                if bars[index + 1]["system"] == bar["system"]
                for x in bars[index + 1]["notes"])
            check("and without the clip this material really would misplace a cursor",
                  swallowed,
                  "expected the raw frames to swallow a neighbour's notes")

    print()
    if FAILURES:
        print(f"FAILED: {len(FAILURES)}")
        for failure in FAILURES:
            print(f"  - {failure}")
        return 1
    print("OK: the rectangle the geometry reports for measure N is the bar the "
          "reader sees as measure N, so a playhead placed by (measure, beat) "
          "lands in the bar it names")
    return 0


if __name__ == "__main__":
    sys.exit(main())
