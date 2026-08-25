#!/usr/bin/env python3
"""Prove the element-address join.

An address like `s1/m15/l1/note#3` is produced by the iPad from the MEI that
Verovio engraves. The engine resolves it against music21's parse of the same
MusicXML. Those are two independent models of one document, and if the join is
subtly wrong an operation edits the WRONG NOTE -- which is worse than the bug
it was built to fix, because an op that hits the whole bar is at least visible.

So this does not test the resolver against itself. It engraves each fixture
with the real Verovio, reads addresses out of the MEI with the SAME rules the
Swift parser uses (MEISemanticsParser: measure @n / staff @n / layer @n, and an
ordinal counting elements of that kind in document order), resolves every one
of them through ops.resolve_address, and asserts the pitch music21 gives back
is the pitch the MEI says is there.

Run: engine/.venv/bin/python engine/scripts/check_addresses.py
"""
import sys
import re
import xml.etree.ElementTree as ET
from fractions import Fraction
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from music21 import chord as m21chord, note as m21note  # noqa: E402
from scoranger_engine import ops, render  # noqa: E402
import fixtures  # noqa: E402

MEI_NS = "{http://www.music-encoding.org/ns/mei}"
FAILURES = []


def check(condition, message):
    if not condition:
        FAILURES.append(message)
    return condition


def addresses_from_mei(mei: str) -> list[dict]:
    """The app's parser, in Python.

    Mirrors ios/Scoranger/ScoreModel/MEISemanticsParser.swift: a stack of
    measure/staff/layer, and a counter per (measure, staff, layer, kind) giving
    each element its ordinal in document order. Kept deliberately close to the
    Swift so a divergence in either is visible here.
    """
    root = ET.fromstring(mei)
    found = []
    counters = {}

    def walk(node, measure, staff, layer):
        tag = node.tag.replace(MEI_NS, "")
        if tag == "measure":
            measure = int(node.get("n") or 0)
        elif tag == "staff":
            staff = int(node.get("n") or 0)
        elif tag == "layer":
            layer = int(node.get("n") or 1)
        elif tag in ("note", "chord", "rest"):
            key = (measure, staff, layer, tag)
            ordinal = counters.get(key, 0)
            counters[key] = ordinal + 1
            entry = {"staff": staff, "measure": measure, "layer": layer,
                     "kind": tag, "ordinal": ordinal,
                     "text": f"s{staff}/m{measure}/l{layer}/{tag}#{ordinal}"}
            if tag == "note":
                entry["pname"] = node.get("pname")
                entry["oct"] = node.get("oct")
            found.append(entry)
        for child in node:
            walk(child, measure, staff, layer)

    walk(root, 0, 0, 1)
    return found


def mei_for(score) -> str:
    tk = render._toolkit()
    xml = render._musicxml_string(score) if hasattr(render, "_musicxml_string") else None
    if xml is None:
        from music21 import converter  # noqa: F401
        import tempfile
        with tempfile.NamedTemporaryFile(suffix=".musicxml", delete=False) as f:
            score.write("musicxml", fp=f.name)
            xml = Path(f.name).read_text()
    if not tk.loadData(xml):
        raise SystemExit("Verovio could not load the fixture")
    return tk.getMEI()


def pitch_of(owner, pitch_index):
    if isinstance(owner, m21note.Rest):
        return None
    if pitch_index is None:
        if isinstance(owner, m21chord.Chord):
            return None
        return owner.pitch
    return owner.pitches[pitch_index]


def check_fixture(name, score):
    mei = mei_for(score)
    entries = addresses_from_mei(mei)
    notes = [e for e in entries if e["kind"] == "note" and e.get("pname")]
    check(len(notes) > 0, f"{name}: the MEI carried no notes at all")

    agreed = 0
    for e in notes:
        try:
            owner, pitch_index, _kind = ops.resolve_address(score, e["text"])
        except ops.AddressError as exc:
            FAILURES.append(f"{name}: {e['text']} did not resolve: {exc}")
            continue
        p = pitch_of(owner, pitch_index)
        if p is None:
            FAILURES.append(f"{name}: {e['text']} resolved to a rest or bare chord")
            continue
        want = f"{e['pname'].upper()}{e['oct']}"
        got = f"{p.step}{p.octave}"
        if want != got:
            FAILURES.append(
                f"{name}: {e['text']} -- MEI says {want}, music21 resolution says {got}")
        else:
            agreed += 1
    print(f"  {name}: {agreed}/{len(notes)} note addresses agree with the MEI")
    return agreed, len(notes)


