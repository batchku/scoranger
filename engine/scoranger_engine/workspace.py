"""Versioned score library.

Source of truth: a local document database (db.SqliteRepository, Firestore-shaped).
Artifacts:       workspace/<slug>/vNNN.musicxml  (the "storage bucket")
Serving layer:   workspace/manifest.json — a denormalized projection of the DB
                 that the viewer polls (the Firestore-listener stand-in).

Every mutation appends an immutable version document carrying the operation
that produced it and a snapshot of the resulting parts.
"""

import json
import os
import re
import uuid
from datetime import datetime
from pathlib import Path

from .db import SqliteRepository

REPO_ROOT = Path(__file__).resolve().parents[2]
WORKSPACE = Path(os.environ.get("SCORANGER_WORKSPACE", REPO_ROOT / "workspace"))

_repo_singleton: SqliteRepository | None = None

# The chat turn in progress, if any: versions created while it's open are
# stamped with it so the UI can group one prompt's operations together.
_current_turn: dict | None = None


def begin_turn(slug: str, prompt: str) -> dict:
    """Open a chat turn: subsequent versions of `slug` carry a shared turn id."""
    global _current_turn
    _current_turn = {"id": uuid.uuid4().hex[:8], "prompt": prompt[:200], "slug": slug}
    return {"turn": _current_turn["id"]}


def end_turn() -> dict:
    """Close the current chat turn (safe to call when none is open)."""
    global _current_turn
    _current_turn = None
    return {"ended": True}


def _now() -> str:
    return datetime.now().astimezone().isoformat(timespec="seconds")


def _repo() -> SqliteRepository:
    global _repo_singleton
    if _repo_singleton is None:
        WORKSPACE.mkdir(parents=True, exist_ok=True)
        _repo_singleton = SqliteRepository(WORKSPACE / "scoranger.db")
        if _repo_singleton.count_scores() == 0:
            _migrate_legacy(_repo_singleton)
    return _repo_singleton


def _migrate_legacy(repo: SqliteRepository) -> None:
    """One-time import of the old meta.json filesystem layout into the DB."""
    for d in sorted(WORKSPACE.iterdir()):
        meta_path = d / "meta.json"
        if not meta_path.is_file():
            continue
        meta = json.loads(meta_path.read_text())
        slug = meta["slug"]
        versions = meta.get("versions", [])
        for i, v in enumerate(versions):
            doc = {"id": v["id"], "seq": i + 1, "file": v["file"], "op": v["op"],
                   "args": v.get("args", {}), "parent": v.get("parent"),
                   "time": v.get("time"), "parts": None}
            if i == len(versions) - 1:
                doc["parts"] = _parts_snapshot(d / v["file"])
            repo.add_version(slug, v["id"], i + 1, doc)
        repo.set_score(slug, {
            "id": slug, "slug": slug, "name": meta["name"],
            "title": meta.get("name"), "composer": None,
            "created": meta.get("created"), "latest": versions[-1]["id"] if versions else None,
        })
        meta_path.rename(d / "meta.legacy.json")


def _parts_snapshot(path_or_score) -> list | None:
    from music21 import converter, stream

    from . import ops
    try:
        if isinstance(path_or_score, (str, Path)):
            m21_score = converter.parse(str(path_or_score), forceSource=True)
        else:
            m21_score = path_or_score
        return ops.info(m21_score)["parts"]
    except Exception:
        return None


