"""Regression check: an arrangement whose artifact is a PDF.

Every version in the workspace has been a MusicXML file. The Newzik migration
brings 44 arrangements that are PDFs, and Ali's decision was to keep them as
they are and run OMR on the ones he actually wants to arrange -- so a PDF has
to be a first-class arrangement: it opens, it reads, it takes Pencil markup,
and it sits in the library like anything else.

What it is NOT is editable. Selection, addresses and every chat op come from
the engraved MEI, which only exists for notation. So the ops must REFUSE a PDF
arrangement clearly, and must not leave a half-made version behind when they
do. "This is a PDF, run OMR to make it editable" is a useful sentence; a
music21 parse error five frames deep is not.

The artifact filename already lives on the version document (`version_path`
reads `v["file"]`), so a PDF version needs no new plumbing to be found -- only
a way to say what KIND it is, and a guard on the paths that assume notation.

Fixtures are synthetic: the repository is public, so no committed fixture may
carry copyrighted music.

Run: engine/.venv/bin/python engine/scripts/check_pdf_arrangements.py
"""

import os
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

FAILURES: list[str] = []


def check(condition: bool, message: str) -> None:
    if condition:
        print(f"  ok   {message}")
    else:
        print(f"  FAIL {message}")
        FAILURES.append(message)


def blank_pdf(path: Path, pages: int = 3) -> Path:
    """A synthetic PDF standing in for a scanned score."""
    from pypdf import PdfWriter

    writer = PdfWriter()
    for _ in range(pages):
        writer.add_blank_page(width=612, height=792)
    with open(path, "wb") as f:
        writer.write(f)
    return path


def a_little_score():
    from music21 import instrument, key, meter, note, stream

    score = stream.Score()
    part = stream.Part()
    part.partName = "Violin"
    part.insert(0, instrument.Violin())
    measure = stream.Measure(number=1)
    measure.insert(0, key.KeySignature(0))
    measure.insert(0, meter.TimeSignature("4/4"))
    for pitch in ["C4", "D4", "E4", "F4"]:
        measure.append(note.Note(pitch, quarterLength=1))
    part.append(measure)
    score.insert(0, part)
    return score


def main() -> int:
    root = Path(tempfile.mkdtemp())
    os.environ["SCORANGER_WORKSPACE"] = str(root / "workspace")

    from scoranger_engine import workspace

    source = blank_pdf(root / "scan.pdf")
    original = source.read_bytes()

    print("importing a PDF")
    slug, entry = workspace.create_pdf_score("Medeno Kolo", source,
                                             args={"source": source.name})
    check(workspace.version_label(entry) == "v001",
          "it gets a first version like any arrangement")
    stored = workspace.resolve_path(slug)
    check(stored.suffix == ".pdf", f"the artifact is a PDF: {stored.name}")
    check(stored.read_bytes() == original,
          "and it is the file itself, byte for byte -- nothing re-encoded it")
    check(workspace.version_kind(slug) == "pdf", "the version says what it is")
    check(entry.get("parts") in ([], None),
          "a PDF has no parts snapshot, and does not invent one")

    print("the library can still file it")
    workspace.assign_score_to_piece(slug, "Medeno Kolo", create_if_missing=True)
    manifest = workspace.rebuild_manifest()
    doc = next(s for s in manifest["scores"] if s["slug"] == slug)
    check(doc["versions"][0].get("kind") == "pdf",
          "the manifest carries the kind, so the app knows before it loads")
    check(any(p["name"] == "Medeno Kolo" for p in manifest["pieces"]),
          "and it files under a piece like any other arrangement")

    print("notation paths refuse it, and refuse it well")
    try:
        workspace.resolve_notation_path(slug)
        check(False, "asking for notation should have raised")
    except workspace.NotNotationError as e:
        text = str(e).lower()
        check("pdf" in text and "omr" in text,
              f"the message says what it is and what to do: {e}")
    before = len(workspace.list_versions(slug))
    check(before == 1, "and no half-made version was left behind")

    print("a notation arrangement is untouched")
    xml_slug, _ = workspace.create_score("Little Tune", a_little_score())
    check(workspace.version_kind(xml_slug) == "musicxml",
          "an ordinary arrangement still reads as notation")
    check(workspace.resolve_notation_path(xml_slug).suffix == ".musicxml",
          "and notation paths resolve for it")
    manifest = workspace.rebuild_manifest()
    xml_doc = next(s for s in manifest["scores"] if s["slug"] == xml_slug)
    check(xml_doc["versions"][0].get("kind") == "musicxml",
          "the kind is stated for notation too, not only for PDFs")

    print("OMR turns a scan into an editable version of the SAME arrangement")
    # what the on-demand OMR action does once the service returns notation
    entry2 = workspace.add_version(slug, a_little_score(), "omr", {"source": "cloud"})
    check(workspace.version_label(entry2) == "v002",
          "the transcription is the next version, not a new score")
    check(workspace.version_kind(slug, "v001") == "pdf",
          "and the scan is still there as v001 -- the page the reader knows")
    check(workspace.version_kind(slug, "v002") == "musicxml",
          "while v002 is notation, so every op works on it")
    check(workspace.resolve_notation_path(slug, "v002").suffix == ".musicxml",
          "the notation path resolves for the transcription")
    try:
        workspace.resolve_notation_path(slug, "v001")
        check(False, "v001 is still a scan and must still refuse")
    except workspace.NotNotationError:
        check(True, "and still refuses for the scan it was made from")
    versions = workspace.list_versions(slug)
    check(len(versions) == 2, f"two versions, one arrangement: {len(versions)}")

    print()
    if FAILURES:
        print(f"{len(FAILURES)} FAILED")
        for f in FAILURES:
            print(f"  - {f}")
        return 1
    print("OK: a PDF is a first-class arrangement, and notation paths refuse it clearly")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
