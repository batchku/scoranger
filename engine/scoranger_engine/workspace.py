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
import tempfile
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


class NotNotationError(Exception):
    """Notation was asked of an arrangement whose artifact is not notation."""


#: Artifact suffixes the engine can actually operate on. Everything else is
#: something a reader can look at but no op can touch.
NOTATION_SUFFIXES = {".musicxml", ".xml", ".mxl", ".mid", ".midi"}


def list_versions(slug: str) -> list:
    return _repo().list_versions(slug)


def version_kind(slug: str, version_id: str | None = None) -> str:
    """"musicxml" or "pdf", from the artifact the version points at.

    DERIVED from the filename rather than stored on the document, so every
    version written before PDFs existed reports correctly with no migration
    and no backfill.
    """
    return artifact_kind(resolve_path(slug, version_id))


def artifact_kind(path) -> str:
    return "musicxml" if Path(path).suffix.lower() in NOTATION_SUFFIXES else "pdf"


def resolve_notation_path(slug: str, version_id: str | None = None) -> Path:
    """The artifact, when it is notation. Raises clearly when it is not.

    Both `cli._load` and the on-device `bridge._load` hand their path straight
    to music21, which would fail on a PDF several frames deep in a parser with
    nothing useful to say. A reader who imported a scan needs to be told that
    it is a scan and that OMR is what makes it editable.
    """
    path = resolve_path(slug, version_id)
    if artifact_kind(path) != "musicxml":
        raise NotNotationError(
            f"'{slug}' {version_id or 'latest'} is a PDF, not notation, so it "
            f"cannot be edited: run OMR on it to turn it into an editable "
            f"arrangement first.")
    return path


def _write_pdf_version(slug: str, pdf_path: Path, op: str, args: dict,
                       parent: str | None) -> dict:
    """A version whose artifact is the PDF itself, copied in unchanged.

    Nothing re-encodes it: what a reader looks at is the file they gave us.
    """
    import shutil

    repo = _repo()
    seq = len(repo.list_versions(slug)) + 1
    vid = f"v{seq:03d}"
    fname = f"{vid}.pdf"
    score_dir(slug).mkdir(parents=True, exist_ok=True)
    shutil.copyfile(pdf_path, score_dir(slug) / fname)
    # `parts` is [] and not a guess: a PDF has no parts until OMR reads it, and
    # inventing one would put a lie in the library.
    doc = {"id": vid, "seq": seq, "file": fname, "op": op, "args": args,
           "parent": parent, "time": _now(), "parts": []}
    if _current_turn is not None and _current_turn["slug"] == slug:
        doc["turn"] = {"id": _current_turn["id"], "prompt": _current_turn["prompt"]}
    repo.add_version(slug, vid, seq, doc)
    score_doc = repo.get_score(slug)
    score_doc["latest"] = vid
    repo.set_score(slug, score_doc)
    rebuild_manifest()
    return doc


def books_dir() -> Path:
    return WORKSPACE / "books"


def book_path(slug: str) -> Path:
    return books_dir() / f"{slug}.pdf"


def list_books() -> list:
    return _repo().list_books()


def create_book(name: str, pdf_path) -> tuple[str, dict]:
    """Store a PDF as a BOOK: a collection arrangements are taken out of.

    A book is not a piece and not an arrangement. A fake book is one file
    holding hundreds of tunes; filing it as an arrangement would put all of
    them under one title, and filing it as a piece would claim it is one
    composition. It is neither -- it is a place to take pieces FROM.
    """
    import shutil

    from pypdf import PdfReader

    source = Path(pdf_path)
    if not source.exists():
        raise FileNotFoundError(f"No such file: {source}")
    if artifact_kind(source) != "pdf":
        raise ValueError(f"{source.name} is not a PDF")

    repo = _repo()
    base = slugify(name)
    slug, n = base, 2
    while repo.get_book(slug) is not None:
        slug = f"{base}-{n}"
        n += 1
    books_dir().mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, book_path(slug))
    doc = {"id": slug, "slug": slug, "name": name,
           "pages": len(PdfReader(str(book_path(slug))).pages),
           "created": _now()}
    repo.set_book(slug, doc)
    rebuild_manifest()
    return slug, doc


