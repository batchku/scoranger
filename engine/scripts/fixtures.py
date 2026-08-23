"""Shared synthetic fixtures for the engine checks.

Synthetic on purpose: the repository is public, so no committed fixture may
carry copyrighted music. Each one is shaped like material that actually broke
something, and says which.
"""

from fractions import Fraction

from music21 import (clef, instrument, key, layout, meter,
                     note as m21note, stream, tie)

E, S, Q, DE, DQ = (Fraction(1, 2), Fraction(1, 4), Fraction(1),
                   Fraction(3, 4), Fraction(3, 2))

_JIG_PATTERNS = [[E] * 6, [DE, S, E, DE, S, E], [Q, E, Q, E], [E, E, E, Q, E]]
_JIG_PITCHES = ["G4", "A4", "B4", "D5", "E5", "G5", "F#5", "D5"]


def jig(bars: int = 16) -> stream.Score:
    """A well-formed 6/8 jig: eighth runs, dotted-eighth + sixteenth pairs, the
    lilt, and a dotted quarter tied across the barline."""
    score = stream.Score()
    part = stream.Part()
    part.partName = "Pennywhistle"
    part.insert(0, instrument.Whistle())
    for bar in range(1, bars + 1):
        measure = stream.Measure(number=bar)
        if bar == 1:
            measure.append(clef.TrebleClef())
            measure.append(key.KeySignature(1))
            measure.append(meter.TimeSignature("6/8"))
        if bar == 5:
            held = m21note.Note("D5", quarterLength=DQ)
            held.tie = tie.Tie("start")
            measure.append(held)
            measure.append(m21note.Note("E5", quarterLength=DQ))
        elif bar == 6:
            stop = m21note.Note("D5", quarterLength=DQ)
            stop.tie = tie.Tie("stop")
            measure.append(stop)
            for p in _JIG_PITCHES[:3]:
                measure.append(m21note.Note(p, quarterLength=E))
        else:
            for i, dur in enumerate(_JIG_PATTERNS[(bar - 1) % len(_JIG_PATTERNS)]):
                measure.append(m21note.Note(_JIG_PITCHES[i % len(_JIG_PITCHES)],
                                            quarterLength=dur))
        part.append(measure)
    score.append(part)
    return score


def omr_jig(over_full_bar: int = 19, extra=S) -> stream.Score:
    """A jig as optical recognition actually delivers it: one bar holds more
    than its meter.

    This is Ali's Morrison's Jig, reduced to the thing that mattered -- bar 19
    came out of Audiveris with 3.25 beats in a 3-beat bar. A write-time
    invariant that refused such a file blocked the import outright, which is
    the wrong answer: OMR is imperfect by nature, and the user has to be able
    to bring the score in and then fix it. The fixture exists so that can never
    be re-broken.
    """
    score = jig(bars=max(over_full_bar + 2, 20))
    part = score.parts[0]
    measure = part.measure(over_full_bar)
    measure.append(m21note.Note("B4", quarterLength=extra))
    return score


def grand_staff(bars: int = 6) -> stream.Score:
    """Two staves braced together, the upper one in two voices, with a tie
    chain running across three bars.

    Two bugs hid in this shape: a volta written to the top staff alone
    vanished in music21's grand-staff merge, and `absorb_part` reused the
    existing voice ids so the writer folded them together.
    """
    score = stream.Score()
    staves = []
    for upper in (True, False):
        staff = stream.PartStaff()
        staff.partName = "Right" if upper else "Left"
        for bar in range(1, bars + 1):
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
    score.insert(0, layout.StaffGroup(staves, symbol="brace"))
    return score


def quartet(bars: int = 8) -> stream.Score:
    """Four independent instruments -- the shape a real arrangement starts
    from, and the one that exercises part selection and clefs."""
    score = stream.Score()
    for name, inst, staff_clef, octave in (
        ("Violin I", instrument.Violin(), clef.TrebleClef(), 0),
        ("Violin II", instrument.Violin(), clef.TrebleClef(), 0),
        ("Viola", instrument.Viola(), clef.AltoClef(), -1),
        ("Violoncello", instrument.Violoncello(), clef.BassClef(), -2),
    ):
        part = stream.Part()
        part.partName = name
        part.insert(0, inst)
        for bar in range(1, bars + 1):
            measure = stream.Measure(number=bar)
            if bar == 1:
                measure.append(staff_clef)
                measure.append(meter.TimeSignature("4/4"))
            for beat in range(4):
                pitch = ["C4", "E4", "G4", "B4"][(bar + beat) % 4]
                n = m21note.Note(pitch, quarterLength=Q)
                n.octave = (n.octave or 4) + octave
                measure.append(n)
            part.append(measure)
        score.append(part)
    return score
