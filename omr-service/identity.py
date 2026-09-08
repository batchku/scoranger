"""Who is asking, and how much it cost them.

The owner's requirement, in his words: *"I want PER-USER tracking of OMR
costs"* -- no cap, but each job attributable to a user identity the service
logs against it. design/FIREBASE.md §0.12, §11.4.

Two things live here and the split matters:

**Verification.** A Firebase ID token is an RS256 JWT signed by Google. It is
verified against Google's PUBLIC certificates, which means this service needs
NO CREDENTIALS OF ANY KIND -- no service-account key, no ADC, nothing to leak
or rotate. That is why `firebase-admin` is not used: it is a large dependency
whose main job is privileged access this service must never have. The cost is
one pip dependency for RSA (`PyJWT[crypto]`), which is why `server.py` can no
longer claim to be stdlib-only.

**Attribution, which is not the same as verification.** A verified `uid` is a
fact. Everything else is a claim. The two are labelled differently in the log
and never merged, because a cost report that treats a self-asserted identity
as equal to a proven one is a report you cannot act on.
"""
from __future__ import annotations

import json
import os
import threading
import time
import urllib.request

# Google's public certs for Firebase ID tokens. Public data; no auth to fetch.
CERT_URL = ("https://www.googleapis.com/robot/v1/metadata/x509/"
            "securetoken@system.gserviceaccount.com")
ISSUER_PREFIX = "https://securetoken.google.com/"

PROJECT_ID = os.environ.get("FIREBASE_PROJECT_ID", "").strip()

_certs: dict[str, str] = {}
_certs_fetched = 0.0
_certs_lock = threading.Lock()
# Google rotates daily and the response carries max-age; an hour is well inside
# it and turns a per-job network call into a per-hour one.
CERT_TTL_S = 3600


class Unverified(Exception):
    """The token was present and did not check out. Never a reason to 500."""


def _certificates() -> dict[str, str]:
    global _certs_fetched
    with _certs_lock:
        if _certs and time.time() - _certs_fetched < CERT_TTL_S:
            return _certs
        with urllib.request.urlopen(CERT_URL, timeout=10) as response:
            fetched = json.load(response)
        _certs.clear()
        _certs.update(fetched)
        _certs_fetched = time.time()
        return _certs


def verify_id_token(token: str) -> dict:
    """The token's claims, or `Unverified`.

    Every check is explicit rather than left to a library default, because the
    two that matter most are the two easiest to omit: `aud` must be THIS
    Firebase project, or a token minted by any other Firebase project would be
    accepted; and `iss` must be Google's securetoken issuer for that project.
    Without both, "verified" means only "signed by Google for somebody".
    """
    if not PROJECT_ID:
        raise Unverified("FIREBASE_PROJECT_ID is not set, so no token can be "
                         "checked against a project")
    try:
        import jwt
        from jwt import PyJWKClient  # noqa: F401  (import proves the extra is installed)
    except ImportError as e:
        raise Unverified(f"token verification needs PyJWT[crypto]: {e}") from e

    try:
        header = jwt.get_unverified_header(token)
    except Exception as e:  # noqa: BLE001 -- a malformed token is not our fault
        raise Unverified(f"malformed token: {type(e).__name__}") from e

    kid = header.get("kid")
    certs = _certificates()
    if kid not in certs:
        # A rotation we have not seen yet: refetch once before refusing.
        with _certs_lock:
            _certs_fetched = 0.0
        certs = _certificates()
    if kid not in certs:
        raise Unverified("token key id is not one of Google's current certs")

    from cryptography.x509 import load_pem_x509_certificate

    public_key = load_pem_x509_certificate(certs[kid].encode()).public_key()
    try:
        claims = jwt.decode(
            token, public_key, algorithms=["RS256"],
            audience=PROJECT_ID,
            issuer=ISSUER_PREFIX + PROJECT_ID,
            options={"require": ["exp", "iat", "aud", "iss", "sub"]},
        )
    except Exception as e:  # noqa: BLE001
        raise Unverified(f"{type(e).__name__}: {e}") from e

    if not claims.get("sub"):
        raise Unverified("token carries no subject")
    return claims


def actor_for(bearer: str | None, api_key_ok: bool) -> tuple[str, str, str | None]:
    """Who to bill this job to: `(actor, trust, detail)`.

    - `("uid:<sub>", "verified", email)` -- a checked Firebase ID token. The
      only attribution that is a fact.
    - `("anonymous", "unattributed", None)` -- a valid shared API key and no
      token. **This is not a failure and not a gap to close by requiring
      sign-in.** Importing a scanned PDF is a core feature of the signed-out
      app, and principle 1 of §0 says no login may gate using it. There is no
      user to attribute the job to because there is no user. Said plainly here
      so a cost report reads "unattributed" rather than implying the
      attribution broke.
    - Raises `Unverified` when a token was offered and did not check out --
      offering a bad token is different from offering none, and answering 401
      beats silently downgrading to anonymous, which would let a spoofed token
      spend under a clean label.
    """
    if bearer:
        claims = verify_id_token(bearer)
        return f"uid:{claims['sub']}", "verified", claims.get("email")
    if api_key_ok:
        return "anonymous", "unattributed", None
    raise Unverified("no bearer token and no valid API key")


def usage_line(job_id: str, actor: str, trust: str, pages: int,
               seconds: float, outcome: str, detail: str | None = None) -> str:
    """One structured line per finished job: the per-user cost record.

    JSON on stdout rather than a database, because on Cloud Run stdout IS the
    durable store -- Cloud Logging ingests it and can aggregate by any field,
    and it survives the instance dying, which an in-process counter does not.
    This service keeps its jobs in process memory (see server.py's note on
    max-instances=1) precisely because nothing in it is meant to be durable.

    `omr_usage` is the field to filter on.
    """
    return json.dumps({
        "omr_usage": True,
        "job": job_id,
        "actor": actor,
        "trust": trust,
        "pages": pages,
        "seconds": round(seconds, 1),
        "outcome": outcome,
        "email": detail,
        "at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    }, sort_keys=True)
