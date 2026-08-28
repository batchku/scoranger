"""Every page of a score is the same size.

Ali's screenshot: in a two-page spread the left page's bottom edge sat higher
than the right page's. Two pages of one score, two different heights.

The cause is `adjustPageHeight`, added in build 119 for a real reason -- without
it Verovio pads every page to full height, so a partly filled last page exported
as a tall white void that read as broken layout. Trimming each page to its own
content fixed the void and created this: a page with less music on it is
literally a shorter page.

The trade is settled the other way now, and it is the right way round for
something people read: **a page is a fixed size**. A partial last page with
white at the bottom is what paper does; pages of different heights is not
something paper can do at all.

US Letter portrait, because that is what the sources are -- the sample PDFs in
this repo measure 8.5x11 and 8.26x11.69 (A4), both portrait.

Run: engine/.venv/bin/python engine/scripts/check_page_size.py
"""

import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "engine"))

FAILURES: list[str] = []


def check(label: str, ok: bool, detail: str = "") -> None:
    if ok:
        print(f"  ok   {label}")
    else:
        FAILURES.append(f"{label}{': ' + detail if detail else ''}")
        print(f"  FAIL {label}{': ' + detail if detail else ''}")


def build_long_score(path: Path, bars: int) -> None:
    """Long enough to run to several pages, with a last page barely filled."""
    from music21 import meter, note, stream

    score = stream.Score()
    part = stream.Part()
    part.partName = "Flute"
    part.append(meter.TimeSignature("4/4"))
    for index in range(bars):
        measure = stream.Measure(number=index + 1)
        for pitch in ("C4", "D4", "E4", "F4"):
            measure.append(note.Note(pitch, quarterLength=1.0))
        part.append(measure)
    score.append(part)
    score.write("musicxml", fp=str(path))


def main() -> int:
    import pypdf
    from scoranger_engine import render

    workspace = Path(tempfile.mkdtemp(prefix="scoranger-pagesize-"))

    print("the size the renderer is set to")
    check("a fixed page height is configured",
          render.PAGE_HEIGHT_TENTHS_MM > 0, str(render.PAGE_HEIGHT_TENTHS_MM))
    check("a fixed page width is configured",
          render.PAGE_WIDTH_TENTHS_MM > 0, str(render.PAGE_WIDTH_TENTHS_MM))
    check("it is portrait, like the sources",
          render.PAGE_HEIGHT_TENTHS_MM > render.PAGE_WIDTH_TENTHS_MM,
          f"{render.PAGE_WIDTH_TENTHS_MM}x{render.PAGE_HEIGHT_TENTHS_MM}")
    # The layout size is in tenths of a millimetre -- Verovio's own A4 default
    # is 2100x2970 -- so US Letter is 2159x2794. Asserted as MILLIMETRES rather
    # than as the two numbers, because the bug this catches was setting them in
    # a different unit entirely and getting a postcard.
    check("the page Verovio lays out on is really US Letter",
          abs(render.PAGE_WIDTH_TENTHS_MM / 10 - 215.9) < 1
          and abs(render.PAGE_HEIGHT_TENTHS_MM / 10 - 279.4) < 1,
          f"{render.PAGE_WIDTH_TENTHS_MM / 10}mm x {render.PAGE_HEIGHT_TENTHS_MM / 10}mm")

    print("\na score that runs to several pages, ending part way down one")
    src = workspace / "long.musicxml"
    build_long_score(src, bars=90)
    out = workspace / "long.pdf"
    render.render_pdf(str(src), str(out))
    check("it rendered", out.exists() and out.stat().st_size > 2000,
          f"{out.stat().st_size if out.exists() else 0} bytes")

    reader = pypdf.PdfReader(str(out))
    pages = len(reader.pages)
    check("it really is more than one page", pages > 1, str(pages))

    sizes = {(round(float(p.mediabox.width), 1), round(float(p.mediabox.height), 1))
             for p in reader.pages}
    check("EVERY page is the same size", len(sizes) == 1,
          f"{pages} pages with {len(sizes)} different sizes: {sorted(sizes)}")

    if len(sizes) == 1:
        width, height = sizes.pop()
        inches = (round(width / 72, 2), round(height / 72, 2))
        print(f"       every page is {inches[0]}x{inches[1]} inches")
        check("it is US Letter portrait",
              inches == (8.5, 11.0), f"{inches[0]}x{inches[1]}")

    # The assertion the first version of this check was missing.
    #
    # It measured the paper and not the music, so a page told to Verovio in the
    # wrong unit -- 82 x 106mm, a postcard -- passed cleanly: the PDF was still
    # 8.5x11, because the physical size is applied afterwards. What gave it away
    # on the iPad was the page counter reading 131. A page that is really Letter
    # takes a 90-bar single-staff jig in a handful of pages; a postcard takes
    # thirty.
    print("\nand the music is laid out for a page that size")
    check("ninety bars of one staff fit in a handful of pages",
          pages <= 6,
          f"{pages} pages -- at that rate the page Verovio is laying out on is "
          f"far smaller than the paper it is printed on")

    print("\nthe same holds for a short score that fills less than one page")
    short_src = workspace / "short.musicxml"
    build_long_score(short_src, bars=4)
    short_out = workspace / "short.pdf"
    render.render_pdf(str(short_src), str(short_out))
    short = pypdf.PdfReader(str(short_out))
    short_sizes = {(round(float(p.mediabox.width), 1), round(float(p.mediabox.height), 1))
                   for p in short.pages}
    check("a nearly empty page is still a full page", len(short_sizes) == 1,
          str(sorted(short_sizes)))

    print("\nand a four-bar score matches a ninety-bar one")
    check("both scores use the same page size", short_sizes == sizes or not sizes,
          "a short score and a long one must not paginate to different sizes")

    print()
    if FAILURES:
        print(f"FAILED: {len(FAILURES)}")
        for f in FAILURES:
            print(f"  - {f}")
        return 1
    print("OK: every page of every score is the same fixed size -- a partial "
          "page carries white at the bottom, which is what paper does, rather "
          "than being trimmed into a shorter page")
    return 0


if __name__ == "__main__":
    sys.exit(main())
