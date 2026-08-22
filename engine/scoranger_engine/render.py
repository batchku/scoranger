"""MusicXML -> PDF rendering: Verovio (engraving to SVG) + cairosvg + pypdf.

Pure-Python pipeline, no external apps. Chord-symbol accidentals use glyphs
from Verovio's music-text font, which cairosvg can't resolve — they are
substituted with plain 'b'/'#' before conversion.
"""

import io
import re
import tempfile
import threading
from pathlib import Path

# Verovio's toolkit only reliably finds its font resources on first
# construction in a process — keep one instance, serialize access.
_tk = None
_tk_lock = threading.Lock()


def _toolkit():
    global _tk
    if _tk is None:
        import verovio
        _tk = verovio.toolkit()
        # Parity with the on-device renderer: trim each page to its content.
        # Verovio otherwise pads every page to full A4 height, so a partly
        # filled page exports as a tall white void. Passed as a dict — this
        # binding rejects the JSON-string form setOptions also accepts.
        _tk.setOptions({"adjustPageHeight": True})
    return _tk


# Verovio text-font glyphs (U+EA6x) and plain unicode accidentals -> ASCII
ACCIDENTAL_TEXT = {
    "": "b", "♭": "b",   # flat
    "": "#", "♯": "#",   # sharp
    "": "", "♮": "",     # natural
    "": "b", "": "#", "": "",  # SMuFL fallbacks
}

_MUSIC_TSPAN = re.compile(
    r'<tspan font-family="(?:Leipzig|VerovioText)"[^>]*?'
    r'font-size="(\d+)(?:\.\d+)?px"[^>]*>(.)</tspan>')


def _sanitize_svg(svg: str) -> str:
    """Replace music-font accidental glyphs in chord-symbol text with b/#.

    The glyph tspans are oversized relative to the surrounding text
    (~16:9), so the substitute letter is scaled back down to match.
    """
    def sub(m):
        rep = ACCIDENTAL_TEXT.get(m.group(2))
        if rep is None:
            return m.group(0)
        size = int(round(int(m.group(1)) * 0.5625))
        return f'<tspan font-size="{size}px">{rep}</tspan>'

    svg = _MUSIC_TSPAN.sub(sub, svg)
    for ch, rep in ACCIDENTAL_TEXT.items():
        svg = svg.replace(ch, rep)
    return svg


def _style_chart_svg(svg: str, harm_staves: set[int], grey: str = "#8f8f8f") -> str:
    """Chart cosmetics Verovio can't express: sans-serif bold chord names and
    grey staff furniture on chord-symbol staves.

    Staff-line paths carry no explicit stroke/fill, so attributes set on the
    n-th `g.staff` group of each measure inherit down; harm text lives in its
    own groups and stays black.
    """
    svg = re.sub(r'(<g\b[^>]*class="harm"[^>]*)>',
                 r'\1 font-family="Helvetica, Arial, sans-serif">', svg)
    if not harm_staves:
        return svg
    out = []
    pos = 0
    staff_idx = 0
    for m in re.finditer(r'<g\b[^>]*class="(measure|staff)"[^>]*>', svg):
        if m.group(1) == "measure":
            staff_idx = 0
            continue
        staff_idx += 1
        if staff_idx in harm_staves:
            out.append(svg[pos:m.start()])
            out.append(m.group(0)[:-1] + f' stroke="{grey}" fill="{grey}" color="{grey}">')
            pos = m.end()
    out.append(svg[pos:])
    return "".join(out)


WHISTLE_TAG = "wf"
_VERSE_RE = re.compile(r'<g[^>]*class="verse">.*?</g>\s*</g>', re.S)
_SYMBOL_RE = re.compile(r'>([XO/])</tspan>')
_X_RE = re.compile(r'<text x="([-\d.]+)"')
_Y_RE = re.compile(r'<text[^>]*y="([-\d.]+)"')
_SIZE_RE = re.compile(r'<tspan font-size="([\d.]+)px">')
_TEXT_RE = re.compile(r"<text.*?</text>", re.S)


