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

import ast
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
    #
    # Derived from bridge.py, not listed here. A hard-coded tuple is what let
    # ids.py go missing, and it would have let bundle.py go missing too: the
    # closure check below cannot see it, because bundle is reached only FROM
    # the bridge and nothing already vendored imports it.
    bridge_src = (ROOT / "ios" / "PythonApp" / "app" / "bridge.py").read_text()
    wanted: set[str] = set()
    for node in ast.walk(ast.parse(bridge_src)):
        if isinstance(node, ast.ImportFrom) and node.module == "scoranger_engine":
            wanted |= {alias.name for alias in node.names}
        elif isinstance(node, ast.ImportFrom) and (node.module or "").startswith(
                "scoranger_engine."):
            wanted.add(node.module.split(".")[1])
        elif isinstance(node, ast.Import):
            wanted |= {alias.name.split(".")[1] for alias in node.names
                       if alias.name.startswith("scoranger_engine.")}
    for mod in sorted(wanted):
        if (SOURCE / f"{mod}.py").exists() and not (VENDORED / f"{mod}.py").exists():
            missing.append(f"bridge.py uses {mod} and it is not vendored")

    # And the SECOND form of it, which the loop above cannot see: a vendored
    # module importing a sibling that was never copied.
    #
    # This is not hypothetical. Stage 0 added `ids.py` and `workspace.py` gained
    # `from . import ids` at module scope; the hand-kept list in
    # vendor_engine.sh did not gain it, and the app shipped an engine that
    # could not import at all. Every UI test failed with "the seeded library
    # never appeared", which is true and says nothing about why. The vendor
    # script now derives the closure instead of listing it, and this asserts
    # the closure is actually closed.
    #
    # Lazy imports count. `from . import ops` inside a function is how most of
    # workspace.py reaches the ops module, and a missing module fails there
    # just as hard, only later and inside whatever the user was doing.
    for v in sorted(VENDORED.glob("*.py")):
        for node in ast.walk(ast.parse(v.read_text())):
            if not (isinstance(node, ast.ImportFrom) and node.level == 1):
                continue
            wanted = ({alias.name for alias in node.names} if node.module is None
                      else {node.module.split(".")[0]})
            for mod in sorted(wanted):
                if not (SOURCE / f"{mod}.py").exists():
                    continue          # not a module of ours; a name from one
                if not (VENDORED / f"{mod}.py").exists():
                    missing.append(
                        f"{v.name} imports {mod} and it is not vendored "
                        f"(line {node.lineno})")

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
