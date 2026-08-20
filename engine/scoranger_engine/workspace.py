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


def _write_version(slug: str, m21_score, op: str, args: dict, parent: str | None) -> dict:
    repo = _repo()
    seq = len(repo.list_versions(slug)) + 1
    vid = f"v{seq:03d}"
    fname = f"{vid}.musicxml"
    score_dir(slug).mkdir(parents=True, exist_ok=True)
    m21_score.write("musicxml", fp=str(score_dir(slug) / fname))
    doc = {"id": vid, "seq": seq, "file": fname, "op": op, "args": args,
           "parent": parent, "time": _now(), "parts": _parts_snapshot(m21_score)}
    if _current_turn is not None and _current_turn["slug"] == slug:
        doc["turn"] = {"id": _current_turn["id"], "prompt": _current_turn["prompt"]}
    repo.add_version(slug, vid, seq, doc)
    score_doc = repo.get_score(slug)
    score_doc["latest"] = vid
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
    md = getattr(m21_score, "metadata", None)
    repo.set_score(slug, {
        "id": slug, "slug": slug, "name": name,
        "title": (md.title or md.movementName) if md else name,
        "composer": md.composer if md else None,
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


def rename_score(slug: str, new_name: str) -> dict:
    """Rename an arrangement (library label only).

    The slug stays put: it is the identity every version artifact, piece order
    and chat 'arr:' reference is keyed on, so renaming must not disturb it.
    No new version is created either -- the notation is untouched.
    """
    repo = _repo()
    doc = repo.get_score(slug)
    if doc is None:
        available = [s["slug"] for s in repo.list_scores()]
        raise FileNotFoundError(f"No score '{slug}'. Available: {available}")
    new_name = (new_name or "").strip()
    if not new_name:
        raise ValueError("A name is required")
    doc["name"] = new_name
    repo.set_score(slug, doc)
    rebuild_manifest()
    return {"score": slug, "name": new_name}


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
    """Create a setlist document (an ordered group of pieces). Returns the doc."""
    repo = _repo()
    base = slugify(name)
    slug, n = base, 2
    while repo.get_setlist(slug) is not None:
        slug = f"{base}-{n}"
        n += 1
    doc = {"id": slug, "slug": slug, "name": name, "pieces": [], "created": _now()}
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


def add_piece_to_setlist(setlist: str, piece: str,
                         create_if_missing: bool = True) -> dict:
    """Append a piece to a setlist (no-op if already a member)."""
    repo = _repo()
    doc = resolve_setlist(setlist, create_if_missing=create_if_missing)
    piece_slug = resolve_piece(piece)["slug"]
    pieces = doc.get("pieces") or []
    if piece_slug not in pieces:
        pieces.append(piece_slug)
        doc["pieces"] = pieces
        repo.set_setlist(doc["slug"], doc)
        rebuild_manifest()
    return doc


def delete_score(slug: str) -> None:
    import shutil
    load_meta(slug)  # raises with available slugs if missing
    _repo().delete_score(slug)
    if score_dir(slug).exists():
        shutil.rmtree(score_dir(slug))
    rebuild_manifest()


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
    piece_slugs = {p["slug"] for p in pieces}
    setlists = [{"slug": s["slug"], "name": s["name"],
                 "pieces": [q for q in (s.get("pieces") or []) if q in piece_slugs]}
                for s in sorted(repo.list_setlists(), key=lambda x: x["name"].lower())]
    manifest = {"generated": _now(), "scores": scores, "pieces": pieces,
                "setlists": setlists}
    WORKSPACE.mkdir(parents=True, exist_ok=True)
    (WORKSPACE / "manifest.json").write_text(json.dumps(manifest, indent=2))
    return manifest
