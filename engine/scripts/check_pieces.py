#!/usr/bin/env python3
"""A piece never exists without at least one arrangement.

Ali hit a piece showing "0 arrangements" that would not delete. Two faults met:
`delete_score` removed the arrangement and left the piece row behind, and the
UI deletes a piece BY deleting its contents -- which for an empty piece is an
empty loop, so the button did nothing at all.

A piece is a folder for arrangements, not a thing in its own right. It cannot
be opened (opening a piece means opening one of its arrangements) and it cannot
be deleted through its contents. So it must not be possible to have one.

Run: engine/.venv/bin/python engine/scripts/check_pieces.py
"""
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

FAILURES = []


def check(condition, message):
    if not condition:
        FAILURES.append(message)
    return condition


def main():
    root = tempfile.mkdtemp(prefix="scoranger-pieces-")
    import os
    os.environ["SCORANGER_HOME"] = root

    from scoranger_engine import workspace
    import fixtures

    workspace.WORKSPACE = Path(root)          # type: ignore[attr-defined]
    if hasattr(workspace, "_reset_repo_for_testing"):
        workspace._reset_repo_for_testing()

    def pieces():
        return {p["slug"]: p for p in workspace.rebuild_manifest().get("pieces", [])}

    # --- a piece with one arrangement, whose arrangement is deleted ---------
    slug_a, _ = workspace.create_score("Cavatina duo", fixtures.jig(bars=4))
    workspace.assign_score_to_piece(slug_a, "Cavatina")
    check("cavatina" in pieces(), "the piece was never created")

    workspace.delete_score(slug_a)
    check("cavatina" not in pieces(),
          "deleting the last arrangement left the piece behind with nothing in it")
    print(f"  last arrangement deleted -> piece gone ({len(pieces())} pieces left)")

    # --- a piece whose only arrangement is RE-FILED elsewhere ---------------
    slug_b, _ = workspace.create_score("Libertango solo", fixtures.jig(bars=4))
    workspace.assign_score_to_piece(slug_b, "Libertango")
    workspace.assign_score_to_piece(slug_b, "Tangos")
    after = pieces()
    check("libertango" not in after,
          "re-filing the last arrangement left its old piece empty")
    check("tangos" in after, "the arrangement did not arrive at its new piece")
    print("  last arrangement re-filed -> old piece gone, new piece holds it")

    # --- a piece with two arrangements loses one and survives ---------------
    slug_c, _ = workspace.create_score("Django one", fixtures.jig(bars=4))
    slug_d, _ = workspace.create_score("Django two", fixtures.jig(bars=4))
    workspace.assign_score_to_piece(slug_c, "Django")
    workspace.assign_score_to_piece(slug_d, "Django")
    workspace.delete_score(slug_c)
    check("django" in pieces(), "a piece with an arrangement left was deleted anyway")
    print("  one of two deleted -> piece survives")

    # --- deleting a piece, both ways ---------------------------------------
    workspace.delete_piece("Django")
    check("django" not in pieces(), "deleting a piece did nothing")
    survivors = {d["slug"] for d in workspace._repo().list_scores()}
    check(slug_d in survivors,
          "deleting a piece without --with-arrangements destroyed its arrangements")
    print("  delete piece -> piece gone, its arrangement unfiled and intact")

    slug_e, _ = workspace.create_score("Bossa one", fixtures.jig(bars=4))
    workspace.assign_score_to_piece(slug_e, "Bossa")
    workspace.delete_piece("Bossa", with_arrangements=True)
    check("bossa" not in pieces(), "delete piece with arrangements left the piece")
    check(slug_e not in {d["slug"] for d in workspace._repo().list_scores()},
          "--with-arrangements did not take the arrangements")
    print("  delete piece with its arrangements -> both gone")

    # --- and the invariant, over whatever the manifest now holds ------------
    manifest = workspace.rebuild_manifest()
    empty = [p["name"] for p in manifest.get("pieces", []) if not p["arrangements"]]
    check(not empty, f"pieces holding nothing survived a rebuild: {empty}")

    print()
    if FAILURES:
        print(f"FAILED ({len(FAILURES)}):")
        for f in FAILURES:
            print("  -", f)
        return 1
    print("OK: a piece cannot exist without an arrangement -- not after a delete, "
          "not after a re-file, and not across a manifest rebuild")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
