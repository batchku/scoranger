#!/usr/bin/env python3
"""Sharing without the cloud: what goes out is what comes in.

design/FIREBASE.md §13, and principle 6 of §0 -- there must be a way to hand
somebody an arrangement or a setlist with no internet and no account. The whole
feature is one file over AirDrop, so the only question that matters is whether
the file is faithful, and the only honest way to ask it is to import into a
workspace that has never seen the material.

What is asserted, and every one of these was confirmed by breaking the code:

  1. An arrangement round-trips: the artifact bytes are IDENTICAL, not
     equivalent. A bundle carries bytes rather than re-serialising through
     music21, because the same music written twice is not the same file.
  2. A setlist round-trips with its running order.
  3. A reader's markup travels and re-attaches to the right page of the right
     version -- keyed by uid, which is the reason the re-key had to land first
     (§13.3): the receiving device's slug for the same music is its own.
  4. Books have no export path at all (§8.2 guard rail 3), and asking for one
     by name is an error rather than an empty bundle.
  5. Importing twice makes two arrangements, not one corrupted one, and says
     which is a duplicate of what.
  6. The default carries the version it opens at; --full-history carries the
     chain, and the chain's parent links survive being renumbered.
  7. Identity is minted fresh on the way in, with the bundle's uids kept only
     as provenance -- two devices must never both hold the same uid.
  8. Provenance is RECORDED, not enforced (§12.12): a chain of only import ops
     is "imported", anything with arrangement work in it is "arranged", and
     neither blocks the bundle.
  9. A damaged bundle is refused rather than half-imported.

Run: engine/.venv/bin/python engine/scripts/check_bundle.py
"""
import json
import os
import shutil
import sys
import tempfile
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(ROOT / "engine"))

FAILURES: list[str] = []


def check(condition, message):
    print(f"    {'ok  ' if condition else 'FAIL'} {message}")
    if not condition:
        FAILURES.append(message)
    return condition


def fresh_workspace() -> Path:
    """A workspace of its own, so the receiving side is genuinely a new device."""
    from scoranger_engine import workspace
    from scoranger_engine.db import SqliteRepository

    root = Path(tempfile.mkdtemp())
    os.environ["SCORANGER_WORKSPACE"] = str(root)
    workspace.WORKSPACE = root
    workspace.repository_factory = SqliteRepository
    workspace._reset_repo_for_testing()
    return root


def a_score(name: str, bars: int = 4) -> str:
    from scoranger_engine import workspace

    import fixtures

    slug, _ = workspace.create_score(name, fixtures.jig(bars=bars))
    return slug


def arrange(slug: str) -> None:
    """Put some of the sharer's own work on top of the import."""
    from music21 import converter

    from scoranger_engine import ops, workspace

    score = converter.parse(str(workspace.resolve_notation_path(slug)))
    ops.transpose(score, "M2")
    workspace.add_version(slug, score, "transpose", {"interval": "M2"})


def ink_for(root: Path, score_uid: str, version_id: str, pages: int) -> Path:
    d = root / "annotations"
    d.mkdir(parents=True, exist_ok=True)
    for page in range(pages):
        (d / f"{score_uid}_{version_id}_p{page}.pkdrawing").write_bytes(
            b"PKDRAWING-" + str(page).encode())
    return d


# -- 1, 3, 7. one arrangement, its bytes, its markup ------------------------

