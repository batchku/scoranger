"""Regression check for the one thing a score may never lose: its rhythm.

An arrangement op may add a staff, change an instrument, or rewrite a line --
but no op, and no write, may move a note the user did not ask to move. This
checks that by running each op that has ever been implicated, writing the
result through the real write path, reading the file back, and comparing every
note's position and duration against what went in.

The write is the point. An op can be perfectly correct in memory and still
leave a corrupt file behind: music21's MusicXML writer emits a note that runs
past its barline AND the bars it swallows, duplicating time and pushing
everything after it later. That is how an eighth note became a dotted eighth
in someone's jig, fifteen versions after the op that caused it.

This file is a DEVELOPMENT gate, not a runtime one. The app no longer refuses
to save anything: refusing blocked a user from importing an imperfect scan and
then from adding a repeat to a score that had inherited an odd bar. The ops are
where correctness belongs; this is where it is proven, before a release.

Fixtures are synthetic: the repository is public, so no committed fixture may
carry copyrighted music. They are shaped like the material that broke --
6/8 with dotted rhythms, ties across barlines, and staves that sing in voices.

Run: engine/.venv/bin/python engine/scripts/check_rhythm.py
"""

import copy
import sys
import tempfile
from fractions import Fraction
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from music21 import (clef, converter, harmony, instrument,  # noqa: E402
                     key, meter, note as m21note, stream, tie)

sys.path.insert(0, str(Path(__file__).resolve().parent))

import fixtures  # noqa: E402
from scoranger_engine import ops, workspace  # noqa: E402

FAILURES: list[str] = []

E, S, Q, DE, DQ = (Fraction(1, 2), Fraction(1, 4), Fraction(1),
                   Fraction(3, 4), Fraction(3, 2))


def jig() -> stream.Score:
    """16 bars of 6/8: straight eighths, dotted-eighth + sixteenth pairs, the
    jig lilt, and a dotted quarter tied across the barline."""
    score = stream.Score()
    part = stream.Part()
    part.partName = "Pennywhistle"
    part.insert(0, instrument.Whistle())
    patterns = [[E] * 6, [DE, S, E, DE, S, E], [Q, E, Q, E], [E, E, E, Q, E]]
    pitches = ["G4", "A4", "B4", "D5", "E5", "G5", "F#5", "D5"]
    for bar in range(1, 17):
        measure = stream.Measure(number=bar)
        if bar == 1:
            measure.append(clef.TrebleClef())
            measure.append(key.KeySignature(1))
            measure.append(meter.TimeSignature("6/8"))
        if bar == 5:                                  # tie into the next bar
            held = m21note.Note("D5", quarterLength=DQ)
            held.tie = tie.Tie("start")
            measure.append(held)
            measure.append(m21note.Note("E5", quarterLength=DQ))
        elif bar == 6:
            stop = m21note.Note("D5", quarterLength=DQ)
            stop.tie = tie.Tie("stop")
            measure.append(stop)
            for p in pitches[:3]:
                measure.append(m21note.Note(p, quarterLength=E))
        else:
            for i, dur in enumerate(patterns[(bar - 1) % len(patterns)]):
                measure.append(m21note.Note(pitches[i % len(pitches)], quarterLength=dur))
        total = sum(Fraction(n.quarterLength) for n in measure.notesAndRests)
        assert total == 3, f"fixture bar {bar} is {total} beats, not 3"
        part.append(measure)
    score.append(part)
    return score


def two_staff() -> stream.Score:
    """A grand staff whose upper staff sings in two voices, with a tie chain
    running across three bars -- the shape that hid the bug for weeks."""
    score = stream.Score()
    staves = []
    for upper in (True, False):
        staff = stream.PartStaff()
        staff.partName = "Right" if upper else "Left"
        for bar in range(1, 7):
            measure = stream.Measure(number=bar)
            if bar == 1:
                measure.append(clef.TrebleClef() if upper else clef.BassClef())
                measure.append(meter.TimeSignature("3/4"))
            if upper:
                melody = stream.Voice(id="1")
                for i, off in enumerate((0, 1, 2)):
                    melody.insert(off, m21note.Note(["C5", "D5", "E5"][i], quarterLength=Q))
                inner = stream.Voice(id="2")
                held = m21note.Note("G4", quarterLength=Q * 3)
                if bar in (2, 3, 4):
                    held.tie = tie.Tie("start" if bar == 2
                                       else ("stop" if bar == 4 else "continue"))
                inner.insert(0, held)
                measure.insert(0, melody)
                measure.insert(0, inner)
            else:
                measure.insert(0, m21note.Note("C3", quarterLength=Q * 3))
            staff.append(measure)
        staves.append(staff)
        score.insert(0, staff)
    from music21 import layout
    score.insert(0, layout.StaffGroup(staves, symbol="brace"))
    return score


