"""The engine ops run as the `scor` PROCESS, not as Python functions.

Every other engine check imports `scoranger_engine` and calls a function. That
leaves a whole layer untested: argparse wiring, the name a subcommand is
registered under, the flag-to-keyword mapping, what `_emit` prints, and what
happens on the error path. `scor whistle-fingerings` was dead for months with a
plain NameError because `check_whistle.py` called `ops.whistle_fingerings`
directly and nothing ever started the binary.

So this check starts the binary. It builds a fixture that carries one of every
addressable added element, imports it through `scor import`, and then drives
the ops the way a person at a terminal -- or the agent in CLAUDE.md -- drives
them: one process per command, JSON read back off stdout, exit codes checked.

It also asserts the ERROR path, because that is half of a CLI: a refusal has to
arrive as JSON on stderr with a non-zero exit, not as a traceback.

THE ENGINE IT RUNS. `engine/.venv` is a symlink in every worktree, so the
binary's own `scoranger_engine` resolves to the MAIN checkout unless PYTHONPATH
says otherwise. The first section proves the process is running the source in
THIS tree; without it a worktree could pass this check against code it does not
contain.

Fixtures are synthetic: the repository is public, so no committed fixture may
carry copyrighted music.

Run: engine/.venv/bin/python engine/scripts/check_cli_process.py
"""

import json
import os
import subprocess
import sys
import tempfile
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
    payload = json.loads(proc.stderr)
    return str(payload["error"])


def marked_score(path: Path) -> Path:
    """A jig carrying one of every addressable added element.

    Built here rather than mutated in by the CLI because there is no op that
    ADDS a dynamic or a fermata -- this build adjusts and moves what a score
    already has, and the UI that puts them there is step 4.
    """
    from music21 import articulations, dynamics, expressions, harmony

    from scoranger_engine import ops

    score = fixtures.jig(bars=8)
    ops.set_chord_symbols(score, "#0", [{"measure": 1, "symbol": "Em"},
                                        {"measure": 3, "symbol": "G"}])
    first_bar = score.parts[0].measure(1)
    first_bar.insert(0.0, dynamics.Dynamic("mf"))
    first_bar.insert(1.0, expressions.TextExpression("dolce"))
    # A chord SYMBOL is a Chord to music21 and sorts first at offset 0, so
    # `notes[0]` is the symbol and not the music. Hanging a fermata there
    # writes it onto something that is not on the staff at all.
    first_note = next(n for n in first_bar.notes
                      if not isinstance(n, harmony.Harmony))
    first_note.expressions.append(expressions.Fermata())
    first_note.articulations.append(articulations.Accent())
    score.write("musicxml", fp=str(path))
    return path


def exported(env: dict, slug: str, out: Path) -> str:
    """The latest version as MusicXML, fetched through the binary."""
    scor(env, "export", slug, "--format", "musicxml", "--out", str(out))
    return out.read_text(encoding="utf-8")


