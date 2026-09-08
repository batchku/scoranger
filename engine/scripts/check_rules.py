#!/usr/bin/env python3
"""Release gate: the security rules are the enforcement, so they are tested.

design/FIREBASE.md §4.2, §4.3, §6.2, §8.2. Everything
`ios/Scoranger/ScoreModel/SetlistPermission.swift` says about who may do what
is the CLIENT's opinion, and a modified client ignores all of it. The rules in
`firebase/` are the copy that binds, and an untested rule file is worse than
none: it looks like enforcement.

This is a wrapper, not the tests. The 44 assertions live in
`firebase/rules.test.mjs` and run against the Firestore, Storage and Auth
emulators -- a real rules engine, on this machine, touching no live project.
They cover the whole model: a stranger cannot see a setlist exists, a member
cannot delete one, no client can write the membership map, an unaccepted
invitation carries no content, nobody writes anybody else's ink, and no storage
path outside the two named ones is readable at all.

Confirmed to bite: letting a member delete a setlist fails 9 of them, letting
the client rewrite the membership map fails 3, making shared files
world-readable fails 2.

SKIPPED, LOUDLY, when the toolchain is absent -- and a skip is reported as a
skip and not as a pass, because a check that quietly disables itself is the
failure mode this suite exists to avoid. It needs `npm install` in `firebase/`
and a JRE (the Firestore emulator is a Java program). On this machine:
`brew install openjdk`.

Run: engine/.venv/bin/python engine/scripts/check_rules.py
"""
import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FIREBASE = ROOT / "firebase"

# Homebrew's openjdk is keg-only, so `java` is not on PATH by default. Looked
# for where brew puts it before giving up, rather than telling somebody with a
# working JRE that they have not got one.
JAVA_CANDIDATES = [
    Path("/opt/homebrew/opt/openjdk/bin"),
    Path("/usr/local/opt/openjdk/bin"),
]


def java_works(binary: Path | str) -> bool:
    """Whether this java actually RUNS.

    Existence is not enough, and `shutil.which` is not enough either: macOS
    ships /usr/bin/java as a stub that exists, is executable, and answers
    `-version` with "Unable to locate a Java Runtime" and exit 1. Trusting
    `which` made this check report a hard failure on a machine with a perfectly
    good Homebrew JDK installed.
    """
    try:
        return subprocess.run([str(binary), "-version"],
                              capture_output=True, timeout=30).returncode == 0
    except (OSError, subprocess.SubprocessError):
        return False


def java_on_path() -> str | None:
    current = os.environ.get("PATH", "")
    # Homebrew's openjdk is keg-only and off PATH, so the working one is
    # usually the one NOT found by `which`. Candidates first, deliberately.
    for candidate in JAVA_CANDIDATES:
        if java_works(candidate / "java"):
            return f"{candidate}:{current}"
    if java_works("java"):
        return current
    return None


def main() -> int:
    if not (FIREBASE / "rules.test.mjs").exists():
        print("  SKIP no firebase/rules.test.mjs")
        return 0
    if not (FIREBASE / "node_modules").exists():
        print("  SKIP the rules toolchain is not installed")
        print("       run: cd firebase && npm install")
        return 0
    path = java_on_path()
    if path is None:
        print("  SKIP no JRE, and the Firestore emulator is a Java program")
        print("       run: brew install openjdk")
        return 0

    env = dict(os.environ, PATH=path)
    result = subprocess.run(
        ["npx", "firebase", "emulators:exec",
         "--only", "firestore,storage,auth",
         "--project", "scoranger-rules-test",
         "node rules.test.mjs"],
        cwd=FIREBASE, env=env, capture_output=True, text=True)

    # The emulator is chatty and most of it is lsof noise on macOS. What
    # matters is the assertion lines and the tally.
    for line in (result.stdout + result.stderr).splitlines():
        stripped = line.strip()
        if stripped.startswith(("ok ", "FAIL")) or stripped.startswith("rules:"):
            print(f"    {stripped}")
        elif "EvaluationException" in line or "undefined on object" in line:
            # A rule that denies by THROWING is right by accident. It was, once
            # (storage.rules indexing the members map with a missing key), and
            # the tests passed anyway -- so this is an error here, not noise.
            print(f"  FAIL a rule raised instead of deciding: {stripped[:120]}")
            return 1

    if result.returncode != 0:
        print(f"\n  FAIL the rules tests failed (exit {result.returncode})")
        tail = (result.stderr or result.stdout).strip().splitlines()[-6:]
        for line in tail:
            print(f"       {line[:160]}")
        return 1
    print("\nsecurity rules: the model is enforced where it counts")
    return 0


if __name__ == "__main__":
    sys.exit(main())
