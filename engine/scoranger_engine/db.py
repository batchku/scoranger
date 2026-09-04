"""Local document store backing the score library.

Document-shaped, not table-shaped:

    scores/{slug}                  -> score document
    scores/{slug}/versions/{id}    -> version document (subcollection)

Artifacts (the .musicxml and .pdf files) live OUTSIDE the database and are
referenced by relative filename. Documents are plain JSON.

This store stays authoritative for the device. It is NOT a cache of a remote
database, and the way to Firebase is not a `FirestoreRepository` implementing
this interface: the engine runs on-device, and a shipped client cannot hold the
service-account credentials a server SDK needs. Sync belongs beside the engine,
in Swift, mirroring these documents upward. See design/FIREBASE.md §2.

`Repository` exists so that mirror can wrap this one and record what changed
without `workspace.py` knowing.
"""

import json
import sqlite3
import threading
from pathlib import Path
from typing import Protocol, runtime_checkable


@runtime_checkable
class Repository(Protocol):
    """What `workspace.py` needs of a document store.

    Stated as a protocol so `workspace._repo()` has something to be given other
    than the concrete class. The intended second implementation is a decorator
    that wraps SqliteRepository and journals every write for the sync layer,
    not a replacement store.
    """

    def set_score(self, score_id: str, doc: dict) -> None: ...
    def get_score(self, score_id: str, include_deleted: bool = True) -> dict | None: ...
    def list_scores(self, include_deleted: bool = False) -> list[dict]: ...
    def count_scores(self) -> int: ...
    def delete_score(self, score_id: str) -> None: ...
    def set_piece(self, piece_id: str, doc: dict) -> None: ...
    def get_piece(self, piece_id: str) -> dict | None: ...
    def list_pieces(self) -> list[dict]: ...
    def delete_piece(self, piece_id: str) -> None: ...
    def set_setlist(self, setlist_id: str, doc: dict) -> None: ...
    def get_setlist(self, setlist_id: str) -> dict | None: ...
    def list_setlists(self) -> list[dict]: ...
    def delete_setlist(self, setlist_id: str) -> None: ...
    def set_book(self, book_id: str, doc: dict) -> None: ...
    def get_book(self, book_id: str) -> dict | None: ...
    def list_books(self) -> list[dict]: ...
    def delete_book(self, book_id: str) -> None: ...
    def add_source(self, score_id: str, source_id: str, doc: dict) -> None: ...
    def get_source(self, score_id: str, source_id: str) -> dict | None: ...
    def list_sources(self, score_id: str) -> list[dict]: ...
    def add_version(self, score_id: str, version_id: str, seq: int, doc: dict) -> None: ...
    def get_version(self, score_id: str, version_id: str) -> dict | None: ...
    def list_versions(self, score_id: str) -> list[dict]: ...
    def delete_version(self, score_id: str, version_id: str) -> None: ...


