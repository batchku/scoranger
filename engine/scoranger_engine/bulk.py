"""Bulk import: a folder of exported scores becomes pieces and arrangements.

Built for the Newzik migration. Newzik has no whole-library export -- a SETLIST
exports as a ZIP of separate PDFs -- so the route is one temporary setlist
holding the whole library, exported once. What comes back is a folder of files
whose names carry the titles, and the grouping has to be recovered from them.

The grouping rule is the one the user stated: files sharing a title are
arrangements of ONE piece. "Nature Boy", "Nature Boy - trio" and "Nature Boy -
lead sheet" are three arrangements of Nature Boy, not three pieces.

Filenames are a guess, so a manifest overrides them entirely, and `run` plans
before it writes: a migration that guesses wrong about a whole library is not
something to find out afterwards.
"""

import re
from pathlib import Path

from . import workspace

#: Extensions the workspace can hold as an arrangement.
#:
#: A PDF is one of them now: it reads and takes markup, and OMR turns it into
#: an editable arrangement when the reader wants that. What it cannot do until
#: then is be edited, which `workspace.resolve_notation_path` enforces.
#: Derived, not typed again. Both halves of this now come from the engine's
#: own lists, so a format the engine learns (ABC) is importable in bulk on the
#: same day rather than whenever someone notices this line.
from .workspace import NOTATION_SUFFIXES, SCAN_SUFFIXES
NOTATION = set(NOTATION_SUFFIXES)
SCANS = set(SCAN_SUFFIXES)
IMPORTABLE = NOTATION | SCANS

#: Nothing is held back any more. Kept as an empty set so the report shape does
#: not change under callers that read it.
PENDING: set[str] = set()

#: What separates a piece's title from the name of one arrangement of it.
#: Newzik exports use a hyphen; the dashes are here because a title typed on an
#: iPad often is not the one on the keyboard.
_SEPARATORS = (" - ", " – ", " — ")


def _normalise(text: str) -> str:
    """The key two spellings of one title agree on."""
    return re.sub(r"\s+", " ", text).strip().casefold()


def split_title(stem: str) -> tuple[str, str]:
    """A file stem as (piece, arrangement).

    With no separator the file IS the piece and its only arrangement, which is
    what a library of one-file-per-piece looks like.
    """
    for separator in _SEPARATORS:
        if separator in stem:
            piece, _, arrangement = stem.partition(separator)
            piece, arrangement = piece.strip(), arrangement.strip()
            if piece and arrangement:
                return piece, arrangement
    return stem.strip(), stem.strip()


def clean_arrangement_name(stem: str) -> str:
    """The name a reader should see, from the name the export happened to use.

    Export filenames carry an ordinal from the setlist position and, often, a
    "copy" left over from the source. Neither means anything once the file is
    an arrangement of a named piece.
    """
    text = re.sub(r"^\s*\d+\s*[.\-)]\s*", "", stem)      # "3. ", "12 - "
    text = re.sub(r"\s+copy(\s*\d+)?$", "", text, flags=re.I)
    return re.sub(r"\s+", " ", text).strip() or stem.strip()


def plan(files: list[str], manifest: list[dict] | None = None) -> dict:
    """Group files into pieces and their arrangements. Reads nothing, writes nothing.

    Two grouping signals, in order of trust:

    1. the FOLDER a file sits in. Newzik's setlist export writes one directory
       per piece, named with the piece's own title -- the human one, not a
       slug -- and the arrangements inside it. That is the real structure and
       it is taken as given.
    2. failing that, the filename rule (`Title - Something.pdf`), for a flat
       folder of loose files.

    A manifest overrides both.
    """
    stated: dict[str, tuple[str, str]] = {}
    for row in manifest or []:
        piece = str(row["piece"])
        stated[str(row["file"])] = (piece, str(row.get("arrangement") or piece))

    pieces: list[dict] = []
    seen: dict[str, int] = {}
    pending: list[dict] = []
    ignored: list[dict] = []

    # how many scores each folder holds, so a piece with ONE arrangement can
    # name it after itself rather than after whatever the file was called
    per_folder: dict[str, int] = {}
    for name in files:
        if Path(name).suffix.lower() in IMPORTABLE | PENDING:
            folder = Path(name).parts[0] if len(Path(name).parts) > 1 else ""
            per_folder[folder] = per_folder.get(folder, 0) + 1

    for name in files:
        path = Path(name)
        suffix = path.suffix.lower()
        if suffix not in IMPORTABLE and suffix not in PENDING:
            ignored.append({"file": name,
                            "why": f"not a score file ({suffix or 'no extension'})"})
            continue

        if name in stated:
            piece, arrangement = stated[name]
        elif len(path.parts) > 1:
            piece = path.parts[0]
            arrangement = (piece if per_folder.get(piece, 0) == 1
                           else clean_arrangement_name(path.stem))
        else:
            piece, arrangement = split_title(path.stem)
        key = _normalise(piece)
        if key not in seen:
            # first spelling seen wins, so one SHOUTED filename does not
            # rename the piece
            seen[key] = len(pieces)
            pieces.append({"piece": piece, "arrangements": []})
        pieces[seen[key]]["arrangements"].append(
            {"file": name, "name": arrangement, "importable": True,
             "kind": "pdf" if suffix in SCANS else "musicxml"})

    return {"pieces": pieces, "pending": pending, "ignored": ignored,
            "counts": {"pieces": len(pieces),
                       "arrangements": sum(len(p["arrangements"]) for p in pieces),
                       "pending": len(pending), "ignored": len(ignored)}}


