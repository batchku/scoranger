"""Regression check: no op may engrave an accidental the key already implies.

The report that caused this: "You've put a lot of accidental sharps in the alto
saxophone part that are in the key signature so it's just making it hard to
read." The agent answered that it could not fix them, which was true and is the
reason two things exist now -- a normalisation step the pitch-changing ops all
run, and a manual accidental tool for when a reader wants an override.

The mechanism, reproduced below: `respell` assigns a fresh `Accidental` to each
pitch it rewrites. A fresh accidental has `displayStatus = None`, and music21's
MusicXML writer PRINTS an accidental whose status is None. So respelling A-flat
to G-sharp inside A major -- where G-sharp is in the signature -- printed a
sharp on every one of them. Transposing imported material does the same to any
accidental the source had already marked as printed.

What is asserted here:

1. the redundant accidental is gone from the MusicXML after the op
2. it is gone from the VEROVIO SVG too, so the glyph is really not drawn
3. every pitch and every MIDI number is byte-for-byte what it was: this is a
   DISPLAY change and may never move a note
4. an accidental that is NOT in the key still prints, and still cancels
5. a transposing part is judged by its OWN written key, not concert pitch
6. the manual tools can force an accidental back on, take one off, and colour
   one, addressed the way the iPad's lasso addresses anything else

Fixtures are synthetic: the repository is public, so no committed fixture may
carry copyrighted music.

Run: engine/.venv/bin/python engine/scripts/check_accidentals.py
"""

import re
import sys
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import verovio                                                        # noqa: E402
from music21 import converter, instrument, key, meter, note, stream   # noqa: E402
from music21.musicxml.m21ToXml import ScoreExporter            # noqa: E402

from scoranger_engine import ops                               # noqa: E402

FAILURES: list[str] = []


def check(condition: bool, message: str) -> None:
    if condition:
        print(f"  ok   {message}")
    else:
        print(f"  FAIL {message}")
        FAILURES.append(message)


def xml_of(score) -> str:
    return ET.tostring(ScoreExporter(score).parse(), encoding="unicode")


def printed_accidentals(score) -> list[str]:
    """The accidentals the notation actually ENGRAVES, in order."""
    return re.findall(r"<accidental[^>]*>([^<]*)</accidental>", xml_of(score))


def fingerprint(score) -> list[tuple[str, int, float]]:
    """Every pitch, its MIDI number and its offset -- what may never change."""
    return [(str(n.pitch), n.pitch.midi, float(n.offset))
            for n in score.recurse().notes]


def round_tripped(score):
    """The score as the app actually holds it: written out and read back.

    This is not ceremony. music21 runs `makeAccidentals` at most ONCE per
    stream and records it in `streamStatus`; a freshly built score therefore
    gets normalised by the exporter on its way out, and nothing that has
    already been through a write ever gets normalised again. Every version in
    the app has been through a write, so a fixture built in memory and exported
    once proves nothing about the material a user actually has. Import also
    marks every printed accidental `displayStatus = True`, which is the state
    the redundant sharps arrive in.
    """
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "fixture.musicxml"
        score.write("musicxml", fp=str(path))
        return converter.parse(str(path))


def build(fifths: int, pitches: list[str], instrument_class=None,
          name: str = "Alto Sax"):
    score = stream.Score()
    part = stream.Part()
    part.partName = name
    part.insert(0, (instrument_class or instrument.AltoSaxophone)())
    measure = stream.Measure(number=1)
    measure.insert(0, key.KeySignature(fifths))
    measure.insert(0, meter.TimeSignature("4/4"))
    for p in pitches:
        measure.append(note.Note(p, quarterLength=1))
    part.append(measure)
    score.insert(0, part)
    return score


