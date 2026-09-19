#!/usr/bin/env python3
"""No build ships music inside the app.

The owner's copyright posture for the 0.7 line, in his words: *"ship with NO
scores bundled, and sharing is limited to groups of UNDER 12 people. That's the
whole posture -- private small-group sharing, no distribution of copyrighted
content, no bundled library."*

**This check exists because a comment claiming the opposite was already there
and was believed.** The `Bake UI-test fixtures` build phase said "NOT a shipped
feature: a fresh install starts with an empty library", which was true about the
LIBRARY and false about the BUNDLE: the fixtures were only ever seeded under
`-seedTestLibrary`, but the copy itself ran in every configuration. Verified in
the shipped artifact -- 0.6.20 build 180 carried all four fixture files, 788 KB,
including a 666 KB PDF of a Hubert Giraud composition arranged by Gheorghe
Branici, on TestFlight.

So prose is not the guard. Two things are checked here, and the first is the
one that matters:

  1. Any archive found on disk contains no score file anywhere inside its .app.
  2. The build phase that copies the fixtures is gated on the configuration,
     so a fresh archive cannot reintroduce them.

Checking the ARCHIVE rather than only the script is deliberate: the script is
what should be right, and the artifact is what actually ships.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PROJECT = ROOT / "ios" / "project.yml"

# What counts as music: the formats this app IMPORTS, which is exactly the set
# it must not redistribute.
#
# `.xml` is deliberately NOT in here, and the first version of this check had
# it. Verovio ships the Bravura music font as several thousand per-glyph `.xml`
# files -- `data/Bravura/E050.xml` is the treble clef -- so `.xml` flagged 20 KB
# of glyph outlines as copyrighted repertoire and buried the four files that
# actually mattered. A notation FONT is not a piece of music, and a check that
# cries wolf on its own dependencies is a check that gets switched off.
SCORE_SUFFIXES = {".mxl", ".musicxml", ".mid", ".midi", ".abc", ".pdf"}

# Bundled resources that are NOT music and legitimately ship. The sound bank is
# an instrument, not a piece; PrivacyInfo and plists are metadata.
ALLOWED_NAMES = {"PrivacyInfo.xcprivacy"}

# The starter library, and the ONLY music this app may ship. Read out of
# starter/PROVENANCE.md rather than restated here, so the list and the reason
# each entry is allowed cannot drift apart -- the whole failure mode of build
# 180 was a claim in one place and the truth in another.
STARTER_DIR = "starter-library"
PROVENANCE = ROOT / "starter" / "PROVENANCE.md"

FAILURES: list[str] = []


def approved_starter_files() -> set[str]:
    """Filenames listed in the per-file record of starter/PROVENANCE.md.

    A row counts only when it names a file AND a licence: a piece somebody
    added to the table without recording what licence its engraving carries is
    exactly the case this is meant to catch, so an empty licence cell fails the
    file rather than approving it.
    """
    if not PROVENANCE.exists():
        return set()
    approved: set[str] = set()
    for line in PROVENANCE.read_text().splitlines():
        if not line.startswith("|"):
            continue
        cells = [c.strip() for c in line.strip("|").split("|")]
        if len(cells) < 4:
            continue
        name, source, licence = cells[0], cells[1], cells[2]
        if name in ("file", "") or name.startswith("_") or name.startswith("-"):
            continue
        if not licence or not source:
            continue        # named but unaccounted for
        approved.add(name)
    return approved


def _is_approved_starter(path, app) -> bool:
    """Inside the starter directory AND named in the provenance table."""
    relative = path.relative_to(app)
    return (relative.parts[0] == STARTER_DIR
            and path.name in approved_starter_files())


def check(ok: bool, label: str) -> None:
    print(f"    {'ok  ' if ok else 'FAIL'} {label}")
    if not ok:
        FAILURES.append(label)


def no_archive_carries_music() -> None:
    """The archive THIS checkout would ship, not every archive on the disk.

    The first version globbed `*.xcarchive` from the repo root, which reaches
    into sibling git worktrees and finds their old build output. It went red on
    0.6.20 build 180's archive -- a correct answer about a build that has
    already shipped, and a useless one to a person running the gate on a
    different branch, who cannot fix it and will learn to ignore the check.
    A gate that is permanently red is off.

    One path: the one `deploy_testflight.sh` archives to. Absent is not a
    failure -- it means nothing has been built here yet, and the script-side
    assertions below still run.
    """
    print("\nthe archive this checkout would ship carries no score")
    archives = [p for p in [ROOT / "ios" / "build" / "Scoranger.xcarchive"]
                if p.exists()]
    # An explicit path wins, so the deploy can point at the archive it just made.
    if len(sys.argv) > 1:
        archives = [Path(sys.argv[1])]
        if not archives[0].exists():
            print(f"    FAIL no archive at {archives[0]}")
            FAILURES.append(f"no archive at {archives[0]}")
            return
    if not archives:
        print("    --   nothing archived in this checkout "
              "(ios/build/Scoranger.xcarchive absent)")
        return
    for archive in archives:
        apps = list((archive / "Products").rglob("*.app"))
        for app in apps:
            music = [
                p for p in app.rglob("*")
                if p.is_file()
                and p.suffix.lower() in SCORE_SUFFIXES
                and p.name not in ALLOWED_NAMES
            ]
            where = f"{archive.name}/{app.name}"

            # THE APP'S OWN REPERTOIRE. Anything outside app_packages is
            # something this project put there -- and since the starter
            # library, "put there" is no longer automatically wrong. What is
            # wrong is putting it there without provenance.
            ours = sorted(str(p.relative_to(app)) for p in music
                          if "app_packages" not in p.parts
                          and not _is_approved_starter(p, app))
            # Named separately because it is the one that actually happened, and
            # because "samples-seed exists" is a sentence somebody can act on
            # where a list of paths is something to squint at.
            check(not (app / "samples-seed").exists(),
                  f"{where} has no samples-seed directory")
            shown = ours[:8] + ([f"... and {len(ours) - 8} more"] if len(ours) > 8 else [])
            check(not ours, f"{where} ships no score of its own; found: {shown}")

            # A DEPENDENCY'S TEST FIXTURES -- reported, not failed, and the
            # distinction is the point. music21 vendors 274 KB of its own
            # synthetic test files (`midi/testPrimitive`, `mei/test`,
            # `musicxml/lilypondTestSuite`) under a BSD licence; its actual
            # score corpus is already stripped by the vendoring. That is bundle
            # hygiene worth trimming, not repertoire being redistributed, and
            # failing on it would put this check in permanent red over
            # something nobody chose and nobody is harmed by -- which is how a
            # check stops being read.
            theirs = sorted(p for p in music if "app_packages" in p.parts)
            if theirs:
                size = sum(p.stat().st_size for p in theirs) / 1024
                roots = sorted({
                    str(p.relative_to(app / "app_packages")).split("/")[0]
                    for p in theirs
                })
                print(f"    --   {where}: {len(theirs)} dependency test "
                      f"fixture(s), {size:.0f} KB, under {', '.join(roots)} "
                      f"-- trimmable, not repertoire")


def the_fixture_phase_is_gated_on_the_configuration() -> None:
    print("\nthe build phase cannot bundle fixtures into a release")
    text = PROJECT.read_text()
    phase = re.search(r"- name: Bake UI-test fixtures\n(.*?)\n        basedOnDependencyAnalysis",
                      text, re.S)
    check(phase is not None, "the 'Bake UI-test fixtures' phase is in project.yml")
    if phase is None:
        return
    body = phase.group(1)
    check("samples-seed" in body, "the phase is the one that copies samples-seed")
    # A configuration guard, and specifically one that admits only Debug.
    check('"$CONFIGURATION" != "Debug"' in body or '"$CONFIGURATION" = "Debug"' in body,
          "the copy is gated on $CONFIGURATION, so a Release build copies nothing")
    check("rm -rf" in body and "samples-seed" in body,
          "a non-Debug build actively REMOVES any samples-seed left by an "
          "earlier incremental build, rather than merely not adding one")


def main() -> int:
    no_archive_carries_music()
    the_fixture_phase_is_gated_on_the_configuration()
    print()
    if FAILURES:
        print(f"{len(FAILURES)} FAILED")
        for f in FAILURES:
            print(f"  - {f}")
        return 1
    print("OK: the only music this app ships is the starter library, "
          "and every file of it has its provenance written down")
    return 0


if __name__ == "__main__":
    sys.exit(main())