def _fingering_diagrams(svg: str) -> str:
    """Replace tagged whistle-fingering glyphs with drawn circles.

    Verovio lays the fingerings out as lyric verses, which is what centres them
    under each notehead; it cannot draw a filled circle, and the circle glyphs
    are missing from the font the rasterizer falls back to. So the letters are
    the notation and the circles are the drawing. Mirrors
    ios/Scoranger/FingeringDiagrams.swift — keep the two in step.
    """
    if f">{WHISTLE_TAG}<" not in svg:
        return svg

    def one(match: "re.Match[str]") -> str:
        block = match.group(0)
        if f">{WHISTLE_TAG}</title>" not in block:
            return block
        symbol = _SYMBOL_RE.search(block)
        x, y = _X_RE.search(block), _Y_RE.search(block)
        size = _SIZE_RE.search(block)
        if not (symbol and x and y and size):
            return block
        cx = float(x.group(1)) + 0.36 * float(size.group(1))
        cy = float(y.group(1)) - 0.35 * float(size.group(1))
        r = 0.28 * float(size.group(1))
        stroke = 0.07 * float(size.group(1))
        # paths rather than <circle>: the on-device renderer draws only the
        # subset Verovio emits, and a <circle> vanished there
        ring = (f'M {cx - r} {cy} A {r} {r} 0 1 0 {cx + r} {cy} '
                f'A {r} {r} 0 1 0 {cx - r} {cy} Z')
        if symbol.group(1) == "X":
            shape = f'<path d="{ring}" fill="currentColor" stroke="none" />'
        elif symbol.group(1) == "O":
            shape = (f'<path d="{ring}" fill="none" stroke="currentColor" '
                     f'stroke-width="{stroke}" />')
        else:
            shape = (f'<path d="{ring}" fill="none" stroke="currentColor" '
                     f'stroke-width="{stroke}" />'
                     f'<path d="M {cx - r} {cy} A {r} {r} 0 0 0 {cx + r} {cy} Z" '
                     f'fill="currentColor" stroke="none" />')
        return _TEXT_RE.sub(shape, block, count=1)

    return _VERSE_RE.sub(one, svg)


def render_pdf(musicxml_path, out_path, parts: list[str] | None = None,
               title: str | None = None) -> dict:
    import cairosvg
    from pypdf import PdfReader, PdfWriter

    src = str(musicxml_path)
    kept = None
    if parts or title:
        from music21 import converter, metadata as m21metadata

        from . import ops
        s = converter.parse(src, forceSource=True)
        if parts:
            ops.keep_parts(s, parts)
            kept = ops.list_part_labels(s)
        if title:
            if s.metadata is None:
                s.metadata = m21metadata.Metadata()
            s.metadata.title = title
            s.metadata.movementName = title
        with tempfile.NamedTemporaryFile(suffix=".musicxml", delete=False) as tmp:
            src = tmp.name
        s.write("musicxml", fp=src)

    writer = PdfWriter()
    with _tk_lock:
        tk = _toolkit()
        if not tk.loadFile(src):
            raise RuntimeError(f"Verovio could not load {src}")
        mei = tk.getMEI()
        if "<harm" in mei:
            # Real Book chord-lane styling, applied semantically in MEI:
            # names ON the staff, centered in the bar, Helvetica bold, and
            # grey staff lines on any staff that carries chord symbols.
            mei = re.sub(r'(<harm\b[^>]*?)\s+place="[^"]*"', r"\1", mei)
            mei = re.sub(r"<harm\b", '<harm place="within"', mei)
            meter = re.search(r'<meterSig[^>]*\bcount="(\d+)"', mei) or re.search(
                r'meter\.count="(\d+)"', mei)
            if meter:
                mid = (int(meter.group(1)) + 1) / 2
                mei = re.sub(r'(<harm\b[^>]*?)tstamp="[^"]*"',
                             rf'\1tstamp="{mid:g}"', mei)
            mei = re.sub(
                r"(<harm\b[^>]*>)([^<]+)(</harm>)",
                r'\1<rend fontweight="bold" fontsize="150%">\2</rend>\3',
                mei)
            harm_staves = {int(n) for n in re.findall(r'<harm\b[^>]*\bstaff="(\d+)"', mei)}
            if not tk.loadData(mei):
                raise RuntimeError("Verovio could not reload MEI with chart styling")
        else:
            harm_staves = set()
        n_pages = tk.getPageCount()
        svgs = [_fingering_diagrams(
                    _style_chart_svg(_sanitize_svg(tk.renderToSVG(p)), harm_staves))
                for p in range(1, n_pages + 1)]
    for svg in svgs:
        pdf_page = cairosvg.svg2pdf(bytestring=svg.encode())
        writer.append(PdfReader(io.BytesIO(pdf_page)))
    out = Path(out_path)
    out.parent.mkdir(parents=True, exist_ok=True)
    with open(out, "wb") as f:
        writer.write(f)
    return {"pages": n_pages, "out": str(out), "parts": kept or "all"}