class SqliteRepository:
    def __init__(self, path: Path):
        self._conn = sqlite3.connect(str(path), check_same_thread=False)
        self._lock = threading.Lock()
        with self._lock:
            self._conn.execute(
                "CREATE TABLE IF NOT EXISTS scores (id TEXT PRIMARY KEY, doc TEXT NOT NULL)")
            self._conn.execute(
                "CREATE TABLE IF NOT EXISTS versions ("
                " score_id TEXT NOT NULL, id TEXT NOT NULL, seq INTEGER NOT NULL,"
                " doc TEXT NOT NULL, PRIMARY KEY (score_id, id))")
            self._conn.execute(
                "CREATE TABLE IF NOT EXISTS sources ("
                " score_id TEXT NOT NULL, id TEXT NOT NULL,"
                " doc TEXT NOT NULL, PRIMARY KEY (score_id, id))")
            self._conn.execute(
                "CREATE TABLE IF NOT EXISTS pieces (id TEXT PRIMARY KEY, doc TEXT NOT NULL)")
            self._conn.execute(
                "CREATE TABLE IF NOT EXISTS setlists (id TEXT PRIMARY KEY, doc TEXT NOT NULL)")
            self._conn.execute(
                "CREATE TABLE IF NOT EXISTS books (id TEXT PRIMARY KEY, doc TEXT NOT NULL)")
            self._conn.commit()

    # -- scores collection ------------------------------------------------

    def set_score(self, score_id: str, doc: dict) -> None:
        with self._lock:
            self._conn.execute(
                "INSERT INTO scores (id, doc) VALUES (?, ?)"
                " ON CONFLICT(id) DO UPDATE SET doc = excluded.doc",
                (score_id, json.dumps(doc)))
            self._conn.commit()

    def get_score(self, score_id: str, include_deleted: bool = True) -> dict | None:
        row = self._conn.execute("SELECT doc FROM scores WHERE id = ?", (score_id,)).fetchone()
        return json.loads(row[0]) if row else None

    def list_scores(self, include_deleted: bool = False) -> list[dict]:
        """Every score. Ones marked for deletion are hidden by default.

        A two-phase delete keeps the row until its undo window passes, so
        everything that lists scores would otherwise still see it -- the
        library, the manifest, the piece membership counts. Only the sweep and
        a restore ask for them.
        """
        rows = self._conn.execute("SELECT doc FROM scores ORDER BY id").fetchall()
        docs = [json.loads(r[0]) for r in rows]
        return docs if include_deleted else [d for d in docs if not d.get("deleted_at")]

    def count_scores(self) -> int:
        return self._conn.execute("SELECT COUNT(*) FROM scores").fetchone()[0]

    def delete_score(self, score_id: str) -> None:
        with self._lock:
            self._conn.execute("DELETE FROM versions WHERE score_id = ?", (score_id,))
            self._conn.execute("DELETE FROM sources WHERE score_id = ?", (score_id,))
            self._conn.execute("DELETE FROM scores WHERE id = ?", (score_id,))
            self._conn.commit()

    # -- pieces collection --------------------------------------------------

    def set_piece(self, piece_id: str, doc: dict) -> None:
        with self._lock:
            self._conn.execute(
                "INSERT INTO pieces (id, doc) VALUES (?, ?)"
                " ON CONFLICT(id) DO UPDATE SET doc = excluded.doc",
                (piece_id, json.dumps(doc)))
            self._conn.commit()

    def get_piece(self, piece_id: str) -> dict | None:
        row = self._conn.execute("SELECT doc FROM pieces WHERE id = ?", (piece_id,)).fetchone()
        return json.loads(row[0]) if row else None

    def list_pieces(self) -> list[dict]:
        rows = self._conn.execute("SELECT doc FROM pieces ORDER BY id").fetchall()
        return [json.loads(r[0]) for r in rows]

    def delete_piece(self, piece_id: str) -> None:
        with self._lock:
            self._conn.execute("DELETE FROM pieces WHERE id = ?", (piece_id,))
            self._conn.commit()

    # -- books collection (a collection arrangements are taken OUT of) --------

    def set_book(self, book_id: str, doc: dict) -> None:
        with self._lock:
            self._conn.execute(
                "INSERT INTO books (id, doc) VALUES (?, ?)"
                " ON CONFLICT(id) DO UPDATE SET doc = excluded.doc",
                (book_id, json.dumps(doc)))
            self._conn.commit()

    def get_book(self, book_id: str) -> dict | None:
        row = self._conn.execute("SELECT doc FROM books WHERE id = ?", (book_id,)).fetchone()
        return json.loads(row[0]) if row else None

    def list_books(self) -> list[dict]:
        rows = self._conn.execute("SELECT doc FROM books ORDER BY id").fetchall()
        return [json.loads(r[0]) for r in rows]

    def delete_book(self, book_id: str) -> None:
        with self._lock:
            self._conn.execute("DELETE FROM books WHERE id = ?", (book_id,))
            self._conn.commit()

    # -- setlists collection (ordered groups of pieces) ----------------------

    def set_setlist(self, setlist_id: str, doc: dict) -> None:
        with self._lock:
            self._conn.execute(
                "INSERT INTO setlists (id, doc) VALUES (?, ?)"
                " ON CONFLICT(id) DO UPDATE SET doc = excluded.doc",
                (setlist_id, json.dumps(doc)))
            self._conn.commit()

    def get_setlist(self, setlist_id: str) -> dict | None:
        row = self._conn.execute(
            "SELECT doc FROM setlists WHERE id = ?", (setlist_id,)).fetchone()
        return json.loads(row[0]) if row else None

    def list_setlists(self) -> list[dict]:
        rows = self._conn.execute("SELECT doc FROM setlists ORDER BY id").fetchall()
        return [json.loads(r[0]) for r in rows]

    def delete_setlist(self, setlist_id: str) -> None:
        with self._lock:
            self._conn.execute("DELETE FROM setlists WHERE id = ?", (setlist_id,))
            self._conn.commit()

    # -- sources subcollection (other found editions of the same piece) -----

    def add_source(self, score_id: str, source_id: str, doc: dict) -> None:
        # upsert, like every other set_*: the caller supplies the key, so
        # writing the same key twice means "this document changed"
        with self._lock:
            self._conn.execute(
                "INSERT INTO sources (score_id, id, doc) VALUES (?, ?, ?)"
                " ON CONFLICT(score_id, id) DO UPDATE SET doc = excluded.doc",
                (score_id, source_id, json.dumps(doc)))
            self._conn.commit()

    def get_source(self, score_id: str, source_id: str) -> dict | None:
        row = self._conn.execute(
            "SELECT doc FROM sources WHERE score_id = ? AND id = ?",
            (score_id, source_id)).fetchone()
        return json.loads(row[0]) if row else None

    def list_sources(self, score_id: str) -> list[dict]:
        rows = self._conn.execute(
            "SELECT doc FROM sources WHERE score_id = ? ORDER BY id", (score_id,)).fetchall()
        return [json.loads(r[0]) for r in rows]

    # -- versions subcollection -------------------------------------------

    def add_version(self, score_id: str, version_id: str, seq: int, doc: dict) -> None:
        # upsert: a version's CONTENT is immutable, but its document is
        # rewritten in place when a pointer inside it has to be repaired (the
        # id migration rewrites `parent`). Failing there would abort a
        # migration halfway, which is the one thing it must never do.
        with self._lock:
            self._conn.execute(
                "INSERT INTO versions (score_id, id, seq, doc) VALUES (?, ?, ?, ?)"
                " ON CONFLICT(score_id, id) DO UPDATE SET"
                " seq = excluded.seq, doc = excluded.doc",
                (score_id, version_id, seq, json.dumps(doc)))
            self._conn.commit()

    def get_version(self, score_id: str, version_id: str) -> dict | None:
        row = self._conn.execute(
            "SELECT doc FROM versions WHERE score_id = ? AND id = ?",
            (score_id, version_id)).fetchone()
        return json.loads(row[0]) if row else None

    def list_versions(self, score_id: str) -> list[dict]:
        # (seq, id) and not seq alone: two versions can share a seq once two
        # devices append to the same parent, and `latest_version` takes the
        # last row, so an unstable order would make "latest" flap between them.
        rows = self._conn.execute(
            "SELECT doc FROM versions WHERE score_id = ? ORDER BY seq, id",
            (score_id,)).fetchall()
        return [json.loads(r[0]) for r in rows]

    def delete_version(self, score_id: str, version_id: str) -> None:
        with self._lock:
            self._conn.execute(
                "DELETE FROM versions WHERE score_id = ? AND id = ?",
                (score_id, version_id))
            self._conn.commit()
