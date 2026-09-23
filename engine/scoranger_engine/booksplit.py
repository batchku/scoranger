"""Where the tunes in a book start, and what they are called.

A fake book, a real book or a session tunebook is one PDF holding a hundred
tunes, mostly one to a page and sometimes not. Taking them out one page range
at a time is the manual path (`extract_from_book`); this module PROPOSES the
whole list, and the reader confirms it before anything is written.

The proposal is built from the strongest evidence the book has, in order:

  1. BOOKMARKS. A book made by software usually carries an outline, one entry
     per tune, and an entry names its page exactly. Where there is one, the
     pages before its first entry are front matter and belong to no tune.
  2. THE HEADING ON THE TEXT LAYER: the largest line in the top band of the
     page, that is not a running header. A running header is text repeated on
     many pages ("Click any tune title to play the tune"), and a page number is
     not a title.
  3. For a SCAN, which has no text layer: the same rule over lines the app
     reads with Apple Vision on the device, handed in as `ocr`. The engine
     reports the pages that need it (`needs_ocr`) and the app reads only those.

A page with no heading CONTINUES the tune before it. A contents or index page
belongs to no tune and ends the one before it, so a book's back matter is not
swallowed by its last tune.

Both text sources are reduced to the same `Line` -- text, height and position
as FRACTIONS of the page -- so one heading rule serves a vector PDF and a
photographed one, and is proven once, in check_book_split.py.

The proposal is data. It is saved as the book's CONTENTS (`set_contents`), so
the book is read tune by tune while staying one book, or it is taken out as
arrangements filed under pieces (`split`). Either way the reader has seen it.
"""

from __future__ import annotations

import math
import re
from collections import Counter
from dataclasses import dataclass
from pathlib import Path

from . import ids, workspace

# A heading is drawn in the top band of the page. The Comhaltas tunebook puts
# its titles at 8% and its cover's title at 30%; a cover is not a tune.
HEADING_BAND = 0.25
# Below this a line is body text, not a title: 12pt on a letter page is 0.015.
MIN_HEADING_HEIGHT = 0.017
# ...and it must stand out from the page's other text by this much, or chord
# names and lyrics in the top band would be read as titles.
HEADING_RATIO = 1.25
# Text on at least this share of the book's pages (and on 3 or more) is a
# running header or footer.
REPEATED_SHARE = 0.25
# A page is a contents or index page when this many of its lines read
# "Title ... 12" and they are most of its lines.
LISTING_MIN_LINES = 6
# ...or, on a scan whose page numbers OCR did not read, this many short rows
# of words starting at one left edge.
TITLE_COLUMN_ROWS = 12

_MATTER_HEADING = re.compile(r"^(table of )?contents$|^index\b|^tune index\b",
                             re.IGNORECASE)
_LISTING_LINE = re.compile(r"^\S.*[^\d\s].*\s\d{1,4}$")
_CONTINUED = re.compile(r"\s*[\(\[]?\s*(cont(inued|'d|\.)?)\s*[\)\]]?\s*$",
                        re.IGNORECASE)


@dataclass(frozen=True)
class Line:
    """One line of text on a page, measured as fractions of the page.

    `top` is the distance of the line's baseline from the TOP edge (0 is the
    top, 1 the bottom), `height` its glyph height, `left` its left edge. Vision
    reports exactly this shape; the text layer is converted to it.

    The two sources measure `height` differently, which is why `heading` judges
    them by different rules: a text layer's is the font size, exact; Vision's
    is the box it drew round the ink, so "Slip Jig" under a title measures 0.9
    of the title and size alone cannot tell them apart.
    """
    text: str
    top: float
    height: float
    left: float = 0.0


@dataclass
class Page:
    number: int                 # 1-based, as printed by a PDF viewer
    lines: list[Line]
    plain: list[str]            # the text layer's lines, for listing detection
    source: str                 # "text", "ocr" or "none"


# -- reading pages --------------------------------------------------------

def _mult(m, n):
    return [m[0] * n[0] + m[1] * n[2], m[0] * n[1] + m[1] * n[3],
            m[2] * n[0] + m[3] * n[2], m[2] * n[1] + m[3] * n[3],
            m[4] * n[0] + m[5] * n[2] + n[4], m[4] * n[1] + m[5] * n[3] + n[5]]


