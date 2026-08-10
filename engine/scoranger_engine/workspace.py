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
from datetime import datetime
from pathlib import Path

from .db import SqliteRepository

REPO_ROOT = Path(__file__).resolve().parents[2]
WORKSPACE = Path(os.environ.get("SCORANGER_WORKSPACE", REPO_ROOT / "workspace"))

_repo_singleton: SqliteRepository | None = None


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
    for doc in repo.list_scores():
        versions = repo.list_versions(doc["slug"])
        scores.append({
            "slug": doc["slug"], "name": doc["name"],
            "title": doc.get("title"), "composer": doc.get("composer"),
            "latest": doc.get("latest"), "versions": versions,
            "sources": repo.list_sources(doc["slug"]),
        })
    manifest = {"generated": _now(), "scores": scores}
    WORKSPACE.mkdir(parents=True, exist_ok=True)
    (WORKSPACE / "manifest.json").write_text(json.dumps(manifest, indent=2))
    return manifest
