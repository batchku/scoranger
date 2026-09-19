"""ABC decorations, from the file a reader downloaded to the written notation.

Driven through the `scor` BINARY -- argparse wiring, subcommand names, flag
mapping, what `_emit` prints -- because an op that works when a check calls its
function and dies when a person runs it has not shipped.

WHAT IT ASSERTS INTO THE FILE, never into a stream: every assertion below
reads a MusicXML file `scor export` wrote and parsed back off disk. A mark can
be perfectly present in memory and absent from the file the reader keeps.

  1. THE FERMATA BUG, which is not part of the feature. music21's ABC reader
     folds a decoration into the note event's string and then discards several
     of those strings; for `H` it discards THE NOTE. `HA2 B2 c2 d2` parsed as
     three notes, so every tune Ali imported with a fermata in it was quietly
     a note short. The assertion is the COUNT first and the mark second.
  2. Every decoration ABC can write, each one to the object it becomes,
     read back out of the written file.
  3. The count guard: a mark is never hung on a note this module is not sure
     of. The scan numbers note events and the restore checks both the tune's
     total and each note's LETTER before attaching.

WHY THE FIXTURES ARE ABC TEXT, which nothing else in this repo is: the golden
rule is that notation is never written as text, and ABC *is* text -- music21
has no ABC writer, so a check that fed this reader anything else would be
testing nothing. The tunes below are short, synthetic and written for this
file; no setting is copied from anybody's transcription, because the
repository is public.

Run: engine/.venv/bin/python engine/scripts/check_abc_decorations.py
"""

import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "engine"))

SCOR = ROOT / "engine" / ".venv" / "bin" / "scor"
PYTHON = ROOT / "engine" / ".venv" / "bin" / "python"

FAILURES: list[str] = []


def check(condition: bool, message: str) -> None:
    if condition:
        print(f"  ok   {message}")
    else:
        print(f"  FAIL {message}")
        FAILURES.append(message)


def scor(env: dict, *args: str) -> dict:
    proc = subprocess.run([str(SCOR), *args], capture_output=True, text=True,
                          env=env)
    if proc.returncode != 0:
        raise AssertionError(
            f"scor {' '.join(args)} exited {proc.returncode}: "
            f"{(proc.stderr or proc.stdout).strip()[-400:]}")
    return json.loads(proc.stdout)


def written(env: dict, slug: str, out: Path):
    """The latest version, exported through the binary and read back off disk."""
    from music21 import converter

    scor(env, "export", slug, "--format", "musicxml", "--out", str(out))
    return converter.parse(str(out), forceSource=True)


HEAD = "X: 1\nT: {title}\nM: 4/4\nL: 1/8\nK: Dmaj\n"


def tune(root: Path, name: str, title: str, body: str) -> Path:
    path = root / name
    path.write_text(HEAD.format(title=title) + body + "\n", encoding="utf-8")
    return path


def marks_on(score) -> list[list[str]]:
    """Per note, every articulation and expression class name on it."""
    return on_each_note(score)


def on_each_note(score) -> list[list[str]]:
    """Per note event, every mark that reached it, whatever family it is in.

    A chord SYMBOL is a Chord to music21 and would come back from `.notes`
    with the music, shifting every index by one -- the same trap the engine's
    `enrich._events` is written around.
    """
    from music21 import dynamics, harmony, repeat, stream

    rows = []
    for part in score.parts:
        for measure in part.getElementsByClass(stream.Measure):
            loose = [type(x).__name__ for x in measure
                     if isinstance(x, (dynamics.Dynamic, repeat.RepeatExpression))]
            for element in measure.recurse().notesAndRests:
                if isinstance(element, harmony.Harmony):
                    continue
                rows.append([type(x).__name__ for x in element.articulations]
                            + [type(x).__name__ for x in element.expressions]
                            + loose)
                loose = []          # only the first note of the bar owns them
    return rows


#: eight notes to hang eight marks on, one tune's worth
PITCHES = ("C", "D", "E", "F", "G", "A", "B", "c")

#: mark -> the music21 class it must become in the WRITTEN file. Written out
#: rather than read from `enrich.DECORATIONS`: a table checked against itself
#: proves nothing. `main` asserts the two cover the same marks.
EXPECTED = {
    "roll": "Turn",
    "trill": "Trill",
    "mordent": "Mordent",
    "pralltriller": "InvertedMordent",
    "turn": "Turn",
    "inverted-turn": "InvertedTurn",
    "slide": "Schleifer",
    "fermata": "Fermata",
    "staccato": "Staccato",
    "staccatissimo": "Staccatissimo",
    "accent": "Accent",
    "marcato": "StrongAccent",
    "tenuto": "Tenuto",
    "up-bow": "UpBow",
    "down-bow": "DownBow",
    "breath": "BreathMark",
    "segno": "Segno",
    "coda": "Coda",
    "fine": "Fine",
    "da-capo": "DaCapo",
    "dal-segno": "DalSegno",
    **{f"dynamic:{d}": "Dynamic" for d in
       ("pppp", "ppp", "pp", "p", "mp", "mf", "f", "ff", "fff", "ffff",
        "sfz", "fp")},
}


