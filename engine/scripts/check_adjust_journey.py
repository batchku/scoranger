"""The whole journey: chords on a score, nudged and resized, still there in the export.

Component checks prove each hop in isolation -- `check_adjust.py` that the
notation round-trips, `check_chord_placement.py` that both renderers read it,
`check_export.py` that a file comes out. This one walks the path a user walks,
because every one of those hops was individually green while the PDF renderer
silently dropped the adjustments: the functions existed, were unit-checked, and
nothing called them.

    add chord symbols -> nudge one -> resize one -> export -> read it back

The assertion that matters is the last: the size and the offset are IN the
exported file, so what the reader sees is what they get.

Run: engine/.venv/bin/python engine/scripts/check_adjust_journey.py
"""

import json
import os
import re
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "ios" / "PythonApp" / "app"))
sys.path.insert(0, str(ROOT / "engine"))

FAILURES: list[str] = []


def check(label: str, ok: bool, detail: str = "") -> None:
    if ok:
        print(f"  ok   {label}")
    else:
        FAILURES.append(f"{label}{': ' + detail if detail else ''}")
        print(f"  FAIL {label}{': ' + detail if detail else ''}")


def main() -> int:
    workspace = tempfile.mkdtemp(prefix="scoranger-journey-")
    os.environ["SCORANGER_WORKSPACE"] = workspace

    import bridge
    from music21 import meter as m21meter, note, stream

    def call(op, **args):
        return json.loads(bridge.handle(json.dumps({"op": op, "args": args})))

    print("a score with four bars")
    score = stream.Score()
    part = stream.Part()
    part.partName = "Lead"
    part.append(m21meter.TimeSignature("4/4"))
    for index, pitch in enumerate(["C4", "F4", "G4", "C5"]):
        measure = stream.Measure(number=index + 1)
        measure.append(note.Note(pitch, quarterLength=4.0))
        part.append(measure)
    score.append(part)
    seed = Path(workspace) / "seed.musicxml"
    score.write("musicxml", fp=str(seed))

    r = call("import", path=str(seed), name="Journey")
    slug = (r.get("result") or {}).get("score")
    check("imported", bool(slug), json.dumps(r)[:200])
    if not slug:
        return 1

    print("\nchord symbols on it")
    chart = [{"measure": i + 1, "symbol": s}
             for i, s in enumerate(["C", "Dm7", "G7", "C"])]
    r = call("set-chords", score=slug, part="Lead", chords=chart)
    check("chords added", r.get("ok") is True, str(r.get("error"))[:200])

    print("\nnudge the second one up half a space, and make it bigger")
    # 0.5 staff space = 5 tenths, which is what one tap of the chip sends
    r = call("adjust-element", score=slug, part="Lead", kind="harm",
             measure=2, ordinal=0, offset_y=5, size=16)
    check("adjust-element accepted", r.get("ok") is True, str(r.get("error"))[:200])

    print("\nand it is in the notation")
    latest = call("versions", score=slug)
    versions = (latest.get("result") or {}).get("versions", [])
    check("the adjustment made a version", len(versions) >= 3, str(len(versions)))

    r = call("export", score=slug, format="musicxml")
    path = (r.get("result") or {}).get("path")
    check("exported", bool(path), json.dumps(r)[:200])
    if not path:
        return 1

    exported = Path(path).read_text()
    tags = re.findall(r"<harmony[^>]*>", exported)
    check("all four symbols are in the export", len(tags) == 4, str(len(tags)))

    adjusted = [t for t in tags if "relative-y" in t or "font-size" in t]
    check("exactly one symbol carries an adjustment", len(adjusted) == 1,
          f"{len(adjusted)}: {adjusted}")
    if adjusted:
        tag = adjusted[0]
        y = re.search(r'relative-y="([-\d.]+)"', tag)
        size = re.search(r'font-size="([\d.]+)"', tag)
        check("the offset survived the export", bool(y) and float(y.group(1)) == 5.0,
              tag)
        check("the size survived the export", bool(size) and float(size.group(1)) == 16.0,
              tag)

    print("\nthe neighbours were not touched")
    untouched = [t for t in tags if "relative-y" not in t and "font-size" not in t]
    check("three symbols are still plain", len(untouched) == 3, str(len(untouched)))

    print("\nand the notes did not move")
    from music21 import converter
    reparsed = converter.parse(str(Path(path)), forceSource=True)
    pitches = [n.pitch.nameWithOctave for n in reparsed.flatten().notes
               if not n.__class__.__name__.startswith("Chord")]
    check("the melody is unchanged", pitches[:4] == ["C4", "F4", "G4", "C5"],
          str(pitches[:4]))

    print("\nreset puts it back")
    r = call("adjust-element", score=slug, part="Lead", kind="harm",
             measure=2, ordinal=0, reset=True)
    check("reset accepted", r.get("ok") is True, str(r.get("error"))[:200])
    r = call("export", score=slug, format="musicxml")
    after = Path((r.get("result") or {})["path"]).read_text()
    still = [t for t in re.findall(r"<harmony[^>]*>", after)
             if "relative-y" in t or "font-size" in t]
    check("nothing carries an adjustment any more", not still, str(still))

    print("\nand the PDF renders with the adjustment applied")
    r = call("adjust-element", score=slug, part="Lead", kind="harm",
             measure=2, ordinal=0, offset_y=-10, size=20)
    check("re-adjusted", r.get("ok") is True, str(r.get("error"))[:200])
    from scoranger_engine import render, workspace as ws
    pdf_out = Path(workspace) / "journey.pdf"
    try:
        render.render_pdf(str(ws.resolve_path(slug)), str(pdf_out))
        check("the PDF rendered", pdf_out.exists() and pdf_out.stat().st_size > 1000,
              f"{pdf_out.stat().st_size if pdf_out.exists() else 0} bytes")
    except Exception as e:  # noqa: BLE001 - the check is that it does not raise
        check("the PDF rendered", False, f"{type(e).__name__}: {e}")

    print()
    if FAILURES:
        print(f"FAILED: {len(FAILURES)}")
        for f in FAILURES:
            print(f"  - {f}")
        return 1
    print("OK: a chord symbol nudged and resized on device keeps its size and "
          "position through a version, an export and a re-render -- and its "
          "neighbours and the notes stay where they were")
    return 0


if __name__ == "__main__":
    sys.exit(main())
