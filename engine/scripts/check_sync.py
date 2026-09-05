#!/usr/bin/env python3
"""What this device still owes the server, and what it costs when nobody signs in.

Sync is optional. The app is usable "like an old school app with just local
files" (the owner's words), so the library database stays authoritative and a
signed-out device must not pay for a feature it declined. That is the first
thing checked here, because it is the one a later refactor is most likely to
break quietly: turn journaling on by default and nothing fails, nothing is
slower to the eye, and the promise is gone.

The rest is the record the Swift sync layer reads. `design/FIREBASE.md` §4.1
asked for a change journal and §7 states the conflict rules; stage 0 built the
injection point (`workspace.repository_factory`) and deliberately left the
journal out until something consumed it. This is that journal, and the claims
it has to hold are:

  1. signed out, there is no journal at all -- no file, no table, no rev
  2. every real change is recorded exactly once per document, in order
  3. a write that changes nothing is not a change (or an idle poll that
     re-saves a document would push the whole library every two seconds)
  4. an acknowledged change stops being owed, and the next edit is owed again
  5. a DELETE outlives the row it deleted -- this is the one that matters.
     `sweep()` reclaims a deleted score's row 30 seconds later, and if the
     only record of the deletion is that row, a device that was offline
     pushes the score back up on reconnect. Deleted things returning from the
     dead is the most alarming sync bug a user can meet (§7 rule 4)
  6. losing the journal loses no library: everything becomes owed again,
     which is a re-push, not a data loss
  7. journaling is transparent -- the same session with it on and off produces
     the same library and the same manifest

Run: engine/.venv/bin/python engine/scripts/check_sync.py
"""
import json
import os
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

FAILURES: list[str] = []


def check(condition, message):
    print(f"    {'ok  ' if condition else 'FAIL'} {message}")
    if not condition:
        FAILURES.append(message)
    return condition


def fresh_workspace() -> Path:
    """A workspace of its own, with the engine pointed at it."""
    from scoranger_engine import workspace

    root = Path(tempfile.mkdtemp())
    os.environ["SCORANGER_WORKSPACE"] = str(root)
    workspace.WORKSPACE = root
    workspace._reset_repo_for_testing()
    return root


def plain() -> None:
    from scoranger_engine import workspace
    from scoranger_engine.db import SqliteRepository

    workspace.repository_factory = SqliteRepository
    workspace._reset_repo_for_testing()


def journaled(root: Path):
    """Point the engine at a journaling repository and return it."""
    from scoranger_engine import sync, workspace

    workspace.repository_factory = sync.journaling_factory(root / "sync.db")
    workspace._reset_repo_for_testing()
    return workspace._repo()


def a_score(name: str = "Morrison's Jig") -> str:
    from scoranger_engine import workspace

    import fixtures

    slug, _ = workspace.create_score(name, fixtures.jig(bars=4))
    return slug


def keys(changes) -> list[str]:
    return [c.key for c in changes]


# -- 1. signed out ---------------------------------------------------------

def signed_out_pays_nothing() -> None:
    print("\nsigned out, there is no sync")
    root = fresh_workspace()
    plain()

    slug = a_score()
    from scoranger_engine import workspace

    workspace.rename_score(slug, "Morrison's")
    workspace.delete_score(slug)

    check(not (root / "sync.db").exists(),
          "no journal file exists after a whole import-rename-delete session")
    docs = [json.loads(json.dumps(d)) for d in workspace._repo().list_scores(include_deleted=True)]
    check(all("rev" not in d for d in docs),
          "no document carries a rev: the signed-out library is byte-for-byte what it was")


# -- 2, 3, 4. the journal --------------------------------------------------