def profile(score) -> list:
    """Every note's bar, position and duration -- what must not change."""
    out = []
    for index, part in enumerate(score.parts or [score]):
        for measure in part.getElementsByClass(stream.Measure):
            for container in (list(measure.voices) or [measure]):
                for el in container.notesAndRests:
                    if isinstance(el, harmony.Harmony):
                        continue
                    out.append((index, measure.number,
                                Fraction(el.offset).limit_denominator(10 ** 6),
                                Fraction(el.quarterLength).limit_denominator(10 ** 6)))
    return sorted(out)


def total_length(score) -> list:
    return [Fraction(p.highestTime).limit_denominator(10 ** 6) for p in (score.parts or [score])]


def write_and_read(score, name: str):
    """Through the real write path, then back off disk.

    The write no longer refuses anything -- refusing at runtime blocked users
    from importing imperfect scans and from adding repeats to scores that had
    inherited an odd bar. Correctness is the ops' job; proving it is this
    file's job, and this file runs before a release, not in front of a user.
    Returns (score read back, the odd bars the file has).
    """
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / f"{name}.musicxml"
        warnings = workspace._write_musicxml(score, path)
        return converter.parse(str(path), forceSource=True), warnings


def expect_rhythm_survives(label: str, build, mutate, *, may_skip: bool = False):
    """Run an op and require the file it produces to play the same.

    `may_skip` allows an op to decline (reporting it) rather than rewrite a part
    it cannot handle -- declining is a correct outcome; corrupting is not.
    """
    score = build()
    before, before_len = profile(score), total_length(score)
    try:
        report = mutate(score)
    except Exception as e:  # noqa: BLE001 — the check is the point
        FAILURES.append(f"{label}: op raised {type(e).__name__}: {e}")
        return
    written, _ = write_and_read(score, label.replace(" ", "-"))
    problems = ops.rhythm_problems(written)
    if problems:
        FAILURES.append(f"{label}: the file it wrote is unsound -- {problems[0]}")
        return

    declined = (isinstance(report, list) and report
                and isinstance(report[0], dict) and report[0].get("skipped"))
    if declined and may_skip:
        return
    after, after_len = profile(written), total_length(written)
    if after_len[:len(before_len)] != before_len:
        FAILURES.append(f"{label}: part length changed {before_len} -> {after_len}")
        return
    # ops that rewrite a line legitimately change which notes are where; what
    # they may never do is change the music that was already on the OTHER staves
    if label.startswith("untouched") and after != before:
        moved = [(b, a) for b, a in zip(before, after) if b != a][:1]
        FAILURES.append(f"{label}: notes moved, first {moved}")


# -- ops that must never touch the rhythm ------------------------------------
for name, build in (("jig", jig), ("grand staff", two_staff)):
    expect_rhythm_survives(f"untouched {name} (control)", build, lambda sc: None)
    expect_rhythm_survives(f"untouched {name}: transpose",
                           build, lambda sc: ops.transpose(sc, "M2", None))
    expect_rhythm_survives(f"untouched {name}: whistle fingerings",
                           build, lambda sc: ops.whistle_fingerings(sc, sc.parts[0], "D"))
    expect_rhythm_survives(f"untouched {name}: change instrument",
                           build, lambda sc: ops.change_instrument(sc.parts[0], "Flute"))
    expect_rhythm_survives(f"untouched {name}: chord symbols",
                           build, lambda sc: ops.set_chord_symbols(
                               sc, "#0", [{"measure": 1, "symbol": "Em"},
                                          {"measure": 3, "symbol": "G"}]))
    expect_rhythm_survives(f"untouched {name}: add a repeat",
                           build, lambda sc: ops.set_structure(sc, "repeat-end", measure=4))

# -- ops that rewrite a line, and must still leave the music playable --------
expect_rhythm_survives("consolidate ties (jig)", jig,
                       lambda sc: ops.consolidate_ties(sc, ["#0"]), may_skip=True)
expect_rhythm_survives("consolidate ties (grand staff)", two_staff,
                       lambda sc: ops.consolidate_ties(sc, ["#0"]), may_skip=True)
expect_rhythm_survives("flatten voices", two_staff,
                       lambda sc: ops.flatten_voices(sc, "#0"), may_skip=True)
expect_rhythm_survives("absorb part", two_staff,
                       lambda sc: ops.absorb_part(sc, "#1", "#0", None))

# absorb folds one staff into another as an extra voice. Everything that was
# already on the target staff must still be exactly where it was -- the first
# version of this op read each note's offset AFTER detaching it, and music21
# reports 0 for a detached element, so the whole melody piled onto the downbeat.
absorbed = two_staff()
melody_before = set(profile(absorbed))
ops.absorb_part(absorbed, "#1", "#0", None)
written, refusal = write_and_read(absorbed, "absorb-keeps-melody")
if written is None:
    FAILURES.append(f"absorb part: write refused -- {refusal}")
else:
    lost = melody_before - set(profile(written))
    if lost:
        FAILURES.append(f"absorb part: {len(lost)} note(s) of the existing music moved, "
                        f"first {sorted(lost)[0]}")
expect_rhythm_survives("pull a part in", two_staff,
                       lambda sc: ops.pull_part(sc, jig(), "#0", "Whistle", None, None))
