"""Local document store backing the score library.

Deliberately modeled on Firestore so the backend swap is mechanical:

    scores/{id}                    -> score document
    scores/{id}/versions/{vid}     -> version document (subcollection)

Artifacts (the .musicxml files) live OUTSIDE the database and are referenced
by relative path — the same shape as Cloud Storage refs. To move to Firebase:
implement FirestoreRepository with this same interface, point artifact refs at
a Storage bucket, and replace the manifest.json projection with Firestore
listeners in the client. Documents are already plain JSON.
"""

import json
import sqlite3
import threading
from pathlib import Path


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
            self._conn.commit()

    # -- scores collection ------------------------------------------------

    def set_score(self, score_id: str, doc: dict) -> None:
        with self._lock:
            self._conn.execute(
                "INSERT INTO scores (id, doc) VALUES (?, ?)"
                " ON CONFLICT(id) DO UPDATE SET doc = excluded.doc",
                (score_id, json.dumps(doc)))
            self._conn.commit()

    def get_score(self, score_id: str) -> dict | None:
        row = self._conn.execute("SELECT doc FROM scores WHERE id = ?", (score_id,)).fetchone()
        return json.loads(row[0]) if row else None

    def list_scores(self) -> list[dict]:
        rows = self._conn.execute("SELECT doc FROM scores ORDER BY id").fetchall()
        return [json.loads(r[0]) for r in rows]

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

    # -- sources subcollection (other found editions of the same piece) -----

    def add_source(self, score_id: str, source_id: str, doc: dict) -> None:
        with self._lock:
            self._conn.execute(
                "INSERT INTO sources (score_id, id, doc) VALUES (?, ?, ?)",
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
        with self._lock:
            self._conn.execute(
                "INSERT INTO versions (score_id, id, seq, doc) VALUES (?, ?, ?, ?)",
                (score_id, version_id, seq, json.dumps(doc)))
            self._conn.commit()

    def get_version(self, score_id: str, version_id: str) -> dict | None:
        row = self._conn.execute(
            "SELECT doc FROM versions WHERE score_id = ? AND id = ?",
            (score_id, version_id)).fetchone()
        return json.loads(row[0]) if row else None

    def list_versions(self, score_id: str) -> list[dict]:
        rows = self._conn.execute(
            "SELECT doc FROM versions WHERE score_id = ? ORDER BY seq", (score_id,)).fetchall()
        return [json.loads(r[0]) for r in rows]
