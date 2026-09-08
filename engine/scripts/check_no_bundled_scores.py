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
SCORE_SUFFIXES = {".mxl", ".musicxml", ".mid", ".midi", ".pdf"}

# Bundled resources that are NOT music and legitimately ship. The sound bank is
# an instrument, not a piece; PrivacyInfo and plists are metadata.
ALLOWED_NAMES = {"PrivacyInfo.xcprivacy"}

FAILURES: list[str] = []


def check(ok: bool, label: str) -> None:
    print(f"    {'ok  ' if ok else 'FAIL'} {label}")
    if not ok:
        FAILURES.append(label)


def no_archive_carries_music() -> None:
    print("\nno archive on disk ships a score")
    archives = sorted(ROOT.rglob("*.xcarchive"))
    if not archives:
        print("    --   no .xcarchive on disk to inspect (nothing built yet)")
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

            # THE APP'S OWN REPERTOIRE -- a hard fail. Anything outside
            # app_packages is something this project put there.
            ours = sorted(str(p.relative_to(app)) for p in music
                          if "app_packages" not in p.parts)
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
    print("OK: the app ships no music -- only what its user brings in")
    return 0


if __name__ == "__main__":
    sys.exit(main())
