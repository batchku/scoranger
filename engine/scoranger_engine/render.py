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
# five or six single X/O/ verses on one note is a fingering, tag or no tag
WHISTLE_COLUMN = 5
_VERSE_RE = re.compile(r'<g[^>]*class="verse">.*?</g>\s*</g>', re.S)
_SYMBOL_RE = re.compile(r'>([XO/])</tspan>')
_X_RE = re.compile(r'<text x="([-\d.]+)"')
_Y_RE = re.compile(r'<text[^>]*y="([-\d.]+)"')
_SIZE_RE = re.compile(r'<tspan font-size="([\d.]+)px">')
_TEXT_RE = re.compile(r"<text.*?</text>", re.S)
_LABEL_RE = re.compile(r'<title class="labelAttr">([^<]*)</title>')
_ANY_SYL_RE = re.compile(r'>([^<>]{1,3})</tspan>')


# Fingerings sit above the staff, and small. Verovio ignores MusicXML's
# lyric placement="above", but honours MEI's place attribute on <verse>, so the
# move happens on the MEI round trip.
#
# The SIZE is ours to decide, not Verovio's. `lyricSize` is a single
# document-wide text size and it governs <harm> chord symbols as well as lyric
# verses, so halving it to shrink the diagrams also halved every chord name on
# the page -- unreadable, on exactly the scores a whistle player uses. So the
# option stays at its default and the diagrams are scaled here, in the pass
# that draws them. DIAGRAM_SCALE is the same 2.2-in-4.5 the diagrams shipped
# at, expressed where it belongs.
DEFAULT_LYRIC_SIZE = 4.5          # Verovio's default, in MEI units
DIAGRAM_SCALE = 2.2 / 4.5         # what the diagrams were shrunk to, ~0.49
# The point size a chord symbol engraves at when nobody has adjusted it, so a
# stored absolute size can be expressed as a ratio of the engraved glyph.
DEFAULT_CHORD_POINTS = 12.0

# Circle geometry as proportions of the verse glyph they replace, before the
# diagram scale is applied. Mirrored in ios/Scoranger/FingeringDiagrams.swift.
HOLE_CENTRE_X = 0.36              # half a glyph advance
HOLE_CENTRE_Y = -0.35             # above the text baseline
HOLE_RADIUS = 0.28
HOLE_STROKE = 0.07


def lyric_size_for(fingerings: bool) -> float:
    """The text size to render at. One answer, whatever the score carries.

    Kept as a function because it used to return something smaller for fingered
    scores, and the whole point of the fix is that it no longer does. A caller
    that asks is told the default; a future caller that wants to shrink text
    has to come through here and read why not.
    """
    return DEFAULT_LYRIC_SIZE

# A chord carries the verses when the fingered note is part of one, so both
# element names have to be scanned — chord first, so its inner notes are not
# matched separately.
_MEI_NOTE_RE = re.compile(r"<(chord|note)\b[^>]*>.*?</\1>", re.S)
_MEI_VERSE_RE = re.compile(r"<verse\b[^>]*>.*?</verse>", re.S)
_MEI_SYL_RE = re.compile(r"<syl\b[^>]*>([^<]*)</syl>")


def _is_fingering_verse_set(verses: list[str]) -> bool:
    """Do these verses of one note form a fingering column?

    Same rule as the SVG pass: five or six single holes, with the octave "+"
    allowed alongside. Applied here so fingerings written before the `wf` tag
    existed move above the staff too.
    """
    holes = 0
    for verse in verses:
        syl = _MEI_SYL_RE.search(verse)
        text = (syl.group(1) if syl else "").strip()
        if text in ("X", "O", "/"):
            holes += 1
        elif text != "+":
            return False
    return holes >= WHISTLE_COLUMN


def mei_with_fingerings_above(mei: str) -> str | None:
    """Mark fingering verses `place="above"`. None when there are none."""
    if "<verse" not in mei:
        return None
    changed = False

    def one_note(match: "re.Match[str]") -> str:
        nonlocal changed
        block = match.group(0)
        verses = _MEI_VERSE_RE.findall(block)
        if len(verses) < WHISTLE_COLUMN:
            return block
        tagged = all('label="wf"' in v for v in verses)
        if not (tagged or _is_fingering_verse_set(verses)):
            return block
        changed = True
        return _MEI_VERSE_RE.sub(
            lambda v: v.group(0) if 'place=' in v.group(0).split(">")[0]
            else v.group(0).replace("<verse", '<verse place="above"', 1),
            block)

    out = _MEI_NOTE_RE.sub(one_note, mei)
    return out if changed else None


