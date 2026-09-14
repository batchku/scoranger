"""One arrangement, or one setlist, as a single file somebody can hand over.

design/FIREBASE.md §13. Principle 6 of §0: there must be a way to share without
internet or cloud. This is it, and it is the only part of the 0.7 line that
needs no account, no Firebase project and no network -- which is why it ships
before any of them.

A bundle is a zip:

    bundle.json                                    what is inside, and whose
    scores/<scoreUid>/<versionUid>.musicxml.gz     notation, compressed 24:1
    scores/<scoreUid>/<versionUid>.pdf             a scan, already compressed
    ink/<scoreUid>/<versionUid>/p<N>.pkdrawing     the reader's own markup

The payload here and the payload a shared setlist entry carries are the same
payload (§0.7). Writing it down first, and round-tripping it through a test, is
most of the reason this is increment one rather than increment four.

WHAT NEVER GOES IN, and it is not a setting: a book, and a source. §8.2 guard
rails 3 and 4. A fake book is the clearest redistribution risk in the library
and there is no legitimate in-app reason to send one to another person; a source
is somebody else's edition, imported for reference. Neither has an export path
anywhere, and `_refuse_books_and_sources` is called on the way in rather than
trusted to the caller.

WHAT IS RECORDED RATHER THAN REFUSED: whether an arrangement is the sharer's own
work or material that arrived from outside. §8.1 computes this from the version
chain -- a chain whose only ops are `import`, `import-pdf` or `book-extract`
carries no work of the sharer's -- and in the cloud that distinction decides
whether an entry ships bytes at all. A bundle always ships the bytes (§12.12: a
reference bundle is a file containing a list of titles, which nobody would
send), so here the classification is carried, shown by `bundle-inspect`, and
left for a person to act on. Whether it should ever BLOCK an AirDrop is §12.13,
and it is the owner's call, not this module's.
"""
from __future__ import annotations

import gzip
import json
import zipfile
from pathlib import Path

FORMAT = 1
SUFFIX = ".scorbundle"

#: Ops that only ever bring material IN. §8.1. A chain of nothing but these is
#: somebody else's music with none of the sharer's work on top of it.
ARRIVED_FROM_OUTSIDE = frozenset({"import", "import-pdf", "book-extract"})


def provenance(versions: list[dict]) -> str:
    """"arranged" if the sharer did work here, "imported" if it all came in.

    The same computation §8.1 specifies for the cloud rights gate, kept in one
    place so the two cannot drift. Deliberately conservative about the empty
    case: an arrangement with no versions has had no work done on it.
    """
    return ("arranged"
            if any(v.get("op") not in ARRIVED_FROM_OUTSIDE for v in versions)
            else "imported")


def _artifact_kind(filename: str) -> str:
    return "pdf" if filename.lower().endswith(".pdf") else "notation"


def _sha256(data: bytes) -> str:
    import hashlib

    return hashlib.sha256(data).hexdigest()


def _ink_files(ink_dir: Path | None, score_uid: str, version_id: str) -> list[tuple[int, Path]]:
    """The reader's markup for one version, as (page, file).

    Keyed the way `DrawingStore` keys it: "<namespace>/<version>/p<N>" with the
    slashes flattened to underscores. The namespace is the score's uid, which is
    the whole reason the re-key happened before this feature (§13.3) -- a slug
    means nothing on the device this bundle is opened on.
    """
    if ink_dir is None or not ink_dir.exists():
        return []
    prefix = f"{score_uid}_{version_id}_p"
    found = []
    for f in sorted(ink_dir.glob(f"{prefix}*.pkdrawing")):
        page = f.stem[len(prefix):]
        if page.isdigit():
            found.append((int(page), f))
    return sorted(found)


def _refuse_books_and_sources(target: str) -> None:
    """§8.2 guard rails 3 and 4, enforced here rather than trusted to callers.

    A book is the clearest redistribution risk in the library and there is no
    legitimate in-app reason to send one to another person. A source is somebody
    else's edition, imported for reference. Neither has an export path, and
    asking for one by name is an error rather than a silently empty bundle.
    """
    from . import workspace

    repo = workspace._repo()
    if repo.get_book(target) is not None:
        raise ValueError(
            f"'{target}' is a book. Books are never shared, in a bundle or "
            "anywhere else (design/FIREBASE.md §8.2). Extract an arrangement "
            "from it and share that.")


# -- export ----------------------------------------------------------------

