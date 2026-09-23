"""Check for AUTO-SPLIT: a book's tunes found, kept as its contents, or taken out.

A tunebook is one PDF holding a hundred tunes. `booksplit.propose` says where
each starts and what it is called; `set_contents` keeps that as the book's
contents (the book stays one book, read tune by tune); `split` takes each out
as an arrangement under a piece of its name. This holds all three, and the
page copy they rest on.

What is asserted, against synthetic books built here:

  - HEADINGS on the text layer are found; a running header, a page number and
    a line of chord names at body size are not titles; a page with no heading
    CONTINUES the tune before it, and "(cont.)" is the same tune turned over.
  - A CONTENTS or INDEX page belongs to no tune, and ends the tune before it,
    so the back matter is not swallowed by the last tune.
  - BOOKMARKS win where there are any, the deeper of two on one page is the
    tune, and pages before the first are front matter.
  - A page with NO TEXT LAYER is named in `needs_ocr`, and Vision-shaped lines
    handed back for it are judged by the same rule.
  - The contents VALIDATE whole before anything is written, and keep their ids.
  - A split JOINS a piece of the same name rather than making a second.
  - A PAGE TAKEN OUT STANDS ALONE. The Comhaltas San Diego tunebook (jsPDF)
    hangs all 689 of its images off every page and links every page to its
    neighbours; one tune out of it was 28 MB. The extract here must carry only
    the image its page draws, byte for byte, with the content stream
    unchanged, while a multi-page extract keeps each page's own image (the
    shared resources are replaced, never pruned in place) and a web link stays.
  - The BINARY answers: book-detect, book-contents and book-split run as a
    process, JSON on stdout.

Fixtures are synthetic: the repository is public, so no committed fixture may
carry copyrighted music. The real tunebook was measured by hand (124 of 124
tunes, bookmarks and headings agreeing; 176 KB a tune), not here.

Run: engine/.venv/bin/python engine/scripts/check_book_split.py
"""

import io
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ENGINE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ENGINE))

FAILURES: list[str] = []


def check(condition: bool, message: str) -> None:
    print(f"  {'ok  ' if condition else 'FAIL'} {message}")
    if not condition:
        FAILURES.append(message)


# -- fixtures -------------------------------------------------------------

HEADER = "Session Tunes 2026"


def _svg(texts: list[tuple[str, float, float, float]]) -> bytes:
    """A letter page with text at (x, baseline y, size), as a PDF page."""
    from xml.sax.saxutils import escape

    import cairosvg

    body = "".join(
        f"<text x='{x}' y='{y}' font-size='{size}' font-family='Helvetica'>{escape(t)}</text>"
        for t, x, y, size in texts)
    svg = (f"<svg xmlns='http://www.w3.org/2000/svg' width='612' height='792'>"
           f"{body}</svg>")
    return cairosvg.svg2pdf(bytestring=svg.encode())


def tune_page(title: str | None, number: int, extra=()) -> bytes:
    # "<<" and ">>" at the TITLE's size, as the tunebook draws them: measured
    # against them, no title stands out from its own page.
    texts = [(HEADER, 230, 24, 12), (str(number), 300, 780, 12),
             ("<<", 8, 436, 20), (">>", 584, 460, 20), *extra]
    if title:
        texts.append((title, 200, 64, 20))
    return _svg(texts)


def listing_page(heading: str, titles: list[str]) -> bytes:
    texts = [(heading, 250, 70, 20)]
    for i, t in enumerate(titles):
        texts.append((f"{t} {i + 3}", 80, 120 + 22 * i, 13))
    return _svg(texts)


TITLES = ["The Silver Spear", "Morrison's Jig", "The Kesh", "Drowsy Maggie",
          "Banish Misfortune", "The Butterfly", "Cooley's", "The Maid Behind the Bar"]