def delete_book(slug: str) -> None:
    _repo().delete_book(slug)
    book_path(slug).unlink(missing_ok=True)
    rebuild_manifest()


def extract_from_book(slug: str, from_page: int, to_page: int, name: str,
                      piece: str | None = None) -> tuple[str, dict]:
    """Take pages out of a book as a new PDF arrangement.

    Page numbers are 1-based and inclusive, as printed. The pages are COPIED:
    a book is a reference and taking a tune out of it must not cut it up.

    The result is an ordinary PDF arrangement, so everything that already works
    for a scan works for it -- it reads, it takes Pencil markup, and OMR can
    turn it into notation.
    """
    from pypdf import PdfReader, PdfWriter

    doc = _repo().get_book(slug)
    if doc is None:
        have = [b["slug"] for b in _repo().list_books()]
        raise FileNotFoundError(f"No book '{slug}'. Have: {have}")
    total = int(doc.get("pages") or 0)
    if from_page < 1 or to_page > total or from_page > to_page:
        raise ValueError(
            f"pages {from_page}-{to_page} are not in '{doc['name']}', "
            f"which has pages 1-{total}")

    reader = PdfReader(str(book_path(slug)))
    writer = PdfWriter()
    for index in range(from_page - 1, to_page):
        writer.add_page(reader.pages[index])
    staging = Path(tempfile.mkdtemp()) / f"{slugify(name)}.pdf"
    with open(staging, "wb") as f:
        writer.write(f)

    score_slug, entry = create_pdf_score(
        name, staging, op="book-extract",
        args={"book": slug, "pages": f"{from_page}-{to_page}"})
    if piece:
        assign_score_to_piece(score_slug, piece, create_if_missing=True)
    rebuild_manifest()
    return score_slug, entry


def create_pdf_score(name: str, pdf_path, op: str = "import-pdf",
                     args: dict | None = None) -> tuple[str, dict]:
    """Create an arrangement whose artifact is a PDF. Returns (slug, version doc).

    It reads, it takes Pencil markup and it sits in the library like anything
    else; what it cannot do is be edited, because selection, addresses and
    every op come from the engraved MEI that only notation has.
    """
    source = Path(pdf_path)
    if not source.exists():
        raise FileNotFoundError(f"No such file: {source}")
    if artifact_kind(source) != "pdf":
        raise ValueError(f"{source.name} is not a PDF")

    repo = _repo()
    base = slugify(name)
    slug, n = base, 2
    while repo.get_score(slug) is not None:
        slug = f"{base}-{n}"
        n += 1
    repo.set_score(slug, {
        "id": slug, "slug": slug, "name": name,
        # the file carries no metadata we can read, so the title is the name
        # the caller gave -- never a slug, never the file name
        "title": name, "composer": None, "arranger": None,
        "created": _now(), "latest": None,
    })
    # same rule as create_score: an arrangement holding no version must not
    # exist, so the row goes if the artifact does not land
    try:
        entry = _write_pdf_version(slug, source, op, args or {}, parent=None)
    except BaseException:
        import shutil
        repo.delete_score(slug)
        if score_dir(slug).exists():
            shutil.rmtree(score_dir(slug), ignore_errors=True)
        rebuild_manifest()
        raise
    return slug, entry


