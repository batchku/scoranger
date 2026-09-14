"""The bridge's import ops return what the app reads, for notation AND a scan.

This is the contract `ios/Scoranger/Account/SharedEntryImport.swift` depends
on, held on the Python side so the two cannot drift apart unnoticed. It exists
because they did, and nothing said so until a person joined a set list:

  - `import` returns `{"score": "<slug>", ...}` with the slug as a STRING. The
    app read it as a dictionary with a `slug` inside, found nothing, and
    reported five successful imports as "could not be prepared for sharing".
  - `import` parses notation with music21 and cannot take a PDF at all
    ("ConverterFileException: cannot find format from file extensions").
    `import-pdf` exists for that and returns the same shape. The app sent the
    PDF to `import`.

Both are asserted here against the REAL bridge (`ios/PythonApp/app/bridge.py`,
which is the file on device, not a copy), on a real MusicXML file and a real
PDF rendered from a fixture. The third assertion pins the reason the split
exists: `import` on a PDF must fail, so the split is not "fixed" by routing
everything through one op.

Run: engine/.venv/bin/python engine/scripts/check_bridge_import.py
"""

import json
import os
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "engine"))
sys.path.insert(0, str(ROOT / "engine" / "scripts"))

FAILURES: list[str] = []


def check(cond: bool, what: str) -> None:
    print(f"  {'ok  ' if cond else 'FAIL'} {what}")
    if not cond:
        FAILURES.append(what)


def main() -> int:
    scratch = Path(tempfile.mkdtemp(prefix="bridge-import-"))
    os.environ["SCORANGER_WORKSPACE"] = str(scratch / "ws")
    (scratch / "ws").mkdir()

    # The bridge the app ships, imported as the app would find it.
    sys.path.insert(0, str(ROOT / "ios" / "PythonApp" / "app"))
    import bridge  # noqa: E402
    import fixtures  # noqa: E402
    from scoranger_engine import render  # noqa: E402

    def call(op: str, args: dict) -> dict:
        return json.loads(bridge.handle(json.dumps({"op": op, "args": args})))

    # A real MusicXML file and a real PDF, both from the same fixture.
    xml = scratch / "jig.musicxml"
    fixtures.jig(bars=8).write("musicxml", fp=str(xml))
    pdf = scratch / "jig.pdf"
    render.render_pdf(str(xml), str(pdf))
    check(pdf.exists() and pdf.read_bytes()[:4] == b"%PDF", "a PDF was rendered to import")

    print("\nimport, on notation")
    r = call("import", {"path": str(xml), "name": "Jig from a set list"})
    check(r.get("ok") is True, f"import succeeds: {r.get('error', '')[:80]}")
    result = r.get("result") or {}
    check(isinstance(result.get("score"), str) and result["score"],
          f"result['score'] is the slug as a STRING: {result.get('score')!r}")
    check("slug" not in result and not isinstance(result.get("score"), dict),
          "there is no dictionary form -- the app's old reading has nothing to find")

    print("\nimport-pdf, on a scan")
    r = call("import-pdf", {"path": str(pdf), "name": "Jig, scanned"})
    check(r.get("ok") is True, f"import-pdf succeeds: {r.get('error', '')[:80]}")
    result = r.get("result") or {}
    check(isinstance(result.get("score"), str) and result["score"],
          f"result['score'] is the slug as a STRING here too: {result.get('score')!r}")
    check(result.get("kind") == "pdf", "and it says what kind it made")

    print("\nimport, on a scan -- must refuse, which is why the split exists")
    r = call("import", {"path": str(pdf), "name": "Jig, misrouted"})
    check(r.get("ok") is False, "import on a PDF fails rather than making something")
    check("ConverterFileException" in (r.get("error") or ""),
          f"and says why: {(r.get('error') or '')[:70]}")

    if FAILURES:
        print(f"\nFAIL: {len(FAILURES)} bridge import check(s) failed")
        for f in FAILURES:
            print("   ", f)
        return 1
    print("\nOK: the bridge's import ops return a string slug for notation and for a scan, "
          "and notation import refuses a scan")
    return 0


if __name__ == "__main__":
    sys.exit(main())
