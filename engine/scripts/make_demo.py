"""Generate a demo score: 8 bars in G major for string quartet-ish forces + piano.

Gives the prototype something with a real melody, inner voices, a bass line,
and a piano part worth removing.
"""

from music21 import chord, clef, instrument, key, metadata, meter, note, stream

from scoranger_engine import workspace

# (chord name, melody quarters, chord tones low->high for accompaniment)
BARS = [
    ("G",  ["D5", "B4", "G4", "A4"],  ["G2", "B3", "D4", "G4"]),
    ("D",  ["F#4", "A4", "D5", "C#5"], ["D3", "F#3", "A3", "D4"]),
    ("Em", ["E5", "B4", "G4", "B4"],  ["E2", "G3", "B3", "E4"]),
    ("C",  ["C5", "E5", "G4", "A4"],  ["C3", "E3", "G3", "C4"]),
    ("G",  ["B4", "D5", "G5", "F#5"], ["G2", "B3", "D4", "G4"]),
    ("D",  ["A4", "F#4", "D4", "E4"], ["D3", "F#3", "A3", "D4"]),
    ("C",  ["E4", "G4", "C5", "B4"],  ["C3", "E3", "G3", "C4"]),
    ("G",  [("G4", 4.0)],             ["G2", "B3", "D4", "G4"]),
]


def new_part(instr, part_clef):
    p = stream.Part()
    p.insert(0, instr)
    p.partName = instr.instrumentName
    p.partAbbreviation = instr.instrumentAbbreviation
    first = True
    for i, (_, _, _) in enumerate(BARS):
        m = stream.Measure(number=i + 1)
        if first:
            m.insert(0, part_clef())
            m.insert(0, key.KeySignature(1))
            m.insert(0, meter.TimeSignature("4/4"))
            first = False
        p.append(m)
    return p


def fill(part, bar_index, elements):
    m = part.measure(bar_index + 1)
    for el in elements:
        m.append(el)


def q(name, dur=1.0):
    n = note.Note(name)
    n.quarterLength = dur
    return n


def build() -> stream.Score:
    score = stream.Score()
    score.metadata = metadata.Metadata(title="Demo in G", composer="Scoranger")

    v1 = new_part(instrument.Violin(), clef.TrebleClef)
    v1.partName = "Violin I"
    v2 = new_part(instrument.Violin(), clef.TrebleClef)
    v2.partName = "Violin II"
    va = new_part(instrument.Viola(), clef.AltoClef)
    vc = new_part(instrument.Violoncello(), clef.BassClef)
    pf = new_part(instrument.Piano(), clef.TrebleClef)

    for i, (_, melody, tones) in enumerate(BARS):
        # Violin I: the melody
        fill(v1, i, [q(x) if isinstance(x, str) else q(x[0], x[1]) for x in melody])
        # Violin II: eighth-note arpeggio over the chord, an octave up to sit in range
        arp = [tones[1], tones[2], tones[3], tones[2]] * 2
        arp_notes = []
        for x in arp:
            n = q(x, 0.5)
            n.pitch.octave += 1
            arp_notes.append(n)
        fill(v2, i, arp_notes)
        # Viola: sustained chord third in its register
        fill(va, i, [q(tones[1], 2.0), q(tones[2], 2.0)])
        # Cello: root, half notes
        fill(vc, i, [q(tones[0], 2.0), q(tones[0], 2.0)])
        # Piano: block chords, quarters
        for _ in range(4):
            c = chord.Chord(tones[1:])
            c.quarterLength = 1.0
            pf.measure(i + 1).append(c)

    for p in (v1, v2, va, vc, pf):
        score.append(p)
    return score


if __name__ == "__main__":
    slug, entry = workspace.create_score("Demo in G", build(), op="demo-generate")
    print(f"Created {slug} {entry['id']} at {workspace.score_dir(slug)}")
