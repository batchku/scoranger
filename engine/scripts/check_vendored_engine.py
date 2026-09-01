"""The engine that ships on device is the engine in this repo.

`ios/PythonApp/app/scoranger_engine` is a COPY, made by ios/scripts/vendor_engine.sh
and checked into nothing. Every edit to the real engine leaves it stale until
that script runs again, and a stale copy fails in a particular way: the feature
works in the CLI, the tests pass, and the app does nothing at all. It has now
happened three times -- `adjust-element` shipped against a vendored ops.py that
had no such function, and twice in one day while adding piece metadata.

Worse, five checks used to IMPORT that copy: they put app/ ahead of engine/ on
sys.path, so `import scoranger_engine` resolved to the snapshot. Breaking the
real source left them green. Their path order is fixed; this check covers the
other half, which is that the snapshot matches what it was copied from.

vendor_engine.sh deliberately leaves some modules behind -- the CLI, the chat
client, the renderer, the server -- so only the files it actually copies are
compared.

Run: engine/.venv/bin/python engine/scripts/check_vendored_engine.py
"""

import hashlib
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "engine" / "scoranger_engine"
VENDORED = ROOT / "ios" / "PythonApp" / "app" / "scoranger_engine"


def digest(p: Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()[:12]


def main() -> int:
    if not VENDORED.exists():
        print(f"  FAIL no vendored engine at {VENDORED}")
        print("\n  run: ios/scripts/vendor_engine.sh")
        return 1

    stale, missing = [], []
    for v in sorted(VENDORED.glob("*.py")):
        s = SOURCE / v.name
        if not s.exists():
            missing.append(f"{v.name} is vendored but no longer in the engine")
            continue
        if digest(s) != digest(v):
            stale.append(v.name)

    # A module the app's bridge imports but that was never copied is the
    # original form of this bug.
    bridge = (ROOT / "ios" / "PythonApp" / "app" / "bridge.py").read_text()
    for mod in ("workspace", "ops", "bulk", "db"):
        if f"from scoranger_engine import" in bridge or f"scoranger_engine.{mod}" in bridge:
            if not (VENDORED / f"{mod}.py").exists():
                missing.append(f"bridge.py uses {mod} and it is not vendored")

    for name in stale:
        print(f"  FAIL {name} differs from the engine it was copied from")
    for m in missing:
        print(f"  FAIL {m}")
    if not stale and not missing:
        n = len(list(VENDORED.glob('*.py')))
        print(f"  ok   all {n} vendored modules match the engine source")
        print("\nvendored engine: in step")
        return 0
    print(f"\n{len(stale) + len(missing)} stale or missing"
          "\n  run: ios/scripts/vendor_engine.sh")
    return 1


if __name__ == "__main__":
    sys.exit(main())