def an_arrangement_round_trips() -> None:
    print("\nan arrangement, with its markup, on a device that has never seen it")
    from scoranger_engine import bundle, ids, workspace

    root = fresh_workspace()
    slug = a_score("Morrison's Jig")
    arrange(slug)
    doc = workspace._repo().get_score(slug)
    uid, latest = doc["uid"], doc["latest"]
    sent_bytes = (workspace.score_dir(slug)
                  / workspace._repo().get_version(slug, latest)["file"]).read_bytes()
    ink = ink_for(root, uid, latest, pages=3)

    out = root / "out" / "morrisons.scorbundle"
    report = bundle.export(slug, out, ink_dir=ink)
    check(Path(report["path"]).exists(), "the bundle is written")
    check(report["arrangements"][0]["ink_pages"] == 3, "it carries 3 pages of markup")

    # a different device: new workspace, no shared state
    receiving = fresh_workspace()
    their_ink = receiving / "annotations"
    got = bundle.import_(out, ink_dir=their_ink)

    entry = got["imported"][0]
    check(len(got["imported"]) == 1, "one arrangement arrives")
    check(entry["duplicate_of"] is None, "and nothing here looks like it already")
    new = workspace._repo().get_score(entry["slug"])
    check(new is not None, f"it is in the library as '{entry['slug']}'")
    check(new["uid"] != uid, "with an identity of its own, not the sender's")
    check(ids.is_id(new["uid"]), "and a real id")
    check(new.get("origin_uid") == uid, "the sender's id is kept as provenance")

    version = workspace._repo().get_version(entry["slug"], new["latest"])
    landed = (workspace.score_dir(entry["slug"]) / version["file"]).read_bytes()
    check(landed == sent_bytes,
          f"the notation is byte-identical ({len(landed)} bytes), not merely equivalent")

    marks = sorted(p.name for p in their_ink.glob("*.pkdrawing"))
    check(len(marks) == 3, f"all 3 pages of markup arrived: {len(marks)}")
    expected = f"{new['uid']}_{new['latest']}_p1.pkdrawing"
    check(expected in marks,
          "and re-attached to the right page of the right version under the NEW uid")
    check((their_ink / expected).read_bytes() == b"PKDRAWING-1",
          "with the strokes intact")


# -- 2. a setlist ----------------------------------------------------------

def a_setlist_round_trips() -> None:
    print("\na setlist, in order")
    from scoranger_engine import bundle, workspace

    root = fresh_workspace()
    names = ["Morrison's Jig", "Banish Misfortune", "The Kesh"]
    for n in names:
        workspace.add_score_to_setlist("Friday", a_score(n), create_if_missing=True)

    out = root / "friday.scorbundle"
    report = bundle.export("Friday", out)
    check(report["kind"] == "setlist", "it exports as a setlist")
    check(len(report["arrangements"]) == 3, "with all three arrangements")

    fresh_workspace()
    got = bundle.import_(out)
    check(got["setlist"] == "Friday", "the setlist arrives by name")
    order = workspace.resolve_setlist("Friday")["scores"]
    titles = [workspace._repo().get_score(s)["title"] for s in order]
    check(titles == names, f"in the order it was sent: {titles}")


# -- 4. the guard rails ----------------------------------------------------

def books_and_sources_never_leave() -> None:
    print("\nbooks do not travel (§8.2 guard rail 3)")
    from scoranger_engine import bundle, workspace

    root = fresh_workspace()
    a_score("Morrison's Jig")
    pdf = root / "book.pdf"
    try:
        from pypdf import PdfWriter
        w = PdfWriter()
        for _ in range(3):
            w.add_blank_page(width=612, height=792)
        with pdf.open("wb") as fh:
            w.write(fh)
        book_slug, _ = workspace.create_book("A Fake Book", pdf)
    except Exception as exc:                                  # noqa: BLE001
        check(False, f"could not build a book fixture: {exc}")
        return

    try:
        bundle.export(book_slug, root / "nope.scorbundle")
        check(False, "exporting a book must be refused")
    except Exception as exc:                                  # noqa: BLE001
        # Deliberately broad. Without the guard the call still fails, but with
        # whatever error the setlist lookup happens to raise -- which is a crash
        # rather than a refusal, and says nothing about books. The guard has to
        # be the thing that stops it, and it has to say so.
        check(isinstance(exc, ValueError) and "never shared" in str(exc),
              f"exporting a book is refused BY THE GUARD, and says why: "
              f"{type(exc).__name__}: {exc}")

    check(not (root / "nope.scorbundle").exists(),
          "and no file is left behind")


# -- 5, 6, 8. duplicates, history, provenance ------------------------------

def importing_twice_makes_two() -> None:
    print("\nimporting the same bundle twice")
    from scoranger_engine import bundle, workspace

    root = fresh_workspace()
    slug = a_score("Morrison's Jig")
    out = root / "m.scorbundle"
    bundle.export(slug, out)

    fresh_workspace()
    first = bundle.import_(out)
    second = bundle.import_(out)
    check(first["imported"][0]["duplicate_of"] is None, "the first is not a duplicate")
    check(second["imported"][0]["duplicate_of"] == first["imported"][0]["slug"],
          "the second says which one it duplicates")
    check(second["imported"][0]["slug"] != first["imported"][0]["slug"],
          "and lands beside it rather than on top of it")
    check(len(workspace._repo().list_scores()) == 2,
          "two arrangements, not one corrupted one")


