"""Regression check for BOOKS: a collection you take arrangements out of.

A book is not a piece. Ali's Newzik export contained a whole fake book -- one
52MB PDF holding hundreds of tunes -- and importing it as an "arrangement"
would have put hundreds of pieces under one title. So a book is its own thing:
it is read, and pieces are taken OUT of it.

  a PIECE is a composition          -> holds arrangements
  a BOOK is a collection of them    -> arrangements are EXTRACTED from it

Extraction is the whole point. Picking pages 42-44 of a fake book and filing
them as an arrangement of "Misty" is what makes a book useful rather than a
2000-page scroll. The extracted arrangement is an ordinary PDF arrangement --
it reads, it takes markup, and OMR can make it editable -- so everything that
already works for a scan works for it.

Fixtures are synthetic: the repository is public, so no committed fixture may
carry copyrighted music.

Run: engine/.venv/bin/python engine/scripts/check_books.py
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


def numbered_pdf(path: Path, pages: int) -> Path:
    """A PDF whose pages are distinguishable, so an extract can be checked."""
    from pypdf import PdfWriter

    writer = PdfWriter()
    for _ in range(pages):
        writer.add_blank_page(width=612, height=792)
    with open(path, "wb") as f:
        writer.write(f)
    return path


def page_count(path: Path) -> int:
    from pypdf import PdfReader

    return len(PdfReader(str(path)).pages)


def main() -> int:
    root = Path(tempfile.mkdtemp())
    os.environ["SCORANGER_WORKSPACE"] = str(root / "workspace")

    from scoranger_engine import workspace


    source = numbered_pdf(root / "fake-book.pdf", 40)

    print("importing a book")
    slug, doc = workspace.create_book("The Real Book", source)
    check(doc["pages"] == 40, f"it knows how long it is: {doc.get('pages')}")
    check(workspace.book_path(slug).exists(), "the PDF is stored")
    check(workspace.book_path(slug).read_bytes() == source.read_bytes(),
          "byte for byte -- nothing re-encoded it")

    print("a book is not a piece and not an arrangement")
    manifest = workspace.rebuild_manifest()
    check(any(b["slug"] == slug for b in manifest.get("books") or []),
          "it is in the manifest under books")
    check(not any(s["slug"] == slug for s in manifest["scores"]),
          "and NOT among the arrangements -- that is the whole distinction")
    check(not any(p["slug"] == slug for p in manifest["pieces"]),
          "nor among the pieces")

    print("taking an arrangement out of it")
    score_slug, entry = workspace.extract_from_book(
        slug, from_page=11, to_page=13, name="Misty", piece="Misty")
    extracted = workspace.resolve_path(score_slug)
    check(page_count(extracted) == 3, f"three pages came out: {page_count(extracted)}")
    check(workspace.version_kind(score_slug) == "pdf",
          "and it is an ordinary PDF arrangement, so markup and OMR both work")
    manifest = workspace.rebuild_manifest()
    check(any(p["name"] == "Misty" and score_slug in p["arrangements"]
              for p in manifest["pieces"]),
          "filed under the piece it was named for")
    check(workspace.version_label(entry) == "v001", "with its own first version")

    print("the book is unchanged by the extraction")
    check(page_count(workspace.book_path(slug)) == 40,
          "taking pages out copies them; it does not cut them out")

    print("bad page ranges are refused, not silently clamped")
    for bad, why in [((0, 3), "a page before the first"),
                     ((39, 45), "a page past the last"),
                     ((13, 11), "backwards")]:
        try:
            workspace.extract_from_book(slug, from_page=bad[0], to_page=bad[1],
                                        name="Nope", piece=None)
            check(False, f"{why} should have been refused")
        except ValueError as e:
            check("page" in str(e).lower(), f"{why} is refused: {e}")

    print()
    if FAILURES:
        print(f"{len(FAILURES)} FAILED")
        for f in FAILURES:
            print(f"  - {f}")
        return 1
    print("OK: a book is read, and arrangements are taken out of it")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