def session_book(path: Path, bookmarks: bool = False) -> Path:
    """Twelve pages, laid out like a real session tunebook.

      1  cover (big title, mid-page)          -> no tune
      2  Contents                             -> matter
      3  The Silver Spear  (+ chord line)
      4  Morrison's Jig
      5  (no heading)                         -> Morrison's continues
      6  The Kesh
      7  The Kesh (cont.)                     -> the same tune
      8  chord names at body size, top band   -> still The Kesh
      9  Drowsy Maggie
     10  a SCAN: no text layer                -> needs_ocr
     11  Index                                -> matter
     12  back cover, mid-page                 -> no tune
    """
    from pypdf import PdfReader, PdfWriter

    pages = [
        _svg([("Session Tunes", 150, 240, 28), ("Autumn 2026", 250, 280, 16)]),
        listing_page("Contents", TITLES),
        tune_page("The Silver Spear", 1, [("Am G Em D", 60, 110, 12)]),
        tune_page("Morrison's Jig", 2),
        tune_page(None, 3),
        tune_page("The Kesh", 4),
        tune_page("The Kesh (cont.)", 5),
        tune_page(None, 6, [("G D Em C", 60, 70, 12), ("and the wind did blow", 60, 300, 12)]),
        tune_page("Drowsy Maggie", 7),
        None,
        listing_page("Index", sorted(TITLES)),
        _svg([("Printed in Cork", 240, 420, 12)]),
    ]
    writer = PdfWriter()
    for data in pages:
        if data is None:
            writer.add_blank_page(width=612, height=792)
        else:
            writer.add_page(PdfReader(io.BytesIO(data)).pages[0])
    if bookmarks:
        writer.add_outline_item("Silver Spear, The", 2)
        writer.add_outline_item("Morrison's", 3)
        reels = writer.add_outline_item("Reels", 5)
        writer.add_outline_item("The Kesh Jig", 5, parent=reels)
        writer.add_outline_item("Drowsy Maggie", 8)
    with open(path, "wb") as f:
        writer.write(f)
    return path


# Shaped like what Vision returned for the Comhaltas tunebook, page 13: its
# heights are INK BOXES, so the rhythm under the title is within a tenth of it,
# chord letters come back as words ("GADAD"), and a misread staff is a box
# four times a title's height.
OCR_PAGE_10 = {10: [{"text": HEADER, "top": 0.033, "height": 0.0145, "left": 0.36},
                    {"text": "Banish Misfortune", "top": 0.082, "height": 0.0182, "left": 0.39},
                    {"text": "Slip Jig", "top": 0.109, "height": 0.0164, "left": 0.07},
                    {"text": "GADAD", "top": 0.166, "height": 0.026, "left": 0.2},
                    {"text": "BEERRRTTAdE", "top": 0.533, "height": 0.0709, "left": 0.07},
                    {"text": "Bhriarir", "top": 0.71, "height": 0.06, "left": 0.07},
                    {"text": "Bsleiegpieg", "top": 0.86, "height": 0.065, "left": 0.07},
                    {"text": "11", "top": 0.98, "height": 0.015, "left": 0.5}]}