def history_is_opt_in() -> None:
    print("\nthe chart by default, the history when asked")
    from scoranger_engine import bundle, workspace

    root = fresh_workspace()
    slug = a_score("Morrison's Jig")
    arrange(slug)
    arrange(slug)
    check(len(workspace._repo().list_versions(slug)) == 3, "the sender has 3 versions")

    plain, full = root / "a.scorbundle", root / "b.scorbundle"
    bundle.export(slug, plain)
    bundle.export(slug, full, full_history=True)
    check(plain.stat().st_size < full.stat().st_size,
          f"the default is smaller ({plain.stat().st_size} < {full.stat().st_size})")

    fresh_workspace()
    got = bundle.import_(plain)
    check(got["imported"][0]["versions"] == 1, "the default brings the chart alone")

    fresh_workspace()
    got = bundle.import_(full)
    entry = got["imported"][0]
    check(entry["versions"] == 3, "--full-history brings the chain")
    versions = workspace._repo().list_versions(entry["slug"])
    ids_seen = {v["id"] for v in versions}
    parents = [v["parent"] for v in versions if v["parent"]]
    check(len(parents) == 2 and all(p in ids_seen for p in parents),
          "and every parent link points at a version that is actually here")


def provenance_is_recorded_not_enforced() -> None:
    print("\nwhose work this is, recorded and not enforced (§12.12)")
    from scoranger_engine import bundle, workspace

    root = fresh_workspace()
    untouched = a_score("Somebody Elses Tune")
    mine = a_score("Morrison's Jig")
    arrange(mine)

    out_a, out_b = root / "a.scorbundle", root / "b.scorbundle"
    ra = bundle.export(untouched, out_a)
    rb = bundle.export(mine, out_b)
    check(ra["arrangements"][0]["provenance"] == "imported",
          "a chain of only import ops is 'imported'")
    check(rb["arrangements"][0]["provenance"] == "arranged",
          "a chain with arrangement work in it is 'arranged'")
    check(out_a.exists() and out_a.stat().st_size > 0,
          "and the 'imported' one still shipped its bytes -- recorded, not blocked")

    seen = bundle.inspect(out_a)
    check(seen["arrangements"][0]["provenance"] == "imported",
          "bundle-inspect says so before anybody imports anything")


# -- 9. a damaged bundle ---------------------------------------------------

def a_damaged_bundle_is_refused() -> None:
    print("\na damaged bundle")
    from scoranger_engine import bundle, workspace

    root = fresh_workspace()
    slug = a_score("Morrison's Jig")
    good = root / "good.scorbundle"
    bundle.export(slug, good)

    bad = root / "bad.scorbundle"
    with zipfile.ZipFile(good) as src, zipfile.ZipFile(bad, "w") as dst:
        for item in src.infolist():
            data = src.read(item.filename)
            if item.filename.endswith(".musicxml.gz"):
                import gzip
                data = gzip.compress(b"<score-partwise/>", 9)
            dst.writestr(item, data)

    fresh_workspace()
    try:
        bundle.import_(bad)
        check(False, "a damaged artifact must be refused")
    except ValueError as exc:
        check("checksum" in str(exc), f"refused, and says why: {exc}")

    not_a_bundle = root / "junk.scorbundle"
    with zipfile.ZipFile(not_a_bundle, "w") as z:
        z.writestr("hello.txt", "not a bundle")
    try:
        bundle.inspect(not_a_bundle)
        check(False, "a zip that is not a bundle must be refused")
    except ValueError as exc:
        check("not a Scoranger bundle" in str(exc), f"refused: {exc}")


def main() -> int:
    an_arrangement_round_trips()
    a_setlist_round_trips()
    books_and_sources_never_leave()
    importing_twice_makes_two()
    history_is_opt_in()
    provenance_is_recorded_not_enforced()
    a_damaged_bundle_is_refused()

    print()
    if FAILURES:
        print(f"{len(FAILURES)} FAILED")
        for f in FAILURES:
            print(f"  - {f}")
        return 1
    print("OK: a bundle is faithful, and it needs no account and no network")
    return 0


if __name__ == "__main__":
    sys.exit(main())
