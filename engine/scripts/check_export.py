"""Regression check for exporting a score out of the app.

The engine CLI has had `scor export` since the prototype, but that is the
LAPTOP path. On device the app talks to `bridge.py`, and until this check was
written `bridge.py` had no export op at all -- so the score's "Share & export"
row led to a screen that said exporting happens in the engine, which the user
of an iPad cannot reach. This checks the op the app actually calls.

Three formats, three different sources, which is the thing worth remembering:

  - **MusicXML** is already a file on disk. A version artifact IS MusicXML, so
    exporting one is resolving a path, not re-serialising. Re-writing it
    through music21 would risk changing bytes the user never asked to change.
  - **MIDI** is a real conversion and goes through music21 here.
  - **PDF is NOT in this file.** It cannot be: `render.py` is not vendored into
    the app, and the on-device engraver is Swift (VerovioRenderer). That split
    matters because chord-symbol adjustments and whistle fingerings are applied
    in the SWIFT render pass -- so a PDF built any other way would not match
    the page the user is looking at. The Swift side owns PDF; this file asserts
    the two formats the bridge owns, and asserts that asking the bridge for a
    PDF fails loudly rather than silently returning something wrong.

Run: engine/.venv/bin/python engine/scripts/check_export.py
"""

import json
import os
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
    workspace = tempfile.mkdtemp(prefix="scoranger-export-")
    os.environ["SCORANGER_WORKSPACE"] = workspace

    import bridge
    from music21 import converter, note, stream

    def call(op, **args):
        raw = bridge.handle(json.dumps({"op": op, "args": args}))
        return json.loads(raw)

    # a small real score, imported the way the app imports one
    src = stream.Score()
    part = stream.Part()
    part.partName = "Flute"
    for name in ("C4", "D4", "E4", "F4", "G4", "A4", "B4", "C5"):
        part.append(note.Note(name, quarterLength=1.0))
    src.append(part)
    seed = Path(workspace) / "seed.musicxml"
    src.write("musicxml", fp=str(seed))

    print("importing a score")
    r = call("import", path=str(seed), name="Export Test")
    check("import succeeded", r.get("ok") is True, json.dumps(r)[:200])
    slug = (r.get("result") or {}).get("score")
    check("import returned a slug", bool(slug))
    if not slug:
        return 1

    print("\nexport musicxml")
    r = call("export", score=slug, format="musicxml")
    check("bridge knows the export op", r.get("ok") is True, str(r.get("error"))[:200])
    out = (r.get("result") or {})
    path = out.get("path")
    check("returns a path", bool(path), json.dumps(out)[:200])
    if path:
        p = Path(path)
        check("the file exists", p.exists(), path)
        check("it is musicxml", p.suffix == ".musicxml", p.suffix)
        # The artifact IS the export: resolving, not re-serialising.
        parsed = converter.parse(str(p), forceSource=True)
        check("it parses back to 8 notes",
              len(parsed.flatten().notes) == 8, str(len(parsed.flatten().notes)))
        check("a suggested filename comes with it", bool(out.get("filename")),
              json.dumps(out)[:200])

    print("\nexport midi")
    r = call("export", score=slug, format="midi")
    check("midi export succeeded", r.get("ok") is True, str(r.get("error"))[:200])
    out = (r.get("result") or {})
    mp = out.get("path")
    check("returns a midi path", bool(mp), json.dumps(out)[:200])
    if mp:
        p = Path(mp)
        check("the midi file exists", p.exists(), mp)
        check("it is a .mid", p.suffix == ".mid", p.suffix)
        head = p.read_bytes()[:4]
        check("it starts with MThd", head == b"MThd", str(head))
        parsed = converter.parse(str(p), forceSource=True)
        check("the midi round-trips to 8 notes",
              len(parsed.flatten().notes) == 8, str(len(parsed.flatten().notes)))

    print("\nexporting one part only")
    r = call("export", score=slug, format="musicxml", parts="Flute")
    check("parts filter is accepted", r.get("ok") is True, str(r.get("error"))[:200])

    print("\npdf is the Swift renderer's job, and the bridge says so")
    r = call("export", score=slug, format="pdf")
    check("asking the bridge for a pdf fails loudly", r.get("ok") is not True,
          "the bridge answered a PDF request it cannot honour correctly")
    msg = str(r.get("error", ""))
    check("and the error names the reason", "render" in msg.lower() or "swift" in msg.lower()
          or "device" in msg.lower(), msg[:200])

    print("\nan unknown format is refused")
    r = call("export", score=slug, format="banjo")
    check("unknown format refused", r.get("ok") is not True, json.dumps(r)[:200])

    print("\nexporting a named version, not just the latest")
    r = call("transpose", score=slug, interval="M2")
    check("made a second version", r.get("ok") is True, str(r.get("error"))[:200])
    r = call("export", score=slug, format="musicxml", version="v001")
    check("v001 exports", r.get("ok") is True, str(r.get("error"))[:200])
    p1 = (r.get("result") or {}).get("path")
    if p1:
        parsed = converter.parse(str(p1), forceSource=True)
        first = parsed.flatten().notes[0].pitch.nameWithOctave
        check("v001 is the ORIGINAL pitch, not the transposed one",
              first == "C4", f"got {first} -- export ignored the version argument")

    print()
    if FAILURES:
        print(f"FAILED: {len(FAILURES)}")
        for f in FAILURES:
            print(f"  - {f}")
        return 1
    print("OK: a score exports to MusicXML and MIDI on device, by version and "
          "by part, and the bridge refuses PDF rather than faking it")
    return 0


if __name__ == "__main__":
    sys.exit(main())
