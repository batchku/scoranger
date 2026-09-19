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

# Read from the engine rather than typed again: this list was a copy, and a
# format added to the engine was rejected by the viewer until someone
# remembered this line. `.abc` is in it now because that is where it belongs.
ALLOWED_SUFFIXES = set(workspace.NOTATION_SUFFIXES)
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

    def _transpose(self, url):
        try:
            q = parse_qs(url.query)
            slug = (q.get("score") or [None])[0]
            semitones = int((q.get("semitones") or ["0"])[0])
            if not slug or not -24 <= semitones <= 24 or semitones == 0:
                raise ValueError("need ?score=<slug>&semitones=<-24..24, nonzero>")
            from music21 import converter
            score = converter.parse(str(workspace.resolve_path(slug)), forceSource=True)
            details = ops.transpose(score, str(semitones))
            entry = workspace.add_version(slug, score, "transpose", {"semitones": semitones})
            self._json(200, {"score": slug, "new_version": entry["id"], "details": details})
        except Exception as e:
            self._json(400, {"error": f"{type(e).__name__}: {e}"})

    def _chat(self):
        """One chat turn with the arrangement agent. Body:
        {"score": slug, "message": str, "model": alias?, "history": json?}"""
        import os
        try:
            length = int(self.headers.get("Content-Length", "0"))
            body = json.loads(self.rfile.read(length)) if length else {}
            slug = body.get("score")
            message = body.get("message", "").strip()
            if not slug or not message:
                raise ValueError('need {"score": ..., "message": ...}')
            from . import chat
            result = chat.run_chat(slug, message, body.get("model"), body.get("history"))
            self._json(200, result)
        except Exception as e:
            self._json(400, {"error": f"{type(e).__name__}: {e}"})

    def do_GET(self):
        url = urlparse(self.path)
        if url.path == "/api/scores":
            self._json(200, workspace.rebuild_manifest())
        elif url.path == "/api/models":
            import os

            from . import chat
            self._json(200, {"default": chat.DEFAULT_MODEL, "models": chat.MODELS,
                             "keys_present": {"openrouter": bool(os.environ.get("OPENROUTER_API_KEY")),
                                              "anthropic": bool(os.environ.get("ANTHROPIC_API_KEY")),
                                              "gcp_adc": bool(os.environ.get("GOOGLE_APPLICATION_CREDENTIALS"))}})
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
        if url.path == "/api/chat":
            self._chat()
            return
        if url.path == "/api/transpose":
            self._transpose(url)
            return
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
            # read_notation, not converter.parse: one ABC upload can hold
            # several tunes and music21 hands those back as an Opus, which has
            # no `.parts` and crashes everything downstream
            tunes = workspace.read_notation(tmp_path)
            if not tunes:
                raise ValueError(f"{filename} holds no music")
            from . import ops as _ops
            source_of = (q.get("source_of") or [None])[0]
            if source_of:
                # a source is one reference edition; several tunes in one file
                # is not a thing to attach, so the first is what is meant
                m21_score = tunes[0]
                name = _ops.clean_imported_metadata(m21_score, name)["title"]
                doc = workspace.add_source(source_of, m21_score, name,
                                           origin=f"upload:{filename}")
                self._json(200, {"score": source_of, "source": doc["id"], "name": name,
                                 "parts": doc.get("parts")})
                return
            rows = []
            for m21_score in tunes:
                one = _ops.clean_imported_metadata(m21_score, name)["title"]
                slug, entry = workspace.create_score(
                    one, m21_score, op="import",
                    args={"source": f"upload:{filename}"})
                # every arrangement belongs to a piece, this path included
                filed = workspace.ensure_own_piece(slug)
                rows.append({"score": slug, "name": one, "version": entry["id"],
                             "piece": filed["piece"], "parts": entry.get("parts")})
            out = dict(rows[0])
            out["tunes_found"] = len(rows)
            out["arrangements"] = rows
            self._json(200, out)
        except Exception as e:
            self._json(400, {"error": f"{type(e).__name__}: {e}"})


def serve(port: int = 8765, host: str = "127.0.0.1") -> None:
    httpd = ThreadingHTTPServer((host, port), Handler)
    print(f"scoranger engine API on http://{host}:{port} (Ctrl-C to stop)")
    if host != "127.0.0.1":
        print("NOTE: listening on the network — any device on your LAN can use this "
              "engine (including chat, which spends API tokens).")
    httpd.serve_forever()
