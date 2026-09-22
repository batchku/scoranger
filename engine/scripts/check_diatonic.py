"""Regression check for diatonic transposition -- the harmony line the engine could not write.

Asked for a violin line a sixth below the tune, the arrangement agent answered
that "diatonic scale-degree remapping within a key is not supported". It was
right: `transpose` moves every pitch by a fixed number of semitones, so a sixth
below G major came back in B-flat major with a new key signature, which is a
modulation and not a harmony.

So the two are checked TOGETHER, and the contrast is the point:

  - down a diatonic sixth in G major, the key signature does not move and the
    sixths come out major or minor as the key requires (three minor, four major
    across one octave) -- which is the whole definition of the thing;
  - down a chromatic major sixth, EVERY sixth is major, the signature changes
    to two flats, and D becomes F natural instead of F#. That is the bug
    reproduced, standing next to its fix.

Then the three decisions the op has to make around music21's primitive:

  - **which key**, read per staff and tracked measure by measure, so a key
    change partway through changes the degrees from that bar on, and a staff
    with no signature at all is REFUSED by name rather than guessed at as C;
  - **notes outside the key**, which have no scale degree: music21 carries the
    alteration and hands back F## in G major, so a double accidental is
    respelled and every such note is reported with its bar;
  - **scope**, because a selection degraded to a measure range is the bug
    `transpose_elements` already exists for.

Run: engine/.venv/bin/python engine/scripts/check_diatonic.py
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from music21 import chord as m21chord  # noqa: E402
from music21 import harmony as m21harmony  # noqa: E402
from music21 import interval as m21interval  # noqa: E402
from music21 import key as m21key  # noqa: E402
from music21 import meter, note as m21note, stream  # noqa: E402

from scoranger_engine import ops  # noqa: E402

FAILURES: list[str] = []


def note_(label: str, ok: bool) -> None:
    print(("  ok   " if ok else "  FAIL ") + label)
    if not ok:
        FAILURES.append(label)


def melody(pitches, key_name="G", bars_per_note=1, signature=True):
    """One part, one pitch per bar, optionally with a key signature."""
    score = stream.Score()
    part = stream.Part()
    for i, p in enumerate(pitches, start=1):
        measure = stream.Measure(number=i)
        if i == 1:
            measure.append(meter.TimeSignature("4/4"))
            if signature:
                measure.append(m21key.Key(key_name))
        measure.append(m21note.Note(p, quarterLength=4))
        part.append(measure)
    score.append(part)
    return score, part


def pitches_of(part):
    return [n.pitch.nameWithOctave for n in part.recurse().notes]


def signature_of(part):
    found = list(part.recurse().getElementsByClass(m21key.KeySignature))
    return found[0].sharps if found else None


# ------------------------------------------------- the ask: a sixth below, in key
SCALE = ["G4", "A4", "B4", "C5", "D5", "E5", "F#5", "G5"]
EXPECTED = ["B3", "C4", "D4", "E4", "F#4", "G4", "A4", "B4"]

score, part = melody(SCALE)
before = signature_of(part)
report = ops.transpose_diatonic(score, -6)
landed = pitches_of(part)
note_(f"a G major scale down a diatonic sixth lands on the key's own degrees: {landed}",
      landed == EXPECTED)
note_(f"the key signature does not move ({before} sharp -> {signature_of(part)})",
      signature_of(part) == before == 1)
note_(f"and the report says so: key={report['key']} changed={report['key_signature_changed']}",
      report["key"] == "G major" and report["key_signature_changed"] is False)

qualities = [m21interval.Interval(noteStart=ops.m21pitch.Pitch(low),
                                  noteEnd=ops.m21pitch.Pitch(high)).name
             for low, high in zip(EXPECTED, SCALE)]
note_(f"the sixths are major AND minor, as the key requires: {qualities}",
      qualities == ["m6", "M6", "M6", "m6", "m6", "M6", "M6", "m6"])
note_(f"every note moved, none skipped: {report['notes_moved']}",
      report["notes_moved"] == len(SCALE))
note_(f"nothing was outside the key: {report['outside_the_key_count']}",
      report["outside_the_key_count"] == 0)

# the same request, chromatically -- the bug, kept as the contrast
chromatic_score, chromatic_part = melody(SCALE)
ops.transpose(chromatic_score, "-M6")
chromatic = pitches_of(chromatic_part)
note_(f"a chromatic major sixth down is a MODULATION: {chromatic[:5]}...",
      chromatic[:5] == ["B-3", "C4", "D4", "E-4", "F4"])
note_(f"...and it rewrites the key signature (1 sharp -> {signature_of(chromatic_part)})",
      signature_of(chromatic_part) == -2)
note_("the two disagree on the fifth degree: diatonic F#4, chromatic F4",
      landed[4] == "F#4" and chromatic[4] == "F4")

# ------------------------------------------------- other intervals and directions
up_score, up_part = melody(["G4", "A4", "B4", "C5"])
up = ops.transpose_diatonic(up_score, "up a third")
note_(f"'up a third' reads as an interval and gives thirds in key: {pitches_of(up_part)}",
      pitches_of(up_part) == ["B4", "C5", "D5", "E5"] and up["degrees"] == 3)

minor_score, minor_part = melody(["E4", "F#4", "G4", "A4", "B4", "C5", "D5"], key_name="e")
ops.transpose_diatonic(minor_score, -6)
note_(f"e minor down a sixth stays in e minor: {pitches_of(minor_part)}",
      pitches_of(minor_part) == ["G3", "A3", "B3", "C4", "D4", "E4", "F#4"])
note_("and its signature is untouched too", signature_of(minor_part) == 1)

flat_score, flat_part = melody(["D4", "E4", "F4", "G4", "A4", "B-4", "C5"], key_name="d")
ops.transpose_diatonic(flat_score, 3)
note_(f"d minor up a third keeps its flat: {pitches_of(flat_part)}",
      pitches_of(flat_part) == ["F4", "G4", "A4", "B-4", "C5", "D5", "E5"])

octave_score, octave_part = melody(["G4", "F#5"])
ops.transpose_diatonic(octave_score, "octave")
note_(f"an octave is 8 and not 7: {pitches_of(octave_part)}",
      pitches_of(octave_part) == ["G5", "F#6"])

# ------------------------------------------------- notes outside the key
outside_score, outside_part = melody(["G4", "D#5", "F4", "A4"])
outside = ops.transpose_diatonic(outside_score, -6)
moved = pitches_of(outside_part)
note_(f"a chromatic note is moved, not dropped: {moved}", len(moved) == 4)
note_(f"no double accidental reaches the page: {moved}",
      not any("##" in p or "--" in p for p in moved))
note_(f"and each one is reported with its bar: {outside['outside_the_key']}",
      outside["outside_the_key_count"] == 2
      and {r["pitch"] for r in outside["outside_the_key"]} == {"D#5", "F4"}
      and all(r["bar"] in ("2", "3") for r in outside["outside_the_key"]))
note_("the note in the key beside them is untouched by any of that",
      moved[0] == "B3" and moved[3] == "C4")

# ------------------------------------------------- which key, and refusing to guess
none_score, none_part = melody(["G4", "A4"], signature=False)
try:
    ops.transpose_diatonic(none_score, -6)
    note_("a staff with no key signature is refused", False)
except ValueError as e:
    note_(f"a staff with no key signature is refused, naming the fix: {e}",
          "--key" in str(e) and "no key signature" in str(e))
note_("and nothing moved when it refused", pitches_of(none_part) == ["G4", "A4"])

ops.transpose_diatonic(none_score, -6, key_name="G")
note_(f"--key supplies what optical recognition dropped: {pitches_of(none_part)}",
      pitches_of(none_part) == ["B3", "C4"])

named_score, named_part = melody(["G4"], signature=False)
ops.transpose_diatonic(named_score, 3, key_name="Bb")
note_(f"'Bb' is read as B-flat major: {pitches_of(named_part)}",
      pitches_of(named_part) == ["B-4"])

# a key change partway through changes the degrees from that bar on
change_score, change_part = melody(["G4", "G4", "G4"])
for measure in change_part.getElementsByClass(stream.Measure):
    if measure.number == 3:
        measure.insert(0, m21key.Key("D"))
ops.transpose_diatonic(change_score, -6)
note_(f"a mid-piece key change is honoured from its own bar: {pitches_of(change_part)}",
      pitches_of(change_part) == ["B3", "B3", "B3"])
change2_score, change2_part = melody(["C5", "C5", "C5"])
for measure in change2_part.getElementsByClass(stream.Measure):
    if measure.number == 3:
        measure.insert(0, m21key.Key("A"))
ops.transpose_diatonic(change2_score, -6)
note_(f"...and the new key's degrees differ from the old one's: {pitches_of(change2_part)}",
      pitches_of(change2_part) == ["E4", "E4", "E-4"])

# ------------------------------------------------- scope: parts, bars, selections
two_score = stream.Score()
kept, moved_part = None, None
for name, pitch in (("Violin I", "G4"), ("Violin II", "B4")):
    p = stream.Part(id=name)
    p.partName = name
    m = stream.Measure(number=1)
    m.append(meter.TimeSignature("4/4"))
    m.append(m21key.Key("G"))
    m.append(m21note.Note(pitch, quarterLength=4))
    p.append(m)
    two_score.append(p)
ops.transpose_diatonic(two_score, -6, names=["Violin II"])
first, second = list(two_score.parts)
note_(f"only the named part moves: {pitches_of(first)} / {pitches_of(second)}",
      pitches_of(first) == ["G4"] and pitches_of(second) == ["D4"])

range_score, range_part = melody(["G4", "A4", "B4", "C5"])
ranged = ops.transpose_diatonic(range_score, -6, from_measure=2, to_measure=3)
note_(f"a measure range moves only those bars: {pitches_of(range_part)}",
      pitches_of(range_part) == ["G4", "C4", "D4", "C5"]
      and ranged["measures"] == "2-3")

chord_score = stream.Score()
chord_part = stream.Part()
chord_measure = stream.Measure(number=1)
chord_measure.append(meter.TimeSignature("4/4"))
chord_measure.append(m21key.Key("G"))
chord_measure.append(m21chord.Chord(["G4", "B4", "D5"], quarterLength=2))
chord_measure.append(m21harmony.ChordSymbol("G"))
chord_measure.append(m21note.Note("E5", quarterLength=2))
chord_part.append(chord_measure)
chord_score.append(chord_part)
def symbols_of(part):
    """A chord symbol as it would be WRITTEN: its figure and its pitches.

    The figure alone is not enough, and the whistle's fingerings taught this
    the hard way: a ChordSymbol is a Chord in music21, so `recurse().notes`
    hands it to any op that iterates notes -- and moving its pitches leaves the
    figure string standing, so a check that reads only the figure passes while
    the symbol has quietly been transposed underneath it.
    """
    return [(s.figure, tuple(p.nameWithOctave for p in s.pitches))
            for s in part.recurse().getElementsByClass(m21harmony.ChordSymbol)]


symbol_before = symbols_of(chord_part)
chord_report = ops.transpose_diatonic(chord_score, -6)
the_chord = next(iter(c for c in chord_part.recurse().getElementsByClass(m21chord.Chord)
                      if not isinstance(c, m21harmony.Harmony)))
note_(f"every pitch of a chord moves: {[p.nameWithOctave for p in the_chord.pitches]}",
      [p.nameWithOctave for p in the_chord.pitches] == ["B3", "D4", "F#4"])
note_(f"a chord SYMBOL is not a chord on the staff, figure OR pitches: {symbol_before}",
      symbols_of(chord_part) == symbol_before)
note_(f"and it is not counted among the notes moved: {chord_report['notes_moved']}",
      chord_report["notes_moved"] == 4)  # three in the chord, one melody note

# the selection form: only the addressed note, never the bar around it
sel_score = stream.Score()
sel_part = stream.Part(id="P1")
sel_measure = stream.Measure(number=1)
sel_measure.append(meter.TimeSignature("4/4"))
sel_measure.append(m21key.Key("G"))
for p in ("G4", "A4", "B4", "C5"):
    sel_measure.append(m21note.Note(p, quarterLength=1))
sel_part.append(sel_measure)
sel_score.append(sel_part)
selected = ops.transpose_diatonic_elements(sel_score, -6, ["s1/m1/l1/note#1"])
note_(f"a selection moves the selected note and nothing else: {pitches_of(sel_part)}",
      pitches_of(sel_part) == ["G4", "C4", "B4", "C5"]
      and selected["elements_transposed"] == 1)
note_(f"and it reports the key it counted degrees in: {selected['key']}",
      selected["key"] == "G major")

# ------------------------------------------------- the four surfaces that must agree
#
# An op in ops.py is not a feature. It reaches a reader through four separate
# lists, each hand-maintained, and check_bridge_ops.py exists because two of
# them have silently disagreed twice already -- `adjust-element` shipped against
# a vendored ops.py that had no such function, and `delete-piece` was called
# against a bridge that could not answer it. The same gap would have made this a
# CLI-only feature after Ali asked for it by name, and no test would have said
# so, because every test either calls Python directly or drives the app.
ROOT = Path(__file__).resolve().parents[2]
SURFACES = {
    "the engine op (ops.py)": (ROOT / "engine/scoranger_engine/ops.py",
                               ["def transpose_diatonic(", "def transpose_diatonic_elements("]),
    "the CLI (cli.py)": (ROOT / "engine/scoranger_engine/cli.py",
                         ['"transpose-diatonic"', '"transpose-diatonic-elements"']),
    "the desktop agent (chat.py)": (ROOT / "engine/scoranger_engine/chat.py",
                                    ["def transpose_diatonic(", "transpose_diatonic,"]),
    "the on-device bridge (bridge.py)": (ROOT / "ios/PythonApp/app/bridge.py",
                                         ['op == "transpose-diatonic"',
                                          'op == "transpose-diatonic-elements"']),
    # The table moved out of LocalChat.swift into ScoreModel/ChatTools.swift in
    # 0.8.2, so the dispatch it feeds could be tested without a host app. The
    # surface is the same one; only the file changed.
    "the on-device agent (ChatTools.swift)": (ROOT / "ios/Scoranger/ScoreModel/ChatTools.swift",
                                              ['name: "transpose_diatonic"',
                                               'op: "transpose-diatonic"']),
}
print()
for where, (path, needles) in SURFACES.items():
    text = path.read_text() if path.exists() else ""
    missing = [n for n in needles if n not in text]
    note_(f"{where} offers it" + (f" -- missing {missing}" if missing else ""), not missing)

# And what the two descriptions SAY, because that is what makes the model pick
# the right one. Both agents read a list of tools and take the first plausible
# match; the chromatic one had no reason to send a harmony request elsewhere.
# The on-device agent is TWO files: its standing instructions stayed in
# LocalChat.swift when the tool table moved to ChatTools.swift, and what the
# model reads is both of them together.
for label, paths in (("the desktop agent", [ROOT / "engine/scoranger_engine/chat.py"]),
                     ("the on-device agent",
                      [ROOT / "ios/Scoranger/ScoreModel/ChatTools.swift",
                       ROOT / "ios/Scoranger/LocalChat.swift"])):
    text = "\n".join(p.read_text() for p in paths).lower()
    note_(f"{label} answers to the reader's own words (sixth below, third above, harmonise)",
          all(w in text for w in ("sixth below", "third above", "harmonis")))
    note_(f"{label}'s CHROMATIC tool points at the diatonic one instead",
          "use transpose_diatonic" in text or "use\n    transpose_diatonic" in text
          or "transpose_diatonic for those" in text)
    note_(f"{label} is told never to call it unsupported again",
          "unsupported" in text)

if FAILURES:
    print(f"\nFAIL: {len(FAILURES)} diatonic transposition(s) wrong")
    for line in FAILURES:
        print("   ", line)
    sys.exit(1)
print("\nOK: diatonic transposition stays in the key, and the chromatic one still modulates")