def check_respell_leaves_no_redundant_accidentals() -> None:
    """The reported case: flats respelled to sharps inside a sharp key."""
    print("respell in a key that already has the sharps")
    # A major has F#, C# and G#. Spelled with flats -- which is what OMR and
    # MIDI hand you -- and then respelled to sharps, every one of them was
    # printed as an accidental.
    score = round_tripped(build(3, ["A-4", "D-5", "A4", "E5"]))
    before = fingerprint(score)
    ops.respell(score, prefer="sharps")
    after = fingerprint(score)

    check(printed_accidentals(score) == [],
          "no accidental is printed for a pitch the key signature implies")
    check([p for p, _, _ in after] == ["G#4", "C#5", "A4", "E5"],
          "the respelling itself still happened")
    check([m for _, m, _ in before] == [m for _, m, _ in after],
          "no pitch moved: the MIDI numbers are unchanged")


def check_a_needed_accidental_survives() -> None:
    """Normalisation may not silence an accidental the reader needs."""
    print("an accidental outside the key")
    score = round_tripped(build(3, ["A4", "D#5", "D5", "E5"]))
    ops.normalize_accidentals(score)
    printed = printed_accidentals(score)
    check("sharp" in printed,
          "a D-sharp in A major still prints its sharp")
    check("natural" in printed,
          "and the D that follows it still prints its cancelling natural")


def check_transposing_part_uses_its_written_key() -> None:
    """An E-flat alto's accidentals are judged against what IS on its staff."""
    print("a transposing part")
    # The part is WRITTEN in A major. Concert pitch is C, which has no sharps
    # at all -- so a normalisation that used concert pitch would print every
    # one of these.
    score = round_tripped(build(3, ["A-4", "D-5", "E5", "A4"], name="Alto Sax"))
    ops.respell(score, prefer="sharps")
    check(printed_accidentals(score) == [],
          "the written key signature is what the accidentals are judged by")


def check_transpose_normalises_too() -> None:
    """Transposition is a pitch change, so it runs the same step."""
    print("transpose")
    score = round_tripped(build(0, ["C4", "E4", "G4", "C5"]))
    ops.transpose(score, "M6")
    check(printed_accidentals(score) == [],
          "transposing into a sharp key prints none of that key's sharps")


def check_pitches_are_never_touched() -> None:
    """The whole feature is display: it may not move or respell anything."""
    print("display only")
    score = round_tripped(build(-3, ["C5", "E-5", "A-5", "B-4"]))
    before = fingerprint(score)
    report = ops.normalize_accidentals(score)
    check(fingerprint(score) == before,
          "normalising accidentals changed no pitch, no MIDI number, no offset")
    check(isinstance(report, dict) and "parts" in report,
          "the op reports what it did per part")


def engraved(score) -> tuple[str, str]:
    """What Verovio actually draws: the MEI and the SVG of page 1."""
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "engrave.musicxml"
        score.write("musicxml", fp=str(path))
        toolkit = verovio.toolkit()
        toolkit.setOptions({"scale": 40, "footer": "none", "adjustPageHeight": True})
        if not toolkit.loadFile(str(path)):
            raise RuntimeError("Verovio refused the fixture")
        return toolkit.getMEI("{}"), toolkit.renderToSVG(1)


def drawn_accidentals(mei: str) -> int:
    """Accidentals with a VISUAL @accid -- the ones that become a glyph.

    Not a count of `<accid>` elements: Verovio emits one for the SOUNDING
    accidental too, carrying only @accid.ges, and that one is never drawn. The
    two counts differ by exactly the thing this feature controls, so counting
    the elements would have made every assertion below pass no matter what.
    """
    return len(re.findall(r'<accid\b[^>]*\baccid="', mei))


def glyph_uses(svg: str) -> int:
    return len(re.findall(r'<g[^>]*class="accid"[^>]*>\s*<use', svg))


