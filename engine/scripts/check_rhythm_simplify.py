"""`scor simplify-rhythm`, driven as the PROCESS a reader drives.

Every other engine check imports `scoranger_engine` and calls a function, which
leaves a whole layer untested: argparse wiring, the name the subcommand is
registered under, the flag-to-keyword mapping, what `_emit` prints, and the
error path. `scor whistle-fingerings` was dead for months with a plain
NameError because its check called `ops.whistle_fingerings` directly and
nothing ever started the binary. So this starts the binary: one process per
command, JSON read back off stdout, exit codes checked, refusals read off
stderr.

THE ENGINE IT RUNS. `engine/.venv` is a symlink in every worktree, so the
binary's own `scoranger_engine` resolves to the MAIN checkout unless PYTHONPATH
says otherwise. The first section proves the process is running the source in
THIS tree; without it a worktree could pass this check against code it does not
contain.

WHAT IT ASSERTS is the musical judgement, not just that the op ran. The op
exists because "reduce the 16th notes down to eighth notes" is two different
pieces of music and the op refuses to choose between them silently:

  augment  every value doubles and the meter's denominator halves. Nothing is
           lost, no bar is added or renumbered. The passage lasts twice as
           long, so it is a change to the WHOLE score and a named part of a
           multi-part score is refused.
  thin     attacks are quantized onto the unit grid and what falls between is
           dropped. Place and length survive, so the part still fits the
           others; notes do not, and `notes_removed` is in the report.

Which notes thinning keeps is checked note by note against `fixtures.sax_study`,
whose every bar is one of the figures that decides the answer.

Fixtures are synthetic: the repository is public, so no committed fixture may
carry copyrighted music.

Run: engine/.venv/bin/python engine/scripts/check_rhythm_simplify.py
"""

import json
import os
import subprocess
import sys
import tempfile
from fractions import Fraction
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "engine"))
sys.path.insert(0, str(Path(__file__).resolve().parent))

import fixtures  # noqa: E402

SCOR = ROOT / "engine" / ".venv" / "bin" / "scor"
PYTHON = ROOT / "engine" / ".venv" / "bin" / "python"

FAILURES: list[str] = []


def check(condition: bool, message: str) -> None:
    if condition:
        print(f"  ok   {message}")
    else:
        print(f"  FAIL {message}")
        FAILURES.append(message)


def run(env: dict, *args: str) -> subprocess.CompletedProcess:
    return subprocess.run([str(SCOR), *args], capture_output=True, text=True,
                          env=env)


def scor(env: dict, *args: str) -> dict:
    """One `scor` command that is expected to succeed, as parsed JSON."""
    proc = run(env, *args)
    if proc.returncode != 0:
        raise AssertionError(
            f"scor {' '.join(args)} exited {proc.returncode}: "
            f"{(proc.stderr or proc.stdout).strip()[-400:]}")
    return json.loads(proc.stdout)


def refusal(env: dict, *args: str) -> str:
    """One `scor` command that is expected to be refused. Returns the message."""
    proc = run(env, *args)
    if proc.returncode == 0:
        raise AssertionError(f"scor {' '.join(args)} was accepted: {proc.stdout[:300]}")
    return str(json.loads(proc.stderr)["error"])


def written(env: dict, slug: str, out: Path):
    """The latest version, exported through the binary and read back off disk.

    Read back, never inspected in memory: an op can be perfectly correct in a
    stream and still leave a corrupt file, which is the whole reason
    check_rhythm.py exists.
    """
    from music21 import converter

    scor(env, "export", slug, "--format", "musicxml", "--out", str(out))
    return converter.parse(str(out), forceSource=True)


def figure(part, bar: int) -> list[tuple]:
    """A bar's attacks, as (offset, duration) in exact fractions."""
    from music21 import stream as m21stream

    measure = next(m for m in part.getElementsByClass(m21stream.Measure)
                   if m.number == bar)
    return [(Fraction(n.offset).limit_denominator(10 ** 6),
             Fraction(n.quarterLength).limit_denominator(10 ** 6))
            for n in sorted(measure.notes, key=lambda n: n.offset)]


def overbeamed(path: Path) -> list[tuple[str, int]]:
    """Notes in the FILE whose beam count outruns their written duration.

    A <note><type>eighth</type> may carry one <beam>. Two means the note used
    to be a sixteenth and nothing re-beamed the bar after it was stretched.
    """
    import xml.etree.ElementTree as ET

    allowed = {"eighth": 1, "16th": 2, "32nd": 3, "64th": 4}
    bad = []
    for note_el in ET.parse(path).getroot().iter("note"):
        written_type = note_el.findtext("type") or ""
        beams = len(note_el.findall("beam"))
        if beams > allowed.get(written_type, 0):
            bad.append((written_type, beams))
    return bad


