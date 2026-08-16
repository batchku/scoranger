"""OMR HTTP service wrapping Audiveris batch mode. Stdlib only.

Job API (progress-aware; the iPad app uses this):
  POST /jobs            raw PDF + X-API-Key -> {"ok":true,"job":id,"pages":N}
  GET  /jobs/<id>       -> {"ok":true,"state":"queued|converting|done|failed",
                            "page":N,"pages":M,"queue":K,"error":...}
  GET  /jobs/<id>/result -> .mxl bytes (409 while running, 404 unknown)

Legacy synchronous API (curl / regression battery):
  POST /omr             raw PDF + X-API-Key -> .mxl bytes (blocks until done)

GET /healthz -> {"ok": true}

Auth: set the OMR_API_KEY env var; requests must send it as X-API-Key.
Progress comes from Audiveris's own log stream: each per-sheet line carries a
"[book#NN]" prefix, and total pages are counted from the PDF itself.

NOTE: jobs live in process memory — deploy with max-instances=1 (polls must
hit the instance that owns the job) and concurrency > 1 (polls arrive while a
conversion runs); an internal lock still serializes Audiveris itself.
"""

import json
import os
import re
import shutil
import signal
import subprocess
import tempfile
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

AUDIVERIS = os.environ.get("AUDIVERIS_BIN", "/opt/audiveris/bin/Audiveris")
API_KEY = os.environ.get("OMR_API_KEY", "").strip()
MAX_BYTES = 50 * 1024 * 1024
TIMEOUT_S = 480
JOB_TTL_S = 3600

JOBS = {}
JOBS_LOCK = threading.Lock()
AUDIVERIS_LOCK = threading.Lock()  # one conversion at a time per instance

SHEET_MARK = re.compile(rb"#(\d{1,3})\]")          # audiveris log prefix [book#03]
PDF_PAGE = re.compile(rb"/Type\s*/Page(?!s)")      # crude but adequate page count


def count_pages(pdf: bytes) -> int:
    return len(PDF_PAGE.findall(pdf))


def find_mxl(out_dir: str):
    for root, _dirs, files in os.walk(out_dir):
        for name in files:
            if name.endswith(".mxl"):
                return os.path.join(root, name)
    return None


def purge_old_jobs():
    now = time.time()
    with JOBS_LOCK:
        stale = [jid for jid, j in JOBS.items() if now - j["created"] > JOB_TTL_S]
        for jid in stale:
            shutil.rmtree(JOBS[jid].get("workdir", ""), ignore_errors=True)
            del JOBS[jid]


