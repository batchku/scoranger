"""A piece carries its own composer, arranger and tags -- and a scan needs it to.

An arrangement imported as a PDF has NO notation. `set-metadata` writes into
MusicXML, so a scanned library could never be credited at all: 34 of the 44 PDFs
in the library this was built for had a title, and those titles said things like
"TEMP_PDF". The credit has to live on the piece.

Tags came with it. They are flat strings on the piece -- origin and tradition in
practice ("Serbia", "Bulgaria") -- deduplicated case-insensitively, order kept.

This also guards the migration that brings a Newzik library across, because the
file it reads ships INSIDE the app and nothing else would notice it rotting.

Run: engine/.venv/bin/python engine/scripts/check_piece_metadata.py
"""

import json
import os
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
# Deliberately NOT importing the vendored on-device copy: this checks the
# engine's behaviour, and reads bridge.py as TEXT for the boundary. Importing
# the vendored copy here would make the result depend on when vendor_engine.sh
# last ran, which is a different fact and has its own check.

FAILURES: list[str] = []


def check(label: str, ok: bool, detail: str = "") -> None:
    if ok:
        print(f"  ok   {label}")
    else:
        FAILURES.append(label)
        print(f"  FAIL {label}{': ' + detail if detail else ''}")


def main() -> int:
    os.environ["SCORANGER_WORKSPACE"] = tempfile.mkdtemp()
    from scoranger_engine import workspace

    p = workspace.create_piece("Pravo Horo")["slug"]

    d = workspace.set_piece_metadata(p, composer="Boris Karlov",
                                     tags=["Bulgaria", "bulgaria", "  Balkan  "])
    check("composer is written", d["composer"] == "Boris Karlov", str(d))
    check("tags are trimmed and deduplicated case-insensitively",
          d["tags"] == ["Bulgaria", "Balkan"], str(d["tags"]))

    d = workspace.set_piece_metadata(p, tags=["Serbia"])
    check("a tags-only edit leaves the composer alone",
          d["composer"] == "Boris Karlov" and d["tags"] == ["Serbia"], str(d))

    d = workspace.set_piece_metadata(p, arranger="transcript: Liviu Gigiu")
    check("an arranger is a separate credit from a composer",
          d["arranger"] == "transcript: Liviu Gigiu" and d["composer"] == "Boris Karlov")

    d = workspace.set_piece_metadata(p, composer="", tags=[])
    check("an empty value clears, rather than being ignored",
          not d["composer"] and d["tags"] == [], str(d))

    workspace.set_piece_metadata(p, tags=["Serbia", "Balkan"])
    check("all_tags reports what is in use", set(workspace.all_tags()) == {"Serbia", "Balkan"},
          str(workspace.all_tags()))

    m = json.loads((Path(os.environ["SCORANGER_WORKSPACE"]) / "manifest.json").read_text())
    piece = m["pieces"][0]
    check("the manifest carries composer, arranger and tags",
          "composer" in piece and "arranger" in piece and piece["tags"] == ["Serbia", "Balkan"],
          str(piece))

    # the bridge -- the app cannot call what the bridge does not answer
    bridge_src = (ROOT / "ios" / "PythonApp" / "app" / "bridge.py").read_text()
    check("the bridge answers set-piece-metadata", 'op == "set-piece-metadata"' in bridge_src)
    check("the bridge answers tags", 'op == "tags"' in bridge_src)

    # the migration file, which ships inside the app
    res = ROOT / "ios" / "Scoranger" / "Resources" / "newzik-metadata.json"
    check("the bundled metadata file is there", res.exists())
    if res.exists():
        rows = json.loads(res.read_text())["pieces"]
        check("it holds the whole library", len(rows) == 40, str(len(rows)))
        by = {r["match"]: r for r in rows}
        check("Nature Boy is credited to its writer, not its performer",
              by.get("Nature Boy (Real Book)", {}).get("composer") == "eden ahbez")
        check("a corrected title is carried as a rename",
              by.get("The Star of Country Down", {}).get("title")
              == "The Star of the County Down")
        check("an origin is a tag, not a composer",
              by.get("Bucimis", {}).get("composer") == ""
              and "Bulgaria" in by.get("Bucimis", {}).get("tags", []))
        check("every row has the fields the migration reads",
              all({"match", "composer", "arranger", "tags"} <= set(r) for r in rows))

    # the Swift side, which an engine test cannot see
    app = (ROOT / "ios" / "Scoranger" / "AppState.swift").read_text()
    check("the app applies the migration at startup",
          "applyBundledMetadataIfNeeded" in app)
    check("the app can set a piece's metadata by hand",
          "set-piece-metadata" in app)
    piece_screen = (ROOT / "ios" / "Scoranger" / "Navigation" / "PieceScreen.swift").read_text()
    for field in ("piece-composer", "piece-arranger", "piece-tags"):
        check(f"{field} is editable in the app", field in piece_screen)

    if FAILURES:
        print(f"\n{len(FAILURES)} failed")
        return 1
    print("\npiece metadata: all good")
    return 0


if __name__ == "__main__":
    sys.exit(main())
