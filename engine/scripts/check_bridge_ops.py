"""Every op the app sends must be one the bridge knows.

This check exists because the same failure has now happened twice, and both
times it was invisible to every other test:

  - `adjust-element` was written, unit-checked and green in the ENGINE while
    the vendored on-device `ops.py` had no such function. The feature simply
    was not there on device.
  - `delete-piece` was called by the app against a shipped `bridge.py` that had
    no such op. The call raised "unknown op", the error went into `lastError`,
    and deleting an orphaned piece silently did nothing -- which is exactly
    what Ali reported.

Engine-level tests cannot see this: they call Python functions directly and
never cross the boundary the app crosses. The gap is between the Swift caller
and `bridge.py`, so that is what this reads.

It compares two literal sets:

  - every `op: "..."` the Swift app sends
  - every `op == "..."` the bridge answers

and fails when the app can ask for something the bridge cannot do. The reverse
(a bridge op nothing calls) is reported but NOT failed: ops exist for the CLI
and for chat too, and an unused one is untidy rather than broken.

Run: engine/.venv/bin/python engine/scripts/check_bridge_ops.py
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BRIDGE = ROOT / "ios" / "PythonApp" / "app" / "bridge.py"
SWIFT = ROOT / "ios" / "Scoranger"

FAILURES: list[str] = []


def check(label: str, ok: bool, detail: str = "") -> None:
    if ok:
        print(f"  ok   {label}")
    else:
        FAILURES.append(f"{label}{': ' + detail if detail else ''}")
        print(f"  FAIL {label}{': ' + detail if detail else ''}")


def bridge_ops() -> set[str]:
    """Every op name the bridge dispatches on."""
    text = BRIDGE.read_text(encoding="utf-8")
    return set(re.findall(r'op == "([a-z0-9-]+)"', text))


def swift_ops() -> dict[str, list[str]]:
    """Every op literal the app sends, with where it is sent from."""
    found: dict[str, list[str]] = {}
    for path in sorted(SWIFT.rglob("*.swift")):
        text = path.read_text(encoding="utf-8", errors="ignore")
        for line_no, line in enumerate(text.splitlines(), 1):
            for name in re.findall(r'op:\s*"([a-z0-9-]+)"', line):
                found.setdefault(name, []).append(
                    f"{path.relative_to(ROOT)}:{line_no}")
    return found


def main() -> int:
    print("reading both sides of the boundary")
    known = bridge_ops()
    sent = swift_ops()
    check("the bridge dispatches on some ops", len(known) > 10, str(len(known)))
    check("the app sends some ops", len(sent) > 10, str(len(sent)))
    print(f"       bridge knows {len(known)}, app sends {len(sent)}")

    print("\nevery op the app sends is answered by the bridge")
    missing = {name: where for name, where in sent.items() if name not in known}
    for name, where in sorted(missing.items()):
        check(f"'{name}' is a real op", False, f"sent from {where[0]}")
    if not missing:
        check("no op reaches a bridge that cannot answer it", True)

    # The ops this bug was about, named explicitly so a future edit that drops
    # one fails with the reason rather than a bare set difference.
    print("\nthe ops the orphaned-piece bug turned on")
    for name in ("delete-piece", "tidy-pieces", "create-piece", "assign-piece"):
        check(f"the bridge answers '{name}'", name in known,
              "an orphaned piece cannot be removed without it")

    print("\nops the bridge answers that nothing in the app calls")
    # Not a failure: the CLI and the chat tool list reach the engine by other
    # routes, so a bridge op with no Swift caller is untidy, not broken.
    unused = sorted(known - set(sent))
    print(f"       {len(unused)}: {', '.join(unused) if unused else 'none'}")

    print()
    if FAILURES:
        print(f"FAILED: {len(FAILURES)}")
        for f in FAILURES:
            print(f"  - {f}")
        return 1
    print("OK: every op the app sends is one the bridge knows -- the gap that "
          "made delete-piece a no-op on device, and adjust-element absent, "
          "cannot reopen silently")
    return 0


if __name__ == "__main__":
    sys.exit(main())