def run_job(job_id: str, pdf: bytes):
    job = JOBS[job_id]
    workdir = tempfile.mkdtemp(prefix="omr-")
    job["workdir"] = workdir
    try:
        pdf_path = os.path.join(workdir, "input.pdf")
        with open(pdf_path, "wb") as f:
            f.write(pdf)
        out_dir = os.path.join(workdir, "out")
        os.makedirs(out_dir)

        with AUDIVERIS_LOCK:
            job["state"] = "converting"
            print(f"job {job_id}: audiveris start ({job['pages']} pages)", flush=True)
            proc = subprocess.Popen(
                [AUDIVERIS, "-batch", "-export", "-output", out_dir, pdf_path],
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            )
            deadline = time.time() + TIMEOUT_S
            tail = []
            for line in proc.stdout:
                tail.append(line)
                if len(tail) > 200:
                    tail.pop(0)
                m = SHEET_MARK.search(line)
                if m:
                    job["page"] = max(job["page"], int(m.group(1)))
                if time.time() > deadline:
                    proc.kill()
                    job.update(state="failed", error="audiveris timed out")
                    return
            proc.wait()

        mxl = find_mxl(out_dir)
        if mxl is None:
            log = b"".join(tail)[-2000:].decode(errors="replace")
            print(f"job {job_id}: no mxl\n{log}", flush=True)
            job.update(state="failed", error="audiveris could not read this PDF as a score")
            return
        job.update(state="done", result=mxl, page=job["pages"] or job["page"])
        print(f"job {job_id}: done", flush=True)
    except Exception as e:  # noqa: BLE001 — report, don't crash the worker
        job.update(state="failed", error=f"{type(e).__name__}: {e}")


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"  # keep-alive; plays nicer with the gateway

    def _json(self, code, payload):
        body = json.dumps(payload).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _bytes(self, data, filename):
        self.send_response(200)
        self.send_header("Content-Type", "application/vnd.recordare.musicxml")
        self.send_header("Content-Disposition", f'attachment; filename="{filename}"')
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _authed(self) -> bool:
        return not API_KEY or self.headers.get("X-API-Key", "").strip() == API_KEY

    # -- GET: health, job status, job result ---------------------------------

    def do_GET(self):
        if self.path == "/healthz":
            self._json(200, {"ok": True})
            return
        m = re.fullmatch(r"/jobs/([0-9a-f]+)(/result)?", self.path)
        if not m:
            self._json(404, {"ok": False, "error": "not found"})
            return
        if not self._authed():
            self._json(401, {"ok": False, "error": "bad api key"})
            return
        job = JOBS.get(m.group(1))
        if job is None:
            self._json(404, {"ok": False, "error": "unknown job"})
            return
        if m.group(2):  # /result
            if job["state"] == "done":
                with open(job["result"], "rb") as f:
                    self._bytes(f.read(), "score.mxl")
            elif job["state"] == "failed":
                self._json(422, {"ok": False, "error": job.get("error", "failed")})
            else:
                self._json(409, {"ok": False, "error": "not finished"})
            return
        queue = 0
        if job["state"] == "queued":
            with JOBS_LOCK:
                queue = sum(1 for j in JOBS.values()
                            if j["state"] == "converting"
                            or (j["state"] == "queued" and j["created"] < job["created"]))
        self._json(200, {"ok": True, "state": job["state"],
                         "page": job["page"], "pages": job["pages"],
                         "queue": queue, "error": job.get("error")})

    # -- POST: submit job (async) or legacy /omr (blocking) -------------------

    def do_POST(self):
        # ALWAYS read the request body before responding — answering early and
        # closing makes the Cloud Run gateway report a 502 "truncated response"
        # instead of delivering our error to the client.
        length = int(self.headers.get("Content-Length", 0))
        pdf = self.rfile.read(min(length, MAX_BYTES)) if length > 0 else b""
        print(f"omr request {self.path}: {length} bytes, "
              f"ua={self.headers.get('User-Agent','?')}, magic={pdf[:8]!r}", flush=True)

        if self.path not in ("/omr", "/jobs"):
            self._json(404, {"ok": False, "error": "not found"})
            return
        if not self._authed():
            self._json(401, {"ok": False, "error": "bad api key"})
            return
        if not 0 < length <= MAX_BYTES:
            self._json(413, {"ok": False, "error": f"body must be 1..{MAX_BYTES} bytes"})
            return
        if not pdf.startswith(b"%PDF"):
            self._json(415, {"ok": False,
                             "error": f"not a PDF (starts with {pdf[:8]!r})"})
            return

        purge_old_jobs()
        job_id = uuid.uuid4().hex[:12]
        JOBS[job_id] = {"state": "queued", "page": 0, "pages": count_pages(pdf),
                        "created": time.time()}
        worker = threading.Thread(target=run_job, args=(job_id, pdf), daemon=True)
        worker.start()

        if self.path == "/jobs":
            self._json(202, {"ok": True, "job": job_id, "pages": JOBS[job_id]["pages"]})
            return

        # legacy blocking /omr: wait for the job inline
        worker.join(TIMEOUT_S + 30)
        job = JOBS[job_id]
        if job["state"] == "done":
            with open(job["result"], "rb") as f:
                self._bytes(f.read(), "score.mxl")
        elif job["state"] == "failed":
            self._json(422, {"ok": False, "error": job.get("error", "failed")})
        else:
            self._json(504, {"ok": False, "error": "audiveris timed out"})

    def log_message(self, fmt, *args):  # quieter Cloud Run logs
        print(f"{self.address_string()} {fmt % args}")


if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8080))
    print(f"omr-service on :{port} (audiveris={AUDIVERIS}, auth={'on' if API_KEY else 'OFF'})")
    server = ThreadingHTTPServer(("0.0.0.0", port), Handler)

    # Cloud Run sends SIGTERM on scale-down (10s grace): stop accepting new
    # connections but let in-flight conversions finish instead of 502ing them.
    def drain(_sig, _frame):
        print("SIGTERM: draining in-flight requests")
        threading.Thread(target=server.shutdown, daemon=True).start()

    signal.signal(signal.SIGTERM, drain)
    server.serve_forever()
    print("drained; exiting")