def _write_musicxml(m21_score, path: Path) -> list[str]:
    """The one place a score becomes a file.

    `makeTies` first: it splits any note running past its barline and ties it.
    Some ops leave such notes behind (`stripTies` produces them by design), and
    music21's MusicXML writer emits an over-long note AND the bars it swallows,
    duplicating that time and shifting everything after it. Splitting here is
    the fix that makes the write correct rather than merely checked.

    The file is then written to one side, read back, and moved into place. The
    read-back reports whatever odd bars the music has -- as WARNINGS, returned
    to the caller and recorded on the version. It never refuses.

    There was a refusal here once, and it was the wrong mechanism twice over:
    it blocked importing a scanned score whose bars were imperfect, and then
    blocked adding a repeat to a score that had inherited such a bar -- a bar
    the repeat never touched. Detecting damage after the fact and refusing to
    save is a band-aid over a transformation that should not damage anything.
    Correctness belongs in the ops, and the proof that they are correct belongs
    in engine/scripts/check_rhythm.py, which runs before a release rather than
    standing between a user and their own music.

    Returns the odd bars the written file has, phrased for a person.
    """
    from music21 import converter, stream as m21stream

    for part in (m21_score.parts or []):
        if part.getElementsByClass(m21stream.Measure):
            part.makeTies(inPlace=True)

    # keep the .musicxml suffix: music21 picks its parser from the extension
    staging = path.with_name(path.stem + ".writing" + path.suffix)
    m21_score.write("musicxml", fp=str(staging))
    text = staging.read_text(encoding="utf-8")
    cleaned = _M21_COMPOSER_STAMP.sub("", text)
    if cleaned != text:
        staging.write_text(cleaned, encoding="utf-8")

    from . import ops
    faults = ops.rhythm_faults(converter.parse(str(staging), forceSource=True))
    staging.replace(path)
    return [f"part {p} bar {b}: {w}" for p, b, w in faults]


def _write_version(slug: str, m21_score, op: str, args: dict, parent: str | None) -> dict:
    from . import ops

    repo = _repo()
    seq = len(repo.list_versions(slug)) + 1
    vid = f"v{seq:03d}"
    fname = f"{vid}.musicxml"
    score_dir(slug).mkdir(parents=True, exist_ok=True)
    warnings = _write_musicxml(m21_score, score_dir(slug) / fname)
    doc = {"id": vid, "seq": seq, "file": fname, "op": op, "args": args,
           "parent": parent, "time": _now(), "parts": _parts_snapshot(m21_score)}
    if warnings:
        # kept on the version so the app can say "this came in with 3 odd bars"
        # rather than the user discovering it while playing
        doc["rhythm_warnings"] = warnings
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
    # An arrangement that holds no music must not exist. The row has to be
    # written first -- _write_version updates it -- so if the version does not
    # land, the row goes with it. Without this, anything that interrupted the
    # write (a disk error, a parse failure building the parts snapshot, the app
    # being killed) left an arrangement of zero versions in the library, which
    # has no version to display and so sat on "Opening…" for ever.
    try:
        entry = _write_version(slug, m21_score, op, args or {}, parent=None)
    except BaseException:
        import shutil
        repo.delete_score(slug)
        if score_dir(slug).exists():
            shutil.rmtree(score_dir(slug), ignore_errors=True)
        rebuild_manifest()
        raise
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
    # through the guarded write, not a bare one: a source is pulled from later,
    # so a source written with a corrupted rhythm hands that corruption to
    # every arrangement that pulls a part out of it
    _write_musicxml(m21_score, src_dir / fname)
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
    # the piece this arrangement just left may now hold nothing
    _drop_empty_pieces(keep=piece_slug)
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


def tidy_pieces() -> list[str]:
    """Drop pieces left holding nothing by an older build. Returns their names."""
    repo = _repo()
    held = {d.get("piece") for d in repo.list_scores() if d.get("piece")}
    gone = [p["name"] for p in repo.list_pieces() if p["slug"] not in held]
    _drop_empty_pieces()
    if gone:
        rebuild_manifest()
    return gone


def delete_piece(name_or_slug: str, with_arrangements: bool = False) -> None:
    """Delete a piece.

    With `with_arrangements`, its arrangements go too -- which is what deleting
    a folder means to the person doing it. Without, they are unfiled, and the
    piece goes because a piece holding nothing is not allowed to exist.
    """
    doc = resolve_piece(name_or_slug)
    members = [d["slug"] for d in _repo().list_scores() if d.get("piece") == doc["slug"]]
    if with_arrangements:
        for slug in members:
            delete_score(slug)
    else:
        for slug in members:
            assign_score_to_piece(slug, None)
    _repo().delete_piece(doc["slug"])
    _drop_empty_pieces()
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


