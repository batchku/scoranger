"""OMR HTTP service wrapping Audiveris batch mode.

Stdlib, plus PyJWT[crypto] for verifying Firebase ID tokens -- an RS256 JWT
needs RSA and stdlib has none. It needs NO credentials: verification is against
Google's public certificates (see identity.py).

Job API (progress-aware; the iPad app uses this):
  POST /jobs            raw PDF + X-API-Key -> {"ok":true,"job":id,"pages":N}
  GET  /jobs/<id>       -> {"ok":true,"state":"queued|converting|done|failed",
                            "page":N,"pages":M,"queue":K,"error":...}
  GET  /jobs/<id>/result -> .mxl bytes (409 while running, 404 unknown)

Legacy synchronous API (curl / regression battery):
  POST /omr             raw PDF + X-API-Key -> .mxl bytes (blocks until done)

GET /healthz -> {"ok": true}

Auth, and WHO the job is billed to (design/FIREBASE.md §0.12):
  - `Authorization: Bearer <firebase id token>` -- verified against Google's
    public certs, and the job is attributed to that user's uid. This is the
    path the app takes when somebody is signed in.
  - `X-API-Key: <OMR_API_KEY>` -- still accepted, and the job is logged as
    `anonymous`. Kept because every build already in the field sends only this,
    and because importing a scan is a signed-out feature: principle 1 says no
    login may gate using the app, so there is genuinely no user to attribute
    those jobs to.
  A token that is OFFERED and does not verify is a 401, never a silent
  downgrade to anonymous -- otherwise a spoofed token spends under a clean
  label.

Per-job usage is emitted as one JSON line with `"omr_usage": true`, which is
the per-user cost record; Cloud Logging aggregates it.
Progress comes from Audiveris's own log stream: each per-sheet line carries a
"[book#NN]" logger prefix, and total pages are counted from the PDF itself.
`page` is the sheet being WORKED ON, not the number finished, so a client
showing a bar has `page - 1` pages behind it (see SHEET_MARK).

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

import identity

AUDIVERIS = os.environ.get("AUDIVERIS_BIN", "/opt/audiveris/bin/Audiveris")
API_KEY = os.environ.get("OMR_API_KEY", "").strip()
MAX_BYTES = 50 * 1024 * 1024
TIMEOUT_S = 480
JOB_TTL_S = 3600

# Audiveris processing switches this service DEPENDS ON, stated rather than
# assumed. Each is one of Audiveris's own boolean constants, addressed by its
# qualified name (org.audiveris.omr.sheet.ProcessingSwitches.<switch>) and set
# for the run with `-option`.
#
# Measured on a 32-bar lead sheet carrying 32 chord symbols and 128 syllables
# (Audiveris 5.11.0, batch export):
#
#   lyrics      defaults ON, and it really is the gate: forced to false the
#               same sheet exported 0 lyrics instead of 124, and the syllables
#               came back instead as 8 dynamics, 23 articulations and 12
#               fermatas that are not on the page. Stated here so a change of
#               default upstream cannot take the words away quietly.
#   chordNames  is documented as the chord-symbol switch and its constant
#               defaults to false -- but on 5.11.0 forcing it either way made
#               no difference whatever (28 <harmony> both ways), so the
#               symbols do not hang off it in this version. It is passed
#               anyway: it costs nothing measurable (7.0s vs 6.5s on the lead
#               sheet, 23.1s vs 23.8s on a 4-page piano score, both inside
#               run-to-run noise) and it is the switch a later version will
#               honour.
#
# Deliberately NOT here: fingerings, frets, pluckings, drumNotation, the
# tablature and one-line-staff switches, smallHeads, crossHeads, tremolos and
# implicitTuplets are for repertoire this app does not take, and each is
# another class of shape for the recogniser to hunt on pages that have none.
# lyricsAboveStaff reads text ABOVE a staff as lyrics, which on these scores
# is where the chord symbols and tempo marks live.
#
# THE SWITCHES ARE NOT WHY CHORDS AND LYRICS WENT MISSING. The reason is OCR:
# Audiveris drives Tesseract in LEGACY mode, and the Debian/Ubuntu
# tesseract-ocr-eng package ships tessdata_fast, which carries no legacy
# components -- so the TEXTS step read nothing at all and every word on the
# page was lost. The Dockerfile installs language data that has them.
PROCESSING_SWITCHES = {"chordNames": True, "lyrics": True}
SWITCH_PREFIX = "org.audiveris.omr.sheet.ProcessingSwitches"


def audiveris_command(out_dir: str, pdf_path: str) -> list[str]:
    """The exact argv a conversion runs, switches included.

    A function rather than a literal buried in `run_job` so a check can assert
    the switches are on the command line: a switch that silently stops being
    passed looks exactly like a switch that was never passed.
    """
    options: list[str] = []
    for switch, value in PROCESSING_SWITCHES.items():
        options += ["-option", f"{SWITCH_PREFIX}.{switch}={str(value).lower()}"]
    return [AUDIVERIS, "-batch", "-export", *options, "-output", out_dir, pdf_path]


JOBS = {}
JOBS_LOCK = threading.Lock()
AUDIVERIS_LOCK = threading.Lock()  # one conversion at a time per instance

# The sheet Audiveris is WORKING ON, taken from the logger prefix its per-sheet
# lines carry: "INFO  [probe#03]  StepMonitoring ... | BINARY".
#
# Anchored to that prefix on purpose. `#(\d{1,3})\]` alone also matched the
# SHEET LIST Audiveris prints in its first second -- "Book reaching PAGE on
# sheets:[#1#2#3#4#5#6#7#8]" -- whose last number is the page TOTAL. `page`
# therefore jumped to `pages` before a single sheet had been read and stayed
# there, and the iPad drew a full progress bar reading "reading page 8 of 8"
# for the whole conversion (0.6.8). Measured on an 8-page score: the counter
# reached 8 at log line 9 of 570, and 100% of the polls over the 78s of
# converting reported page == pages.
SHEET_MARK = re.compile(rb"^\w+\s+\[[^\[\]]*#(\d{1,3})\]")
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
    started = time.time()

    def bill(outcome: str) -> None:
        """Emitted on EVERY exit path, including the failures.

        A failed conversion still ran Audiveris for up to eight minutes and
        still cost what it cost. A usage record that counted only successes
        would under-report the expensive cases -- a PDF Audiveris cannot read
        is exactly the one it grinds hardest on.
        """
        print(identity.usage_line(
            job_id, job.get("actor", "anonymous"), job.get("trust", "unattributed"),
            job.get("pages", 0), time.time() - started, outcome,
            job.get("email")), flush=True)

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
                audiveris_command(out_dir, pdf_path),
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
                    bill("timeout")
                    return
            proc.wait()

        mxl = find_mxl(out_dir)
        if mxl is None:
            log = b"".join(tail)[-2000:].decode(errors="replace")
            print(f"job {job_id}: no mxl\n{log}", flush=True)
            job.update(state="failed", error="audiveris could not read this PDF as a score")
            bill("unreadable")
            return
        job.update(state="done", result=mxl, page=job["pages"] or job["page"])
        print(f"job {job_id}: done", flush=True)
        bill("done")
    except Exception as e:  # noqa: BLE001 — report, don't crash the worker
        job.update(state="failed", error=f"{type(e).__name__}: {e}")
        bill("error")


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

    def _bearer(self) -> str | None:
        raw = self.headers.get("Authorization", "").strip()
        if raw.lower().startswith("bearer "):
            token = raw[7:].strip()
            return token or None
        return None

    def _actor(self):
        """`(actor, trust, email)`, or None having already answered 401.

        Reads on job status and result are NOT attributed: they cost nothing,
        they are polled every second while a bar moves, and verifying a token
        on each one would turn one RSA check per job into hundreds.
        """
        try:
            return identity.actor_for(self._bearer(), self._authed())
        except identity.Unverified as e:
            # Deliberately says which of the two failed. A client sending a
            # stale token needs to know to refresh it, and a client sending no
            # credentials needs to know that is what happened -- one opaque
            # 401 for both is how a token refresh bug looks like an outage.
            print(f"omr auth refused: {e}", flush=True)
            self._json(401, {"ok": False, "error": f"not authorised: {e}"})
            return None

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
        who = self._actor()
        if who is None:
            return
        actor, trust, email = who
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
                        "created": time.time(),
                        "actor": actor, "trust": trust, "email": email}
        print(f"job {job_id}: accepted for {actor} ({trust})", flush=True)
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
    # Said at STARTUP, not at first use. Without FIREBASE_PROJECT_ID nothing can
    # be verified, so every signed-in request gets a 401 while signed-out ones
    # keep working -- a misconfiguration that looks exactly like "sharing broke
    # for people with accounts". One line in the boot log turns an afternoon of
    # confusion into a `gcloud run services update --update-env-vars`.
    if identity.PROJECT_ID:
        print(f"omr-service: attributing jobs against Firebase project "
              f"{identity.PROJECT_ID}", flush=True)
    else:
        print("omr-service: WARNING FIREBASE_PROJECT_ID is unset -- no bearer "
              "token can be verified, so every signed-in request will 401. "
              "Fix with: gcloud run services update scoranger-omr "
              "--update-env-vars FIREBASE_PROJECT_ID=<id>", flush=True)
    server = ThreadingHTTPServer(("0.0.0.0", port), Handler)

    # Cloud Run sends SIGTERM on scale-down (10s grace): stop accepting new
    # connections but let in-flight conversions finish instead of 502ing them.
    def drain(_sig, _frame):
        print("SIGTERM: draining in-flight requests")
        threading.Thread(target=server.shutdown, daemon=True).start()

    signal.signal(signal.SIGTERM, drain)
    server.serve_forever()
    print("drained; exiting")