def _text_layer(page) -> tuple[list[Line], list[str]]:
    height = float(page.mediabox.height) or 1.0
    lines: list[Line] = []

    def visit(text, cm, tm, font_dict, font_size):
        text = " ".join(text.split())
        if not text:
            return
        m = _mult(tm, cm)
        size = font_size * math.hypot(m[0], m[1])
        top = 1.0 - (m[5] - float(page.mediabox.bottom)) / height
        lines.append(Line(text, min(max(top, 0.0), 1.0), size / height))

    plain = page.extract_text(visitor_text=visit) or ""
    return lines, [" ".join(s.split()) for s in plain.splitlines() if s.strip()]


def _ocr_lines(raw: list[dict]) -> list[Line]:
    out = []
    for item in raw:
        text = " ".join(str(item.get("text", "")).split())
        if text:
            out.append(Line(text, float(item["top"]), float(item["height"]),
                            float(item.get("left", 0.0))))
    return out


def _rows(lines: list[Line]) -> list[str]:
    """OCR lines joined into printed rows, left to right.

    Vision reports "The Abbey" and its page number "1" as two observations; a
    contents page is only recognisable as one once they are a row again.
    """
    rows: list[list[Line]] = []
    for line in sorted(lines, key=lambda l: l.top):
        if rows and abs(line.top - rows[-1][0].top) < 0.6 * max(line.height, rows[-1][0].height):
            rows[-1].append(line)
        else:
            rows.append([line])
    return [" ".join(l.text for l in sorted(row, key=lambda l: l.left)) for row in rows]


def read_pages(pdf_path: Path, ocr: dict[int, list[dict]] | None = None) -> list[Page]:
    """Every page's lines, from the text layer or else from the app's OCR."""
    from pypdf import PdfReader

    ocr = ocr or {}
    pages = []
    for index, page in enumerate(PdfReader(str(pdf_path)).pages):
        number = index + 1
        lines, plain = _text_layer(page)
        if lines:
            pages.append(Page(number, lines, plain, "text"))
        elif number in ocr:
            ocr_lines = _ocr_lines(ocr[number])
            pages.append(Page(number, ocr_lines, _rows(ocr_lines), "ocr"))
        else:
            pages.append(Page(number, [], [], "none"))
    return pages


def outline(pdf_path: Path) -> list[tuple[int, str, int]]:
    """The book's bookmarks as (page, title, depth), in page order.

    Where a section bookmark and a tune bookmark name the same page, the deeper
    one is the tune ("Reels" > "The Silver Spear" both on page 40).
    """
    from pypdf import PdfReader

    reader = PdfReader(str(pdf_path))
    found: dict[int, tuple[str, int]] = {}

    def walk(items, depth):
        for item in items:
            if isinstance(item, list):
                walk(item, depth + 1)
                continue
            try:
                page = reader.get_destination_page_number(item) + 1
            except Exception:  # a bookmark to nowhere names no tune
                continue
            title = " ".join(str(item.title or "").split())
            if page < 1 or not title:
                continue
            if page not in found or depth > found[page][1]:
                found[page] = (title, depth)

    walk(reader.outline or [], 0)
    return [(p, t, d) for p, (t, d) in sorted(found.items())]


# -- judging pages --------------------------------------------------------

def _key(text: str) -> str:
    return re.sub(r"[^\w]+", " ", text.casefold()).strip()


def repeated_text(pages: list[Page]) -> set[str]:
    """Text that recurs across the book: running headers, footers, nav marks."""
    with_text = [p for p in pages if p.lines]
    counts = Counter()
    for page in with_text:
        counts.update({_key(l.text) for l in page.lines})
    floor = max(3, math.ceil(REPEATED_SHARE * len(with_text)))
    return {k for k, n in counts.items() if n >= floor}


