"""Import Folder must not depend on Python being able to walk the folder.

The bug this pins, reported from a real library:

  Import Folder on a library in iCloud Drive did nothing. The picker closed and
  the library came back, no preview and no message. Import FILE on a PDF in the
  very same folder worked -- so access was fine. What failed was ENUMERATION: a
  directory vended by the iCloud file provider yields NOTHING to `os.walk`,
  although opening a file inside it succeeds. The empty walk produced an empty
  plan, the empty plan returned false, and the caller navigated nowhere.

The fix moves the LISTING to Swift (`FolderScan`), which enumerates through
FileManager inside the security scope the picker granted, and hands the engine
relative paths. The engine is given the names; it is no longer asked to find
them.

Three things must hold, and the third is the one that rots quietly:

  1. a listing is honoured even when the folder cannot be walked at all
  2. no listing still walks, so the CLI and desktop keep working
  3. the SWIFT side still sends one -- an engine-level test cannot see this,
     which is the same blind spot check_bridge_ops.py exists for

Run: engine/.venv/bin/python engine/scripts/check_folder_listing.py
"""

import json
import os
import re
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "ios" / "PythonApp" / "app"))

FAILURES: list[str] = []


def check(label: str, ok: bool, detail: str = "") -> None:
    if ok:
        print(f"  ok   {label}")
    else:
        FAILURES.append(f"{label}{': ' + detail if detail else ''}")
        print(f"  FAIL {label}{': ' + detail if detail else ''}")


def library(root: Path) -> list[str]:
    """A folder-per-piece export, the shape Newzik writes."""
    for piece, files in {
        "Balkan Ornaments": ["Balkan Ornaments.pdf"],
        "Jovano Jovanke": ["3. Jovano Jovanke (G).pdf", "lead.musicxml"],
        "Kaitarma": ["Kaitarma.pdf"],
    }.items():
        (root / piece).mkdir(parents=True, exist_ok=True)
        for f in files:
            (root / piece / f).write_bytes(b"%PDF-1.4\n")
    return [os.path.relpath(os.path.join(d, f), root)
            for d, _, fs in os.walk(root) for f in fs]


def counts(bridge, args: dict) -> dict:
    out = json.loads(bridge.handle(json.dumps({"op": "bulk-import", "args": args})))
    if not out.get("ok"):
        raise AssertionError(f"bridge refused: {out}")
    return out["result"]["plan"]["counts"]


def main() -> int:
    os.environ["SCORANGER_WORKSPACE"] = tempfile.mkdtemp()
    import bridge

    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp) / "Library"
        root.mkdir()
        listing = library(root)

        # 1. the device case: the folder cannot be enumerated, but we know the names
        c = counts(bridge, {"folder": "/nowhere/file-provider", "files": listing,
                            "commit": False})
        check("a listing plans a folder that cannot be walked",
              c["pieces"] == 3 and c["arrangements"] == 4, str(c))

        # 2. no listing: the walk still does the work (CLI, desktop, chat)
        c = counts(bridge, {"folder": str(root), "commit": False})
        check("no listing still walks the folder",
              c["pieces"] == 3 and c["arrangements"] == 4, str(c))

        # 3. an unwalkable folder WITHOUT a listing is still empty -- proving the
        #    check above is testing the listing and not something else
        c = counts(bridge, {"folder": "/nowhere/file-provider", "commit": False})
        check("an unwalkable folder with no listing finds nothing",
              c["pieces"] == 0, str(c))

        # 4. dotfiles stay out however they arrive
        c = counts(bridge, {"folder": str(root),
                            "files": listing + [".DS_Store", "Kaitarma/.hidden.pdf"],
                            "commit": False})
        check("dotfiles in a listing are dropped",
              c["pieces"] == 3 and c["arrangements"] == 4, str(c))

    # 5. the Swift boundary: the app must still LIST and still SEND
    app = (ROOT / "ios" / "Scoranger" / "AppState.swift").read_text()
    engine_swift = (ROOT / "ios" / "Scoranger" / "LocalEngine.swift").read_text()
    scan = ROOT / "ios" / "Scoranger" / "ScoreModel" / "FolderScan.swift"

    check("FolderScan exists", scan.exists())
    check("the preview lists the folder in Swift",
          "FolderScan.relativePaths(in: url)" in app)
    check("the commit lists it too -- writing must see what the preview saw",
          "FolderScan.relativePaths(in: plan.folder)" in app)
    check("bulkImport forwards the listing to the bridge",
          re.search(r'args\["files"\]\s*=\s*files', engine_swift) is not None)
    check("the bridge reads it",
          'a.get("files")' in (ROOT / "ios" / "PythonApp" / "app" / "bridge.py").read_text())

    # 6. an empty listing must SAY so. The silence is what cost the reader the
    #    time, not the enumeration.
    check("an empty folder produces a notice, not silence",
          re.search(r"files\.isEmpty[\s\S]{0,200}notice\s*=", app) is not None)

    # 7. and the notice must be SHOWN. `notice` was assigned in five places and
    #    read in none: declared, written, rendered nowhere. Every message the
    #    app tried to give -- a PDF that would not transcribe, a missing OMR
    #    service -- went nowhere. Assignment is not delivery.
    views = "\n".join(p.read_text() for p in
                      (ROOT / "ios" / "Scoranger").rglob("*.swift")
                      if p.name != "AppState.swift")
    check("some view renders state.notice", "state.notice" in views)
    check("a NoticeBar exists to render it", "struct NoticeBar" in views)

    if FAILURES:
        print(f"\n{len(FAILURES)} failed")
        return 1
    print("\nfolder listing: all good")
    return 0


if __name__ == "__main__":
    sys.exit(main())
