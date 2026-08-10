"""Tiny local API server — the seam where a real backend slots in later.

The viewer talks to this for anything that mutates the library (today: import).
In the Firebase deployment this becomes Cloud Run endpoints; the routes and
payloads are designed to survive that move.

Run with:  scor serve  (default port 8765; the Vite dev server proxies /api)
"""

import json
import re
import tempfile
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

from . import ops, workspace

ALLOWED_SUFFIXES = {".musicxml", ".xml", ".mxl", ".mid", ".midi"}
MAX_UPLOAD = 50 * 1024 * 1024


class Handler(BaseHTTPRequestHandler):
    server_version = "scoranger/0.1"

    def _json(self, status: int, payload: dict) -> None:
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):  # quiet request log to stderr, one line
        print(f"[serve] {self.address_string()} {fmt % args}")

    def do_GET(self):
        url = urlparse(self.path)
        if url.path == "/api/scores":
            self._json(200, workspace.rebuild_manifest())
        elif url.path == "/api/health":
            self._json(200, {"ok": True})
        elif url.path == "/api/export":
            self._export(url)
        else:
            self._json(404, {"error": f"no route {url.path}"})

    def _export(self, url):
        import tempfile
        try:
            q = parse_qs(url.query)
            slug = (q.get("score") or [None])[0]
            if not slug:
                raise ValueError("missing ?score=")
            version = (q.get("version") or [None])[0]
            fmt = (q.get("format") or ["pdf"])[0]
            if fmt not in ("pdf", "musicxml", "midi"):
                raise ValueError(f"format must be pdf|musicxml|midi, got '{fmt}'")
            parts_q = (q.get("parts") or [""])[0]
            parts = [p for p in parts_q.split(",") if p.strip()] or None

            meta = workspace.load_meta(slug)
            vid = version or meta["latest"]
            suffix = {"pdf": ".pdf", "musicxml": ".musicxml", "midi": ".mid"}[fmt]
            with tempfile.NamedTemporaryFile(suffix=suffix, delete=False) as tmp:
                out = tmp.name
            if fmt == "pdf":
                from . import render
                title = meta["name"] + (f" — {', '.join(parts)}" if parts else "")
                render.render_pdf(workspace.resolve_path(slug, vid), out, parts=parts, title=title)
            else:
                from music21 import converter
                s = converter.parse(str(workspace.resolve_path(slug, vid)), forceSource=True)
                if parts:
                    ops.keep_parts(s, parts)
                s.write(fmt, fp=out)
            data = Path(out).read_bytes()
            tag = "" if not parts else "-" + "-".join(workspace.slugify(p) for p in parts)
            fname = f"{slug}-{vid}{tag}{suffix}"
            ctype = {"pdf": "application/pdf", "musicxml": "application/vnd.recordare.musicxml+xml",
                     "midi": "audio/midi"}[fmt]
            self.send_response(200)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Disposition", f'attachment; filename="{fname}"')
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
        except Exception as e:
            self._json(400, {"error": f"{type(e).__name__}: {e}"})

    def do_POST(self):
        url = urlparse(self.path)
        if url.path != "/api/import":
            self._json(404, {"error": f"no route {url.path}"})
            return
        try:
            q = parse_qs(url.query)
            filename = (q.get("filename") or ["upload.musicxml"])[0]
            suffix = Path(filename).suffix.lower()
            if suffix not in ALLOWED_SUFFIXES:
                raise ValueError(f"Unsupported file type '{suffix}'. Allowed: {sorted(ALLOWED_SUFFIXES)}")
            name = (q.get("name") or [Path(filename).stem])[0]
            name = re.sub(r"\s+", " ", name).strip() or Path(filename).stem

            length = int(self.headers.get("Content-Length", "0"))
            if not 0 < length <= MAX_UPLOAD:
                raise ValueError(f"Upload size {length} outside limits")
            data = self.rfile.read(length)

            from music21 import converter
            with tempfile.NamedTemporaryFile(suffix=suffix, delete=False) as tmp:
                tmp.write(data)
                tmp_path = tmp.name
            m21_score = converter.parse(tmp_path, forceSource=True)
            if m21_score.metadata is not None and not m21_score.metadata.title:
                m21_score.metadata.title = name
            slug, entry = workspace.create_score(name, m21_score, op="import",
                                                 args={"source": f"upload:{filename}"})
            self._json(200, {"score": slug, "name": name, "version": entry["id"],
                             "parts": entry.get("parts")})
        except Exception as e:
            self._json(400, {"error": f"{type(e).__name__}: {e}"})


def serve(port: int = 8765) -> None:
    httpd = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    print(f"scoranger engine API on http://127.0.0.1:{port} (Ctrl-C to stop)")
    httpd.serve_forever()
