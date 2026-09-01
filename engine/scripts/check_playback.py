"""The score as it is PLAYED, and the map from its beats back to the page.

Playback needs two things that must not disagree: MIDI for a synthesiser, and
a map saying which engraved bar each beat of that MIDI belongs to. A play head
that follows the wrong bar is worse than no play head -- the reader trusts it,
looks away from the music, and is lost. So both come out of ONE performed
score, and this file asserts the three ways that score differs from the
engraved one. Every assertion below was written against a measured music21
behaviour, not a remembered one.

**Repeats are played out.** music21's MIDI writer expands them: four bars whose
first two repeat write six bars of audio. That makes the beat->bar map
one-to-MANY -- bar 1 owns two separate stretches of the timeline -- and it is
the reason the map cannot be arithmetic over bar numbers. A volta is the same
mechanism: first time through takes the first ending, second time the second.

**Written pitch is not sounding pitch.** The writer emits what is on the page.
A B-flat clarinet part therefore played a whole tone sharp against every other
part, which is not a subtle defect -- it is the arrangement out of tune with
itself. `toSoundingPitch` is a no-op on music that does not transpose, so it
costs nothing to apply always.

**A bar is not four beats.** A pickup is a short bar whose clicks land at the
END of the grid, so the pickup's click is not a downbeat. 6/8 has two clicks,
not six. The engine emits the click positions rather than a rule for finding
them, so the metronome on the other side of the boundary needs no music theory.

And the boundary itself: the app does not call the CLI, it calls `bridge.py`,
so the last section asks the bridge for playback the way the app will.

Run: engine/.venv/bin/python engine/scripts/check_playback.py
"""

import json
import os
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
# ORDER MATTERS, and it is the reason this check was briefly worthless.
#
# `ios/PythonApp/app` holds `bridge.py`, which the last section needs -- but it
# also holds a VENDORED COPY of `scoranger_engine`, written by
# scripts/vendor_engine.sh so the iPad app can carry the engine in its bundle.
# Put that directory first and `from scoranger_engine import ops` resolves to
# the copy: the check then grades a snapshot, and a fix reverted in the real
# source still passes. It was verified by reverting `toSoundingPitch` and
# watching every assertion go green.
#
# So `engine` goes ahead of it, and the bridge -- which imports the engine the
# same way -- is graded against the source too.
sys.path.insert(0, str(ROOT / "ios" / "PythonApp" / "app"))
sys.path.insert(0, str(ROOT / "engine" / "scripts"))
sys.path.insert(0, str(ROOT / "engine"))

FAILURES: list[str] = []


def check(label: str, ok: bool, detail: str = "") -> None:
    if ok:
        print(f"  ok   {label}")
    else:
        FAILURES.append(f"{label}{': ' + detail if detail else ''}")
        print(f"  FAIL {label}{': ' + detail if detail else ''}")


