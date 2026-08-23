"""Release gate: every score a user can bring in must import.

This exists because a write-time rhythm invariant, added to stop scores being
silently corrupted by edits, also refused scores on the way IN -- and an
imported PDF of a scanned jig is metrically imperfect by nature. The import
failed with "refusing to write v001.musicxml: part 1 bar 19: 3.25 beats of
music in a 3-beat bar" and the user could not open their own music.

The rule this gate enforces:

    Importing external material NEVER fails because the material is imperfect.
    It comes in as it is, its odd bars are reported as warnings, and the user
    fixes them from there. Only EDITS are held to the invariant, and only
    against the bar they started from.

Sources checked: every real sample in testdata/app-samples (whatever is there),
plus synthetic fixtures for the shapes that have broken before.

Run: engine/.venv/bin/python engine/scripts/check_import.py
"""

import os
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "engine"))
sys.path.insert(0, str(Path(__file__).resolve().parent))

FAILURES: list[str] = []
CHECKED: list[str] = []


def fresh_workspace(tmp: str):
    """A workspace of its own, so a check never touches the real library."""
    os.environ["SCORANGER_WORKSPACE"] = tmp
    for name in [m for m in sys.modules if m.startswith("scoranger_engine")]:
        del sys.modules[name]
    from scoranger_engine import ops, workspace  # noqa: PLC0415
    workspace.WORKSPACE = Path(tmp)
    workspace._repo_singleton = None
    return workspace, ops


def expect_imports(label: str, build_or_path, *, expect_warnings: bool = False):
    """Import something and require a usable v001 to come out of it."""
    from music21 import converter

    with tempfile.TemporaryDirectory() as tmp:
        workspace, ops = fresh_workspace(tmp)
        try:
            if isinstance(build_or_path, (str, Path)):
                score = converter.parse(str(build_or_path), forceSource=True)
                name = Path(build_or_path).stem
            else:
                score = build_or_path()
                name = label
            slug, entry = workspace.create_score(name, score)
        except Exception as e:  # noqa: BLE001 — the gate is the point
            FAILURES.append(f"{label}: import raised {type(e).__name__}: {e}")
            return
        CHECKED.append(label)

        if entry["id"] != "v001":
            FAILURES.append(f"{label}: first version is {entry['id']}, not v001")
            return

        path = workspace.resolve_path(slug)
        if not path.exists():
            FAILURES.append(f"{label}: v001 was recorded but no file was written")
            return

        # usable means: it parses, it has parts, and it has notes in them
        try:
            back = converter.parse(str(path), forceSource=True)
        except Exception as e:  # noqa: BLE001
            FAILURES.append(f"{label}: v001 does not parse back -- {e}")
            return
        if not back.parts:
            FAILURES.append(f"{label}: v001 has no parts")
            return
        if not list(back.recurse().notes):
            FAILURES.append(f"{label}: v001 has no notes")
            return

        warnings = entry.get("rhythm_warnings") or []
        if expect_warnings and not warnings:
            FAILURES.append(f"{label}: imperfect source imported with no warning -- "
                            "the odd bars must be reported, not hidden")
        if not expect_warnings and warnings:
            FAILURES.append(f"{label}: a clean source reported {len(warnings)} "
                            f"warning(s): {warnings[:2]}")

        # and the score must be workable afterwards: an op on top must succeed
        try:
            edited = converter.parse(str(path), forceSource=True)
            ops.transpose(edited, "M2", None)
            workspace.add_version(slug, edited, "transpose", {"interval": "M2"})
        except Exception as e:  # noqa: BLE001
            FAILURES.append(f"{label}: imported, but the first edit failed -- "
                            f"{type(e).__name__}: {e}")


import fixtures  # noqa: E402

# -- the regression that closed a release --------------------------------------
# An OMR jig with one over-full bar. This must import, with a warning naming
# the bar, and must not raise.
expect_imports("OMR jig with an over-full bar 19",
               fixtures.omr_jig, expect_warnings=True)
expect_imports("OMR jig, over-full bar 3 (early in the score)",
               lambda: fixtures.omr_jig(over_full_bar=3), expect_warnings=True)
expect_imports("OMR jig, a whole extra beat in a bar",
               lambda: fixtures.omr_jig(extra=fixtures.Q), expect_warnings=True)

# -- shapes that must keep importing cleanly -----------------------------------
expect_imports("clean 6/8 jig", fixtures.jig)
expect_imports("grand staff with a tie chain", fixtures.grand_staff)
expect_imports("string quartet", fixtures.quartet)

# -- every real sample the app ships or the repo carries -----------------------
samples = sorted((ROOT / "testdata" / "app-samples").glob("*.mxl")) \
    + sorted((ROOT / "testdata" / "app-samples").glob("*.musicxml"))
for sample in samples:
    expect_imports(f"sample: {sample.name}", sample)
if not samples:
    print("    note: no real samples in testdata/app-samples -- synthetic only")

# -- and the guard must still hold for EDITS ------------------------------------
# The point of narrowing the invariant was not to switch it off. An op that
# breaks a bar which was sound must still be refused.
with tempfile.TemporaryDirectory() as tmp:
    workspace, ops = fresh_workspace(tmp)
    from music21 import converter, note as m21note

    slug, _ = workspace.create_score("guard still holds", fixtures.jig())
    score = converter.parse(str(workspace.resolve_path(slug)), forceSource=True)
    # jam an extra beat into a bar that was fine: this is an edit, and it must fail
    score.parts[0].measure(4).append(m21note.Note("C5", quarterLength=1))
    try:
        workspace.add_version(slug, score, "deliberate-damage", {})
        FAILURES.append("an edit that broke a sound bar was accepted")
    except workspace.RhythmCorruption as e:
        if "bar 4" not in str(e):
            FAILURES.append(f"the refusal does not name the bar it broke: {e}")

    # while an edit that leaves an ALREADY-odd bar alone must be allowed through
    try:
        slug2, entry2 = workspace.create_score("odd source", fixtures.omr_jig())
        if not entry2.get("rhythm_warnings"):
            FAILURES.append("importing an odd source produced no warning")
        score2 = converter.parse(str(workspace.resolve_path(slug2)), forceSource=True)
        ops.transpose(score2, "M2", None)
        workspace.add_version(slug2, score2, "transpose", {"interval": "M2"})
    except workspace.RhythmCorruption as e:
        # the failure this whole file exists to prevent: reported, not raised,
        # so the gate says what went wrong instead of printing a traceback
        FAILURES.append(f"an imperfect source was refused rather than imported "
                        f"and warned about: {e}")

if FAILURES:
    print(f"FAIL: {len(FAILURES)} import gate check(s) failed")
    for line in FAILURES:
        print("   ", line)
    sys.exit(1)
print(f"OK: {len(CHECKED)} source(s) import to a usable v001, "
      "imperfect ones with warnings, and edits are still guarded")