def set_setlist_order(name_or_slug: str, order: list) -> dict:
    """Set a set list's running order. Every slug must already be in it.

    One reorder rather than a remove and a re-add: the latter would drop the
    arrangement to the end and lose the position of everything after it, which
    is the opposite of what "move up" means.
    """
    doc = resolve_setlist(name_or_slug)
    members = set(doc.get("scores") or [])
    bad = [s for s in order if s not in members]
    if bad:
        raise ValueError(f"Not in '{doc['slug']}': {bad}. Members: {sorted(members)}")
    doc["scores"] = list(order)
    _repo().set_setlist(doc["slug"], doc)
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


# How long a deleted thing stays recoverable. The UI offers an undo bar for
# ~10s; the engine keeps it a little longer so a slow tap still lands.
UNDO_WINDOW_SECONDS = 30


def delete_score(slug: str, immediate: bool = False) -> None:
    """Delete an arrangement, and the piece with it if it was the last one.

    A piece does not exist without at least one arrangement. It is a folder for
    arrangements, not a thing in its own right: an empty one can be neither
    opened (opening a piece means opening one of its arrangements) nor deleted
    through the UI, because the UI deletes a piece BY deleting its contents --
    and an empty piece has none. Ali hit exactly that: a piece showing "0
    arrangements" that would not go away.

    Deleting is TWO PHASES. The row is marked and disappears from the library
    at once, but its artifacts stay on disk for `UNDO_WINDOW_SECONDS` so the
    undo bar can put it back exactly as it was -- versions, sources, annotations
    and all. `sweep()` is what actually reclaims. `immediate=True` skips the
    window, for callers that mean it (a test, or a sweep of something already
    marked).

    Marking rather than copying: an arrangement is a directory of MusicXML and
    a row of history, and duplicating that to hold it in reserve would be both
    slow and a second source of truth.
    """
    import shutil
    load_meta(slug)  # raises with available slugs if missing
    if immediate:
        _repo().delete_score(slug)
        if score_dir(slug).exists():
            shutil.rmtree(score_dir(slug))
        _drop_empty_pieces()
        rebuild_manifest()
        return
    doc = _repo().get_score(slug) or {}
    doc["deleted_at"] = _now()
    _repo().set_score(slug, doc)
    _drop_empty_pieces()
    rebuild_manifest()


def restore_score(slug: str) -> dict:
    """Put a marked arrangement back, with everything it had."""
    repo = _repo()
    doc = repo.get_score(slug)
    if doc is None:
        raise FileNotFoundError(f"No score '{slug}' to restore.")
    if not doc.pop("deleted_at", None):
        return doc          # never deleted; restoring is a no-op, not an error
    repo.set_score(slug, doc)
    rebuild_manifest()
    return doc


def sweep(now: str | None = None) -> list[str]:
    """Reclaim anything whose undo window has passed. Returns what went.

    Called on launch and after each delete. Until this runs the artifacts are
    still on disk, which is exactly what makes undo possible.
    """
    from datetime import datetime, timedelta
    repo = _repo()
    cutoff = datetime.fromisoformat(now or _now()) - timedelta(seconds=UNDO_WINDOW_SECONDS)
    gone = []
    for doc in list(repo.list_scores(include_deleted=True)):
        stamp = doc.get("deleted_at")
        if not stamp:
            continue
        try:
            when = datetime.fromisoformat(stamp)
        except ValueError:
            when = cutoff       # unparseable: treat as expired rather than immortal
        if when <= cutoff:
            delete_score(doc["slug"], immediate=True)
            gone.append(doc["slug"])
    if gone:
        rebuild_manifest()
    return gone