def what_is_owed() -> None:
    print("\nwhat this device owes")
    root = fresh_workspace()
    repo = journaled(root)
    from scoranger_engine import workspace

    slug = a_score()
    owed = repo.pending()
    check(f"scores/{slug}" in keys(owed), f"the new score is owed ({len(owed)} entries)")
    check(len([c for c in owed if c.key == f"scores/{slug}"]) == 1,
          "owed once, not once per write during creation")
    version = workspace.latest_version(slug)
    check(f"scores/{slug}/versions/{version['id']}" in keys(owed),
          "its version is owed too, under the score it belongs to")

    doc = repo.get_score(slug)
    check(doc.get("rev", 0) >= 1, f"the score document carries a rev ({doc.get('rev')})")

    # a write that changes nothing
    before = repo.get_score(slug)["rev"]
    repo.set_score(slug, dict(before_doc := repo.get_score(slug)))
    check(repo.get_score(slug)["rev"] == before,
          "re-saving an unchanged document does not bump its rev")
    check(len([c for c in repo.pending() if c.key == f"scores/{slug}"]) == 1,
          "...and does not add a second entry to what is owed")
    assert before_doc is not None

    # acknowledge
    repo.mark_synced(repo.pending())
    check(repo.pending() == [], "after the server acknowledges, nothing is owed")

    workspace.rename_score(slug, "Morrison's Reel")
    owed = repo.pending()
    check(keys(owed) == [f"scores/{slug}"] or f"scores/{slug}" in keys(owed),
          f"the next edit is owed again ({keys(owed)})")
    check(repo.get_score(slug)["rev"] > before, "and its rev moved")


def order_and_pruning() -> None:
    print("\nthe cursor")
    root = fresh_workspace()
    repo = journaled(root)
    from scoranger_engine import workspace

    first = a_score("First Tune")
    second = a_score("Second Tune")
    owed = repo.pending()
    order = [c.key for c in owed if c.key.startswith("scores/") and "/versions/" not in c.key]
    check(order == [f"scores/{first}", f"scores/{second}"],
          f"entries come back in the order they happened ({order})")

    repo.mark_synced([c for c in owed if c.key == f"scores/{first}"])
    still = [c.key for c in repo.pending()]
    check(f"scores/{first}" not in still and f"scores/{second}" in still,
          "acknowledging a prefix leaves the rest owed")

    repo.mark_synced(repo.pending())
    repo.prune()
    check(repo.pending() == [], "pruning an acknowledged journal owes nothing")
    workspace.rename_score(second, "Second Reel")
    # a rename is a metadata edit AND a new version, so both are owed
    owed_after = [c.key for c in repo.pending()]
    check(f"scores/{second}" in owed_after,
          f"and a later edit is still detected after the prune ({owed_after})")


# -- 5. the tombstone ------------------------------------------------------

def a_delete_outlives_its_row() -> None:
    print("\na delete outlives the row it deleted")
    root = fresh_workspace()
    repo = journaled(root)
    from scoranger_engine import workspace

    slug = a_score()
    uid = repo.get_score(slug)["uid"]
    repo.mark_synced(repo.pending())

    workspace.delete_score(slug)          # phase one: marked, undo window open
    workspace.sweep(now="2099-01-01T00:00:00+00:00")   # phase two: row reclaimed
    check(repo.get_score(slug) is None, "the row is gone, as the undo window says it should be")

    owed = repo.pending()
    tomb = [c for c in owed if c.key == f"scores/{slug}"]
    check(len(tomb) == 1, f"the deletion is still owed ({keys(owed)})")
    check(bool(tomb) and tomb[0].op == "delete", "and it is owed as a delete, not as an edit")
    check(bool(tomb) and tomb[0].uid == uid,
          "carrying the uid, which is the only name the server knows it by")


def a_piece_dropped_behind_the_users_back_is_still_owed() -> None:
    """The delete with no tombstone phase at all.

    A piece does not exist without arrangements, so `_drop_empty_pieces` removes
    it the moment its last one leaves -- no `deleted_at`, no undo window,
    nothing left in the library to notice afterwards. If that is not journaled
    the piece comes back from another device for ever.
    """
    print("\na piece dropped behind the user's back")
    root = fresh_workspace()
    repo = journaled(root)
    from scoranger_engine import workspace

    slug = a_score()
    piece = workspace.assign_score_to_piece(slug, "Morrison's Jig")["piece"]
    repo.mark_synced(repo.pending())
    check(repo.get_piece(piece) is not None, "the piece is there")

    workspace.delete_score(slug, immediate=True)
    check(repo.get_piece(piece) is None, "and goes when its last arrangement does")
    owed = [c for c in repo.pending() if c.key == f"pieces/{piece}"]
    check(len(owed) == 1 and owed[0].op == "delete",
          f"the drop is owed as a delete ({owed})")


