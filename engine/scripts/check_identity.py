#!/usr/bin/env python3
"""A document's identity outlives its name, and needs no coordination to mint.

Both of the library's old identifiers were computed from something that moves.

  - A score's key was `slugify(title)`. Renaming an arrangement therefore had
    to rewrite the key AND hunt down every reference to it -- the artifact
    directory, the version and source rows, each piece's `order` -- which is
    what `rename_slug` does. One missed reference silently orphans a score.
  - A version's key was `v{count+1:03d}`, from counting the rows already there.
    Read, then write, with no transaction. Two devices arranging offline both
    count 30 versions, both allocate `v031`, and when they meet one of them has
    to lose work that a musician did.

So identity moved to `ids.new_id()` (design/FIREBASE.md §3) and `vNNN` became a
display label. This check is what says that landed without costing anyone a
library.

Three things have to hold:

  1. an EXISTING workspace migrates with every reference intact -- and without
     touching a single file on disk, because a migration that renames 44
     arrangements' artifacts is a migration that can half-rename them
  2. a rename changes the slug and NOTHING else: not the score's uid, not any
     version id, not the history
  3. two devices appending to the same parent both keep their work

Run: engine/.venv/bin/python engine/scripts/check_identity.py
"""
import os
import sys
import tempfile
import threading
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

FAILURES: list[str] = []


def check(condition, message):
    print(f"    {'ok  ' if condition else 'FAIL'} {message}")
    if not condition:
        FAILURES.append(message)
    return condition


def build_pre_migration_workspace(root: Path) -> dict:
    """A workspace exactly as builds up to 0.5.1 wrote it.

    Written through the repository directly rather than through `workspace`,
    because `workspace` is the thing that now migrates: asking it to produce
    old documents would be asking the fix to reproduce the bug.
    """
    from music21 import converter
    from scoranger_engine.db import SqliteRepository

    import fixtures

    repo = SqliteRepository(root / "scoranger.db")
    slug = "morrisons-jig"
    (root / slug / "sources").mkdir(parents=True, exist_ok=True)

    # three versions, each a real artifact named the old way, chained by parent
    labels = ["v001", "v002", "v003"]
    for i, vid in enumerate(labels):
        score = fixtures.jig(bars=8)
        score.write("musicxml", fp=str(root / slug / f"{vid}.musicxml"))
        repo.add_version(slug, vid, i + 1, {
            "id": vid, "seq": i + 1, "file": f"{vid}.musicxml",
            "op": "import" if i == 0 else "transpose",
            "args": {} if i == 0 else {"interval": "M2"},
            "parent": labels[i - 1] if i else None,
            "time": "2026-08-01T10:0%d:00+00:00" % i,
            "parts": [{"index": 0, "name": "Pennywhistle"}],
        })
    repo.set_score(slug, {
        "id": slug, "slug": slug, "name": "Morrison's Jig",
        "title": "Morrison's Jig", "composer": None, "arranger": None,
        "created": "2026-08-01T10:00:00+00:00", "latest": "v003",
        "piece": "morrisons",
    })

    src = fixtures.jig(bars=4)
    src.write("musicxml", fp=str(root / slug / "sources" / "s01.musicxml"))
    repo.add_source(slug, "s01", {
        "id": "s01", "name": "MuseScore tab version", "origin": "import",
        "file": "sources/s01.musicxml", "time": "2026-08-01T11:00:00+00:00",
        "parts": [{"index": 0, "name": "Pennywhistle"}]})

    repo.set_piece("morrisons", {
        "id": "morrisons", "slug": "morrisons", "name": "Morrison's",
        "order": [slug], "created": "2026-08-01T09:00:00+00:00"})
    repo.set_setlist("friday", {
        "id": "friday", "slug": "friday", "name": "Friday session",
        "scores": [slug], "created": "2026-08-01T09:00:00+00:00"})
    repo.set_book("real-book", {
        "id": "real-book", "slug": "real-book", "name": "The Real Book",
        "pages": 40, "created": "2026-08-01T09:00:00+00:00"})

    del converter  # imported only to prove music21 is available before we start
    return {"slug": slug, "labels": labels}