def check_transpose_touches_only_the_selection():
    """The actual bug: a chord selected, the whole bar moved."""
    score = fixtures.quartet(bars=4)
    mei = mei_for(score)
    entries = addresses_from_mei(mei)
    bar2 = [e for e in entries
            if e["kind"] == "note" and e["measure"] == 2 and e["staff"] == 1]
    check(len(bar2) >= 2, "the fixture's bar 2 has too few notes to test with")
    if len(bar2) < 2:
        return

    chosen = [bar2[0]["text"]]
    before = {}
    for e in bar2:
        owner, idx, _ = ops.resolve_address(score, e["text"])
        before[e["text"]] = str(pitch_of(owner, idx))

    report = ops.transpose_elements(score, "M2", chosen)
    check(report["elements_transposed"] == 1,
          f"expected 1 element transposed, got {report['elements_transposed']}")

    moved, stayed = [], []
    for e in bar2:
        owner, idx, _ = ops.resolve_address(score, e["text"])
        (moved if str(pitch_of(owner, idx)) != before[e["text"]] else stayed).append(e["text"])
    check(moved == chosen,
          f"transpose moved {moved}, but only {chosen} was selected")
    check(len(stayed) == len(bar2) - 1,
          "the rest of the bar did not stay put")
    print(f"  scoping: 1 of {len(bar2)} notes in the bar moved, "
          f"{len(stayed)} untouched")


def check_a_chord_moves_one_note_only():
    """A chord is ONE music21 object holding several pitches. Transposing a
    selected note of it must not move its neighbours."""
    from music21 import stream, chord as c, meter
    score = stream.Score()
    part = stream.Part()
    m = stream.Measure(number=1)
    m.append(meter.TimeSignature("4/4"))
    m.append(c.Chord(["C4", "E4", "G4"], quarterLength=4))
    part.append(m)
    score.append(part)

    entries = addresses_from_mei(mei_for(score))
    notes = [e for e in entries if e["kind"] == "note"]
    check(len(notes) == 3, f"expected a 3-note chord in the MEI, saw {len(notes)}")
    if len(notes) != 3:
        return
    ops.transpose_elements(score, "M2", [notes[0]["text"]])
    got = sorted(str(p) for p in score.recurse().getElementsByClass(c.Chord)[0].pitches)
    # only the addressed note moves; the other two are where they were
    check("E4" in got and "G4" in got,
          f"transposing one note of a chord disturbed the others: {got}")
    check("D4" in got, f"the addressed note did not move: {got}")
    print(f"  chord: one note moved, neighbours intact -> {got}")


def check_missing_addresses_are_reported_not_guessed():
    score = fixtures.jig(bars=4)
    out = ops.resolve_elements(score, ["s1/m2/l1/note#0", "s1/m99/l1/note#0",
                                       "s9/m1/l1/note#0"])
    check(len(out["resolved"]) == 1, "a valid address was lost")
    check(len(out["missing"]) == 2, "invalid addresses were not reported")
    check(all("why" in m for m in out["missing"]), "a missing address gave no reason")
    print(f"  missing: {len(out['resolved'])} resolved, "
          f"{len(out['missing'])} reported rather than guessed")


def check_rhythm_is_untouched():
    """Transposing must not move anything in time."""
    score = fixtures.jig(bars=6)
    entries = addresses_from_mei(mei_for(score))
    notes = [e["text"] for e in entries if e["kind"] == "note"][:5]
    before = [(m.number, Fraction(m.duration.quarterLength))
              for m in score.parts[0].getElementsByClass("Measure")]
    ops.transpose_elements(score, "m3", notes)
    after = [(m.number, Fraction(m.duration.quarterLength))
             for m in score.parts[0].getElementsByClass("Measure")]
    check(before == after, "transposing a selection changed the bar lengths")
    print(f"  rhythm: {len(before)} bars, all durations unchanged")


def main():
    print("checking the element-address join against Verovio's MEI")
    total_ok = total = 0
    for name, score in (("jig", fixtures.jig(bars=8)),
                        ("quartet", fixtures.quartet(bars=4)),
                        ("grand staff (2 staves, 2 voices)", fixtures.grand_staff(bars=4)),
                        ("omr jig (over-full bar)", fixtures.omr_jig())):
        ok, n = check_fixture(name, score)
        total_ok += ok
        total += n
    check_transpose_touches_only_the_selection()
    check_a_chord_moves_one_note_only()
    check_missing_addresses_are_reported_not_guessed()
    check_rhythm_is_untouched()

    print()
    if FAILURES:
        print(f"FAILED ({len(FAILURES)}):")
        for f in FAILURES[:25]:
            print("  -", f)
        if len(FAILURES) > 25:
            print(f"  ... and {len(FAILURES) - 25} more")
        return 1
    print(f"OK: {total_ok}/{total} note addresses resolved to the pitch the MEI names, "
          "and every scoping check passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