def jspdf_book(path: Path, pages: int = 5, image_bytes: int = 120_000) -> Path:
    """A book built the way jsPDF builds one: ONE resource dictionary naming
    every page's image, hung off every page, and GoTo links between pages."""
    from pypdf import PdfWriter
    from pypdf.generic import (ArrayObject, DecodedStreamObject, DictionaryObject,
                               FloatObject, NameObject, NumberObject, TextStringObject)

    writer = PdfWriter()
    images = DictionaryObject()
    for i in range(pages):
        img = DecodedStreamObject()
        img.set_data(os.urandom(image_bytes))
        img.update({NameObject("/Type"): NameObject("/XObject"),
                    NameObject("/Subtype"): NameObject("/Image"),
                    NameObject("/Width"): NumberObject(200),
                    NameObject("/Height"): NumberObject(image_bytes // 600),
                    NameObject("/ColorSpace"): NameObject("/DeviceRGB"),
                    NameObject("/BitsPerComponent"): NumberObject(8)})
        images[NameObject(f"/I{i}")] = writer._add_object(img)
    shared = writer._add_object(DictionaryObject({NameObject("/XObject"): images}))
    for i in range(pages):
        page = writer.add_blank_page(width=612, height=792)
        content = DecodedStreamObject()
        content.set_data(f"q 500 0 0 200 50 400 cm /I{i} Do Q".encode())
        page[NameObject("/Contents")] = writer._add_object(content)
        page[NameObject("/Resources")] = shared
    for i, page in enumerate(writer.pages):
        target = writer.pages[(i + 1) % pages].indirect_reference
        goto = DictionaryObject({
            NameObject("/Type"): NameObject("/Annot"),
            NameObject("/Subtype"): NameObject("/Link"),
            NameObject("/Rect"): ArrayObject([FloatObject(v) for v in (580, 400, 600, 420)]),
            NameObject("/Dest"): ArrayObject([target, NameObject("/Fit")])})
        web = DictionaryObject({
            NameObject("/Type"): NameObject("/Annot"),
            NameObject("/Subtype"): NameObject("/Link"),
            NameObject("/Rect"): ArrayObject([FloatObject(v) for v in (200, 760, 400, 780)]),
            NameObject("/A"): DictionaryObject({
                NameObject("/S"): NameObject("/URI"),
                NameObject("/URI"): TextStringObject(f"https://example.org/tune/{i}")})})
        page[NameObject("/Annots")] = ArrayObject([writer._add_object(goto),
                                                   writer._add_object(web)])
    with open(path, "wb") as f:
        writer.write(f)
    return path


def entries(result: dict) -> list[tuple[str, int, int, str]]:
    return [(e["title"], e["from"], e["to"], e["evidence"]) for e in result["entries"]]


# -- the checks -----------------------------------------------------------

def check_detection(root: Path) -> None:
    from scoranger_engine import booksplit

    print("headings, continuations and matter")
    book = session_book(root / "session.pdf")
    got = booksplit.propose(book)
    check(entries(got) == [("The Silver Spear", 3, 3, "heading"),
                           ("Morrison's Jig", 4, 5, "heading"),
                           ("The Kesh", 6, 8, "heading"),
                           ("Drowsy Maggie", 9, 10, "heading")],
          f"four tunes, continuations joined: {entries(got)}")
    check(got["matter"] == [2, 11], f"contents and index are matter: {got['matter']}")
    check(got["unassigned"] == [1, 12],
          f"the covers belong to no tune: {got['unassigned']}")
    check(got["needs_ocr"] == [10], f"the scanned page is named for OCR: {got['needs_ocr']}")

    print("a scanned page, read by the app")
    got = booksplit.propose(book, OCR_PAGE_10)
    check(("Banish Misfortune", 10, 10, "ocr") in entries(got),
          f"Vision's lines start a tune by the same rule: {entries(got)[-1]}")
    check(("Drowsy Maggie", 9, 9, "heading") in entries(got),
          "and the tune before it ends where the scan begins")
    check(got["needs_ocr"] == [],
          "and needs_ocr is empty once it has been read -- the app asks until it is")

    Line, Page = booksplit.Line, booksplit.Page
    turned = [Line("G A D", 0.05, 0.02, 0.2), Line("GADAD", 0.07, 0.026, 0.3),
              # Words INSIDE the band would be read as a title: a KNOWN LIMIT of
              # judging a scan by position, in BACKLOG. The review list is where
              # such a row is merged back into its tune.
              Line("Em D", 0.12, 0.02, 0.5), Line("and the wind did blow", 0.4, 0.017, 0.1)]
    check(booksplit.heading(Page(11, turned, [], "ocr"), set()) is None,
          "chord letters over a turned page are not a title, so it continues its tune")

    print("a scanned contents page, recognised by its shape")
    titles = [Line(t, 0.16 + 0.023 * i, 0.017, 0.23) for i, t in enumerate(TITLES * 2)]
    check(booksplit.is_matter(Page(3, titles, booksplit._rows(titles), "ocr"), None),
          "a column of short titles at one left edge, no page numbers read")
    verses = [Line("and the wind did blow across the bay that night", 0.16 + 0.023 * i,
                   0.017, 0.23) for i in range(16)]
    check(not booksplit.is_matter(Page(3, verses, booksplit._rows(verses), "ocr"), None),
          "but a page of lyric verses is not one")

    print("bookmarks")
    marked = session_book(root / "marked.pdf", bookmarks=True)
    got = booksplit.propose(marked, OCR_PAGE_10)
    check(entries(got) == [("Silver Spear, The", 3, 3, "bookmark"),
                           ("Morrison's", 4, 5, "bookmark"),
                           ("The Kesh Jig", 6, 8, "bookmark"),
                           ("Drowsy Maggie", 9, 9, "bookmark"),
                           ("Banish Misfortune", 10, 10, "ocr")],
          f"bookmarks name the tunes, the deeper of two on a page wins: {entries(got)}")
    check(got["bookmarks"] == 4, f"four pages bookmarked: {got['bookmarks']}")


def check_standalone_page(root: Path) -> None:
    from pypdf import PdfReader

    from scoranger_engine import workspace

    print("a page taken out stands alone")
    source = jspdf_book(root / "jspdf.pdf")
    slug, _ = workspace.create_book("jsPDF book", source)
    whole = source.stat().st_size

    score, _ = workspace.extract_from_book(slug, 3, 3, "One tune")
    out = workspace.resolve_path(score)
    size = out.stat().st_size
    check(size < whole / 3,
          f"one page of five is not the whole book: {size} of {whole} bytes")
    page = PdfReader(str(out)).pages[0]
    book_page = PdfReader(str(source)).pages[2]
    xo = page["/Resources"]["/XObject"]
    check(sorted(xo.keys()) == ["/I2"], f"it holds the one image it draws: {sorted(xo.keys())}")
    check(xo["/I2"].get_object().get_data()
          == book_page["/Resources"]["/XObject"]["/I2"].get_object().get_data(),
          "that image is byte-identical to the book's")
    check(page.get_contents().get_data() == book_page.get_contents().get_data(),
          "and the content stream is unchanged")
    annots = [a.get_object() for a in page.get("/Annots") or []]
    check(len(annots) == 1 and annots[0]["/A"]["/URI"] == "https://example.org/tune/2",
          "the link to the next page is gone and the web link stays")

    score, _ = workspace.extract_from_book(slug, 2, 3, "Two pages")
    reader = PdfReader(str(workspace.resolve_path(score)))
    held = [sorted(p["/Resources"]["/XObject"].keys()) for p in reader.pages]
    check(held == [["/I1"], ["/I2"]],
          f"two pages from one shared dictionary each keep their own image: {held}")


def check_contents_and_split(root: Path) -> None:
    from scoranger_engine import booksplit, workspace

    print("contents: the book stays a book")
    slug, _ = workspace.create_book("Session Tunes", session_book(root / "s2.pdf"))
    plan = booksplit.propose(workspace.book_path(slug), OCR_PAGE_10)["entries"]
    scores_before = len(workspace._repo().list_scores())
    doc = booksplit.set_contents(slug, plan)
    check([(e["id"], e["title"], e["from"], e["to"]) for e in doc["contents"]]
          == [(e["id"], e["title"], e["from"], e["to"]) for e in plan],
          "the proposal is saved as the contents, each entry keeping the id it was proposed with")
    check(len(workspace._repo().list_scores()) == scores_before,
          "and no arrangement is made")
    manifest = json.loads((workspace.WORKSPACE / "manifest.json").read_text())
    projected = next(b for b in manifest["books"] if b["slug"] == slug)
    check(len(projected["contents"]) == len(plan), "the manifest carries the contents")

    first = doc["contents"][0]
    edited = [{**first, "title": "The Silver Spear (reel)"}] + doc["contents"][1:]
    doc = booksplit.set_contents(slug, edited)
    check(doc["contents"][0]["id"] == first["id"]
          and doc["contents"][0]["title"] == "The Silver Spear (reel)",
          "a renamed entry keeps its id")

    for bad, why in (([{"title": "X", "from": 11, "to": 13}], "past the last page"),
                     ([{"title": "X", "from": 5, "to": 4}], "backwards"),
                     ([{"title": " ", "from": 3, "to": 3}], "untitled"),
                     ([], "empty")):
        try:
            booksplit.set_contents(slug, bad)
            refused = False
        except ValueError:
            refused = True
        check(refused, f"a plan {why} is refused")
    check(len(workspace.resolve_book(slug)["contents"]) == len(plan),
          "and a refused plan changed nothing")
    booksplit.set_contents(slug, None)
    check("contents" not in workspace.resolve_book(slug), "clearing removes them")

    print("split: the tunes taken out")
    workspace.create_piece("Drowsy Maggie")
    pieces_before = len(workspace.list_pieces())
    report = booksplit.split(slug, plan)
    check(len(report["arrangements"]) == len(plan),
          f"an arrangement per entry: {len(report['arrangements'])}")
    check(report["pieces_joined"] == 1 and report["pieces_created"] == len(plan) - 1,
          f"'Drowsy Maggie' joins the piece already there: {report['pieces_joined']} joined")
    check(len(workspace.list_pieces()) == pieces_before + len(plan) - 1,
          "and no second piece of that name is made")
    from pypdf import PdfReader
    kesh = next(a for a in report["arrangements"] if a["title"] == "The Kesh")
    check(len(PdfReader(str(workspace.resolve_path(kesh["score"]))).pages) == 3,
          "a three-page tune comes out with three pages")


def check_binary(root: Path) -> None:
    print("the binary")
    env = {**os.environ, "SCORANGER_WORKSPACE": str(root / "cli-workspace"),
           "PYTHONPATH": str(ENGINE)}

    def scor(*args) -> dict:
        proc = subprocess.run([sys.executable, "-m", "scoranger_engine.cli", *args],
                              capture_output=True, text=True, env=env)
        if proc.returncode != 0:
            raise RuntimeError(proc.stderr.strip()[-300:])
        return json.loads(proc.stdout)

    book = scor("import-book", str(session_book(root / "cli.pdf")), "--name", "CLI Book")["book"]
    (root / "ocr.json").write_text(json.dumps({str(k): v for k, v in OCR_PAGE_10.items()}))
    detected = scor("book-detect", book, "--ocr", str(root / "ocr.json"))
    check(len(detected["entries"]) == 5, f"book-detect: {len(detected['entries'])} entries")
    (root / "plan.json").write_text(json.dumps(detected))
    kept = scor("book-contents", book, "--plan", str(root / "plan.json"))
    check(len(kept["contents"]) == 5, "book-contents takes book-detect's output as it is")
    split = scor("book-split", book, "--plan", str(root / "plan.json"))
    check(len(split["arrangements"]) == 5, "book-split takes it too")
    cleared = scor("book-contents", book, "--clear")
    check(cleared["contents"] == [], "book-contents --clear")


def main() -> int:
    root = Path(tempfile.mkdtemp())
    os.environ["SCORANGER_WORKSPACE"] = str(root / "workspace")
    check_detection(root)
    check_standalone_page(root)
    check_contents_and_split(root)
    check_binary(root)
    if FAILURES:
        print(f"\n{len(FAILURES)} FAILED")
        for f in FAILURES:
            print(f"  - {f}")
        return 1
    print("\nOK: a book's tunes are found, kept as its contents, or taken out standing alone")
    return 0


if __name__ == "__main__":
    sys.exit(main())