def main() -> int:
    root = Path(tempfile.mkdtemp())
    env = dict(os.environ)
    env["SCORANGER_WORKSPACE"] = str(root / "workspace")
    # The whole point: the process must run the engine in THIS tree.
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

    print("\na score with one of every added element goes in through the binary")
    source = marked_score(root / "marked.musicxml")
    imported = scor(env, "import", str(source), "--name", "CLI Process")
    slug = imported["score"]
    check(imported["version_label"] == "v001", f"it imported as {imported['version_label']}")
    check(scor(env, "info", slug)["parts"][0]["measures"] == 8,
          "and `scor info` reads it back")

    print("\nadjust-element reaches every kind, through the process")
    # harm was the only kind before this build; the other four are what
    # generalising past `kind=harm` was for.
    for kind, flags, expect in (
            ("harm", ["--scale", "1.5"], 18.0),
            ("dynamic", ["--scale", "1.5"], 18.0),
            ("text", ["--scale", "1.25", "--offset-y", "-6"], 15.0),
            ("articulation", ["--scale", "2"], 24.0),
            ("fermata", ["--offset-y", "-9"], None)):
        out = scor(env, "adjust-element", slug, "--part", "#0",
                   "--kind", kind, "--measure", "1", *flags)
        details = out["details"]
        check(details["adjusted"] == 1 and details["kind"] == kind,
              f"--kind {kind} adjusted exactly one element")
        check(details["size"] == expect,
              f"--kind {kind} wrote size {details['size']} (expected {expect})")

    print("\nsize is RELATIVE to the engraved default, and says so both ways")
    out = scor(env, "adjust-element", slug, "--part", "#0", "--kind", "dynamic",
               "--measure", "1", "--scale", "2")["details"]
    check(out["scale"] == 2.0 and out["size"] == 24.0,
          f"--scale 2 is 2x the engraved default: {out['size']}pt of 12.0")
    check("not both" in refusal(env, "adjust-element", slug, "--part", "#0",
                                "--kind", "dynamic", "--measure", "1",
                                "--scale", "2", "--size", "24"),
          "a scale and a size together are refused rather than one winning")
    check("greater than 0" in refusal(env, "adjust-element", slug, "--part", "#0",
                                      "--kind", "dynamic", "--measure", "1",
                                      "--scale", "0"),
          "a scale of 0 is refused")

    print("\nthe adjustments are in the exported notation, not just in a report")
    xml = exported(env, slug, root / "adjusted.musicxml")
    check('font-size="18"' in xml or 'font-size="18.0"' in xml,
          "a font-size reached the file")
    check('relative-y="-6"' in xml or 'relative-y="-6.0"' in xml,
          "and so did an offset")

    print("\nmove-element: an offset-anchored element lands in another bar")
    out = scor(env, "move-element", slug, "--part", "#0", "--kind", "dynamic",
               "--measure", "1", "--to-measure", "3", "--to-offset", "1.5")["details"]
    check(out["anchor"] == "offset" and out["to"] == {"measure": 3, "offset": 1.5},
          f"the dynamic moved to bar 3 at 1.5: {out['to']}")
    check(refusal(env, "adjust-element", slug, "--part", "#0", "--kind",
                  "dynamic", "--measure", "1", "--scale", "1.5")
          .endswith("(it has 0)"),
          "and bar 1 no longer has one -- a move is a move, not a copy")
    moved = scor(env, "adjust-element", slug, "--part", "#0", "--kind",
                 "dynamic", "--measure", "3", "--scale", "1.5")["details"]
    check(moved["adjusted"] == 1, "bar 3 has it")

    print("\nduplicate-element: the original stays where it was")
    out = scor(env, "duplicate-element", slug, "--part", "#0", "--kind",
               "fermata", "--measure", "1", "--to-measure", "4",
               "--to-offset", "0")["details"]
    check(out["anchor"] == "note" and out["op"] == "duplicate",
          f"a fermata is note-attached and was duplicated: {out['anchor']}")
    for bar in (1, 4):
        still = scor(env, "adjust-element", slug, "--part", "#0", "--kind",
                     "fermata", "--measure", str(bar), "--offset-y", "-2")["details"]
        check(still["adjusted"] == 1, f"bar {bar} carries a fermata")

    print("\nrefusals arrive as JSON on stderr with a non-zero exit")
    check("spanner" in refusal(env, "move-element", slug, "--part", "#0",
                               "--kind", "slur", "--measure", "1",
                               "--to-measure", "2"),
          "a slur is refused by name: spanners are out of scope")
    check("hang off a note" in refusal(env, "move-element", slug, "--part", "#0",
                                        "--kind", "articulation", "--measure", "1",
                                        "--to-measure", "4", "--to-offset", "0.3"),
          "a note-attached element cannot land where no note starts")
    check("not inside measure" in refusal(env, "move-element", slug, "--part", "#0",
                                          "--kind", "harm", "--measure", "1",
                                          "--to-measure", "2", "--to-offset", "9"),
          "an offset past the end of the destination bar is refused")
    check("no measure" in refusal(env, "move-element", slug, "--part", "#0",
                                  "--kind", "harm", "--measure", "1",
                                  "--to-measure", "99"),
          "so is a bar the part does not have")

    print("\nthe ops that write onto notes still start as processes")
    # `scor whistle-fingerings` raised NameError for months. The function was
    # checked; the command was not. Both of these write verses onto notes and
    # both are reachable only through argparse.
    for command in (["whistle-fingerings", slug, "--part", "#0"],
                    ["guitar-tab", slug, "--part", "#0"],
                    ["chord-diagrams", slug, "--part", "#0"]):
        out = scor(env, *command)
        check(bool(out.get("details")), f"`scor {command[0]}` ran and reported")

    print("\na tab column is adjustable but NOT movable: it is the note")
    check(scor(env, "adjust-element", slug, "--part", "#0", "--kind", "tab",
               "--measure", "1", "--scale", "1.5")["details"]["adjusted"] >= 1,
          "--kind tab resizes the column")
    check("Can move" in refusal(env, "move-element", slug, "--part", "#0",
                                "--kind", "tab", "--measure", "1",
                                "--to-measure", "2"),
          "and moving one is refused: moving it would mean moving the music")

    print("\nevery mutation left a version behind it")
    versions = scor(env, "versions", slug)["versions"]
    made = [v["op"] for v in versions]
    for op in ("import", "adjust-element", "move-element", "duplicate-element"):
        check(op in made, f"'{op}' is in the history")

    print("\nrename-book, through the binary the app's Rename will mirror")
    from pypdf import PdfWriter

    book_pdf = root / "fake-book.pdf"
    writer = PdfWriter()
    for _ in range(4):
        writer.add_blank_page(width=612, height=792)
    with open(book_pdf, "wb") as f:
        writer.write(f)
    book = scor(env, "import-book", str(book_pdf), "--name", "Teh Rael Bok")
    renamed = scor(env, "rename-book", book["book"], "--name", "The Real Book")
    check(renamed["name"] == "The Real Book", f"the name changed: {renamed['name']}")
    check(renamed["slug"] == book["book"],
          "the slug did not -- it names the stored PDF and every extraction's args")
    listed = {b["slug"]: b["name"] for b in scor(env, "books")["books"]}
    check(listed.get(book["book"]) == "The Real Book",
          "and `scor books` reports the new name")
    manifest = json.loads((Path(env["SCORANGER_WORKSPACE"]) / "manifest.json")
                          .read_text(encoding="utf-8"))
    check(any(b["slug"] == book["book"] and b["name"] == "The Real Book"
              for b in manifest["books"]),
          "the manifest the app reads was rebuilt, so the row redraws")
    check("No book" in refusal(env, "rename-book", "not-a-book", "--name", "X"),
          "renaming a book that is not there names the ones that are")
    check("name is required" in refusal(env, "rename-book", book["book"],
                                        "--name", "   "),
          "and a blank name is refused rather than stored")

    print()
    if FAILURES:
        print(f"{len(FAILURES)} FAILED")
        for f in FAILURES:
            print(f"  - {f}")
        return 1
    print("OK: the ops answer as a PROCESS -- argparse wiring, flag mapping, "
          "JSON on stdout and refusals on stderr, all of it the layer that let "
          "`scor whistle-fingerings` be dead while its function was green")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