def main() -> int:
    workspace_dir = tempfile.mkdtemp(prefix="scoranger-playback-")
    os.environ["SCORANGER_WORKSPACE"] = workspace_dir

    from music21 import bar, converter, instrument, meter, note, stream
    from scoranger_engine import ops, workspace

    import fixtures

    # ---------------------------------------------------------------- parts
    print("a quartet: one entry per part, in the order the MIDI tracks come")
    quartet = fixtures.quartet(bars=8)
    _played, timeline = ops.playback_timeline(quartet)
    parts = timeline["parts"]
    check("four parts", len(parts) == 4, str(len(parts)))
    check("named as the score names them",
          [p["name"] for p in parts] == ["Violin I", "Violin II", "Viola", "Violoncello"],
          str([p["name"] for p in parts]))
    check("indexed 0..3 so a track number is a part number",
          [p["index"] for p in parts] == [0, 1, 2, 3])
    # The instrument name repeats across the two violins; the PART name does
    # not. A mute list keyed on the instrument would collapse the two violins
    # into one switch, which is why the part name is what is carried.
    check("General MIDI programs come through",
          [p["program"] for p in parts] == [40, 40, 41, 42],
          str([p["program"] for p in parts]))

    print("\na part with no instrument -- every staff OMR labels 'Voice'")
    voiceless = stream.Score()
    part = stream.Part()
    part.partName = "Voice"
    measure = stream.Measure(number=1)
    measure.insert(0, meter.TimeSignature("4/4"))
    measure.append(note.Note("C4", quarterLength=4.0))
    part.append(measure)
    voiceless.insert(0, part)
    _played, timeline = ops.playback_timeline(voiceless)
    # Honest, not guessed. A wrong instrument is a decision the engine has no
    # grounds to make; the player picks its own documented default.
    check("its program is null rather than a guess",
          timeline["parts"][0]["program"] is None,
          str(timeline["parts"][0]["program"]))

    # -------------------------------------------------------------- repeats
    print("\na repeat: bar 1 is played TWICE, so it owns two stretches of time")
    repeated = stream.Score()
    part = stream.Part()
    part.partName = "P"
    for number in (1, 2, 3, 4):
        measure = stream.Measure(number=number)
        if number == 1:
            measure.insert(0, meter.TimeSignature("4/4"))
        measure.append(note.Note("C4", quarterLength=4.0))
        part.append(measure)
    measures = part.getElementsByClass(stream.Measure)
    measures[0].leftBarline = bar.Repeat(direction="start")
    measures[1].rightBarline = bar.Repeat(direction="end", times=2)
    repeated.insert(0, part)
    _played, timeline = ops.playback_timeline(repeated)
    check("the repeat was expanded", timeline["repeats_expanded"] is True)
    check("four written bars became six performed ones",
          (timeline["written_bars"], timeline["performed_bars"]) == (4, 6),
          str((timeline["written_bars"], timeline["performed_bars"])))
    played_order = [b["measure"] for b in timeline["bars"]]
    check("in the order they are played",
          played_order == [1, 2, 1, 2, 3, 4], str(played_order))
    ones = [b["start"] for b in timeline["bars"] if b["measure"] == 1]
    check("bar 1 appears at two different beats", ones == [0.0, 8.0], str(ones))
    check("the timeline is as long as the performance",
          timeline["beats"] == 24.0, str(timeline["beats"]))

    print("\nand the MIDI agrees with the map, because it is the same object")
    performed, timeline = ops.playback_timeline(repeated)
    midi_path = Path(workspace_dir) / "repeat.mid"
    performed.write("midi", fp=str(midi_path))
    back = converter.parse(str(midi_path), forceSource=True)
    # Six bars of one note each. If the writer's expansion and the map's ever
    # drifted apart, this is where it would show.
    check("the MIDI holds the performed note count, not the written one",
          len(back.flatten().notes) == 6, str(len(back.flatten().notes)))
    check("and is as long as the map says",
          abs(float(back.highestTime) - timeline["beats"]) < 1e-6,
          f"{float(back.highestTime)} vs {timeline['beats']}")

    print("\na volta: first time through takes the first ending")
    with_volta = converter.parse(str(_seed(fixtures.jig(bars=8), ops, workspace)),
                                 forceSource=True)
    ops.set_structure(with_volta, "repeat-start", measure=1)
    ops.set_structure(with_volta, "repeat-end", measure=4)
    ops.set_structure(with_volta, "volta", measure=4, number=1)
    ops.set_structure(with_volta, "volta", measure=5, number=2)
    _played, timeline = ops.playback_timeline(with_volta)
    order = [b["measure"] for b in timeline["bars"]]
    check("bar 4 is played once and bar 5 replaces it second time",
          order == [1, 2, 3, 4, 1, 2, 3, 5, 6, 7, 8], str(order))

    print("\nan unbalanced repeat -- what optical recognition delivers")
    lopsided = stream.Score()
    part = stream.Part()
    part.partName = "P"
    for number in (1, 2, 3):
        measure = stream.Measure(number=number)
        if number == 1:
            measure.insert(0, meter.TimeSignature("4/4"))
        measure.append(note.Note("C4", quarterLength=4.0))
        part.append(measure)
    part.getElementsByClass(stream.Measure)[1].rightBarline = bar.Repeat(direction="end")
    lopsided.insert(0, part)
    _played, timeline = ops.playback_timeline(lopsided)
    # The rule the whole engine is built on: material from outside is accepted
    # as it is. A repeat with no start still plays -- it does not refuse.
    check("it still produces a timeline", len(timeline["bars"]) > 0,
          "a score OMR mangled must still be playable")

    # --------------------------------------------------- transposing pitch
    print("\na B-flat clarinet sounds a tone below what is written")
    clarinet = stream.Score()
    part = stream.Part()
    part.partName = "Clarinet in Bb"
    part.insert(0, instrument.Clarinet())
    measure = stream.Measure(number=1)
    measure.insert(0, meter.TimeSignature("4/4"))
    measure.append(note.Note("C4", quarterLength=4.0))
    part.append(measure)
    clarinet.insert(0, part)
    written = Path(workspace_dir) / "clarinet.musicxml"
    clarinet.write("musicxml", fp=str(written))
    reloaded = converter.parse(str(written), forceSource=True)
    check("the notation is at written pitch to begin with",
          [n.pitch.nameWithOctave for n in reloaded.flatten().notes] == ["C4"],
          str([n.pitch.nameWithOctave for n in reloaded.flatten().notes]))
    performed, timeline = ops.playback_timeline(reloaded)
    check("playback converted it", timeline["sounding_pitch"] is True)
    sounding = [n.pitch.nameWithOctave for n in performed.flatten().notes]
    # Without this the clarinet is a whole tone sharp against every other part
    # for the length of the piece.
    check("a written C4 plays as B-flat 3", sounding == ["B-3"], str(sounding))

    print("\nand a score that does not transpose is left exactly alone")
    plain = fixtures.quartet(bars=4)
    performed, _timeline = ops.playback_timeline(plain)
    # PART BY PART, never `score.flatten()`. Flattening orders notes by their
    # absolute offset, and `quartet` builds its parts with `Score.append`,
    # which lays them end to end at 0, 8, 16 and 24 rather than together at 0.
    # Expanding normalises that -- correctly -- so a flat comparison reports
    # every pitch as changed when not one of them moved.
    changed = [a.partName for a, b in zip(plain.parts, performed.parts)
               if [n.pitch.nameWithOctave for n in a.flatten().notes]
               != [n.pitch.nameWithOctave for n in b.flatten().notes]]
    check("every pitch in every part is unchanged", not changed, str(changed))

    # ---------------------------------------------------------- the clicks
    print("\n4/4: four clicks a bar, the first of them the downbeat")
    simple = stream.Score()
    part = stream.Part()
    part.partName = "P"
    for number in (1, 2):
        measure = stream.Measure(number=number)
        if number == 1:
            measure.insert(0, meter.TimeSignature("4/4"))
        measure.append(note.Note("C4", quarterLength=4.0))
        part.append(measure)
    simple.insert(0, part)
    _played, timeline = ops.playback_timeline(simple)
    beats = [c["beat"] for c in timeline["clicks"]]
    check("eight clicks over two bars", beats == [0, 1, 2, 3, 4, 5, 6, 7], str(beats))
    check("two of them are downbeats",
          [c["beat"] for c in timeline["clicks"] if c["down"]] == [0.0, 4.0])

    print("\n6/8: two clicks a bar, not six -- it is a compound meter")
    jig = fixtures.jig(bars=2)
    _played, timeline = ops.playback_timeline(jig)
    beats = [c["beat"] for c in timeline["clicks"]]
    check("four clicks over two bars", beats == [0.0, 1.5, 3.0, 4.5], str(beats))

    print("\na pickup: its click lands at the END of the grid, not on beat one")
    pickup = stream.Score()
    part = stream.Part()
    part.partName = "P"
    upbeat = stream.Measure(number=0)
    upbeat.insert(0, meter.TimeSignature("4/4"))
    upbeat.paddingLeft = 3.0
    upbeat.append(note.Note("G4", quarterLength=1.0))
    full = stream.Measure(number=1)
    full.append(note.Note("C5", quarterLength=4.0))
    part.append([upbeat, full])
    pickup.insert(0, part)
    _played, timeline = ops.playback_timeline(pickup)
    check("the short bar is marked as a pickup",
          timeline["bars"][0]["pickup"] is True)
    check("it gets ONE click", len([c for c in timeline["clicks"]
                                    if c["beat"] < 1.0]) == 1)
    # A downbeat here would put the player's foot in the wrong place for the
    # whole first phrase.
    check("and that click is not a downbeat",
          timeline["clicks"][0]["down"] is False)
    check("the next bar's downbeat is where the bar starts",
          timeline["clicks"][1] == {"beat": 1.0, "down": True},
          str(timeline["clicks"][1]))
    check("bar 1 starts one beat in, not four",
          timeline["bars"][1]["start"] == 1.0, str(timeline["bars"][1]["start"]))

    # ---------------------------------------------------------- the tempos
    print("\ntempo: what the score says, or 120 said out loud")
    _played, timeline = ops.playback_timeline(fixtures.quartet(bars=4))
    check("a score with no mark reports the default",
          timeline["tempos"] == [{"beat": 0.0, "bpm": 120.0}], str(timeline["tempos"]))
    check("and says the tempo is not the arranger's",
          timeline["tempo_from_score"] is False)

    from music21 import tempo as m21tempo
    paced = stream.Score()
    part = stream.Part()
    part.partName = "P"
    for number in (1, 2, 3):
        measure = stream.Measure(number=number)
        if number == 1:
            measure.insert(0, meter.TimeSignature("4/4"))
            measure.insert(0, m21tempo.MetronomeMark(number=72))
        if number == 3:
            measure.insert(0, m21tempo.MetronomeMark(number=144))
        measure.append(note.Note("C4", quarterLength=4.0))
        part.append(measure)
    paced.insert(0, part)
    _played, timeline = ops.playback_timeline(paced)
    check("a mid-score change is carried, with the beat it lands on",
          timeline["tempos"] == [{"beat": 0.0, "bpm": 72.0},
                                 {"beat": 8.0, "bpm": 144.0}],
          str(timeline["tempos"]))
    check("and the tempo is reported as the score's", timeline["tempo_from_score"] is True)

    # --------------------------------------------------------- the bridge
    print("\nthe boundary the app actually crosses")
    import bridge

    def call(op, **args):
        return json.loads(bridge.handle(json.dumps({"op": op, "args": args})))

    seed = Path(workspace_dir) / "seed.musicxml"
    fixtures.quartet(bars=6).write("musicxml", fp=str(seed))
    result = call("import", path=str(seed), name="Playback Test")
    slug = (result.get("result") or {}).get("score")
    check("the fixture imported", bool(slug), json.dumps(result)[:200])

    result = call("playback", score=slug)
    check("the bridge knows the playback op", result.get("ok") is True,
          str(result.get("error"))[:300])
    out = result.get("result") or {}
    path = out.get("path")
    check("it returns a midi path", bool(path), json.dumps(out)[:200])
    if path:
        midi = Path(path)
        check("the file is there", midi.exists(), path)
        check("and it is MIDI", midi.read_bytes()[:4] == b"MThd",
              str(midi.read_bytes()[:4]))
    timeline = out.get("timeline") or {}
    check("the timeline comes back with it", bool(timeline.get("bars")),
          json.dumps(timeline)[:200])
    check("four parts, matching the score", len(timeline.get("parts") or []) == 4)
    # Playback is a READING of the arrangement. If it ever made a version, the
    # history would fill with entries for pressing play.
    versions = (call("versions", score=slug).get("result") or {}).get("versions") or []
    check("playing made no new version", len(versions) == 1, str(len(versions)))

    print()
    if FAILURES:
        print(f"FAILED: {len(FAILURES)}")
        for failure in FAILURES:
            print(f"  - {failure}")
        return 1
    print("OK: the performed score plays its repeats out, sounds transposing "
          "parts at concert pitch, and hands back a bar map and a click grid "
          "that describe the same performance the MIDI holds")
    return 0


def _seed(score, ops, workspace):
    """Round-trip a fixture through the workspace, so structural ops see the
    same MusicXML the app would -- `set_structure` reads barlines that only
    exist after a write."""
    slug, _entry = workspace.create_score("Structure Seed", score, op="import", args={})
    return workspace.resolve_path(slug)


if __name__ == "__main__":
    sys.exit(main())
