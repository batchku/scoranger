"""An imported score is titled, not named after its file (L18).

Ali's screenshot: the score's title read "sous-le-ciel-quartet" in the top bar
AND engraved at the top of the page. That is the file's name, twice.

CLAUDE.md names the trap: music21 seeds the movement title from the source FILE
NAME when the file carries no title, and Verovio engraves the movement title.
There was a guard for it, and it only caught a name with an EXTENSION still
attached -- "my-score.mxl". A stem on its own walked straight through.

Then it came back through the other door. `import` was guarded; ADDING A
VERSION FROM A FILE was not, and that is the OMR path: the app hands the engine
`v001.mxl`, named after the version it transcribed, and the arrangement the
reader had titled "Sous le ciel de Paris" was suddenly called "v001.mxl" in the
library and at the top of the page. So the last two sections here cover every
path that builds a version out of a file, not only the first import.

Run: engine/.venv/bin/python engine/scripts/check_import_title.py
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

    print("\nOMR: adding a version FROM A FILE does not rename the arrangement")
    # A scan, imported the way the app imports one: the title is the human
    # name, the artifact is a PDF, and the version is v001.
    from pypdf import PdfWriter
    pdf_writer = PdfWriter()
    pdf_writer.add_blank_page(width=612, height=792)
    scan_src = Path(workspace) / "sous-le-ciel-quartet.pdf"
    with open(scan_src, "wb") as f:
        pdf_writer.write(f)
    r = call("import-pdf", path=str(scan_src), name="sous-le-ciel-quartet")
    scan = (r.get("result") or {}).get("score")
    check("the scan imported", bool(scan), json.dumps(r)[:200])
    manifest = (call("manifest").get("result") or {})
    scan_doc = next((s for s in manifest.get("scores", []) if s["slug"] == scan), None)
    check("a scan's title is spelled out, not left as the file's stem",
          scan_doc is not None and scan_doc.get("title") == "Sous le ciel quartet",
          f"title is {(scan_doc or {}).get('title')!r}")

    # Now the OMR path: a file named after the VERSION it transcribed,
    # carrying no title of its own. This is the whole bug -- what came back
    # was called "v001.mxl", in the library and on the page.
    omr = stream.Score()
    omr_part = stream.Part()
    omr_part.partName = "Flute"
    for pitch in ("C4", "D4", "E4", "F4"):
        omr_part.append(note.Note(pitch, quarterLength=1.0))
    omr.append(omr_part)
    transcription = Path(workspace) / "v001.musicxml"
    omr.write("musicxml", fp=str(transcription))
    # Strip the title elements music21 writes for itself. OMR output has none
    # -- Audiveris read a page, not a header -- and a file with none is what
    # makes music21 seed the movement title from the FILE NAME. Written by
    # music21 and then cut down, because a fixture that keeps its own title
    # cannot show the bug at all.
    xml = transcription.read_text()
    xml = re.sub(r"\s*<work>.*?</work>", "", xml, flags=re.S)
    xml = re.sub(r"\s*<movement-title>.*?</movement-title>", "", xml, flags=re.S)
    transcription.write_text(xml)
    seeded = (converter.parse(str(transcription), forceSource=True)
              .metadata.movementName)
    check("the fixture reproduces the trap: music21 titles it after the file",
          seeded == "v001.musicxml", f"music21 seeded {seeded!r}")
    r = json.loads(bridge.handle(json.dumps({
        "op": "add-version-from-file",
        "args": {"score": scan, "path": str(transcription), "op": "omr"}})))
    check("the transcription became a version", bool((r.get("result") or {}).get("version")),
          json.dumps(r)[:200])

    manifest = (call("manifest").get("result") or {})
    after = next((s for s in manifest.get("scores", []) if s["slug"] == scan), None)
    check("the arrangement keeps its title after OMR",
          after is not None and after.get("title") == "Sous le ciel quartet",
          f"title is {(after or {}).get('title')!r}")

    r = call("export", score=scan, format="musicxml")
    path = (r.get("result") or {}).get("path")
    check("the transcription exported", bool(path), json.dumps(r)[:200])
    if path:
        text = Path(path).read_text()
        engraved = re.findall(r"<(?:work|movement)-title>(.*?)</(?:work|movement)-title>",
                              text, re.S)
        check("and the NOTATION carries it -- that is what engraves",
              all(t.strip() == "Sous le ciel quartet" for t in engraved) and engraved,
              f"titles are {engraved!r}")
        check("no file name reached the page",
              not any("v001" in t for t in engraved), f"titles are {engraved!r}")
        check("and no placeholder either",
              not any("music21" in t.casefold() for t in engraved),
              f"titles are {engraved!r}")

    print("\nand an arrangement with no title of its own takes the file's, if real")
    plain2 = stream.Score()
    p4 = stream.Part()
    p4.partName = "Flute"
    p4.append(note.Note("C4", quarterLength=4.0))
    plain2.append(p4)
    from music21 import metadata as m21meta2
    plain2.metadata = m21meta2.Metadata()
    plain2.metadata.title = "Autumn Leaves"
    named = Path(workspace) / "v002.mxl"
    plain2.write("musicxml", fp=str(named))
    for existing, incoming, stem, expected in [
        ("Sous le ciel de Paris", "v001.mxl", "v001", "Sous le ciel de Paris"),
        (None, "Autumn Leaves", "v002", "Autumn Leaves"),
        ("under-paris-skies", "v001.mxl", "v001", "Under paris skies"),
        (None, "v001.mxl", "v001", None),
    ]:
        got = ops.title_for_added_version(existing, incoming, stem)
        check(f"existing={existing!r} + file={incoming!r} -> {expected!r}",
              got == expected, f"got {got!r}")

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

    print("\nand a title already spoiled is not tidied into another one")
    check_a_poisoned_title_is_not_tidied_into_another_one()

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


def check_a_poisoned_title_is_not_tidied_into_another_one():
    """A title already spoiled before the fix must not be smartened up.

    The first version of this fix rejected `v001.mxl` and then humanised the
    same string on the way out, engraving "V001". The reader saw the bug it was
    meant to end, wearing different capitals. A rejected name does not improve
    by being tidied.
    """
    from scoranger_engine.ops import title_for_added_version as t
    cases = [
        (("v001.mxl", None), None, "a poisoned title with nothing to replace it"),
        (("v002.musicxml", None), None, "the same, another extension"),
        (("v001.mxl", "Jovano Jovanke"), "Jovano Jovanke", "a real incoming title wins"),
        (("Jovano Jovanke", "v001.mxl"), "Jovano Jovanke", "the arrangement's own wins"),
        ((None, None), None, "nothing in, nothing out"),
    ]
    for (existing, incoming), want, why in cases:
        got = t(existing, incoming)
        check(f"{why}: {existing!r} + {incoming!r} -> {got!r}", got == want,
              f"expected {want!r}")


if __name__ == "__main__":
    sys.exit(main())
