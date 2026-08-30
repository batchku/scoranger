"""Regression check for the bulk importer: titles and piece/arrangement grouping.

Built for the Newzik migration. Newzik has no whole-library export; a SETLIST
exports as a ZIP of separate PDFs, so the plan is one temporary setlist holding
everything, exported once. What comes back is a folder of files whose names
carry the titles -- and the grouping has to be recovered from those names.

The grouping rule is the one Ali stated himself: files sharing a title are
arrangements of ONE piece. "Nature Boy", "Nature Boy - trio" and
"Nature Boy - lead sheet" are three arrangements of Nature Boy, not three
pieces.

The importer PLANS before it writes. A migration that guesses wrong about a
whole library is not something to discover afterwards, so `--dry-run` prints
the tree it would build and touches nothing.

What is asserted here:

1. a bare title makes a piece with one arrangement of the same name
2. "Title - Something" files join the piece named by the title
3. grouping is case- and spacing-insensitive, and keeps the first spelling seen
4. an explicit manifest overrides the filename rule entirely
5. the plan is a PLAN: dry-run creates nothing
6. files the workspace cannot hold yet (PDFs, pending the artifact decision)
   are REPORTED, not silently dropped
7. the order of files does not change the tree

Run: engine/.venv/bin/python engine/scripts/check_bulk_import.py
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from scoranger_engine import bulk                                  # noqa: E402

FAILURES: list[str] = []


def check(condition: bool, message: str) -> None:
    if condition:
        print(f"  ok   {message}")
    else:
        print(f"  FAIL {message}")
        FAILURES.append(message)


def tree(plan: dict) -> dict[str, list[str]]:
    return {p["piece"]: [a["name"] for a in p["arrangements"]] for p in plan["pieces"]}


def check_a_bare_title_is_its_own_piece() -> None:
    print("one file, one piece")
    plan = bulk.plan(["Nature Boy.pdf"])
    check(tree(plan) == {"Nature Boy": ["Nature Boy"]},
          f"a lone file makes a piece holding one arrangement: {tree(plan)}")


def check_files_sharing_a_title_become_arrangements() -> None:
    print("several files, one piece")
    plan = bulk.plan([
        "Nature Boy.pdf",
        "Nature Boy - trio.pdf",
        "Nature Boy - lead sheet.pdf",
        "Autumn Leaves.pdf",
    ])
    check(tree(plan) == {
        "Nature Boy": ["Nature Boy", "trio", "lead sheet"],
        "Autumn Leaves": ["Autumn Leaves"],
    }, f"the title groups them: {tree(plan)}")


def check_grouping_is_forgiving_about_spelling() -> None:
    print("spelling")
    plan = bulk.plan(["Nature Boy.pdf", "nature  boy - trio.pdf", "NATURE BOY - duo.pdf"])
    check(len(plan["pieces"]) == 1, f"one piece, not three: {tree(plan)}")
    check(plan["pieces"][0]["piece"] == "Nature Boy",
          "and it keeps the first spelling seen, not the shouted one")


def check_an_explicit_manifest_wins() -> None:
    """Filenames are a guess; a manifest is the truth."""
    print("an explicit manifest")
    plan = bulk.plan(
        ["a.pdf", "b.pdf"],
        manifest=[{"file": "a.pdf", "piece": "Sous le ciel de Paris",
                   "arrangement": "quartet"},
                  {"file": "b.pdf", "piece": "Sous le ciel de Paris",
                   "arrangement": "accordion"}])
    check(tree(plan) == {"Sous le ciel de Paris": ["quartet", "accordion"]},
          f"the manifest decides: {tree(plan)}")


def check_every_score_is_accounted_for() -> None:
    """A migration that silently drops half a library is worse than one that fails.

    PDFs used to be HELD here, because the workspace could only store MusicXML.
    They are first-class arrangements now (see check_pdf_arrangements.py), so
    what this guards has moved: every score file must be planned, every
    non-score must be ignored WITH A REASON, and nothing may simply vanish.
    """
    print("everything is accounted for")
    plan = bulk.plan(["Nature Boy.pdf", "Autumn Leaves.musicxml", "notes.txt"])
    check("notes.txt" in [f["file"] for f in plan["ignored"]],
          "a file that is not a score at all is ignored, and said so")
    planned = {a["file"] for p in plan["pieces"] for a in p["arrangements"]}
    check(planned == {"Nature Boy.pdf", "Autumn Leaves.musicxml"},
          f"both scores are planned, the PDF included: {planned}")
    check(plan["pending"] == [],
          "nothing is held back any more")
    kinds = {a["file"]: a["kind"] for p in plan["pieces"] for a in p["arrangements"]}
    check(kinds["Nature Boy.pdf"] == "pdf"
          and kinds["Autumn Leaves.musicxml"] == "musicxml",
          f"and each says which kind it is, so the import knows: {kinds}")
    check(len(planned) + len(plan["ignored"]) == 3,
          "every input file ended up somewhere")


def check_a_folder_is_the_piece() -> None:
    """What Newzik actually exports: one folder per piece.

    The setlist export puts each piece in its own directory named with the
    piece's title, and that title is the human one -- "Sous le Ciel de Paris",
    not a slug. The files inside are its arrangements, and their names are
    whatever the source PDF happened to be called. So the FOLDER is the
    grouping signal and the filename rule is only a fallback for a flat folder.
    """
    print("a folder is a piece")
    plan = bulk.plan([
        "Sous le Ciel de Paris/sous-le-ciel-de-paris-hubert-giraud.pdf",
        "Sous le Ciel de Paris/under-paris-skies-accordion-solo.pdf",
        "Bucimis/Bucimis copy.pdf",
    ])
    grouped = tree(plan)
    check(set(grouped) == {"Sous le Ciel de Paris", "Bucimis"},
          f"the folder names the piece: {set(grouped)}")
    check(len(grouped["Sous le Ciel de Paris"]) == 2,
          "both files in a folder are arrangements of that piece")


def check_a_lone_file_takes_the_piece_name() -> None:
    """A one-file piece should not be called "Bucimis copy"."""
    print("a piece with one arrangement")
    plan = bulk.plan(["Bucimis/Bucimis copy.pdf"])
    check(tree(plan) == {"Bucimis": ["Bucimis"]},
          f"the single arrangement takes the piece's name: {tree(plan)}")


def check_arrangement_names_are_tidied() -> None:
    """Export filenames carry ordinals and 'copy'; the names a reader sees
    should not."""
    print("arrangement names")
    plan = bulk.plan([
        "Jovano Jovanke/3. Jovano Jovanke (G).pdf",
        "Jovano Jovanke/Jovano Jovanke A Hijaz copy.pdf",
    ])
    names = tree(plan)["Jovano Jovanke"]
    check("Jovano Jovanke (G)" in names,
          f"a leading ordinal is dropped: {names}")
    check("Jovano Jovanke A Hijaz" in names,
          f"a trailing 'copy' is dropped: {names}")


def check_pieces_can_be_left_out() -> None:
    """The reader deselects on the plan screen; the counts follow."""
    print("leaving a piece out")
    plan = bulk.plan(["Real Book/RealBk1.pdf", "Bucimis/Bucimis.pdf",
                      "Nature Boy/Nature Boy.pdf"])
    check(plan["counts"]["pieces"] == 3, "all three are planned")
    kept = bulk.without(plan, ["Real Book"])
    check(set(tree(kept)) == {"Bucimis", "Nature Boy"},
          f"the deselected piece is not written: {set(tree(kept))}")
    check(kept["counts"]["pieces"] == 2 and kept["counts"]["arrangements"] == 2,
          f"and the counts follow it: {kept['counts']}")
    check(plan["counts"]["pieces"] == 3,
          "the original plan is untouched -- the screen still shows what it showed")
    check(bulk.without(plan, []) is plan, "excluding nothing changes nothing")


def check_the_order_of_files_does_not_matter() -> None:
    print("order")
    names = ["Nature Boy - trio.pdf", "Autumn Leaves.pdf", "Nature Boy.pdf"]
    a = tree(bulk.plan(names))
    b = tree(bulk.plan(list(reversed(names))))
    check(set(a) == set(b), f"the same pieces either way: {set(a)} vs {set(b)}")
    check(sorted(a["Nature Boy"]) == sorted(b["Nature Boy"]),
          "holding the same arrangements")


def check_a_dry_run_writes_nothing(tmp: Path) -> None:
    print("dry run")
    before = sorted(p.name for p in tmp.iterdir()) if tmp.exists() else []
    report = bulk.run(bulk.plan(["Nature Boy.pdf"]), dry_run=True)
    after = sorted(p.name for p in tmp.iterdir()) if tmp.exists() else []
    check(report["dry_run"] is True, "the report says it was a dry run")
    check(report["created"] == [], "and it created nothing")
    check(before == after, "the workspace is untouched")


def main() -> int:
    check_a_bare_title_is_its_own_piece()
    check_a_folder_is_the_piece()
    check_a_lone_file_takes_the_piece_name()
    check_arrangement_names_are_tidied()
    check_files_sharing_a_title_become_arrangements()
    check_grouping_is_forgiving_about_spelling()
    check_an_explicit_manifest_wins()
    check_every_score_is_accounted_for()
    check_pieces_can_be_left_out()
    check_the_order_of_files_does_not_matter()
    check_a_dry_run_writes_nothing(Path("workspace"))

    print()
    if FAILURES:
        print(f"{len(FAILURES)} FAILED")
        for f in FAILURES:
            print(f"  - {f}")
        return 1
    print("OK: the bulk importer plans titles and grouping, and a dry run writes nothing")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