# Chord-symbol adjustments. Verovio's MusicXML importer drops `font-size`,
# `relative-x` and `relative-y` from <harmony>, so the values a user set have to
# be carried across by hand: position into MEI @ho/@vo, which Verovio honours
# per element, and size into the SVG afterwards, because Verovio has no
# per-element text size at all -- @fontsize is ignored as a percentage and as a
# keyword. Mirrored in ios/Scoranger/ChordAdjustments.swift; keep the two in step.
_HARMONY_TAG_RE = re.compile(r"<harmony\b[^>]*>")
_HARM_MEI_RE = re.compile(r"<harm\b")
# A chord symbol's glyph carries x and y after its size, so the fingering-era
# pattern (which expects the tag to close right after font-size) never matches
# it. Same trap, different tag.
_CHORD_SIZE_RE = re.compile(r'(<tspan[^>]*font-size=")([\d.]+)(px")')
# MEI units are half-spaces; MusicXML tenths are tenths of a staff space.
_TENTHS_TO_HALF_SPACES = 0.2


def chord_adjustments(musicxml_path) -> list[dict]:
    """Each chord symbol's size and offset, in document order.

    Read straight from the file rather than from a parsed score: the renderer
    only needs three numbers per symbol, and the MEI it is matching against is
    in the same order.
    """
    try:
        text = Path(musicxml_path).read_text(encoding="utf-8")
    except OSError:
        return []
    out = []
    for tag in _HARMONY_TAG_RE.findall(text):
        def number(attr):
            found = re.search(rf'{attr}="([-\d.]+)"', tag)
            return float(found.group(1)) if found else None
        out.append({"size": number("font-size"),
                    "dx": number("relative-x"), "dy": number("relative-y")})
    return out


def mei_with_chord_adjustments(mei: str, musicxml_path) -> str | None:
    """Carry each chord symbol's offset into the MEI, or None if none have one."""
    adjustments = chord_adjustments(musicxml_path)
    if not any(a["dx"] is not None or a["dy"] is not None for a in adjustments):
        return None

    index = 0

    def place(match):
        nonlocal index
        adjustment = adjustments[index] if index < len(adjustments) else {}
        index += 1
        attrs = ""
        if adjustment.get("dx") is not None:
            attrs += f' ho="{adjustment["dx"] * _TENTHS_TO_HALF_SPACES:g}"'
        if adjustment.get("dy") is not None:
            # MusicXML measures up, MEI @vo measures down
            attrs += f' vo="{-adjustment["dy"] * _TENTHS_TO_HALF_SPACES:g}"'
        return match.group(0) + attrs

    return _HARM_MEI_RE.sub(place, mei)


def apply_chord_sizes(svg: str, musicxml_path) -> str:
    """Rescale each adjusted chord symbol's glyph in the rendered SVG.

    The size lives on the INNER tspan; the enclosing <text> is font-size="0px",
    and reading that is what once gave every fingering circle a radius of zero.
    """
    adjustments = chord_adjustments(musicxml_path)
    if not any(a["size"] is not None for a in adjustments):
        return svg

    blocks = list(re.finditer(r'<g[^>]*class="harm".*?</g>\s*</g>', svg, re.S))
    if not blocks:
        return svg

    out, cursor = [], 0
    for index, block in enumerate(blocks):
        out.append(svg[cursor:block.start()])
        text = block.group(0)
        wanted = adjustments[index]["size"] if index < len(adjustments) else None
        if wanted is not None:
            base = _CHORD_SIZE_RE.search(text)
            if base and float(base.group(2)) > 0:
                # the stored size is in points; scale the engraved glyph by the
                # ratio to the default, so it stays right at any page scale
                scale = float(wanted) / DEFAULT_CHORD_POINTS
                text = _CHORD_SIZE_RE.sub(
                    lambda m: f"{m.group(1)}{float(m.group(2)) * scale:g}{m.group(3)}",
                    text, count=1)
        out.append(text)
        cursor = block.end()
    out.append(svg[cursor:])
    return "".join(out)