def _score_payload(slug: str, full_history: bool, ink_dir: Path | None) -> tuple[dict, list]:
    """One arrangement as a bundle entry, plus the files it needs carried."""
    from . import workspace

    repo = workspace._repo()
    doc = repo.get_score(slug)
    if doc is None:
        raise FileNotFoundError(f"No arrangement '{slug}'")
    uid = doc.get("uid") or slug
    versions = repo.list_versions(slug)
    if not versions:
        raise ValueError(f"'{slug}' has no versions; there is nothing to send")

    # The pinned version, not the whole chain, unless asked. A bandmate needs
    # the chart; the arranging history is 24x the bytes and answers a question
    # they did not ask (§13.2).
    if not full_history:
        latest = doc.get("latest")
        chosen = [v for v in versions if v["id"] == latest] or versions[-1:]
    else:
        chosen = versions

    carried, entries = [], []
    for v in chosen:
        path = workspace.score_dir(slug) / v["file"]
        if not path.exists():
            raise FileNotFoundError(
                f"'{slug}' version {v.get('label') or v['id']} is missing its "
                f"artifact ({v['file']}); refusing to write a bundle with a hole in it")
        raw = path.read_bytes()
        kind = _artifact_kind(v["file"])
        name = (f"scores/{uid}/{v['id']}.musicxml.gz" if kind == "notation"
                else f"scores/{uid}/{v['id']}.pdf")
        # Notation is text and compresses about 24:1 (§1.2). A PDF is already
        # compressed and gzipping it buys nothing but CPU.
        carried.append((name, gzip.compress(raw, 9) if kind == "notation" else raw))
        entry = {k: v.get(k) for k in
                 ("id", "label", "seq", "op", "args", "parent", "time", "parts")}
        entry.update(kind=kind, bytes=len(raw), sha256=_sha256(raw), stored=name)
        entries.append(entry)

    ink = []
    for v in chosen:
        for page, f in _ink_files(ink_dir, uid, v["id"]):
            name = f"ink/{uid}/{v['id']}/p{page}.pkdrawing"
            carried.append((name, f.read_bytes()))
            ink.append({"version": v["id"], "page": page, "stored": name})

    payload = {
        "uid": uid, "slug": slug, "name": doc.get("name"),
        "title": doc.get("title"), "composer": doc.get("composer"),
        "arranger": doc.get("arranger"), "piece": doc.get("piece"),
        "latest": chosen[-1]["id"] if not full_history else doc.get("latest"),
        # Recorded, not enforced. §8.1 computes the same thing for the cloud
        # rights gate; here it rides along so `bundle-inspect` can say whose
        # work this is and a person can decide. §12.12, §12.13.
        "provenance": provenance(versions),
        "versions": entries,
        "ink": ink,
    }
    return payload, carried


def export(target: str, out_path, full_history: bool = False,
           ink_dir=None) -> dict:
    """An arrangement or a setlist as one file. Returns a report.

    `target` is a score slug or a setlist name/slug; a setlist wins only if no
    score answers to the name, because `arr:<slug>` is what chat means by a
    bare name everywhere else.
    """
    from . import workspace

    _refuse_books_and_sources(target)
    repo = workspace._repo()
    out = Path(out_path)
    if out.suffix != SUFFIX:
        out = out.with_suffix(SUFFIX)
    ink = Path(ink_dir) if ink_dir else None

    if repo.get_score(target) is not None:
        kind, slugs, setlist = "arrangement", [target], None
    else:
        doc = workspace.resolve_setlist(target)
        setlist = {"uid": doc.get("uid"), "name": doc["name"],
                   "slug": doc["slug"]}
        slugs = [s for s in doc.get("scores", []) if repo.get_score(s) is not None]
        kind = "setlist"
        if not slugs:
            raise ValueError(f"Setlist '{doc['name']}' has no arrangements in it")

    scores, carried, pieces = [], [], {}
    for slug in slugs:
        payload, files = _score_payload(slug, full_history, ink)
        scores.append(payload)
        carried.extend(files)
        if payload["piece"] and payload["piece"] not in pieces:
            p = repo.get_piece(payload["piece"])
            if p:
                pieces[p["slug"]] = {k: p.get(k) for k in
                                     ("uid", "slug", "name", "composer",
                                      "arranger", "tags")}

    manifest = {"format": FORMAT, "kind": kind, "exported": workspace._now(),
                "setlist": setlist, "pieces": list(pieces.values()),
                "scores": scores}

    out.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("bundle.json", json.dumps(manifest, indent=2))
        for name, data in carried:
            z.writestr(name, data)

    return {"path": str(out), "kind": kind, "bytes": out.stat().st_size,
            "arrangements": [{"name": s["title"] or s["name"],
                              "versions": len(s["versions"]),
                              "pages": sum(1 for _ in s["ink"]) or None,
                              "provenance": s["provenance"],
                              "ink_pages": len(s["ink"])} for s in scores],
            "setlist": setlist["name"] if setlist else None,
            "full_history": full_history}