def imported(env: dict, score, name: str, root: Path) -> str:
    path = root / f"{name}.musicxml"
    score.write("musicxml", fp=str(path))
    return scor(env, "import", str(path), "--name", name)["score"]


def main() -> int:  # noqa: C901 -- a checklist reads better whole
    from music21 import duration as m21duration
    from music21 import meter as m21meter
    from music21 import note as m21note
    from music21 import spanner as m21spanner
    from music21 import stream as m21stream

    root = Path(tempfile.mkdtemp())
    env = dict(os.environ)
    env["SCORANGER_WORKSPACE"] = str(root / "workspace")
    env["PYTHONPATH"] = str(ROOT / "engine")

    print("the binary runs the engine in this checkout")
    probe = subprocess.run(
        [str(PYTHON), "-c",
         "import scoranger_engine; print(scoranger_engine.__file__)"],
        capture_output=True, text=True, env=env)
    where = Path(probe.stdout.strip()) if probe.stdout.strip() else None
    check(SCOR.exists(), f"the scor binary is at {SCOR}")
    check(where is not None and ROOT in where.parents,
          f"scoranger_engine resolves inside this tree: {where}")

    E, Q, H, W = Fraction(1, 2), Fraction(1), Fraction(2), Fraction(4)
    S, DE, DQ = Fraction(1, 4), Fraction(3, 4), Fraction(3, 2)
    third = Fraction(1, 3)

    # ---------------------------------------------------------------- thin ---
    print("\nthinning a sax study to eighths, through the binary")
    solo = imported(env, fixtures.sax_study(), "Sax Study", root)
    before = scor(env, "info", solo)["parts"][0]
    out = scor(env, "simplify-rhythm", solo, "--mode", "thin",
               "--part", "Alto Saxophone", "--unit", "eighth")
    told = out["details"]
    check(out["op"] == "simplify-rhythm" and out["new_version_label"] == "v002",
          f"it made {out['new_version_label']} with op '{out['op']}'")
    check(told["mode"] == "thin" and told["unit"] == "eighth",
          f"the report names the choice that was made: {told['mode']}")
    check(told["shortest_before"] == "16th" and told["shortest_now"] == "eighth",
          f"the fastest value went {told['shortest_before']} -> "
          f"{told['shortest_now']}")
    check(told["reached_unit"] is True, "and it says the unit was reached")

    print("\nthe report says how many notes it took, because that is someone's music")
    after = scor(env, "info", solo)["parts"][0]
    check(told["notes_removed"] > 0, f"notes_removed is stated: {told['notes_removed']}")
    check(before["notes"] - after["notes"] == told["notes_removed"],
          f"and it is the truth: the part went {before['notes']} -> "
          f"{after['notes']} notes, a loss of "
          f"{before['notes'] - after['notes']}, reported as "
          f"{told['notes_removed']}")
    check(sum(told["removed_by_measure"].values()) == told["notes_removed"],
          "the per-bar tally adds up to the total, so a reader can go and look")

    print("\nWHICH notes it kept is the metrical judgement, bar by bar")
    part = written(env, solo, root / "thinned.musicxml").parts[0]
    check(figure(part, 1) == [(Fraction(i, 2), E) for i in range(8)],
          "bar 1: sixteen sixteenths became eight eighths -- the first and "
          "third of each group, which is what a player keeps")
    check(figure(part, 2) == [(Fraction(i), Q) for i in range(4)],
          "bar 2: dotted eighth + sixteenth became a quarter -- the pickup "
          "sixteenth is what goes, not the beat")
    check(figure(part, 3) == [(Fraction(0), E), (E, Q), (DQ, E),
                              (Fraction(2), Q), (Fraction(3), Q)],
          "bar 3: an eighth-note syncopation is ON the grid and is untouched")
    check(figure(part, 4) == [(Fraction(0), W)],
          "bar 4: a whole note is not a fast note and is untouched")
    check(figure(part, 6) == [(third * 4 * i, third * 4) for i in range(3)],
          "bar 6: QUARTER-note triplets are longer than an eighth, so they "
          "survive whole despite landing between the grid lines")
    check(figure(part, 7) == [(Fraction(i), Q) for i in range(4)],
          "bar 7: eighth triplets ARE faster than an eighth, so they thin")
    check(figure(part, 8) == [(Fraction(0), DQ), (DQ, E), (Fraction(2), H)],
          "bar 8: dotted quarter + eighth + half is already slow and is untouched")

    print("\nnothing moved: the passage keeps its place and its length")
    check([float(p.highestTime) for p in
           written(env, solo, root / "len.musicxml").parts] == [32.0],
          "the part is as long as it was -- thinning drops notes, it does not "
          "shorten the music, which is what keeps it in step with the others")
    from scoranger_engine import ops  # noqa: E402  -- for its fault detector only

    check(ops.rhythm_problems(part) == [],
          "and the file it wrote holds its meter in every bar")

    print("\na removed note takes its slur with it")
    # bar 5 is a sixteenth run with a slur over its first four notes. Thinning
    # removes the 2nd and the 4th, one of which the slur ENDS on. The slur has
    # to end on the note that swallowed it instead -- not vanish (which is what
    # the writer does with a spanner pointing at nothing) and not reach past
    # the bar (which is what Verovio drew on the first render: one arc across a
    # whole system, plus 11 beamspans it could not close).
    slurs = list(part.recurse().getElementsByClass(m21spanner.Slur))
    check(len(slurs) == 1,
          f"the slur in bar 5 survived thinning: {len(slurs)} slur(s)")
    ends = [(e.getContextByClass(m21stream.Measure).number,
             Fraction(e.offset).limit_denominator(10 ** 6))
            for s in slurs for e in s.getSpannedElements()]
    check(ends == [(5, Fraction(0)), (5, Fraction(1, 2))],
          f"and it now runs between the two notes that are still there, both "
          f"inside bar 5: {ends}")
    check(told["slurs_dropped"] == 0,
          f"none had to be dropped for having one end left: "
          f"{told['slurs_dropped']}")
    # A sixteenth carries two beams. Stretch it into an eighth and leave the
    # beams alone and the file says "eighth note, two beams" -- which is what
    # Verovio reported on the first render of real music as 11 beamspans left
    # without an ending. So a thinned bar is re-beamed from the meter.
    #
    # Read off the RAW XML, not off a parsed stream: music21's MusicXML reader
    # derives a note's beams from its duration type and quietly discards the
    # extras, so a file with the defect in it comes back through `converter`
    # looking clean. The first version of this check did exactly that and
    # passed with the fix reverted.
    check(not overbeamed(root / "thinned.musicxml"),
          f"no note in the file carries more beams than its own duration has -- "
          f"no eighth is left holding a sixteenth's second beam "
          f"({len(overbeamed(root / 'thinned.musicxml'))} do)")

    print("\na bar attacked entirely between the grid lines is LEFT ALONE, not emptied")
    odd = m21stream.Score()
    odd_part = m21stream.Part()
    odd_part.partName = "Alto Saxophone"
    for bar in (1, 2):
        measure = m21stream.Measure(number=bar)
        if bar == 1:
            measure.insert(0.0, m21meter.TimeSignature("4/4"))
        offsets = ([Fraction(1, 4), Fraction(3, 4)] if bar == 2
                   else [Fraction(i, 4) for i in range(16)])
        for offset in offsets:
            n = m21note.Note("C5")
            n.duration = m21duration.Duration(S)
            measure.insert(offset, n)
        odd_part.append(measure)
    odd.append(odd_part)
    stubborn = imported(env, odd, "Off The Grid", root)
    told2 = scor(env, "simplify-rhythm", stubborn, "--mode", "thin",
                 "--part", "#0", "--unit", "eighth")["details"]
    check(told2.get("measures_left_alone") == [2],
          f"bar 2 is reported as left alone: {told2.get('measures_left_alone')}")
    check("left exactly as written" in told2["cost"],
          "and the cost sentence says so in words a reader can act on")
    kept = figure(written(env, stubborn, root / "odd.musicxml").parts[0], 2)
    check(kept == [(Fraction(1, 4), S), (Fraction(3, 4), S)],
          f"its notes are exactly as they were: {kept}")

    # ------------------------------------------------------------- augment ---
    print("\naugmenting a solo: nothing lost, nothing renumbered")
    aug = imported(env, fixtures.sax_study(), "Sax Study Augmented", root)
    was = scor(env, "info", aug)["parts"][0]
    told3 = scor(env, "simplify-rhythm", aug, "--mode", "augment",
                 "--unit", "eighth")["details"]
    now = scor(env, "info", aug)["parts"][0]
    check(told3["notes_removed"] == 0 and now["notes"] == was["notes"],
          f"not a note was lost: {was['notes']} -> {now['notes']}")
    check(now["measures"] == was["measures"],
          f"and not a bar was added: {was['measures']} -> {now['measures']}")
    check(told3["meters"][0] == {"measure": 1, "from": "4/4", "to": "4/2"},
          f"the meter halved instead: {told3['meters'][0]}")
    aug_part = written(env, aug, root / "augmented.musicxml").parts[0]
    check(figure(aug_part, 1) == [(Fraction(i, 2), E) for i in range(16)],
          "bar 1's sixteen sixteenths are sixteen EIGHTHS -- every one of them, "
          "where thinning kept eight")
    check(float(aug_part.highestTime) == 64.0,
          f"the passage takes twice as long: {float(aug_part.highestTime)} "
          f"beats where it took 32")
    check(told3["beats_now"] == told3["beats_before"] * 2
          and "half speed" in told3["cost"],
          "and the report says that in words: it sounds at half speed")
    check("Doubling the tempo mark as well would undo the whole thing"
          in told3["cost"],
          "including the thing nobody says out loud -- that this IS 'play it "
          "slower', and doubling the tempo back would leave the music unchanged")
    check(ops.rhythm_problems(aug_part) == [],
          "the file it wrote holds its meter in every bar")

    print("\naugmenting a passage puts the meter back after it")
    ranged = imported(env, fixtures.sax_study(), "Just The Hard Bars", root)
    told4 = scor(env, "simplify-rhythm", ranged, "--mode", "augment",
                 "--from-measure", "3", "--to-measure", "4")["details"]
    moves = {m["measure"]: (m["from"], m["to"]) for m in told4["meters"]}
    check(moves.get(3) == ("4/4", "4/2"), f"bar 3 goes into 4/2: {moves.get(3)}")
    check(moves.get(5) == ("4/2", "4/4"),
          f"and bar 5 comes back out of it: {moves.get(5)} -- without that the "
          f"rest of the piece silently inherits half speed")
    ranged_part = written(env, ranged, root / "ranged.musicxml").parts[0]
    lengths = {m.number: float(m.barDuration.quarterLength)
               for m in ranged_part.getElementsByClass(m21stream.Measure)}
    check(lengths[2] == 4.0 and lengths[3] == 8.0 and lengths[5] == 4.0,
          f"the bars around it are untouched: {lengths[2]}, {lengths[3]}, "
          f"{lengths[5]}")
    check(sorted(lengths) == list(range(1, 9)),
          "and every bar still answers to the number it had, so a repeat or a "
          "rehearsal mark still points where it did")

    print("\nthe report does not send a reader into a refusal it can predict")
    check("doubling has gone as far as the meter allows" in
          told3.get("still_faster_than_unit", "")
          or told3["reached_unit"],
          "when another pass would be refused, it says so instead of "
          "suggesting one")
    check("4/1" in refusal(env, "simplify-rhythm", aug, "--mode", "augment"),
          "and the second pass on a 4/2 really is refused, by the meter it "
          "would have to write")

    # ------------------------------------------------------------ refusals ---
    print("\nrefusals arrive as JSON on stderr with a non-zero exit")
    duet = imported(env, fixtures.quartet(bars=4), "A Quartet", root)
    message = refusal(env, "simplify-rhythm", duet, "--mode", "augment",
                      "--part", "Viola")
    check("whole score" in message and "--mode thin" in message,
          "augmenting ONE part of a quartet is refused by name and names the "
          "op that can do it")
    check(scor(env, "info", duet)["parts"][2]["measures"] == 4,
          "and the refusal changed nothing")
    check("needs to be told whose" in
          refusal(env, "simplify-rhythm", duet, "--mode", "thin"),
          "thinning with no --part is refused: it drops notes, so it has to "
          "be told whose")
    check("No part matches" in
          refusal(env, "simplify-rhythm", duet, "--mode", "thin",
                  "--part", "Trombone"),
          "a part that is not there is refused by name")
    check("not a note value" in
          refusal(env, "simplify-rhythm", solo, "--mode", "thin",
                  "--part", "#0", "--unit", "crotchety"),
          "and so is a unit that is not a note value")
    check("invalid choice" in
          run(env, "simplify-rhythm", solo, "--mode", "shorten").stderr,
          "a mode that is not one of the two is refused by argparse, which "
          "means the choice cannot be fudged")

    print("\naugmenting every part of the quartet together is accepted")
    told5 = scor(env, "simplify-rhythm", duet, "--mode", "augment")["details"]
    check(len(told5["parts"]) == 4,
          f"all four went together: {told5['parts']}")
    quartet_parts = written(env, duet, root / "quartet.musicxml").parts
    check(len({float(p.highestTime) for p in quartet_parts}) == 1,
          f"and they are still the same length as each other: "
          f"{[float(p.highestTime) for p in quartet_parts]} -- which is the "
          f"whole reason one part alone is refused")

    print("\nevery run left a version behind it, named for what it did")
    made = [v["op"] for v in scor(env, "versions", solo)["versions"]]
    check(made.count("simplify-rhythm") >= 1,
          f"'simplify-rhythm' is in the history: {made}")

    print()
    if FAILURES:
        print(f"{len(FAILURES)} FAILED")
        for f in FAILURES:
            print(f"  - {f}")
        return 1
    print("OK: simplify-rhythm answers as a PROCESS, it does not choose between "
          "augmenting and thinning on the reader's behalf, and it says what the "
          "choice cost -- every note, or none")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