def _fingering_diagrams(svg: str) -> str:
    """Replace whistle-fingering glyphs with drawn circles.

    Verovio lays the fingerings out as lyric verses, which is what centres them
    under each notehead; it cannot draw a filled circle, and the circle glyphs
    are missing from the font the rasterizer falls back to. So the letters are
    the notation and the circles are the drawing.

    Two kinds of verse qualify: ones the engine tagged (<lyric name="wf">), and
    untagged columns of five or six single X/O/ verses on one note — fingerings
    written before the tag existed, which are already sitting in scores.
    Mirrors ios/Scoranger/FingeringDiagrams.swift; keep the two in step.
    """
    if 'class="verse"' not in svg:
        return svg

    verses = list(_VERSE_RE.finditer(svg))
    if not verses:
        return svg

    parsed = []
    for match in verses:
        block = match.group(0)
        symbol = _SYMBOL_RE.search(block)
        label = _LABEL_RE.search(block)
        text = label.group(1) if label else ""
        parsed.append({
            "match": match,
            "block": block,
            "tagged": text == WHISTLE_TAG,
            "symbol": symbol.group(1) if symbol else None,
            # the verse number, which restarts at 1 on each note. Grouping on
            # this rather than on x: Verovio centres each syllable on its own
            # width, so "X" and "O" verses of the SAME note sit at different x
            # and a column of mixed holes never grouped.
            "number": int(text) if text.isdigit() else None,
            "text": (_ANY_SYL_RE.search(block).group(1)
                     if _ANY_SYL_RE.search(block) else None),
        })

    convert = [bool(v["tagged"] and v["symbol"]) for v in parsed]
    start = 0
    while start < len(parsed):
        end = start
        while (end + 1 < len(parsed)
               and parsed[end]["number"] is not None
               and parsed[end + 1]["number"] is not None
               and parsed[end + 1]["number"] > parsed[end]["number"]):
            end += 1
        run = parsed[start:end + 1]
        holes = sum(1 for v in run if v["symbol"])
        # the "+" octave mark belongs to the column but is not a hole; it stays
        # text. Requiring every verse to be a hole rejected the second octave.
        only_holes_and_octave = all(v["symbol"] or v["text"] == "+" for v in run)
        if holes >= WHISTLE_COLUMN and only_holes_and_octave:
            for i in range(start, end + 1):
                if parsed[i]["symbol"]:
                    convert[i] = True
        start = end + 1

    if not any(convert):
        return svg

    # A column's octave "+" stays text -- every font has it, unlike the circle
    # glyphs -- but it belongs to the diagram, so it is scaled with the holes
    # rather than left at the engraving's full text size. The engine tags every
    # whistle verse including the "+", so the tag identifies it directly; the
    # verse-number grouping above cannot, because a tagged verse carries the tag
    # in the label where a number would otherwise be.
    out, cursor = [], 0
    for wanted, v in zip(convert, parsed):
        match = v["match"]
        out.append(svg[cursor:match.start()])
        if wanted:
            out.append(_draw_hole(v["block"]))
        elif v["tagged"] and v["text"] == "+":
            out.append(_scale_text(v["block"]))
        else:
            out.append(v["block"])
        cursor = match.end()
    out.append(svg[cursor:])
    return "".join(out)


def _scale_text(block: str) -> str:
    """Shrink a verse's glyph to the diagram scale, leaving it as text."""
    def shrink(m):
        return f'<tspan font-size="{float(m.group(1)) * DIAGRAM_SCALE:g}px">'
    return _SIZE_RE.sub(shrink, block, count=1)


def _draw_hole(block: str) -> str:
    """One verse, already judged to be a hole."""
    symbol = _SYMBOL_RE.search(block)
    x, y = _X_RE.search(block), _Y_RE.search(block)
    size = _SIZE_RE.search(block)
    if not (symbol and x and y and size):
        return block
    font = float(size.group(1))
    if font <= 0:
        return block
    # the glyph is full size now; the diagram drawn in its place is not
    drawn = font * DIAGRAM_SCALE
    cx = float(x.group(1)) + HOLE_CENTRE_X * drawn
    cy = float(y.group(1)) + HOLE_CENTRE_Y * drawn
    r = HOLE_RADIUS * drawn
    stroke = HOLE_STROKE * drawn
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
        # Fingerings go above their staff and render small. Verovio ignores
        # MusicXML's lyric placement, so the move is made on the MEI and the
        # document reloaded — the same round trip the chart styling below uses.
        above = mei_with_fingerings_above(mei)
        tk.setOptions({"lyricSize": lyric_size_for(fingerings=above is not None)})
        if above is not None:
            mei = above
            if not tk.loadData(mei):
                raise RuntimeError("Verovio could not reload MEI with fingerings above")
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
