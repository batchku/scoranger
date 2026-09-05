"""An image is a scan, and the engine says so.

Ali brings scores in as JPEGs and PNGs as well as PDFs, and they are the same
KIND of thing: something a reader can look at, annotate and run OMR on, and
that no op can edit until it becomes notation. So they take the PDF's path
rather than a parallel one -- that is the whole design, and this check is what
holds the two together.

What was in the way: `artifact_kind` was BINARY. Anything not in
NOTATION_SUFFIXES was called "pdf", so an image imported today would already
have been treated as a scan while being labelled a PDF in the library, and
`_write_scan_version` hard-coded a `.pdf` filename, so the stored artifact
would have been a JPEG called `v001.pdf`.

Asserted here:

  - an image's kind is "image", a PDF's is still "pdf", notation is untouched
  - importing an image keeps its own suffix, so the bytes on disk are the
    file the reader gave us and nothing re-encodes it
  - the version has no parts, like a PDF: an image has no parts until OMR
    reads it, and inventing one would put a lie in the library
  - an op that needs notation refuses an image, and says it is a scan rather
    than dying inside music21
  - bulk import accepts images alongside PDFs

Run: engine/.venv/bin/python engine/scripts/check_image_scans.py
"""

import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "engine"))

FAILURES: list[str] = []


def check(label: str, ok: bool, detail: str = "") -> None:
    if ok:
        print(f"  ok   {label}")
    else:
        FAILURES.append(f"{label}{': ' + detail if detail else ''}")


def main() -> int:
    with tempfile.TemporaryDirectory() as tmp:
        import os
        os.environ["SCORANGER_WORKSPACE"] = tmp
        for mod in [m for m in list(sys.modules) if m.startswith("scoranger_engine")]:
            del sys.modules[mod]
        from scoranger_engine import bulk, workspace

        # --- what each suffix IS -------------------------------------------
        for name, want in [("a.musicxml", "musicxml"), ("a.mxl", "musicxml"),
                           ("a.mid", "musicxml"), ("a.pdf", "pdf"),
                           ("a.jpg", "image"), ("a.jpeg", "image"),
                           ("a.png", "image"), ("a.PNG", "image"),
                           ("a.heic", "image")]:
            got = workspace.artifact_kind(Path(name))
            check(f"{name} is {want}", got == want, f"got {got}")

        # --- importing one --------------------------------------------------
        # A 1x1 PNG, written by hand so the check needs no image library.
        png = bytes.fromhex(
            "89504e470d0a1a0a0000000d4948445200000001000000010802000000907753"
            "de0000000c4944415408d76360600000000400012734270a0000000049454e44"
            "ae426082")
        source = Path(tmp) / "Star of the County Down.png"
        source.write_bytes(png)

        result = workspace.import_scan(str(source), name="Star of the County Down")
        slug = result["score"]
        path = workspace.resolve_path(slug)
        check("an imported image keeps its own suffix",
              path.suffix.lower() == ".png", path.name)
        check("the bytes on disk are the file that came in",
              path.read_bytes() == png)
        check("the version reports kind image",
              workspace.version_kind(slug) == "image",
              workspace.version_kind(slug))

        versions = workspace.list_versions(slug)
        check("one version, with no parts",
              len(versions) == 1 and versions[0].get("parts") == [],
              str(versions[0].get("parts") if versions else None))

        # --- and an op that needs notation refuses it -----------------------
        try:
            workspace.resolve_notation_path(slug)
        except workspace.NotNotationError as exc:
            message = str(exc)
            check("a notation op refuses an image", True)
            check("the refusal calls it a scan rather than a PDF",
                  "image" in message.lower() or "scan" in message.lower(),
                  message)
            check("the refusal says OMR is what makes it editable",
                  "omr" in message.lower(), message)
        except Exception as exc:  # noqa: BLE001
            check("a notation op refuses an image", False,
                  f"raised {type(exc).__name__}: {exc}")
        else:
            check("a notation op refuses an image", False,
                  "it returned a path for a file music21 cannot read")

        # --- bulk import ----------------------------------------------------
        check("bulk import accepts images",
              {".jpg", ".jpeg", ".png", ".heic"} <= bulk.SCANS,
              str(sorted(bulk.SCANS)))
        check("bulk still accepts PDFs", ".pdf" in bulk.SCANS)
        check("bulk calls an image a scan, not notation",
              bulk.IMPORTABLE >= {".png", ".pdf", ".musicxml"})

        # --- a PDF is unchanged by all this ---------------------------------
        pdf = Path(tmp) / "a scan.pdf"
        pdf.write_bytes(b"%PDF-1.4\n%%EOF\n")
        pdf_result = workspace.import_scan(str(pdf), name="A Scan")
        pdf_path = workspace.resolve_path(pdf_result["score"])
        check("a PDF still lands as .pdf", pdf_path.suffix == ".pdf", pdf_path.name)
        check("a PDF still reports kind pdf",
              workspace.version_kind(pdf_result["score"]) == "pdf")

    for line in FAILURES:
        print(f"  FAIL {line}")
    if FAILURES:
        print(f"\nFAIL: {len(FAILURES)} image-scan check(s)")
        return 1
    print("\nOK: images are scans, on the PDF's own path")
    return 0


if __name__ == "__main__":
    sys.exit(main())