def without(plan_: dict, excluded) -> dict:
    """The plan with some pieces left out, by name.

    A whole exported library usually holds something that does not belong -- a
    fake book, a lyrics sheet -- and taking it out at import is easier than
    unpicking it afterwards. The counts are recomputed so what the reader
    approves is what gets written.
    """
    names = set(excluded or [])
    if not names:
        return plan_
    kept = [p for p in plan_["pieces"] if p["piece"] not in names]
    return dict(plan_, pieces=kept,
                counts={**plan_["counts"],
                        "pieces": len(kept),
                        "arrangements": sum(len(p["arrangements"]) for p in kept)})


def describe(plan_: dict) -> str:
    """The tree, for a person to read before anything is written."""
    lines = []
    for piece in plan_["pieces"]:
        lines.append(piece["piece"])
        for arrangement in piece["arrangements"]:
            mark = " " if arrangement["importable"] else "*"
            lines.append(f"  {mark} {arrangement['name']}  ({arrangement['file']})")
    counts = plan_["counts"]
    lines.append("")
    lines.append(f"{counts['pieces']} pieces, {counts['arrangements']} arrangements")
    if counts["pending"]:
        lines.append(f"* {counts['pending']} held: a PDF needs OMR or a PDF-backed "
                     f"arrangement before it can be stored")
    if counts["ignored"]:
        lines.append(f"{counts['ignored']} ignored (not score files)")
    return "\n".join(lines)


def run(plan_: dict, dry_run: bool = True, root: str | None = None) -> dict:
    """Create the pieces and import what can be imported.

    `dry_run` is the default deliberately: this writes across a whole library,
    and the tree it would build is worth reading first.
    """
    if dry_run:
        return {"dry_run": True, "created": [], "imported": [],
                "would_create": [p["piece"] for p in plan_["pieces"]],
                "would_import": [a["file"] for p in plan_["pieces"]
                                 for a in p["arrangements"] if a["importable"]],
                "held": [f["file"] for f in plan_["pending"]]}

    created, imported, failed = [], [], []
    base = Path(root) if root else Path(".")
    for piece in plan_["pieces"]:
        workspace.create_piece(piece["piece"])
        created.append(piece["piece"])
        for arrangement in piece["arrangements"]:
            if not arrangement["importable"]:
                continue
            source = base / arrangement["file"]
            try:
                # a list, because one file can hold several tunes; they all
                # belong to the piece the FOLDER named, so `ensure_own_piece`
                # is deliberately not used here -- the reader's own filing
                # already said where these go and must not be second-guessed
                for slug in _import_one(source, arrangement["name"]):
                    workspace.assign_score_to_piece(slug, piece["piece"],
                                                    create_if_missing=True)
                    imported.append({"file": arrangement["file"], "score": slug})
            except Exception as exc:                      # noqa: BLE001
                # one bad file may not abandon the other forty
                failed.append({"file": arrangement["file"],
                               "error": f"{type(exc).__name__}: {exc}"})
    return {"dry_run": False, "created": created, "imported": imported,
            "failed": failed, "held": [f["file"] for f in plan_["pending"]]}


def _import_one(source: Path, name: str) -> list[str]:
    """Every arrangement one file yields. A list of one, except for ABC.

    It returned a single slug while every importable file was one score. An
    ABC file holding several tunes is several arrangements, and music21 gives
    back an Opus for those -- so this reads through `workspace.read_notation`
    and the caller files each of them.
    """
    from . import ops

    if not source.exists():
        raise FileNotFoundError(f"No such file: {source}")
    if source.suffix.lower() in SCANS:
        # the name is the one the plan decided, never the file's -- these come
        # out of an export called things like "3.pdf"
        slug, _entry = workspace.create_pdf_score(name, source, op="bulk-import",
                                                  args={"source": source.name})
        return [slug]
    slugs = []
    for score in workspace.read_notation(source):
        title = ops.clean_imported_metadata(score, name,
                                            source_stem=source.stem)["title"]
        slug, _entry = workspace.create_score(title, score, op="bulk-import",
                                              args={"source": source.name})
        slugs.append(slug)
    return slugs
