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

        first = workspace.version_label(entry)
        if first != "v001":
            FAILURES.append(f"{label}: first version is labelled {first}, not v001")
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
samples = sorted(p for p in (ROOT / "testdata" / "app-samples").iterdir()
                 if p.suffix.lower() in {".mxl", ".musicxml", ".abc"})
for sample in samples:
    expect_imports(f"sample: {sample.name}", sample)
if not samples:
    print("    note: no real samples in testdata/app-samples -- synthetic only")

# -- and a damaging edit must still be CAUGHT, in development ------------------
# The runtime no longer refuses anything. What has to hold is that a bad
# transformation is detectable here, before a release, rather than in a user's
# score afterwards.
with tempfile.TemporaryDirectory() as tmp:
    workspace, ops = fresh_workspace(tmp)
    from music21 import converter, note as m21note

    slug, _ = workspace.create_score("damage is detectable", fixtures.jig())
    sound = converter.parse(str(workspace.resolve_path(slug)), forceSource=True)
    if ops.rhythm_faults(sound):
        FAILURES.append("the clean fixture is not clean")

    sound.parts[0].measure(4).append(m21note.Note("C5", quarterLength=1))
    entry = workspace.add_version(slug, sound, "deliberate-damage", {})
    written = converter.parse(str(workspace.resolve_path(slug)), forceSource=True)
    faults = ops.rhythm_faults(written)
    if not any(bar == 4 for _, bar, _ in faults):
        FAILURES.append("an op that added a beat to a sound bar went undetected")
    if not entry.get("rhythm_warnings"):
        FAILURES.append("the damaged version carries no warning for the app to show")

    # and an edit that inherits an odd bar is ordinary work, not an error
    slug2, entry2 = workspace.create_score("odd source", fixtures.omr_jig())
    if not entry2.get("rhythm_warnings"):
        FAILURES.append("importing an odd source produced no warning")
    inherited = len(entry2["rhythm_warnings"])
    score2 = converter.parse(str(workspace.resolve_path(slug2)), forceSource=True)
    ops.set_structure(score2, "repeat-end", measure=8)
    entry3 = workspace.add_version(slug2, score2, "set-structure", {"kind": "repeat-end"})
    if len(entry3.get("rhythm_warnings") or []) > inherited:
        FAILURES.append("adding a repeat to an OMR score made its odd bars worse")

# -- a half-finished import must leave nothing behind ---------------------------
# Ali's device grew a "Morrison's jig" arrangement with ZERO versions: tapping
# it sat on "Opening…" forever, because an arrangement with no versions has no
# version to display. create_score wrote the score row first and the version
# second, so anything that went wrong in between -- a write error, a parse
# failure building the parts snapshot, the app being killed -- left the row
# behind with nothing in it. An arrangement that holds no music should not
# exist.
with tempfile.TemporaryDirectory() as tmp:
    workspace, ops = fresh_workspace(tmp)

    real_write = workspace._write_musicxml

    def explode(score, path, **kwargs):
        raise OSError("disk full, or any other reason a write does not finish")

    workspace._write_musicxml = explode
    try:
        workspace.create_score("doomed import", fixtures.jig())
        FAILURES.append("a failed write still created an arrangement")
    except OSError:
        pass
    finally:
        workspace._write_musicxml = real_write

    leftover = [s["slug"] for s in workspace._repo().list_scores()]
    if leftover:
        FAILURES.append(f"a failed import left an arrangement behind: {leftover}")
    if (Path(tmp) / "doomed-import").exists():
        FAILURES.append("a failed import left its directory behind")

    # and the library never contains an arrangement with no versions
    workspace.create_score("good one", fixtures.jig())
    for doc in workspace._repo().list_scores():
        if not workspace._repo().list_versions(doc["slug"]):
            FAILURES.append(f"{doc['slug']} exists with no versions")

if FAILURES:
    print(f"FAIL: {len(FAILURES)} import gate check(s) failed")
    for line in FAILURES:
        print("   ", line)
    sys.exit(1)
print(f"OK: {len(CHECKED)} source(s) import to a usable v001, imperfect ones "
      "with warnings, and a damaging edit is still detectable in development")
