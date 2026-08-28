"""An imported score is titled, not named after its file (L18).

Ali's screenshot: the score's title read "sous-le-ciel-quartet" in the top bar
AND engraved at the top of the page. That is the file's name, twice.

CLAUDE.md names the trap: music21 seeds the movement title from the source FILE
NAME when the file carries no title, and Verovio engraves the movement title.
There was a guard for it, and it only caught a name with an EXTENSION still
attached -- "my-score.mxl". A stem on its own walked straight through.

Run: engine/.venv/bin/python engine/scripts/check_import_title.py
"""

import json
import os
import re
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "engine"))
sys.path.insert(0, str(ROOT / "ios" / "PythonApp" / "app"))

FAILURES: list[str] = []


def check(label: str, ok: bool, detail: str = "") -> None:
    if ok:
        print(f"  ok   {label}")
    else:
        FAILURES.append(f"{label}{': ' + detail if detail else ''}")
        print(f"  FAIL {label}{': ' + detail if detail else ''}")


def main() -> int:
    workspace = tempfile.mkdtemp(prefix="scoranger-title-")
    os.environ["SCORANGER_WORKSPACE"] = workspace

    import bridge
    from music21 import note, stream
    from scoranger_engine import ops

    def call(op, **args):
        return json.loads(bridge.handle(json.dumps({"op": op, "args": args})))

    # A file with NO title of its own, named the way an export names things.
    score = stream.Score()
    part = stream.Part()
    part.partName = "Flute"
    for pitch in ("C4", "D4", "E4", "F4"):
        part.append(note.Note(pitch, quarterLength=1.0))
    score.append(part)
    src = Path(workspace) / "sous-le-ciel-quartet.musicxml"
    score.write("musicxml", fp=str(src))

    print("what music21 does with a file that has no title")
    from music21 import converter
    reparsed = converter.parse(str(src), forceSource=True)
    seeded = (reparsed.metadata.movementName if reparsed.metadata else None) or ""
    print(f"       music21 seeded the movement title as {seeded!r}")

    print("\nimporting it under a human name, through the app's bridge")
    r = call("import", path=str(src), name="Sous le ciel de Paris")
    slug = (r.get("result") or {}).get("score")
    check("it imported", bool(slug), json.dumps(r)[:200])
    if not slug:
        return 1

    manifest = (call("manifest").get("result") or {})
    doc = next((s for s in manifest.get("scores", []) if s["slug"] == slug), None)
    check("the library has a score document", doc is not None)
    if doc:
        check("the library title is the human name, not the file stem",
              doc.get("title") == "Sous le ciel de Paris",
              f"title is {doc.get('title')!r}")
        check("and its name too", doc.get("name") == "Sous le ciel de Paris",
              f"name is {doc.get('name')!r}")

    print("\nand the NOTATION carries it, which is what engraves")
    r = call("export", score=slug, format="musicxml")
    path = (r.get("result") or {}).get("path")
    check("exported", bool(path), json.dumps(r)[:200])
    if path:
        text = Path(path).read_text()
        for tag in ("work-title", "movement-title"):
            found = re.search(rf"<{tag}>(.*?)</{tag}>", text, re.S)
            check(f"<{tag}> is the human title",
                  bool(found) and found.group(1).strip() == "Sous le ciel de Paris",
                  f"{tag} is {found.group(1) if found else 'absent'!r}")
        check("the file stem is nowhere in the notation's titles",
              "sous-le-ciel-quartet" not in
              " ".join(re.findall(r"<(?:work|movement)-title>(.*?)</(?:work|movement)-title>",
                                  text, re.S)))

    print("\na real title in the file is KEPT, not overwritten by the import name")
    titled = stream.Score()
    p2 = stream.Part()
    p2.partName = "Flute"
    p2.append(note.Note("C4", quarterLength=4.0))
    titled.append(p2)
    from music21 import metadata as m21metadata
    titled.metadata = m21metadata.Metadata()
    titled.metadata.title = "Blue Bossa"
    titled_src = Path(workspace) / "whatever-the-file-is-called.musicxml"
    titled.write("musicxml", fp=str(titled_src))
    r = call("import", path=str(titled_src), name="whatever-the-file-is-called")
    slug2 = (r.get("result") or {}).get("score")
    manifest = (call("manifest").get("result") or {})
    doc2 = next((s for s in manifest.get("scores", []) if s["slug"] == slug2), None)
    check("the score's own title wins", doc2 is not None and doc2.get("title") == "Blue Bossa",
          f"title is {(doc2 or {}).get('title')!r}")

    print("\nimported under a name that is itself a file stem")
    plain = stream.Score()
    p3 = stream.Part()
    p3.partName = "Flute"
    p3.append(note.Note("C4", quarterLength=4.0))
    plain.append(p3)
    plain_src = Path(workspace) / "under-paris-skies-solo.musicxml"
    plain.write("musicxml", fp=str(plain_src))
    r = call("import", path=str(plain_src), name="under-paris-skies-solo")
    slug3 = (r.get("result") or {}).get("score")
    manifest = (call("manifest").get("result") or {})
    doc3 = next((s for s in manifest.get("scores", []) if s["slug"] == slug3), None)
    check("a slug-shaped name is spelled out rather than engraved as a slug",
          doc3 is not None and doc3.get("title") == "Under paris skies solo",
          f"title is {(doc3 or {}).get('title')!r}")
    r = call("export", score=slug3, format="musicxml")
    if (r.get("result") or {}).get("path"):
        text3 = Path(r["result"]["path"]).read_text()
        check("and the notation carries the spelled-out title",
              "under-paris-skies-solo" not in
              " ".join(re.findall(r"<(?:work|movement)-title>(.*?)</(?:work|movement)-title>",
                                  text3, re.S)))

    print("\nand the rule itself, on the strings it has to tell apart")
    for text, stem, expected in [
        ("my-score.mxl", None, True),
        ("sous-le-ciel-quartet", None, True),
        ("under_paris_skies", None, True),
        ("quartet", "quartet", True),
        ("Nocturne", None, False),
        ("Sous le ciel de Paris", None, False),
        ("Jean-Pierre Rampal suite", None, False),
        # music21's own placeholder, which is what it writes when the file
        # carries no title at all -- and which then engraves
        ("Music21 Fragment", None, True),
        ("Untitled", None, True),
    ]:
        got = ops._is_junk_title(text, stem)
        check(f"{text!r} is {'a file name' if expected else 'a title'}", got == expected,
              f"got {got}")

    print()
    if FAILURES:
        print(f"FAILED: {len(FAILURES)}")
        for f in FAILURES:
            print(f"  - {f}")
        return 1
    print("OK: an imported score is titled by its own notation or by the name it "
          "was imported under -- never by the file it came out of, in the "
          "library or on the page")
    return 0


if __name__ == "__main__":
    sys.exit(main())
