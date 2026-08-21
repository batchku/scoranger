"""Generate the score-model test fixtures.

Synthetic on purpose: the repository is public, so committed fixtures must not
carry copyrighted music. This builds a four-staff score with chord symbols and
ties -- the material the hit-test model needs to be exercised against -- and
renders it twice from independent Verovio loads, so the tests can prove that
element addresses survive the ids changing.

    engine/.venv/bin/python engine/scripts/make_test_fixture.py
"""
import pathlib

import verovio
from music21 import chord, clef, harmony, instrument, layout, meter, note, stream

OUT = pathlib.Path(__file__).resolve().parents[2] / "ios/ScorangerTests/Fixtures"
PITCHES = ["C4", "E4", "G4", "B4", "A4", "F4", "D4", "G4"]
CHORDS = ["Cmaj7", "Am7", "Dm7", "G7"]


def build() -> stream.Score:
    score = stream.Score()
    for staff, (name, inst, clef_obj, octave) in enumerate([
        ("Violin I", instrument.Violin(), clef.TrebleClef(), 0),
        ("Violin II", instrument.Violin(), clef.TrebleClef(), 0),
        ("Viola", instrument.Viola(), clef.AltoClef(), -1),
        ("Cello", instrument.Violoncello(), clef.BassClef(), -2),
    ]):
        part = stream.Part()
        part.partName = name
        part.insert(0, inst)
        for bar in range(1, 5):
            measure = stream.Measure(number=bar)
            if bar == 1:
                measure.append(clef_obj)
                measure.append(meter.TimeSignature("4/4"))
            # chord symbols on the top staff only, as a real chart would have
            if staff == 0:
                measure.insert(0, harmony.ChordSymbol(CHORDS[(bar - 1) % len(CHORDS)]))
            for beat in range(4):
                pitch = PITCHES[(bar * 4 + beat) % len(PITCHES)]
                n = note.Note(pitch, quarterLength=1.0)
                n.octave = max(1, n.octave + octave)
                # a tie across the middle of each bar, so tie geometry exists
                if beat == 1:
                    n.tie = __import__("music21").tie.Tie("start")
                elif beat == 2:
                    n.tie = __import__("music21").tie.Tie("stop")
                measure.append(n)
            part.append(measure)
        score.append(part)
    return score


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    tmp = OUT / "_fixture.musicxml"
    build().write("musicxml", fp=str(tmp))
    # two independent loads: same music, different Verovio session ids
    for tag in ("a", "b"):
        tk = verovio.toolkit()
        if not tk.loadFile(str(tmp)):
            raise SystemExit("verovio failed to load the generated score")
        (OUT / f"fixture-{tag}.svg").write_text(tk.renderToSVG(1))
        (OUT / f"fixture-{tag}.mei").write_text(tk.getMEI())
    tmp.unlink()
    for f in sorted(OUT.iterdir()):
        print(f"  {f.name:18} {f.stat().st_size:>7} bytes")


if __name__ == "__main__":
    main()