def main() -> int:
    root = Path(tempfile.mkdtemp(prefix="abc-decorations-"))
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

    # ------------------------------------------------ the fermata BUG ---
    #
    # A bug, not a feature: the note came back one short. The count is the
    # assertion; the fermata itself is the feature's business below.
    print("\nthe note an `H` used to delete")
    out = scor(env, "import",
               str(tune(root, "fermata.abc", "Fermata Bug", "|HA2 B2 c2 d2|")))
    score = written(env, out["score"], root / "fermata.musicxml")
    notes = [n.nameWithOctave for n in score.flatten().notes]
    check(notes == ["A4", "B4", "C#5", "D5"],
          f"`HA2 B2 c2 d2` is FOUR notes in the written file: {notes}")
    check(marks_on(score)[0] == ["Fermata"],
          f"and the H is a fermata on the first of them: {marks_on(score)[0]}")
    fermatas = [e for n in score.flatten().notes for e in n.expressions
                if type(e).__name__ == "Fermata"]
    check(len(fermatas) == 1 and fermatas[0].type == "upright",
          f"drawn above the note, which is what an ABC `H` means: "
          f"{[f.type for f in fermatas]}")

    print("\nthe same fermata written the long way")
    out = scor(env, "import",
               str(tune(root, "fermata2.abc", "Long Fermata",
                        "|!fermata!A2 B2 c2 d2|")))
    score = written(env, out["score"], root / "fermata2.musicxml")
    check([n.nameWithOctave for n in score.flatten().notes]
          == ["A4", "B4", "C#5", "D5"],
          "`!fermata!` keeps its note too")
    check(marks_on(score)[0] == ["Fermata"],
          f"and becomes a fermata: {marks_on(score)[0]}")

    # ------------------------------------- every mark, to the written file ---
    #
    # EXPECTED is written out here rather than derived from
    # `enrich.DECORATIONS`, which would only prove the table equals itself.
    # The assertion below that the two cover the same marks is what makes a
    # decoration added to the engine without a test here FAIL rather than
    # pass unnoticed.
    from scoranger_engine import enrich

    print("\nevery decoration ABC can write, in the file that comes out")
    check(sorted(EXPECTED) == sorted(enrich.DECORATIONS),
          f"the check covers every mark the engine claims: "
          f"{sorted(set(EXPECTED) ^ set(enrich.DECORATIONS)) or 'all of them'}")

    # NOTE-ATTACHED marks first: one note per mark, `PITCHES` long tunes,
    # all in one file. They have to be proved through the BINARY and an
    # import apiece is a minute of subprocess for nothing.
    attached = [(mark, s) for mark, group in enrich._SPELLINGS.items()
                for s in group
                if enrich.DECORATIONS[mark][0] in ("expression", "articulation")]
    tunes, bodies = [], []
    for start in range(0, len(attached), len(PITCHES)):
        batch = attached[start:start + len(PITCHES)]
        body = " ".join(f"{s}{p}2" for (_m, s), p in zip(batch, PITCHES))
        pad = " ".join(f"{p}2" for p in PITCHES[len(batch):])
        bodies.append(f"|{body} {pad}|\n|{' '.join(f'{p}2' for p in PITCHES)}|")
        tunes.append(batch)

    source = root / "attached.abc"
    source.write_text("\n".join(
        f"X: {i + 1}\nT: Marks {i + 1}\nM: 8/4\nL: 1/8\nK: Cmaj\n{b}\n"
        for i, b in enumerate(bodies)), encoding="utf-8")
    out = scor(env, "import", str(source))
    check(out["tunes_found"] == len(tunes),
          f"the fixture imported as {out['tunes_found']} tunes")
    check((out.get("abc") or {}).get("decorations_carried") == len(attached),
          f"every one of the {len(attached)} note-attached spellings is "
          f"reported carried: "
          f"{(out.get('abc') or {}).get('decorations_carried')}")
    check(not (out.get("abc") or {}).get("decorations_misplaced"),
          "and none was declined")

    wrong = []
    for row, batch in zip(out["arrangements"], tunes):
        score = written(env, row["score"], root / f"{row['score']}.musicxml")
        got = on_each_note(score)
        for index, (mark, spelling) in enumerate(batch):
            want = EXPECTED[mark]
            if got[index] != [want]:
                wrong.append(f"{spelling} ({mark}) -> {got[index]}, want [{want}]")
    check(not wrong,
          f"each one becomes what it should: {wrong[:6] or f'all {len(attached)}'}")

    # NAVIGATION marks are not note-attached: a segno marks a place in the
    # FORM, so it goes into the measure at the barline -- exactly where
    # `ops._navigation_mark` puts one, which is what keeps `set-structure
    # --kind segno --remove` able to find it. One per BAR, therefore.
    print("\nand the marks that name a place in the form, one to a bar")
    navigation = [(mark, s) for mark, group in enrich._SPELLINGS.items()
                  for s in group
                  if enrich.DECORATIONS[mark][0] == "navigation"]
    body = "\n".join(f"|{s}C2 D2 E2 F2|" for _m, s in navigation)
    out = scor(env, "import", str(tune(root, "navigation.abc", "Navigation", body)))
    score = written(env, out["score"], root / "navigation.musicxml")
    from music21 import repeat as m21repeat
    from music21 import stream as m21stream
    got = [[type(x).__name__ for x in m
            if isinstance(x, m21repeat.RepeatExpression)]
           for m in score.parts[0].getElementsByClass(m21stream.Measure)]
    want = [[EXPECTED[mark]] for mark, _s in navigation]
    check(got == want, f"each lands in its own bar as itself: {got} want {want}")

    # DYNAMICS are offset-anchored, at the note they were written against --
    # the anchor `ops.ELEMENT_KINDS["dynamic"]` declares, so `adjust-element`
    # and `move-element` can already address them.
    print("\nand the dynamics, at the note each was written on")
    dyn = [(mark, s) for mark, group in enrich._SPELLINGS.items()
           for s in group if enrich.DECORATIONS[mark][0] == "dynamic"]
    rows = []
    for start in range(0, len(dyn), len(PITCHES)):
        batch = dyn[start:start + len(PITCHES)]
        body = " ".join(f"{s}{p}2" for (_m, s), p in zip(batch, PITCHES))
        pad = " ".join(f"{p}2" for p in PITCHES[len(batch):])
        rows.append((batch, f"|{body} {pad}|\n|{' '.join(f'{p}2' for p in PITCHES)}|"))
    source = root / "dynamics.abc"
    source.write_text("\n".join(
        f"X: {i + 1}\nT: Dynamics {i + 1}\nM: 8/4\nL: 1/8\nK: Cmaj\n{b}\n"
        for i, (_batch, b) in enumerate(rows)), encoding="utf-8")
    out = scor(env, "import", str(source))
    from music21 import dynamics as m21dynamics
    wrong = []
    for row, (batch, _b) in zip(out["arrangements"], rows):
        score = written(env, row["score"], root / f"{row['score']}.musicxml")
        first = list(score.parts[0].getElementsByClass(m21stream.Measure))[0]
        marks = sorted((float(x.offset), x.value) for x in first
                       if isinstance(x, m21dynamics.Dynamic))
        want = sorted((float(i), mark.split(":")[1])
                      for i, (mark, _s) in enumerate(batch))
        if marks != want:
            wrong.append(f"{marks} want {want}")
    check(not wrong,
          f"each sits at the offset of the note it was written on: "
          f"{wrong or f'all {len(dyn)}'}")

    # ------------------------------------------------- the count guard ---
    #
    # `[1` opens a first ending, not a chord. Read as a chord it swallows the
    # rest of the line as one event and every mark after it lands on the
    # wrong note -- which is what happened to 31 marks in a 541-tune
    # download before the walker learned the difference.
    print("\na first-ending bracket is not a chord")
    out = scor(env, "import", str(tune(
        root, "volta.abc", "Volta",
        "|:~A2 B2 c2 d2|\n[1 e2 f2 g2 a2:|\n[2 ~b2 a2 g2 f2|]")))
    check((out.get("abc") or {}).get("decorations_carried") == 2,
          f"both rolls are carried across the bracket: "
          f"{(out.get('abc') or {}).get('decorations_carried')}")
    score = written(env, out["score"], root / "volta.musicxml")
    rolls = [i for i, marks in enumerate(on_each_note(score)) if marks == ["Turn"]]
    check(rolls == [0, 8],
          f"on the first note of the tune and the first of the second "
          f"ending -- not on whatever the bracket swallowed: {rolls}")

    # --------------------------------------------- a mark on a chord ---
    print("\na chord is one event, and a mark on it lands on the chord")
    out = scor(env, "import", str(tune(
        root, "chord.abc", "Chord", "|~[CEG]2 B2 c2 d2|\n|e2 f2 g2 a2|")))
    score = written(env, out["score"], root / "chord.musicxml")
    first = list(score.flatten().notes)[0]
    check(first.isChord and [type(e).__name__ for e in first.expressions] == ["Turn"],
          f"the roll is on the chord: chord={first.isChord} "
          f"{[type(e).__name__ for e in first.expressions]}")

    if FAILURES:
        print(f"\nFAIL: {len(FAILURES)} ABC decoration check(s) failed")
        for f in FAILURES:
            print(f"    {f}")
        return 1
    print("\nOK: ABC decorations reach the written notation")
    return 0


if __name__ == "__main__":
    sys.exit(main())