def slugify(name: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")
    return slug or "score"


def score_dir(slug: str) -> Path:
    return WORKSPACE / slug


def load_meta(slug: str) -> dict:
    """Score document + its version documents (kept for CLI compatibility)."""
    repo = _repo()
    doc = repo.get_score(slug)
    if doc is None:
        available = [s["slug"] for s in repo.list_scores()]
        raise FileNotFoundError(f"No score '{slug}'. Available: {available}")
    doc = dict(doc)
    doc["versions"] = repo.list_versions(slug)
    return doc


def version_path(slug: str, version_id: str) -> Path:
    v = _repo().get_version(slug, version_id)
    if v is None:
        have = [x["id"] for x in _repo().list_versions(slug)]
        raise FileNotFoundError(f"No version '{version_id}' of '{slug}'. Have: {have}")
    return score_dir(slug) / v["file"]


def latest_version(slug: str) -> dict:
    meta = load_meta(slug)
    if not meta["versions"]:
        raise FileNotFoundError(f"Score '{slug}' has no versions")
    return meta["versions"][-1]


def resolve_path(slug: str, version_id: str | None = None) -> Path:
    if version_id is None:
        version_id = latest_version(slug)["id"]
    return version_path(slug, version_id)


# music21 writes itself in as the composer on every export when the score has
# none, and there is no way to suppress it from the metadata object -- so it is
# removed from the file after the write. Left in, it shows up as the composer of
# every arrangement the moment any op runs.
_M21_COMPOSER_STAMP = re.compile(
    r'[ \t]*<creator type="composer">Music21</creator>\r?\n?')


def _write_musicxml(m21_score, path: Path) -> None:
    m21_score.write("musicxml", fp=str(path))
    text = path.read_text(encoding="utf-8")
    cleaned = _M21_COMPOSER_STAMP.sub("", text)
    if cleaned != text:
        path.write_text(cleaned, encoding="utf-8")


def _write_version(slug: str, m21_score, op: str, args: dict, parent: str | None) -> dict:
    from . import ops

    repo = _repo()
    seq = len(repo.list_versions(slug)) + 1
    vid = f"v{seq:03d}"
    fname = f"{vid}.musicxml"
    score_dir(slug).mkdir(parents=True, exist_ok=True)
    _write_musicxml(m21_score, score_dir(slug) / fname)
    doc = {"id": vid, "seq": seq, "file": fname, "op": op, "args": args,
           "parent": parent, "time": _now(), "parts": _parts_snapshot(m21_score)}
    if _current_turn is not None and _current_turn["slug"] == slug:
        doc["turn"] = {"id": _current_turn["id"], "prompt": _current_turn["prompt"]}
    repo.add_version(slug, vid, seq, doc)
    score_doc = repo.get_score(slug)
    score_doc["latest"] = vid
    # the doc's metadata is a projection of the latest version's notation, never
    # an independent value -- that divergence is what gave the app one title in
    # the library and a different one engraved on the page
    meta = ops.score_metadata(m21_score)
    score_doc["title"] = meta["title"]
    score_doc["composer"] = meta["composer"]
    score_doc["arranger"] = meta["arranger"]
    repo.set_score(slug, score_doc)
    rebuild_manifest()
    return doc


def create_score(name: str, m21_score, op: str = "import", args: dict | None = None) -> tuple[str, dict]:
    """Create a new score with its first version. Returns (slug, version doc)."""
    repo = _repo()
    base = slugify(name)
    slug, n = base, 2
    while repo.get_score(slug) is not None:
        slug = f"{base}-{n}"
        n += 1
    from . import ops
    meta = ops.score_metadata(m21_score)
    repo.set_score(slug, {
        "id": slug, "slug": slug, "name": name,
        "title": meta["title"], "composer": meta["composer"],
        "arranger": meta["arranger"],
        "created": _now(), "latest": None,
    })
    entry = _write_version(slug, m21_score, op, args or {}, parent=None)
    return slug, entry


def add_version(slug: str, m21_score, op: str, args: dict) -> dict:
    """Append a new immutable version derived from the current latest."""
    parent = latest_version(slug)["id"]
    return _write_version(slug, m21_score, op, args, parent=parent)


def add_source(slug: str, m21_score, name: str, origin: str) -> dict:
    """Attach another found edition/tab of the piece as a reference source."""
    repo = _repo()
    load_meta(slug)  # validates the score exists
    sid = f"s{len(repo.list_sources(slug)) + 1:02d}"
    src_dir = score_dir(slug) / "sources"
    src_dir.mkdir(parents=True, exist_ok=True)
    fname = f"{sid}.musicxml"
    m21_score.write("musicxml", fp=str(src_dir / fname))
    doc = {"id": sid, "name": name, "origin": origin, "file": f"sources/{fname}",
           "time": _now(), "parts": _parts_snapshot(m21_score)}
    repo.add_source(slug, sid, doc)
    rebuild_manifest()
    return doc


def source_path(slug: str, source_id: str) -> Path:
    doc = _repo().get_source(slug, source_id)
    if doc is None:
        have = [s["id"] for s in _repo().list_sources(slug)]
        raise FileNotFoundError(f"No source '{source_id}' of '{slug}'. Have: {have}")
    return score_dir(slug) / doc["file"]


def create_piece(name: str) -> dict:
    """Create a piece document (a work that groups arrangements). Returns the doc."""
    repo = _repo()
    base = slugify(name)
    slug, n = base, 2
    while repo.get_piece(slug) is not None:
        slug = f"{base}-{n}"
        n += 1
    doc = {"id": slug, "slug": slug, "name": name, "created": _now()}
    repo.set_piece(slug, doc)
    rebuild_manifest()
    return doc


def resolve_piece(name_or_slug: str, create_if_missing: bool = False) -> dict:
    """Find a piece by slug, then by case-insensitive name; optionally create it."""
    repo = _repo()
    doc = repo.get_piece(name_or_slug)
    if doc is not None:
        return doc
    for p in repo.list_pieces():
        if p["name"].lower() == name_or_slug.lower():
            return p
    if create_if_missing:
        return create_piece(name_or_slug)
    available = [p["slug"] for p in repo.list_pieces()]
    raise FileNotFoundError(f"No piece '{name_or_slug}'. Available: {available}")


def assign_score_to_piece(slug: str, piece: str | None,
                          create_if_missing: bool = True) -> dict:
    """File an arrangement under a piece (None = unfile). The link lives on the score doc."""
    repo = _repo()
    doc = repo.get_score(slug)
    if doc is None:
        available = [s["slug"] for s in repo.list_scores()]
        raise FileNotFoundError(f"No score '{slug}'. Available: {available}")
    if piece is None:
        doc.pop("piece", None)
        piece_slug = None
    else:
        piece_slug = resolve_piece(piece, create_if_missing=create_if_missing)["slug"]
        doc["piece"] = piece_slug
    repo.set_score(slug, doc)
    # Maintain each piece's explicit arrangement order: drop the slug from
    # every other piece's order, append it to the target's.
    for p in repo.list_pieces():
        order = p.get("order") or []
        if p["slug"] == piece_slug:
            if slug not in order:
                order.append(slug)
                p["order"] = order
                repo.set_piece(p["slug"], p)
        elif slug in order:
            order.remove(slug)
            p["order"] = order
            repo.set_piece(p["slug"], p)
    rebuild_manifest()
    return {"score": slug, "piece": piece_slug}


def set_piece_order(name_or_slug: str, order: list) -> dict:
    """Set a piece's arrangement order. Every slug must belong to the piece."""
    repo = _repo()
    doc = resolve_piece(name_or_slug)
    members = {s["slug"] for s in repo.list_scores() if s.get("piece") == doc["slug"]}
    bad = [s for s in order if s not in members]
    if bad:
        raise ValueError(f"Not arrangements of '{doc['slug']}': {bad}. Members: {sorted(members)}")
    doc["order"] = list(order)
    repo.set_piece(doc["slug"], doc)
    rebuild_manifest()
    return doc


def set_score_metadata(slug: str, title: str | None = None,
                       composer: str | None = None,
                       arranger: str | None = None) -> dict:
    """Edit an arrangement's metadata, notation included.

    The title is one value, not two: it is the arrangement's name in the library
    AND the title engraved at the top of the page. Because the engraved title
    lives in the notation, this appends a version like any other mutating op --
    the edit is versioned and reversible, and no file is ever hand-edited.

    The slug never moves: it is the identity every version artifact, piece order
    and chat 'arr:' reference is keyed on.
    """
    from music21 import converter

    from . import ops

    repo = _repo()
    doc = repo.get_score(slug)
    if doc is None:
        available = [s["slug"] for s in repo.list_scores()]
        raise FileNotFoundError(f"No score '{slug}'. Available: {available}")
    if title is not None and not title.strip():
        raise ValueError("A title is required")
    if title is None and composer is None and arranger is None:
        raise ValueError("Nothing to change: pass a title, composer or arranger")

    score = converter.parse(str(resolve_path(slug)), forceSource=True)
    applied = ops.set_metadata(score, title=title, composer=composer,
                              arranger=arranger)
    entry = add_version(slug, score, "set-metadata",
                        {k: v for k, v in (("title", title), ("composer", composer),
                                           ("arranger", arranger)) if v is not None})
    if title is not None:
        doc = repo.get_score(slug)          # add_version refreshed the projection
        doc["name"] = title.strip()
        repo.set_score(slug, doc)
        rebuild_manifest()
    return {"score": slug, "version": entry["id"], "name": repo.get_score(slug)["name"],
            **applied}


def rename_slug(slug: str, new_slug: str) -> dict:
    """Change a score's slug -- the identity it is filed under.

    The slug is not a title: it is the key the artifact directory, the version
    and source rows, and each piece's ordering are all filed under, and the
    handle chat uses to refer to a sibling arrangement ('arr:<slug>'). So this
    is a move, not an edit: the directory is renamed and every reference is
    rewritten in the same call. Nothing outside the workspace holds a slug
    except the app's own pencil annotations, which it migrates itself.

    Slugs stay slugs: the requested name is normalized the same way an import
    would normalize it, and a collision is refused rather than suffixed --
    the caller asked for a specific handle, so silently getting another one
    would be worse than an error.
    """
    repo = _repo()
    doc = repo.get_score(slug)
    if doc is None:
        available = [s["slug"] for s in repo.list_scores()]
        raise FileNotFoundError(f"No score '{slug}'. Available: {available}")
    # slugify falls back to "score" for input with nothing usable in it, which
    # would quietly file the arrangement under a name nobody asked for
    if not re.search(r"[a-z0-9]", (new_slug or "").lower()):
        raise ValueError("A slug needs at least one letter or number")
    target = slugify(new_slug)
    if target == slug:
        return {"score": slug, "previous": slug, "renamed": False}
    if repo.get_score(target) is not None:
        raise ValueError(f"The slug '{target}' is already taken by another arrangement")

    src, dst = score_dir(slug), score_dir(target)
    if dst.exists():
        raise ValueError(f"{dst} already exists on disk; not overwriting it")
    if src.exists():
        src.rename(dst)

    versions = repo.list_versions(slug)
    sources = repo.list_sources(slug)
    doc = dict(doc)
    doc["id"] = doc["slug"] = target
    repo.set_score(target, doc)
    for v in versions:
        repo.add_version(target, v["id"], v["seq"], v)
    for src_doc in sources:
        repo.add_source(target, src_doc["id"], src_doc)
    repo.delete_score(slug)

    # a piece's ordering is a list of score slugs
    for piece in repo.list_pieces():
        order = piece.get("order") or []
        if slug in order:
            piece["order"] = [target if x == slug else x for x in order]
            repo.set_piece(piece["slug"], piece)

    rebuild_manifest()
    return {"score": target, "previous": slug, "renamed": True,
            "versions": len(versions), "sources": len(sources)}


def rename_score(slug: str, new_name: str) -> dict:
    """Rename an arrangement: its library name and its engraved title together.

    Kept as the name every caller already uses; the work is set_score_metadata's,
    so a rename can never leave the page saying something else.
    """
    return set_score_metadata(slug, title=new_name or "")


def rename_piece(name_or_slug: str, new_name: str) -> dict:
    """Rename a piece (the slug is immutable; only the display name changes)."""
    repo = _repo()
    doc = resolve_piece(name_or_slug)
    doc["name"] = new_name
    repo.set_piece(doc["slug"], doc)
    rebuild_manifest()
    return doc


def delete_piece(name_or_slug: str) -> None:
    """Delete a piece document (scores keep their 'piece' key; not exposed in UI)."""
    doc = resolve_piece(name_or_slug)
    _repo().delete_piece(doc["slug"])
    rebuild_manifest()


def create_setlist(name: str) -> dict:
    """Create a setlist document (an ordered group of arrangements)."""
    repo = _repo()
    base = slugify(name)
    slug, n = base, 2
    while repo.get_setlist(slug) is not None:
        slug = f"{base}-{n}"
        n += 1
    doc = {"id": slug, "slug": slug, "name": name, "scores": [], "created": _now()}
    repo.set_setlist(slug, doc)
    rebuild_manifest()
    return doc


def resolve_setlist(name_or_slug: str, create_if_missing: bool = False) -> dict:
    """Find a setlist by slug, then by case-insensitive name; optionally create it."""
    repo = _repo()
    doc = repo.get_setlist(name_or_slug)
    if doc is not None:
        return doc
    for s in repo.list_setlists():
        if s["name"].lower() == name_or_slug.lower():
            return s
    if create_if_missing:
        return create_setlist(name_or_slug)
    available = [s["slug"] for s in repo.list_setlists()]
    raise FileNotFoundError(f"No setlist '{name_or_slug}'. Available: {available}")


def add_score_to_setlist(setlist: str, score: str,
                         create_if_missing: bool = True) -> dict:
    """Append an arrangement to a setlist (no-op if already in it).

    A setlist is a running order, and what gets played is an arrangement, not a
    piece: "the quartet version, then the accordion one" is a set; "Sous le
    ciel de Paris" is not.
    """
    repo = _repo()
    doc = resolve_setlist(setlist, create_if_missing=create_if_missing)
    if repo.get_score(score) is None:
        available = [s["slug"] for s in repo.list_scores()]
        raise FileNotFoundError(f"No arrangement '{score}'. Available: {available}")
    scores = doc.get("scores") or []
    if score not in scores:
        scores.append(score)
        doc["scores"] = scores
        repo.set_setlist(doc["slug"], doc)
        rebuild_manifest()
    return doc


def remove_score_from_setlist(setlist: str, score: str) -> dict:
    """Drop an arrangement from a setlist. The arrangement itself is untouched."""
    repo = _repo()
    doc = resolve_setlist(setlist)
    doc["scores"] = [s for s in (doc.get("scores") or []) if s != score]
    repo.set_setlist(doc["slug"], doc)
    rebuild_manifest()
    return doc


def rename_setlist(name_or_slug: str, new_name: str) -> dict:
    """Rename a setlist (slug is immutable, like pieces and scores)."""
    repo = _repo()
    doc = resolve_setlist(name_or_slug)
    new_name = (new_name or "").strip()
    if not new_name:
        raise ValueError("A name is required")
    doc["name"] = new_name
    repo.set_setlist(doc["slug"], doc)
    rebuild_manifest()
    return doc


def delete_setlist(name_or_slug: str) -> dict:
    """Delete a setlist document. Pieces and arrangements are untouched: a
    setlist is only an ordered grouping."""
    doc = resolve_setlist(name_or_slug)
    _repo().delete_setlist(doc["slug"])
    rebuild_manifest()
    return {"deleted": doc["slug"]}


def delete_score(slug: str) -> None:
    import shutil
    load_meta(slug)  # raises with available slugs if missing
    _repo().delete_score(slug)
    if score_dir(slug).exists():
        shutil.rmtree(score_dir(slug))
    rebuild_manifest()


def _setlist_with_scores(doc: dict, pieces: list[dict]) -> dict:
    """Bring a setlist written before setlists held arrangements up to date.

    Setlists used to be ordered lists of *pieces*. A piece is not a thing you
    play — its arrangements are — so a stored piece is expanded, in place and
    once, into that piece's arrangements in their existing order. Nothing is
    dropped and nothing is guessed: a piece with three arrangements becomes
    those three, and the user reorders or removes from there.
    """
    if doc.get("scores") is not None or not doc.get("pieces"):
        doc.setdefault("scores", [])
        return doc
    by_piece = {p["slug"]: p.get("arrangements") or [] for p in pieces}
    expanded: list[str] = []
    for piece_slug in doc.get("pieces") or []:
        for score in by_piece.get(piece_slug, []):
            if score not in expanded:
                expanded.append(score)
    doc["scores"] = expanded
    doc.pop("pieces", None)
    _repo().set_setlist(doc["slug"], doc)
    return doc


def rebuild_manifest() -> dict:
    """Project the DB into workspace/manifest.json for the viewer."""
    repo = _repo()
    scores = []
    score_docs = repo.list_scores()
    for doc in score_docs:
        versions = repo.list_versions(doc["slug"])
        scores.append({
            "slug": doc["slug"], "name": doc["name"],
            "title": doc.get("title"), "composer": doc.get("composer"),
            "arranger": doc.get("arranger"),
            "latest": doc.get("latest"), "versions": versions,
            "sources": repo.list_sources(doc["slug"]),
            "piece": doc.get("piece"),
        })
    pieces = []
    for p in sorted(repo.list_pieces(), key=lambda x: x["name"].lower()):
        members = {d["slug"] for d in score_docs if d.get("piece") == p["slug"]}
        # explicit order first (only slugs that still exist and point back),
        # then any stragglers by creation time
        ordered = [s for s in (p.get("order") or []) if s in members]
        stragglers = sorted(members - set(ordered),
                            key=lambda s: next(d.get("created") or ""
                                               for d in score_docs if d["slug"] == s))
        pieces.append({"slug": p["slug"], "name": p["name"],
                       "arrangements": ordered + stragglers})
    known = {d["slug"] for d in score_docs}
    setlists = []
    for doc in sorted(repo.list_setlists(), key=lambda x: x["name"].lower()):
        doc = _setlist_with_scores(doc, pieces)
        setlists.append({"slug": doc["slug"], "name": doc["name"],
                         "arrangements": [s for s in doc.get("scores") or []
                                          if s in known]})
    manifest = {"generated": _now(), "scores": scores, "pieces": pieces,
                "setlists": setlists}
    WORKSPACE.mkdir(parents=True, exist_ok=True)
    (WORKSPACE / "manifest.json").write_text(json.dumps(manifest, indent=2))
    return manifest