def heading(page: Page, repeated: set[str]) -> str | None:
    """The page's title, or None if it has none."""
    if not page.lines:
        return None
    candidates = [l for l in page.lines
                  if l.top <= HEADING_BAND
                  and _key(l.text) not in repeated
                  and sum(c.isalpha() for c in l.text) >= 3]
    if not candidates:
        return None
    if page.source == "ocr":
        return _ocr_heading(page, candidates, repeated)
    best = max(candidates, key=lambda l: (l.height, -l.top))
    # Measured against the page's own WORDS: a running header, a nav mark
    # ("<<" at the title's size, in the tunebook) or a page number says
    # nothing about how big this page's text is.
    others = sorted(l.height for l in page.lines
                    if l is not best and _key(l.text) not in repeated
                    and sum(c.isalpha() for c in l.text) >= 3)
    typical = others[len(others) // 2] if others else 0.0
    if best.height < MIN_HEADING_HEIGHT or best.height < HEADING_RATIO * typical:
        return None
    return best.text


_CHORD_LETTERS = set("ABCDEFG#")
_VOWEL = re.compile(r"[aeiouyáéíóúàèìòùâêîôûäëïöü]", re.IGNORECASE)


def _wordlike(text: str) -> bool:
    """Whether OCR'd text reads as WORDS rather than as music it misread.

    Vision reads a staff as text too: chord letters over it ("G A D", "GADAD")
    and noteheads as runs of consonants and dots. A title is mostly letters and
    has at least one word of three with a vowel in it.
    """
    compact = text.replace(" ", "")
    words = re.findall(r"[^\W\d_]+", text)
    letters = sum(len(w) for w in words)
    if letters < 3 or letters < 0.7 * len(compact):
        return False
    if all(set(t) <= _CHORD_LETTERS for t in text.split()):
        return False
    return any(len(w) >= 3 and _VOWEL.search(w) for w in words)


def _ocr_heading(page: Page, candidates: list[Line], repeated: set[str]) -> str | None:
    """A scan's title: the TOPMOST line of real words in the heading band.

    Not the tallest, because Vision's heights are ink boxes (see `Line`): the
    rhythm under a title ("Slip Jig", "Polka") measures within a tenth of it.
    Position is what a scan preserves -- a title is printed above its tempo,
    its rhythm and its music -- and the line must not be smaller than the
    band's words usually are, so a small caption above a title does not win.
    The band's, not the page's: Vision draws a staff it misread as a box five
    lines tall, and a page of those would outsize any title.
    """
    words = [l for l in candidates if _wordlike(l.text)]
    if not words:
        return None
    sizes = sorted(l.height for l in words)
    typical = sizes[len(sizes) // 2]
    best = min((l for l in words if l.height >= typical), key=lambda l: l.top, default=None)
    return best.text if best else None


def is_matter(page: Page, title: str | None) -> bool:
    """A contents or index page: part of the book, not of any tune."""
    if title and _MATTER_HEADING.match(title.strip()):
        return True
    listing = [s for s in page.plain if _LISTING_LINE.match(s)]
    if len(listing) >= LISTING_MIN_LINES and 2 * len(listing) >= len(page.plain):
        return True
    return page.source == "ocr" and _title_column(page.lines)


def _title_column(lines: list[Line]) -> bool:
    """A scanned contents or index page, recognised by its SHAPE.

    Vision misses most small page numbers (on the Comhaltas tunebook at 100
    dpi it read five of thirty-two on one contents page), so "Title ... 12"
    cannot be relied on. What it does read is the column of titles: many short
    rows of words starting at one left edge. Lyrics are longer lines, and a
    page of music has no such column.
    """
    words = [l for l in lines if _wordlike(l.text)]
    if len(words) < TITLE_COLUMN_ROWS:
        return False
    edges = Counter(round(l.left / 0.015) for l in words)
    edge, _ = edges.most_common(1)[0]
    column = [l for l in words if abs(round(l.left / 0.015) - edge) <= 1]
    lengths = sorted(len(l.text.split()) for l in column)
    return len(column) >= TITLE_COLUMN_ROWS and lengths[len(lengths) // 2] <= 5


# -- the proposal ---------------------------------------------------------

def _same_tune(a: str, b: str) -> bool:
    return _key(_CONTINUED.sub("", a)) == _key(_CONTINUED.sub("", b))


def propose(pdf_path: Path, ocr: dict[int, list[dict]] | None = None) -> dict:
    """The proposed contents of a book. Reads the book; writes nothing.

    Returns {"entries": [{title, from, to, evidence}], "unassigned": [pages],
    "needs_ocr": [pages], "matter": [pages], "bookmarks": n}.
    """
    pages = read_pages(Path(pdf_path), ocr)
    repeated = repeated_text(pages)
    marks = outline(Path(pdf_path))
    by_page = {p: t for p, t, _ in marks}
    first_mark = marks[0][0] if marks else None

    entries: list[dict] = []
    unassigned: list[int] = []
    matter: list[int] = []
    current: dict | None = None
    # What the current tune is called ON ITS PAGE as well as in its entry: a
    # bookmark says "The Kesh Jig" where the page prints "The Kesh", and the
    # next page's "The Kesh (cont.)" continues the page's name, not the mark's.
    names: list[str] = []
    for page in pages:
        title = heading(page, repeated)
        if is_matter(page, title):
            matter.append(page.number)
            current = None
            continue
        if page.number in by_page:
            start = (by_page[page.number], "bookmark")
        elif title and (first_mark is None or page.number > first_mark):
            start = (title, "heading" if page.source == "text" else "ocr")
        else:
            start = None
        if start and current and any(_same_tune(title or start[0], n) for n in names):
            start = None        # "Tune (cont.)" -- the same tune, turned over
        if start:
            # the id is minted HERE so an entry is the same entry from the
            # review list to the saved contents (set_contents keeps it)
            current = {"id": ids.new_id(), "title": start[0], "from": page.number,
                       "to": page.number, "evidence": start[1]}
            names = [n for n in (start[0], title) if n]
            entries.append(current)
        elif current is not None:
            current["to"] = page.number
        else:
            unassigned.append(page.number)

    return {
        "entries": entries,
        "unassigned": unassigned,
        "matter": matter,
        "needs_ocr": [p.number for p in pages if p.source == "none"],
        "bookmarks": len(marks),
        "pages": len(pages),
    }


# -- committing it --------------------------------------------------------

def _validated(plan: list[dict], pages: int) -> list[dict]:
    """The plan, checked whole before anything is written."""
    if not isinstance(plan, list) or not plan:
        raise ValueError("The plan is empty: nothing to take out of the book")
    clean = []
    for n, item in enumerate(plan, 1):
        title = " ".join(str(item.get("title") or "").split())
        if not title:
            raise ValueError(f"Entry {n} has no title")
        try:
            start, end = int(item["from"]), int(item["to"])
        except (KeyError, TypeError, ValueError):
            raise ValueError(f"Entry {n} ('{title}') needs whole-number 'from' and 'to' pages")
        if start < 1 or end > pages or start > end:
            raise ValueError(f"Entry {n} ('{title}') is pages {start}-{end}; "
                             f"the book has pages 1-{pages}")
        clean.append({"id": item.get("id") or ids.new_id(), "title": title,
                      "from": start, "to": end})
    return clean


def set_contents(slug: str, plan: list[dict] | None) -> dict:
    """Save (or with None, clear) the book's contents: its tunes, as page ranges.

    The book stays ONE book. Nothing is copied and no arrangement or piece is
    made; the contents are how it is read, a tune at a time. An entry keeps its
    id across edits, so the app's place in the list survives a rename.
    Overlapping entries are allowed: two tunes printed on one page each own it.
    """
    doc = workspace.resolve_book(slug)
    if plan is None:
        doc.pop("contents", None)
    else:
        doc["contents"] = _validated(plan, int(doc.get("pages") or 0))
    workspace.save_book(slug, doc)
    return doc


def split(slug: str, plan: list[dict]) -> dict:
    """Take every entry of the plan out of the book as an arrangement, filed
    under a piece named after its title.

    A piece already called that is JOINED rather than duplicated -- the rule
    every import follows -- so "Drowsy Maggie" out of a tunebook lands beside
    the thesession.org settings already in the library. The report says which.
    """
    doc = workspace.resolve_book(slug)
    clean = _validated(plan, int(doc.get("pages") or 0))
    existing = {p["name"].casefold() for p in workspace.list_pieces()}
    made = []
    for item in clean:
        joined = item["title"].casefold() in existing
        score, entry = workspace.extract_from_book(
            slug, item["from"], item["to"], item["title"], item["title"])
        existing.add(item["title"].casefold())
        made.append({"score": score, "version": entry["id"],
                     "title": item["title"],
                     "pages": f"{item['from']}-{item['to']}",
                     "piece": item["title"], "joined_existing_piece": joined})
    return {"book": slug, "arrangements": made,
            "pieces_joined": sum(m["joined_existing_piece"] for m in made),
            "pieces_created": sum(not m["joined_existing_piece"] for m in made)}
