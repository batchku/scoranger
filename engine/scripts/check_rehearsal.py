"""Regression check for rehearsal marks: lettering, placement and the dedupe.

Rehearsal marks go on EVERY part, which is a deliberate decision and not the
obvious one. The workflow this app is for is parts-first: a player reads from
an extracted part, and a mark that lives only on the top staff of the full
score is missing from every part but the first -- which is exactly where it is
needed. So the op writes one to each part.

The cost of that decision is what the last two checks here are about. Verovio
renders a direction from every part, and in a combined score it anchors them
all to STAFF 1: two parts give two "A" glyphs in the same place, drawn over
each other. So the combined score is deduped at render time -- the mark is kept
once -- while an extracted part keeps its own. Falling back to top-only would
have been easier and would have lost the marks from the parts.

Lettering past Z is A-Z then AA, BB, CC (not AA, AB, AC).

Fixtures are synthetic: the repository is public, so no committed fixture may
carry copyrighted music.

Run: engine/.venv/bin/python engine/scripts/check_rehearsal.py
"""

import re
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import verovio                                                    # noqa: E402
from music21 import instrument, key, meter, note, stream          # noqa: E402

from scoranger_engine import ops, render                          # noqa: E402

FAILURES: list[str] = []


def check(condition: bool, message: str) -> None:
    if condition:
        print(f"  ok   {message}")
    else:
        print(f"  FAIL {message}")
        FAILURES.append(message)


def build(parts: int = 2, measures: int = 6):
    score = stream.Score()
    for i in range(parts):
        part = stream.Part()
        part.partName = f"Part {i + 1}"
        part.insert(0, instrument.Violin())
        for number in range(1, measures + 1):
            measure = stream.Measure(number=number)
            if number == 1:
                measure.insert(0, key.KeySignature(0))
                measure.insert(0, meter.TimeSignature("4/4"))
            for pitch in ["C4", "D4", "E4", "F4"]:
                measure.append(note.Note(pitch, quarterLength=1))
            part.append(measure)
        score.insert(0, part)
    return score


def engrave(score) -> tuple[str, str]:
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "reh.musicxml"
        score.write("musicxml", fp=str(path))
        toolkit = verovio.toolkit()
        toolkit.setOptions({"scale": 40, "footer": "none", "adjustPageHeight": True})
        if not toolkit.loadFile(str(path)):
            raise RuntimeError("Verovio refused the fixture")
        return toolkit.getMEI("{}"), toolkit.renderToSVG(1)


def marks_in(score) -> list[tuple[str, int, str]]:
    """(part, measure, letter) for every rehearsal mark in the score."""
    from music21 import expressions
    out = []
    for part in score.parts:
        for measure in part.getElementsByClass(stream.Measure):
            for mark in measure.getElementsByClass(expressions.RehearsalMark):
                out.append((ops.part_label(part), measure.number, str(mark.content)))
    return out


def check_lettering_past_z() -> None:
    print("lettering")
    letters = [ops.rehearsal_letter(i) for i in range(29)]
    check(letters[:3] == ["A", "B", "C"], "it starts at A")
    check(letters[25] == "Z", "the 26th is Z")
    check(letters[26:29] == ["AA", "BB", "CC"],
          f"past Z it doubles the letter: got {letters[26:29]}")


def check_a_mark_lands_on_every_part() -> None:
    print("every part carries the mark")
    score = build(parts=3)
    ops.set_rehearsal(score, measure=3, mark="A")
    marks = marks_in(score)
    check(len(marks) == 3,
          f"one mark per part, so an extracted part keeps it: got {len(marks)}")
    check({m for _, _, m in marks} == {"A"}, "and they all say the same thing")
    check({b for _, b, _ in marks} == {3}, "in the same bar")


def check_add_remove_and_move() -> None:
    print("add, remove, move")
    score = build(parts=2)
    ops.set_rehearsal(score, measure=2, mark="A")
    ops.set_rehearsal(score, measure=5, mark="B")
    check(len(marks_in(score)) == 4, "two marks across two parts")

    ops.set_rehearsal(score, measure=5, remove=True)
    check([m for _, _, m in marks_in(score)] == ["A", "A"],
          "remove takes it off every part, not just the first")

    ops.set_rehearsal(score, measure=2, move_to=4)
    moved = marks_in(score)
    check({b for _, b, _ in moved} == {4} and len(moved) == 2,
          f"move takes it to the new bar on every part: got {moved}")


def check_relettering_follows_bar_order() -> None:
    print("auto-lettering")
    score = build(parts=2)
    # deliberately out of order and mislabelled
    ops.set_rehearsal(score, measure=5, mark="Q")
    ops.set_rehearsal(score, measure=2, mark="Q")
    report = ops.set_rehearsal(score, reletter=True)
    letters = sorted({(b, m) for _, b, m in marks_in(score)})
    check(letters == [(2, "A"), (5, "B")],
          f"relettering runs A, B in bar order: got {letters}")
    check(report["marks"] == 2, "and the report counts what it lettered")


def check_the_combined_score_is_deduped() -> None:
    """Marks on every part must not stack up on staff 1 of the full score."""
    print("what Verovio draws for a combined score")
    score = build(parts=2)
    ops.set_rehearsal(score, measure=3, mark="A")
    mei, _svg = engrave(score)
    raw = len(re.findall(r"<reh\b", mei))
    check(raw == 2, f"Verovio does render one per part (this is the problem): {raw}")
    staves = re.findall(r'<reh\b[^>]*staff="(\d+)"', mei)
    check(len(set(staves)) == 1,
          f"and it anchors them all to the same staff, so they overlap: {staves}")

    deduped = render.mei_with_deduped_rehearsals(mei)
    kept = len(re.findall(r"<reh\b", deduped))
    check(kept == 1, f"the render dedupe keeps exactly one: got {kept}")
    check("A" in deduped, "and the one it keeps still says A")


def check_a_single_part_keeps_its_mark() -> None:
    """An extracted part is one part: the dedupe must not empty it."""
    print("an extracted part")
    score = build(parts=1)
    ops.set_rehearsal(score, measure=3, mark="A")
    mei, _ = engrave(score)
    deduped = render.mei_with_deduped_rehearsals(mei)
    check(len(re.findall(r"<reh\b", deduped)) == 1,
          "the part a player reads from still has its mark")


def main() -> int:
    check_lettering_past_z()
    check_a_mark_lands_on_every_part()
    check_add_remove_and_move()
    check_relettering_follows_bar_order()
    check_the_combined_score_is_deduped()
    check_a_single_part_keeps_its_mark()

    print()
    if FAILURES:
        print(f"{len(FAILURES)} FAILED")
        for f in FAILURES:
            print(f"  - {f}")
        return 1
    print("OK: rehearsal marks letter, place, move and dedupe")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
