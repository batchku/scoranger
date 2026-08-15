"""Minimal OMR HTTP service wrapping Audiveris batch mode. Stdlib only.

POST /omr   body = raw PDF bytes, header X-API-Key -> .mxl bytes (or JSON error)
GET  /healthz -> {"ok": true}

Auth: set the OMR_API_KEY env var; requests must send it as X-API-Key.
"""

import json
import os
import shutil
import subprocess
import tempfile
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

AUDIVERIS = os.environ.get("AUDIVERIS_BIN", "/opt/audiveris/bin/Audiveris")
API_KEY = os.environ.get("OMR_API_KEY", "")
MAX_BYTES = 50 * 1024 * 1024
TIMEOUT_S = 480


class Handler(BaseHTTPRequestHandler):
    def _json(self, code, payload):
        body = json.dumps(payload).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/healthz":
            self._json(200, {"ok": True})
        else:
            self._json(404, {"ok": False, "error": "not found"})

    def do_POST(self):
        if self.path != "/omr":
            self._json(404, {"ok": False, "error": "not found"})
            return
        if API_KEY and self.headers.get("X-API-Key", "") != API_KEY:
            self._json(401, {"ok": False, "error": "bad api key"})
            return
        length = int(self.headers.get("Content-Length", 0))
        if not 0 < length <= MAX_BYTES:
            self._json(413, {"ok": False, "error": f"body must be 1..{MAX_BYTES} bytes"})
            return
        pdf = self.rfile.read(length)

        workdir = tempfile.mkdtemp(prefix="omr-")
        try:
            pdf_path = os.path.join(workdir, "input.pdf")
            with open(pdf_path, "wb") as f:
                f.write(pdf)
            out_dir = os.path.join(workdir, "out")
            os.makedirs(out_dir)
            proc = subprocess.run(
                [AUDIVERIS, "-batch", "-export", "-output", out_dir, pdf_path],
                capture_output=True, text=True, timeout=TIMEOUT_S,
            )
            mxl = None
            for root, _dirs, files in os.walk(out_dir):
                for name in files:
                    if name.endswith(".mxl"):
                        mxl = os.path.join(root, name)
                        break
            if mxl is None:
                print("=== audiveris stdout ===\n", proc.stdout, flush=True)
                print("=== audiveris stderr ===\n", proc.stderr, flush=True)
                tail = (proc.stdout + "\n" + proc.stderr)[-8000:]
                self._json(422, {"ok": False,
                                 "error": "audiveris produced no .mxl",
                                 "log": tail})
                return
            with open(mxl, "rb") as f:
                data = f.read()
            self.send_response(200)
            self.send_header("Content-Type", "application/vnd.recordare.musicxml")
            self.send_header("Content-Disposition", 'attachment; filename="score.mxl"')
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
        except subprocess.TimeoutExpired:
            self._json(504, {"ok": False, "error": "audiveris timed out"})
        except Exception as e:  # noqa: BLE001 — report, don't crash the server
            self._json(500, {"ok": False, "error": f"{type(e).__name__}: {e}"})
        finally:
            shutil.rmtree(workdir, ignore_errors=True)

    def log_message(self, fmt, *args):  # quieter Cloud Run logs
        print(f"{self.address_string()} {fmt % args}")


if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8080))
    print(f"omr-service on :{port} (audiveris={AUDIVERIS}, auth={'on' if API_KEY else 'OFF'})")
    ThreadingHTTPServer(("0.0.0.0", port), Handler).serve_forever()