# -- what a shared entry carries -------------------------------------------

def share_payload(slug: str, ink_dir=None) -> dict:
    """One arrangement, described for a SHARED SETLIST ENTRY.

    design/FIREBASE.md §4.2 and §0.7. A bundle entry and a shared entry carry
    the same thing -- a pinned version's bytes, its document and its ink -- and
    this is that description without the zip around it: the app uploads the
    file to `shared/{setlistId}/{entryId}/` and writes the rest as the entry
    document.

    It exists here rather than in Swift because the ENGINE is what knows what a
    score is: which version is pinned, where its artifact lives, whether the
    chain contains the sharer's own work. A second answer computed in the app
    would drift from `bundle.py`'s the first time either changed.

    The artifact is described, not read. A 52 MB book has no business passing
    through the bridge as base64, so the app opens the path itself.
    """
    from . import workspace

    _refuse_books_and_sources(slug)
    repo = workspace._repo()
    doc = repo.get_score(slug)
    if doc is None:
        raise FileNotFoundError(f"No arrangement '{slug}'")
    versions = repo.list_versions(slug)
    if not versions:
        raise ValueError(f"'{slug}' has no versions; there is nothing to share")

    latest = doc.get("latest")
    pinned = next((v for v in versions if v["id"] == latest), versions[-1])
    path = workspace.score_dir(slug) / pinned["file"]
    if not path.exists():
        raise FileNotFoundError(
            f"'{slug}' version {pinned.get('label') or pinned['id']} is missing "
            f"its artifact ({pinned['file']})")
    raw = path.read_bytes()
    uid = doc.get("uid") or slug

    return {
        "scoreUid": uid,
        "slug": slug,
        "title": doc.get("title") or doc.get("name"),
        "composer": doc.get("composer"),
        "arranger": doc.get("arranger"),
        # The version is PINNED (§6.1): an entry names a version, not a score,
        # so nobody's page reflows mid-gig because the arranger ran a transpose
        # in the car park.
        "versionUid": pinned["id"],
        "versionLabel": pinned.get("label"),
        "path": str(path),
        "kind": _artifact_kind(pinned["file"]),
        "bytes": len(raw),
        "sha256": _sha256(raw),
        # Recorded, not enforced (§12.13, settled: the owner's own purchased
        # material shares as a COPY, to named people, capped). The app shows it;
        # it blocks nothing.
        "provenance": provenance(versions),
        # Every page of the sharer's own markup on the pinned version, so the
        # app knows what to upload without listing the directory itself.
        "ink": [{"page": page, "path": str(f)}
                for page, f in _ink_files(Path(ink_dir) if ink_dir else None,
                                          uid, pinned["id"])],
    }


# -- inspect ---------------------------------------------------------------

def _read_manifest(path: Path) -> dict:
    with zipfile.ZipFile(path) as z:
        try:
            manifest = json.loads(z.read("bundle.json"))
        except KeyError:
            raise ValueError(f"{path.name} is not a Scoranger bundle "
                             "(no bundle.json inside)") from None
    if manifest.get("format") != FORMAT:
        raise ValueError(
            f"{path.name} was written in bundle format {manifest.get('format')} "
            f"and this app reads {FORMAT}")
    return manifest


def inspect(path) -> dict:
    """What is in a bundle, without importing any of it.

    The import screen is built from this: a person is told what they are about
    to take in -- titles, how many versions, whose markup, how big -- and asked.
    A file that lands in Files and imports itself is not something anyone asked
    for (§13.3).
    """
    p = Path(path)
    manifest = _read_manifest(p)
    return {
        "path": str(p), "kind": manifest["kind"],
        "exported": manifest.get("exported"),
        "bytes": p.stat().st_size,
        "setlist": (manifest.get("setlist") or {}).get("name"),
        "arrangements": [
            {"name": s.get("title") or s.get("name"),
             "composer": s.get("composer"),
             "versions": len(s["versions"]),
             "provenance": s.get("provenance"),
             "ink_pages": len(s.get("ink", []))}
            for s in manifest["scores"]],
    }


# -- import ----------------------------------------------------------------

def _free_slug(base: str) -> str:
    from . import workspace

    repo = workspace._repo()
    slug, n = base, 2
    while repo.get_score(slug) is not None:
        slug = f"{base}-{n}"
        n += 1
    return slug