expect_rhythm_survives("split bass", two_staff,
                       lambda sc: ops.split_bass(sc, "#0", "Bass", "Chords", None))

# -- the detector itself must be able to fail --------------------------------
# A check that cannot fail is worse than no check. The runtime no longer
# refuses anything, so what has to work is the DETECTION: a damaged score must
# be reported by ops.rhythm_faults, which is what makes every check above real.
def corrupt() -> stream.Score:
    part = stream.Part()
    for bar in (1, 2, 3):
        measure = stream.Measure(number=bar)
        if bar == 1:
            measure.append(meter.TimeSignature("3/4"))
            measure.insert(0, m21note.Note("C5", quarterLength=3))
            measure.insert(0, m21note.Note("C5", quarterLength=Fraction(7, 3)))
        else:
            measure.insert(0, m21note.Note("D5", quarterLength=3))
        part.append(measure)
    score = stream.Score()
    score.insert(0, part)
    return score


damaged, warnings = write_and_read(corrupt(), "corrupt")
if not ops.rhythm_faults(damaged):
    FAILURES.append("a score whose bars do not hold their music was reported as sound")
if not warnings:
    FAILURES.append("the write reported no warning for a damaged score")
elif not any("bar" in w for w in warnings):
    FAILURES.append(f"the warning does not name a bar: {warnings[:1]}")


# A note running past its barline is legal in memory -- stripTies produces
# them by design -- and the write is what splits and re-ties it. This is the
# prevention that stays: correct by construction, not caught afterwards.
def over_long() -> stream.Score:
    part = stream.Part()
    for bar in (1, 2, 3):
        measure = stream.Measure(number=bar)
        if bar == 1:
            measure.append(meter.TimeSignature("3/4"))
            measure.insert(0, m21note.Note("C5", quarterLength=9))   # spans all three
        part.append(measure)
    score = stream.Score()
    score.insert(0, part)
    return score


split, _ = write_and_read(over_long(), "over-long")
if total_length(split) != [Fraction(9)]:
    FAILURES.append(f"splitting a 9-beat note across 3-beat bars gave "
                    f"{total_length(split)} beats, not 9")
if ops.rhythm_faults(split):
    FAILURES.append(f"the split left the bars unsound: {ops.rhythm_problems(split)[:1]}")


# -- structural marks may never touch a note ---------------------------------
# Repeats, endings and navigation marks are notation ABOUT the music, not the
# music. Adding one must leave every note exactly where it was -- which is why
# the write blocking such an edit was a false positive, not a rhythm bug.
for kind, kwargs in (("repeat-start", {"measure": 3}),
                     ("repeat-end", {"measure": 4}),
                     ("repeat-both", {"measure": 5}),
                     ("volta", {"measure": 3, "to_measure": 4, "number": 1}),
                     ("segno", {"measure": 2}),
                     ("coda", {"measure": 6}),
                     ("fine", {"measure": 8}),
                     ("da-capo-al-fine", {"measure": 8}),
                     ("dal-segno-al-coda", {"measure": 8})):
    for shape, build in (("jig", jig), ("grand staff", two_staff)):
        score = build()
        before = profile(score)
        try:
            ops.set_structure(score, kind, **kwargs)
        except ValueError:
            continue                     # bar out of range for this fixture
        written, _ = write_and_read(score, f"structure-{kind}-{shape}".replace(" ", "-"))
        if profile(written) != before:
            moved = [(b, a) for b, a in zip(before, profile(written)) if b != a][:1]
            FAILURES.append(f"{kind} on the {shape} moved a note: {moved}")
    # And on a score that arrived with an odd bar -- an OMR'd scan, which is
    # what Ali's jig is -- the mark must still apply, and must not make the odd
    # bar any odder. This is the case the write used to refuse outright.
    odd = fixtures.omr_jig()
    odd_before = ops.rhythm_faults(odd)
    try:
        ops.set_structure(odd, kind, **kwargs)
    except ValueError:
        continue
    odd_written, _ = write_and_read(odd, f"structure-odd-{kind}".replace(" ", "-"))
    if len(ops.rhythm_faults(odd_written)) > len(odd_before):
        FAILURES.append(f"{kind} on an OMR score made its odd bars worse: "
                        f"{len(odd_before)} -> {len(ops.rhythm_faults(odd_written))}")


# -- the guard must cover the ways music ENTERS the library ------------------
# Ali's score was corrupted on the way in, not by an arrangement op: a source
# is parsed and re-written when it is attached, and pull-part copies from it.
import inspect  # noqa: E402

for func, what in ((workspace.add_source, "add_source"),
                   (workspace._write_version, "_write_version")):
    if "_write_musicxml" not in inspect.getsource(func):
        FAILURES.append(f"{what} does not go through the guarded write path")

if FAILURES:
    print(f"FAIL: {len(FAILURES)} rhythm check(s) failed")
    for line in FAILURES:
        print("   ", line)
    sys.exit(1)
print("OK: rhythm survives every op, structural marks move no note, "
      "and damage is still detectable")