def main():
    root = Path(tempfile.mkdtemp(prefix="scoranger-identity-"))
    os.environ["SCORANGER_WORKSPACE"] = str(root)
    from scoranger_engine import ids, workspace
    workspace.WORKSPACE = root                    # type: ignore[attr-defined]
    workspace._reset_repo_for_testing()

    print("an existing library migrates, and nothing on disk moves")
    built = build_pre_migration_workspace(root)
    slug, labels = built["slug"], built["labels"]
    artifacts_before = sorted(p.name for p in (root / slug).glob("*.musicxml"))

    # first touch through `workspace` is what runs the migration
    versions = workspace.list_versions(slug)

    check(artifacts_before == sorted(p.name for p in (root / slug).glob("*.musicxml"))
          and artifacts_before == ["v001.musicxml", "v002.musicxml", "v003.musicxml"],
          f"every artifact keeps the name it had: {artifacts_before}")
    check(all(ids.is_id(v["id"]) for v in versions),
          "every version now has an opaque id")
    check([workspace.version_label(v) for v in versions] == labels,
          "and is still called what it was always called: "
          f"{[workspace.version_label(v) for v in versions]}")
    check(len({v['id'] for v in versions}) == 3, "the three ids are distinct")

    for label in labels:
        try:
            got = workspace.resolve_version(slug, label)
            ok = workspace.version_label(got) == label
        except FileNotFoundError:
            ok = False
        check(ok, f"'{label}' still resolves, so the CLI and chat keep working")
    check(workspace.resolve_version(slug, versions[1]["id"])["id"] == versions[1]["id"],
          "and so does the opaque id")

    chain = [v.get("parent") for v in versions]
    check(chain[0] is None and chain[1] == versions[0]["id"]
          and chain[2] == versions[1]["id"],
          "the parent chain was rewritten to the new ids, same shape as before")
    check(all(p is None or ids.is_id(p) for p in chain),
          "no parent still points at a `vNNN` that no longer keys anything")

    score = workspace.load_meta(slug)
    check(score.get("latest") == versions[-1]["id"],
          "the score's `latest` pointer followed the version it named")
    check(ids.is_id(score.get("uid")), "the score has a uid")

    for parsed in (workspace.resolve_path(slug, label) for label in labels):
        check(parsed.exists(), f"{parsed.name} is where its document says it is")

    srcs = workspace._repo().list_sources(slug)
    check(len(srcs) == 1 and srcs[0]["id"] == "s01" and ids.is_id(srcs[0].get("uid")),
          "the source kept its id and gained a uid")
    check(workspace.source_path(slug, "s01").exists(), "and its file is untouched")

    piece = workspace.resolve_piece("morrisons")
    check(piece.get("order") == [slug] and ids.is_id(piece.get("uid")),
          "the piece still lists its arrangement, and has a uid")
    setlist = workspace.resolve_setlist("friday")
    check(setlist.get("scores") == [slug] and ids.is_id(setlist.get("uid")),
          "the setlist still lists its arrangement, and has a uid")
    book = workspace._repo().get_book("real-book")
    check(ids.is_id(book.get("uid")), "the book has a uid")

    manifest = workspace.rebuild_manifest()
    m_score = next(s for s in manifest["scores"] if s["slug"] == slug)
    check([v["label"] for v in m_score["versions"]] == labels,
          "the manifest hands the app a label for every version, never a bare id")
    check(m_score.get("uid") is not None and m_score.get("uid") == score.get("uid"),
          "and carries the score's uid")

    print("migrating again does nothing")
    before = ([v["id"] for v in workspace.list_versions(slug)], score["uid"])
    workspace._migrate_ids(workspace._repo())
    after = ([v["id"] for v in workspace.list_versions(slug)],
             workspace.load_meta(slug)["uid"])
    check(before == after, "a second run leaves every id exactly as it was")

    print("a rename moves the slug and nothing else")
    uid_before = workspace.load_meta(slug)["uid"]
    ids_before = [v["id"] for v in workspace.list_versions(slug)]
    workspace.rename_slug(slug, "morrisons-jig-in-a")
    moved = "morrisons-jig-in-a"
    check(workspace.load_meta(moved)["uid"] == uid_before,
          "the score's uid survived the rename")
    check([v["id"] for v in workspace.list_versions(moved)] == ids_before,
          "and so did every version id")
    check([workspace.version_label(v) for v in workspace.list_versions(moved)] == labels,
          "and every label")
    check(workspace.resolve_piece("morrisons").get("order") == [moved],
          "the piece's order followed the slug, which is what slugs are for")
    check(len(workspace._repo().list_sources(moved)) == 1, "the source came too")

    print("two devices, each offline, append to the same arrangement")
    # The real scenario, and the only one that catches counted allocation:
    # two devices that CANNOT SEE each other's rows. Done in one process by
    # cloning the library and pointing the engine at the copy -- a second
    # `_write_version` in the same workspace would see the first's row and
    # count past it, which is exactly why the sequential version of this test
    # passed with the bug still in.
    import shutil

    import fixtures
    parent = workspace.latest_version(moved)["id"]
    device_a = root
    device_b = Path(tempfile.mkdtemp(prefix="scoranger-identity-b-"))
    shutil.rmtree(device_b)
    shutil.copytree(device_a, device_b)

    a = workspace._write_version(moved, fixtures.jig(bars=8), "transpose",
                                 {"interval": "M2"}, parent=parent)

    workspace.WORKSPACE = device_b                # type: ignore[attr-defined]
    workspace._reset_repo_for_testing()
    check(workspace.latest_version(moved)["id"] == parent,
          "the second device starts from the same version, knowing nothing of the first")
    b = workspace._write_version(moved, fixtures.jig(bars=8), "transpose",
                                 {"interval": "m3"}, parent=parent)

    check(a["id"] != b["id"],
          f"the two devices minted different ids ({a['id'][:8]}… / {b['id'][:8]}…), "
          "so neither overwrites the other on sync")
    check(a["file"] != b["file"],
          "and named their artifacts differently, so neither overwrites the other's file")
    check(a["seq"] == b["seq"], f"same seq ({a['seq']}): a fork is two versions "
                                "at the same depth, not one after the other")
    check(a["label"] == b["label"] == f"v{a['seq']:03d}",
          f"so both read as {a['label']}, which is what a branch looks like")
    check(a["parent"] == b["parent"] == parent,
          "and both record the version they actually came from")

    workspace.WORKSPACE = device_a                # type: ignore[attr-defined]
    workspace._reset_repo_for_testing()

    print("and a fork inside one library keeps both children")
    c = workspace._write_version(moved, fixtures.jig(bars=8), "transpose",
                                 {"interval": "P5"}, parent=parent)
    kept = {v["id"] for v in workspace.list_versions(moved)}
    check(a["id"] in kept and c["id"] in kept,
          "both children of the same parent are in the history")
    check(workspace.list_versions(moved)[-1]["id"] in (a["id"], c["id"]),
          "and the order is stable, so `latest` does not flap between them")

    print("a build rolled BACK cannot strand a version")
    # The migration skips an arrangement that already carries a uid, which is
    # what keeps launch cheap. That skip once had a hole: downgrade the build,
    # run an op, and the old engine appends a version keyed `vNNN` into an
    # arrangement whose uid says "already done" -- so it was skipped for ever.
    # One version that can never sync, and if the old build wrote a second it
    # would compute the same `vNNN` and overwrite the first. `latest` is
    # checked alongside the uid because any version an old engine writes
    # becomes `latest`.
    stranded = workspace.load_meta(moved)
    doc = dict(workspace._repo().get_version(moved, stranded["latest"]))
    workspace._repo().delete_version(moved, doc["id"])
    doc["id"] = "v099"                       # as a pre-stage-0 engine keys it
    doc.pop("label", None)
    workspace._repo().add_version(moved, "v099", doc["seq"], doc)
    score_doc = workspace._repo().get_score(moved)
    score_doc["latest"] = "v099"             # ... and points `latest` at it
    workspace._repo().set_score(moved, score_doc)

    workspace._migrate_ids(workspace._repo())
    after = workspace.list_versions(moved)
    check(all(ids.is_id(v["id"]) for v in after),
          "a `vNNN` version left by an older build is migrated, not skipped")
    check(ids.is_id(workspace.load_meta(moved).get("latest")),
          "and `latest` follows it instead of pointing at a key that is gone")
    check("v099" in [workspace.version_label(v) for v in after],
          "keeping its label, so the history still reads the way it did")

    print("id allocation needs no coordination")
    minted: list[str] = []
    lock = threading.Lock()

    def mint():
        batch = [ids.new_id() for _ in range(2000)]
        with lock:
            minted.extend(batch)

    threads = [threading.Thread(target=mint) for _ in range(8)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    check(len(minted) == len(set(minted)),
          f"16000 ids minted across 8 threads, {len(set(minted))} distinct")
    check(all(ids.is_id(i) for i in minted[:100]) and not ids.is_id("v001"),
          "an id is tellable from a label, which is how both resolve")

    print()
    if FAILURES:
        print(f"{len(FAILURES)} FAILED")
        for f in FAILURES:
            print(f"  - {f}")
        return 1
    print("OK: identity survives migration, rename and concurrent allocation")
    return 0


if __name__ == "__main__":
    sys.exit(main())
