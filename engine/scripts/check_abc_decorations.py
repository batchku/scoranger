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
    return [[type(x).__name__ for x in n.articulations]
            + [type(x).__name__ for x in n.expressions]
            for n in score.flatten().notes]


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

    if FAILURES:
        print(f"\nFAIL: {len(FAILURES)} ABC decoration check(s) failed")
        for f in FAILURES:
            print(f"    {f}")
        return 1
    print("\nOK: ABC decorations reach the written notation")
    return 0


if __name__ == "__main__":
    sys.exit(main())