def a_delete_beats_a_pending_create() -> None:
    print("\na delete beats an edit that was never pushed")
    root = fresh_workspace()
    repo = journaled(root)
    from scoranger_engine import workspace

    slug = a_score()
    workspace.rename_score(slug, "Renamed Before Anyone Saw It")
    workspace.delete_score(slug, immediate=True)
    owed = [c for c in repo.pending() if c.key == f"scores/{slug}"]
    check(len(owed) == 1 and owed[0].op == "delete",
          f"created, renamed and deleted offline collapses to one delete ({owed})")


# -- 6. the journal is not the library -------------------------------------

def losing_the_journal_loses_no_library() -> None:
    print("\nthe journal is not the library")
    root = fresh_workspace()
    repo = journaled(root)
    slug = a_score()
    repo.mark_synced(repo.pending())
    check(repo.pending() == [], "nothing owed")

    (root / "sync.db").unlink()
    repo = journaled(root)
    check(repo.get_score(slug) is not None, "the library is still there")
    owed = [c.key for c in repo.pending()]
    check(f"scores/{slug}" in owed,
          "and everything is owed again -- a re-push, which is not a data loss")


# -- 7. transparency -------------------------------------------------------

def journaling_changes_nothing_a_user_sees() -> None:
    print("\njournaling is transparent")

    def session() -> dict:
        from music21 import converter

        from scoranger_engine import ops, workspace

        import fixtures

        slug, _ = workspace.create_score("Transparent Tune", fixtures.jig(bars=4))
        score = converter.parse(str(workspace.resolve_notation_path(slug)))
        ops.transpose(score, "M2")
        workspace.add_version(slug, score, "transpose", {"interval": "M2"})
        workspace.assign_score_to_piece(slug, "Transparent Tune")
        workspace.rename_score(slug, "Transparent Reel")
        return json.loads((workspace.WORKSPACE / "manifest.json").read_text())

    root_a = fresh_workspace()
    plain()
    without = session()

    root_b = fresh_workspace()
    journaled(root_b)
    with_journal = session()

    def scrub(m):
        m = json.loads(json.dumps(m))
        m.pop("generated", None)
        for s in m.get("scores", []):
            s.pop("uid", None)
            s.pop("rev", None)
            for v in s.get("versions", []):
                for k in ("id", "file", "time", "rev", "parent", "uid"):
                    v.pop(k, None)
            s.pop("latest", None)
            s.pop("created", None)
        for coll in ("pieces", "setlists", "books"):
            for d in m.get(coll) or []:
                d.pop("uid", None)
                d.pop("rev", None)
                d["arrangements"] = ["<slug>" for _ in d.get("arrangements", [])]
        # the library's identity and birthday, for the same reason as every
        # uid above: two workspaces are two libraries, and a fresh ULID and a
        # fresh timestamp differ between any two runs, journal or no journal
        for k in ("uid", "created", "rev"):
            (m.get("library") or {}).pop(k, None)
        return m

    check(scrub(without) == scrub(with_journal),
          "the same session produces the same library with the journal on and off")
    check(all(root_a != root_b for _ in [0]), "(two workspaces, not one)")


def main() -> int:
    signed_out_pays_nothing()
    what_is_owed()
    order_and_pruning()
    a_delete_outlives_its_row()
    a_piece_dropped_behind_the_users_back_is_still_owed()
    a_delete_beats_a_pending_create()
    losing_the_journal_loses_no_library()
    journaling_changes_nothing_a_user_sees()

    print()
    if FAILURES:
        print(f"{len(FAILURES)} FAILED")
        for f in FAILURES:
            print(f"  - {f}")
        return 1
    print("OK: signed out costs nothing, and what is owed survives the row it deleted")
    return 0


if __name__ == "__main__":
    sys.exit(main())