def _drop_empty_pieces(keep: str | None = None) -> None:
    """Remove any piece left holding nothing.

    Called where an arrangement LEAVES a piece -- deleted, or re-filed -- and
    never on a plain rebuild: a piece is legitimately empty for the instant
    between being created and its first arrangement arriving, which is exactly
    what "new piece, then import into it" does. `keep` protects that piece.
    """
    repo = _repo()
    held = {d.get("piece") for d in repo.list_scores() if d.get("piece")}
    for piece in repo.list_pieces():
        if piece["slug"] not in held and piece["slug"] != keep:
            repo.delete_piece(piece["slug"])


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


def set_piece_metadata(slug: str, composer: str | None = None,
                       tags: list[str] | None = None,
                       arranger: str | None = None) -> dict:
    """Write a piece's own metadata. Only the fields passed are touched.

    Composer lives HERE as well as in the notation, and for most of this
    library it can only live here: an arrangement imported as a PDF has no
    notation to write a composer into, so a score brought in as a scan could
    never be credited at all. The piece is the thing a person credits anyway --
    the tune has a composer; a particular chart of it does not have a different
    one.

    Tags are a flat set on the piece: origin and tradition, in practice
    ("Serbia", "Bulgaria", "Macedonia"). They are deduplicated and their order
    is kept, because the first one a person types is the one they think of
    first. An empty list clears them; None leaves them alone.
    """
    repo = _repo()
    doc = repo.get_piece(slug)
    if doc is None:
        raise KeyError(f"no piece {slug!r}")
    if composer is not None:
        doc["composer"] = composer.strip() or None
    if arranger is not None:
        # Where a credit that is not a composer belongs: "interpretare: X
        # transcript: Y" is a performer and a transcriber, and putting that in
        # the composer field says the tune was written by them.
        doc["arranger"] = arranger.strip() or None
    if tags is not None:
        seen, kept = set(), []
        for t in tags:
            t = str(t).strip()
            if t and t.lower() not in seen:
                seen.add(t.lower())
                kept.append(t)
        doc["tags"] = kept
    repo.set_piece(slug, doc)
    rebuild_manifest()
    return doc


def all_tags() -> list[str]:
    """Every tag in use, by falling frequency then alphabetically.

    What the library's filter is built from: a tag exists because a piece
    carries it, so there is no separate vocabulary to keep in step.
    """
    counts: dict[str, tuple[int, str]] = {}
    for p in _repo().list_pieces():
        for t in p.get("tags") or []:
            n, spelling = counts.get(t.lower(), (0, t))
            counts[t.lower()] = (n + 1, spelling)
    return [spelling for _, (n, spelling) in
            sorted(counts.items(), key=lambda kv: (-kv[1][0], kv[1][1].lower()))]


def rebuild_manifest() -> dict:
    """Project the DB into workspace/manifest.json for the viewer."""
    repo = _repo()
    scores = []
    score_docs = repo.list_scores()
    for doc in score_docs:
        versions = repo.list_versions(doc["slug"])
        for v in versions:
            # derived from the artifact, so versions written before PDFs
            # existed report correctly without a backfill
            v["kind"] = artifact_kind(v.get("file") or "")
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
                       "composer": p.get("composer"),
                       "arranger": p.get("arranger"),
                       "tags": p.get("tags") or [],
                       "arrangements": ordered + stragglers})
    known = {d["slug"] for d in score_docs}
    setlists = []
    for doc in sorted(repo.list_setlists(), key=lambda x: x["name"].lower()):
        doc = _setlist_with_scores(doc, pieces)
        setlists.append({"slug": doc["slug"], "name": doc["name"],
                         "arrangements": [s for s in doc.get("scores") or []
                                          if s in known]})
    books = [{"slug": b["slug"], "name": b["name"], "pages": b.get("pages")}
             for b in sorted(repo.list_books(), key=lambda x: x["name"].lower())]
    manifest = {"generated": _now(), "scores": scores, "pieces": pieces,
                "setlists": setlists, "books": books}
    WORKSPACE.mkdir(parents=True, exist_ok=True)
    (WORKSPACE / "manifest.json").write_text(json.dumps(manifest, indent=2))
    return manifest