def import_(path, into_piece: str | None = None, ink_dir=None) -> dict:
    """Take a bundle in as NEW local arrangements. Returns a report.

    Identity is minted fresh and the bundle's own uids are kept only as
    provenance. A uid is a claim on a document in a namespace, and two devices
    both holding `01J...7Q` for a score neither can see is exactly the collision
    stage 0 exists to prevent (§13.3).

    Nothing merges and nothing is overwritten. A bundle of something already in
    the library becomes a second arrangement, flagged in the report by
    `duplicate_of`, and the caller decides what to tell the reader. Merging two
    divergent version chains is §7 rule 2's fork problem and is not worth
    solving for a file that arrived over AirDrop.
    """
    from . import ids, workspace

    p = Path(path)
    manifest = _read_manifest(p)
    repo = workspace._repo()
    ink = Path(ink_dir) if ink_dir else None
    imported, duplicates = [], []

    with zipfile.ZipFile(p) as z:
        # pieces first, so an arrangement has somewhere to be filed
        piece_slugs: dict[str, str] = {}
        for doc in manifest.get("pieces", []):
            name = into_piece or doc.get("name")
            if not name:
                continue
            piece_slugs[doc["slug"]] = workspace.resolve_piece(
                name, create_if_missing=True)["slug"]

        for s in manifest["scores"]:
            title = s.get("title") or s.get("name") or "Untitled"
            existing = [d for d in repo.list_scores()
                        if (d.get("title") or d.get("name")) == title]
            slug = _free_slug(workspace.slugify(s.get("name") or title))
            score_uid = ids.new_id()
            directory = workspace.score_dir(slug)
            directory.mkdir(parents=True, exist_ok=True)

            remap: dict[str, str] = {}
            versions = []
            for v in s["versions"]:
                vid = ids.new_id()
                remap[v["id"]] = vid
                raw = z.read(v["stored"])
                if v["kind"] == "notation":
                    raw = gzip.decompress(raw)
                # The bytes are carried verbatim -- re-serialising through
                # music21 would produce a different file for the same music and
                # break the one thing a bundle promises.
                if v.get("sha256") and _sha256(raw) != v["sha256"]:
                    raise ValueError(
                        f"{p.name}: '{title}' version {v.get('label')} does not "
                        "match its checksum; the file is damaged")
                fname = f"{vid}.{'pdf' if v['kind'] == 'pdf' else 'musicxml'}"
                (directory / fname).write_bytes(raw)
                versions.append({
                    "id": vid, "seq": v.get("seq") or len(versions) + 1,
                    "label": v.get("label") or f"v{len(versions) + 1:03d}",
                    "file": fname, "op": v.get("op") or "import",
                    "args": v.get("args") or {},
                    "parent": None,          # rewritten below, once all ids exist
                    "time": v.get("time") or workspace._now(),
                    "parts": v.get("parts"),
                    "origin_version_uid": v["id"],
                })
            for new, old in zip(versions, s["versions"]):
                parent = old.get("parent")
                if parent in remap:
                    new["parent"] = remap[parent]

            repo.set_score(slug, {
                "id": slug, "slug": slug, "uid": score_uid,
                "name": s.get("name") or title, "title": title,
                "composer": s.get("composer"), "arranger": s.get("arranger"),
                "created": workspace._now(),
                "latest": remap.get(s.get("latest")) or versions[-1]["id"],
                "piece": piece_slugs.get(s.get("piece")),
                # Where this came from, kept so a later bundle from the same
                # source can be recognised as an update of it rather than a
                # third copy. Never used as a key.
                "origin_uid": s.get("uid"),
                "imported_from": p.name,
            })
            for v in versions:
                repo.add_version(slug, v["id"], v["seq"], v)

            pages = 0
            for entry in s.get("ink", []):
                vid = remap.get(entry["version"])
                if vid is None or ink is None:
                    continue
                ink.mkdir(parents=True, exist_ok=True)
                dest = ink / f"{score_uid}_{vid}_p{entry['page']}.pkdrawing"
                if dest.exists():
                    continue          # never overwrite live markup
                dest.write_bytes(z.read(entry["stored"]))
                pages += 1

            imported.append({"slug": slug, "title": title,
                             "versions": len(versions), "ink_pages": pages,
                             "provenance": s.get("provenance"),
                             "duplicate_of": existing[0]["slug"] if existing else None})
            if existing:
                duplicates.append(title)

    setlist = manifest.get("setlist")
    setlist_name = None
    if setlist and imported:
        setlist_name = setlist["name"]
        for entry in imported:
            workspace.add_score_to_setlist(setlist_name, entry["slug"],
                                           create_if_missing=True)

    workspace.rebuild_manifest()
    return {"kind": manifest["kind"], "setlist": setlist_name,
            "imported": imported, "duplicates": duplicates}