def check_the_glyph_really_goes() -> None:
    """MusicXML is not the page. Verovio has to agree."""
    print("what Verovio draws")
    dirty = round_tripped(build(3, ["A-4", "D-5", "A4", "E5"]))
    ops.respell(dirty, prefer="sharps")
    mei, svg = engraved(dirty)
    check(drawn_accidentals(mei) == 0,
          "no accidental glyph is engraved for a pitch the key implies")
    check(glyph_uses(svg) == 0,
          "and the SVG holds no accidental glyph either")

    needed = round_tripped(build(3, ["A4", "D#5", "E5", "A4"]))
    ops.normalize_accidentals(needed)
    mei2, svg2 = engraved(needed)
    check(drawn_accidentals(mei2) >= 1 and glyph_uses(svg2) >= 1,
          "an accidental outside the key is still drawn")


def check_the_manual_tools() -> None:
    """Add, remove, show, hide, colour -- addressed the way a lasso addresses."""
    print("the manual tools")
    address = "s1/m1/l1/note#1"

    # force-show what the key implies: a courtesy accidental
    score = round_tripped(build(3, ["A4", "C#5", "E5", "A4"]))
    ops.normalize_accidentals(score)
    check(drawn_accidentals(engraved(score)[0]) == 0, "the C-sharp starts hidden")
    ops.set_accidental(score, [address], show=True)
    mei, svg = engraved(score)
    check(drawn_accidentals(mei) == 1 and glyph_uses(svg) == 1,
          "--show forces a courtesy accidental back onto the page")

    # hide one that would otherwise print
    score = round_tripped(build(3, ["A4", "D#5", "E5", "A4"]))
    before = fingerprint(score)
    ops.set_accidental(score, [address], show=False)
    check(glyph_uses(engraved(score)[1]) == 0, "--hide takes the glyph off")
    check(fingerprint(score) == before, "and hiding moved no pitch")

    # colour it
    score = round_tripped(build(3, ["A4", "D#5", "E5", "A4"]))
    ops.set_accidental(score, [address], show=True, color="#CC4125")
    mei, svg = engraved(score)
    check('color="#CC4125"' in mei, "the colour reaches the MEI")
    check(re.search(r'fill="#CC4125"', svg, re.I) is not None,
          "and Verovio draws the glyph in it")

    # add one: this is a PITCH change, and the report must say so
    score = round_tripped(build(0, ["C5", "D5", "E5", "F5"]))
    report = ops.set_accidental(score, [address], add="sharp")
    pitches = [p for p, _, _ in fingerprint(score)]
    check(pitches[1] == "D#5", f"--add sharp made the note D#5 (got {pitches[1]})")
    check(report["pitch_changes"] == 1,
          "the report states that a pitch changed, because one did")
    check(glyph_uses(engraved(score)[1]) == 1,
          "and the added accidental is engraved")

    # take one off again
    report = ops.set_accidental(score, [address], remove=True)
    check([p for p, _, _ in fingerprint(score)][1] == "D5",
          "--remove puts it back to a natural D")
    check(report["pitch_changes"] == 1, "which is also a pitch change")


def check_an_unknown_address_is_reported_not_swallowed() -> None:
    print("addresses that no longer exist")
    score = round_tripped(build(0, ["C5", "D5", "E5", "F5"]))
    report = ops.set_accidental(score, ["s1/m1/l1/note#0", "s1/m99/l1/note#0"],
                                show=True)
    check(len(report["missing"]) == 1,
          "the address that landed is used and the one that did not is reported")
    check(report["resolved"] == 1, "and the count says how many were operated on")


def main() -> int:
    check_respell_leaves_no_redundant_accidentals()
    check_a_needed_accidental_survives()
    check_transposing_part_uses_its_written_key()
    check_transpose_normalises_too()
    check_pitches_are_never_touched()
    check_the_glyph_really_goes()
    check_the_manual_tools()
    check_an_unknown_address_is_reported_not_swallowed()

    print()
    if FAILURES:
        print(f"{len(FAILURES)} FAILED")
        for f in FAILURES:
            print(f"  - {f}")
        return 1
    print("all accidental checks passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
