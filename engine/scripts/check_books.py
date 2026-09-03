"""Regression check for BOOKS: a collection you take arrangements out of.

A book is not a piece. Ali's Newzik export contained a whole fake book -- one
52MB PDF holding hundreds of tunes -- and importing it as an "arrangement"
would have put hundreds of pieces under one title. So a book is its own thing:
it is read, and pieces are taken OUT of it.

  a PIECE is a composition          -> holds arrangements
  a BOOK is a collection of them    -> arrangements are EXTRACTED from it

Extraction is the whole point. Picking pages 42-44 of a fake book and filing
them as an arrangement of "Misty" is what makes a book useful rather than a
2000-page scroll. The extracted arrangement is an ordinary PDF arrangement --
it reads, it takes markup, and OMR can make it editable -- so everything that
already works for a scan works for it.

Import Book was broken end to end on device and nowhere else. `create_book`
and `extract_from_book` both `import pypdf`, and pypdf was not among the
packages ios/scripts/vendor_engine.sh vendors into the app -- so on an iPad
every book op raised ModuleNotFoundError inside the engine, into a `lastError`
the library never displayed. The host had pypdf, so every check here passed.

That is why the last section runs the two book ops through the app's own
bridge on the DEVICE's sys.path: the embedded interpreter is isolated and sees
only the stdlib, PythonApp/app and PythonApp/app_packages (PythonBridge.c), so
a dependency that is merely installed on this Mac does not count as shipped.

Fixtures are synthetic: the repository is public, so no committed fixture may
carry copyrighted music.

Run: engine/.venv/bin/python engine/scripts/check_books.py
"""

import json
import os
import subprocess
import sys
import tempfile
import textwrap
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

FAILURES: list[str] = []


def check(condition: bool, message: str) -> None:
    if condition:
        print(f"  ok   {message}")
    else:
        print(f"  FAIL {message}")
        FAILURES.append(message)


def numbered_pdf(path: Path, pages: int) -> Path:
    """A PDF whose pages are distinguishable, so an extract can be checked."""
    from pypdf import PdfWriter

    writer = PdfWriter()
    for _ in range(pages):
        writer.add_blank_page(width=612, height=792)
    with open(path, "wb") as f:
        writer.write(f)
    return path


def page_count(path: Path) -> int:
    from pypdf import PdfReader

    return len(PdfReader(str(path)).pages)



ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / "ios" / "PythonApp" / "app"
APP_PACKAGES = ROOT / "ios" / "PythonApp" / "app_packages"

# What PythonBridge.c hands the embedded interpreter, and nothing else. The
# child rebuilds sys.path from the stdlib entries of whatever python runs it,
# then appends these two -- so this Mac's site-packages, which is where pypdf
# lives when it has not been vendored, is out of reach exactly as on device.
DEVICE_CHILD = """
import json, os, sys
sys.path = [p for p in sys.path
            if p and "site-packages" not in p and "dist-packages" not in p]
sys.path += [{app!r}, {packages!r}]
os.environ["SCORANGER_WORKSPACE"] = {workspace!r}
import bridge
out = []
for op, args in [("import-book", {{"path": {pdf!r}, "name": "The Real Book"}}),
                 ("book-extract", {{"book": "the-real-book", "from_page": 11,
                                    "to_page": 13, "name": "Misty"}})]:
    out.append(json.loads(bridge.handle(json.dumps({{"op": op, "args": args}}))))
print("RESULT" + json.dumps(out))
"""


def on_the_device_path(root: Path) -> list[tuple[str, bool, str]]:
    """Run import-book and book-extract the way the iPad runs them."""
    if not APP_PACKAGES.exists():
        return [("the app has vendored packages to run against", False,
                 f"{APP_PACKAGES} is missing -- run ios/scripts/vendor_engine.sh")]

    source = numbered_pdf(root / "device-book.pdf", 40)
    script = DEVICE_CHILD.format(app=str(APP), packages=str(APP_PACKAGES),
                                 workspace=str(root / "device-workspace"),
                                 pdf=str(source))
    proc = subprocess.run([sys.executable, "-I", "-c", textwrap.dedent(script)],
                          capture_output=True, text=True)
    line = next((l for l in proc.stdout.splitlines() if l.startswith("RESULT")), None)
    if line is None:
        return [("the app's bridge answered at all", False,
                 (proc.stderr or proc.stdout).strip()[-300:])]
    results = json.loads(line[len("RESULT"):])
    out = []
    for label, r in zip(("a book imports", "and an arrangement comes out of it"),
                        results):
        out.append((label, bool(r.get("ok")), str(r.get("error") or "")[:200]))
    return out


def main() -> int:
    root = Path(tempfile.mkdtemp())
    os.environ["SCORANGER_WORKSPACE"] = str(root / "workspace")

    from scoranger_engine import workspace


    source = numbered_pdf(root / "fake-book.pdf", 40)

    print("importing a book")
    slug, doc = workspace.create_book("The Real Book", source)
    check(doc["pages"] == 40, f"it knows how long it is: {doc.get('pages')}")
    check(workspace.book_path(slug).exists(), "the PDF is stored")
    check(workspace.book_path(slug).read_bytes() == source.read_bytes(),
          "byte for byte -- nothing re-encoded it")

    print("a book is not a piece and not an arrangement")
    manifest = workspace.rebuild_manifest()
    check(any(b["slug"] == slug for b in manifest.get("books") or []),
          "it is in the manifest under books")
    check(not any(s["slug"] == slug for s in manifest["scores"]),
          "and NOT among the arrangements -- that is the whole distinction")
    check(not any(p["slug"] == slug for p in manifest["pieces"]),
          "nor among the pieces")

    print("taking an arrangement out of it")
    score_slug, entry = workspace.extract_from_book(
        slug, from_page=11, to_page=13, name="Misty", piece="Misty")
    extracted = workspace.resolve_path(score_slug)
    check(page_count(extracted) == 3, f"three pages came out: {page_count(extracted)}")
    check(workspace.version_kind(score_slug) == "pdf",
          "and it is an ordinary PDF arrangement, so markup and OMR both work")
    manifest = workspace.rebuild_manifest()
    check(any(p["name"] == "Misty" and score_slug in p["arrangements"]
              for p in manifest["pieces"]),
          "filed under the piece it was named for")
    check(entry["id"] == "v001", "with its own first version")

    print("the book is unchanged by the extraction")
    check(page_count(workspace.book_path(slug)) == 40,
          "taking pages out copies them; it does not cut them out")

    print("bad page ranges are refused, not silently clamped")
    for bad, why in [((0, 3), "a page before the first"),
                     ((39, 45), "a page past the last"),
                     ((13, 11), "backwards")]:
        try:
            workspace.extract_from_book(slug, from_page=bad[0], to_page=bad[1],
                                        name="Nope", piece=None)
            check(False, f"{why} should have been refused")
        except ValueError as e:
            check("page" in str(e).lower(), f"{why} is refused: {e}")

    print("and the app can do all of it on the sys.path it actually ships with")
    for label, ok, detail in on_the_device_path(root):
        check(ok, f"{label}{': ' + detail if detail else ''}")

    print()
    if FAILURES:
        print(f"{len(FAILURES)} FAILED")
        for f in FAILURES:
            print(f"  - {f}")
        return 1
    print("OK: a book is read, and arrangements are taken out of it")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
