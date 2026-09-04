"""A title already engraved wrong is repairable, and repaired the legitimate way.

The reported bug, twice: "v001.mxl" at the top of the page. `check_import_title`
covers the way IN -- no version written from now on can carry a file name. It
says nothing about the versions already on disk, and that is where the reader's
library lives: forty pieces OMR'd before any of this existed, each with the file
name written into its notation. Nothing re-runs the title logic over a file that
has been written, so a fix at the door leaves every one of them exactly as it
was.

So this check starts from the damage rather than from an import: it builds a
version the OLD code would have produced -- the movement title set to
"v001.mxl" -- and then asserts the repair

  - finds it, and proposes the arrangement's own name;
  - does nothing at all until asked (the scan is separate from the write);
  - fixes it by ADDING a version, leaving the poisoned one byte-for-byte
    where it was, because versions are immutable;
  - puts the corrected title in the NOTATION, which is what engraves;
  - finds nothing the second time, so an offer derived from this scan
    disappears once the work is done;
  - and leaves a healthy arrangement, and a scan with no notation, alone.

Run: engine/.venv/bin/python engine/scripts/check_title_repair.py
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


def _tune(title: str | None = None):
    """A few bars of something, optionally titled."""
    from music21 import metadata as m21metadata
    from music21 import note, stream

    score = stream.Score()
    part = stream.Part()
    part.partName = "Flute"
    for pitch in ("C4", "D4", "E4", "F4"):
        part.append(note.Note(pitch, quarterLength=1.0))
    score.append(part)
    if title is not None:
        score.metadata = m21metadata.Metadata()
        score.metadata.title = title
        score.metadata.movementName = title
    return score


def _engraved_titles(path: Path) -> list[str]:
    """The titles in a MusicXML file -- what Verovio puts at the top."""
    return [t.strip() for t in re.findall(
        r"<(?:work|movement)-title>(.*?)</(?:work|movement)-title>",
        path.read_text(), re.S)]


def main() -> int:
    ws = tempfile.mkdtemp(prefix="scoranger-repair-")
    os.environ["SCORANGER_WORKSPACE"] = ws

    from scoranger_engine import ops, workspace

    # the module caches its workspace root at import, and this check sets one
    workspace.WORKSPACE = Path(ws)

    print("the rule, on the strings it has to tell apart")
    for stored, name, piece, expected, why in [
        ("v001.mxl", "Jovano Jovanke", None, "Jovano Jovanke",
         "the poisoned title the reader photographed"),
        ("V001", "Jovano Jovanke", None, "Jovano Jovanke",
         "the same bug wearing the capitals the first fix gave it"),
        ("v002.musicxml", "Jovano Jovanke", None, "Jovano Jovanke",
         "another extension"),
        ("Jovano Jovanke", "Jovano Jovanke", None, None,
         "a real title is left alone"),
        ("Jean-Pierre Rampal suite", "whatever", None, None,
         "a real title with a hyphen in it is still a real title"),
        ("v001.mxl", "under-paris-skies", None, "Under paris skies",
         "a slug-shaped NAME is spelled out, never engraved as a slug"),
        ("under-paris-skies", "under-paris-skies", None, "Under paris skies",
         "a title that is a file stem is the same defect"),
        ("v001.mxl", None, "Jovano Jovanke", "Jovano Jovanke",
         "with no name of its own, the piece can say it"),
        ("v001.mxl", "v001", None, None,
         "and when nothing anywhere is a name, nothing is invented"),
        ("Music21 Fragment", "Blue Bossa", None, "Blue Bossa",
         "music21's own placeholder is not a title either"),
    ]:
        got = ops.title_repair(stored, name, piece)
        check(f"{why}: {stored!r} -> {got!r}", got == expected, f"expected {expected!r}")

    print("\nbuilding the library the reader has: two arrangements of one piece,")
    print("each carrying the file name the OLD code wrote into its notation")
    workspace.create_piece("Jovano Jovanke")
    poisoned = []
    for name in ("Jovano Jovanke accordion", "Jovano Jovanke voice"):
        # imported cleanly first, exactly as the app does it
        slug, _ = workspace.create_score(name, _tune("Jovano Jovanke"),
                                         op="bulk-import", args={})
        workspace.assign_score_to_piece(slug, "Jovano Jovanke")
        # then the OMR of the day appends a version titled after the FILE it
        # transcribed. This is the bug as it was, reproduced through the same
        # writer the app used -- not a doc field poked by hand.
        workspace.add_version(slug, _tune("v001.mxl"), "omr", {})
        poisoned.append(slug)

    healthy, _ = workspace.create_score("Nature Boy", _tune("Nature Boy"),
                                        op="import", args={})

    repo = workspace._repo()
    check("the fixture reproduces the damage: both engrave a file name",
          all(repo.get_score(s)["title"] == "v001.mxl" for s in poisoned),
          str([repo.get_score(s)["title"] for s in poisoned]))
    check("and it is in the NOTATION, which is what actually engraves",
          _engraved_titles(workspace.resolve_path(poisoned[0])) == ["v001.mxl"] * 2,
          str(_engraved_titles(workspace.resolve_path(poisoned[0]))))
    check("both arrangements of the piece show the IDENTICAL string, "
          "which is the second half of what he reported",
          repo.get_score(poisoned[0])["title"] == repo.get_score(poisoned[1])["title"])

    print("\nthe scan finds them, and only them")
    found = workspace.title_repairs()
    check("two arrangements need repair", len(found) == 2,
          json.dumps(found, indent=None))
    check("the healthy one is not among them",
          healthy not in [r["slug"] for r in found])
    check("each is offered its own name back, so the two stop being identical",
          sorted(r["proposed"] for r in found)
          == ["Jovano Jovanke accordion", "Jovano Jovanke voice"],
          str([r["proposed"] for r in found]))
    check("and the report says WHICH defect it is",
          all(r["kind"] == "artifact-name" for r in found),
          str([r["kind"] for r in found]))

    print("\nlooking is not writing")
    before = {s: len(workspace.list_versions(s)) for s in poisoned}
    dry = workspace.repair_titles(dry_run=True)
    check("a dry run reports the count", dry["affected"] == 2, json.dumps(dry)[:200])
    check("and adds no version to anything",
          all(len(workspace.list_versions(s)) == before[s] for s in poisoned))
    check("and changes no title",
          all(repo.get_score(s)["title"] == "v001.mxl" for s in poisoned))

    print("\nrepairing, the legitimate way: a NEW version each")
    poisoned_file = workspace.resolve_path(poisoned[0])
    poisoned_bytes = poisoned_file.read_bytes()
    done = workspace.repair_titles(dry_run=False)
    check("it reports how many arrangements it affected", done["affected"] == 2,
          json.dumps(done)[:300])
    check("nothing failed", not done.get("failed"), json.dumps(done.get("failed")))
    for slug in poisoned:
        versions = workspace.list_versions(slug)
        check(f"{slug}: a version was added, not edited",
              len(versions) == before[slug] + 1,
              f"{before[slug]} -> {len(versions)}")
        check(f"{slug}: the new version says what made it",
              versions[-1]["op"] == "set-metadata", versions[-1]["op"])

    check("THE POISONED VERSION IS UNTOUCHED -- versions are immutable",
          poisoned_file.read_bytes() == poisoned_bytes)
    check("and it still says what it said, so history is honest",
          _engraved_titles(poisoned_file) == ["v001.mxl"] * 2,
          str(_engraved_titles(poisoned_file)))

    print("\nand the correction is in the notation, which is what engraves")
    for slug, expected in zip(poisoned, ["Jovano Jovanke accordion",
                                         "Jovano Jovanke voice"]):
        engraved = _engraved_titles(workspace.resolve_path(slug))
        check(f"{slug}: the page now reads {expected!r}",
              engraved == [expected] * 2, str(engraved))
        check(f"{slug}: no file name anywhere in it",
              not any("v001" in t for t in engraved), str(engraved))
        check(f"{slug}: and the library agrees with the page",
              repo.get_score(slug)["title"] == expected,
              repr(repo.get_score(slug)["title"]))

    check("the two arrangements no longer show the same label",
          repo.get_score(poisoned[0])["title"] != repo.get_score(poisoned[1])["title"])
    check("the healthy arrangement was not versioned at all",
          len(workspace.list_versions(healthy)) == 1)

    print("\nand the offer disappears once the work is done")
    check("a second scan finds nothing", workspace.title_repairs() == [],
          json.dumps(workspace.title_repairs()))
    check("and a second repair does nothing",
          workspace.repair_titles(dry_run=False)["affected"] == 0)

    print("\na scan whose latest version is still its PDF is left alone")
    from pypdf import PdfWriter

    writer = PdfWriter()
    writer.add_blank_page(width=612, height=792)
    pdf = Path(ws) / "v001.pdf"
    with open(pdf, "wb") as f:
        writer.write(f)
    scan, _ = workspace.create_pdf_score("v001", pdf, op="import-pdf", args={})
    # its title IS junk -- create_pdf_score had only "v001" to go on -- but
    # there is no notation to write a correction into, and writing the document
    # alone is the divergence between library and page that started all of this
    check("it is not offered for repair",
          scan not in [r["slug"] for r in workspace.title_repairs()],
          json.dumps(workspace.title_repairs()))
    check("and no version was appended to it",
          len(workspace.list_versions(scan)) == 1)

    print()
    if FAILURES:
        print(f"FAILED: {len(FAILURES)}")
        for f in FAILURES:
            print(f"  - {f}")
        return 1
    print("OK: an arrangement engraving a file name is found and corrected by "
          "ADDING a version, its history left where it was written")
    return 0


if __name__ == "__main__":
    sys.exit(main())
