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
    """The token was present and did not check out. Never a reason to 500.

    A CLIENT problem: a stale token, a forged one, one minted for another
    project. Answering 401 is right, because the client can fix it by
    refreshing.
    """


class CannotVerify(Exception):
    """This SERVER is not able to verify any token at all.

    A different failure with a different remedy, and keeping them apart is the
    whole reason this class exists. `FIREBASE_PROJECT_ID` unset, or the RSA
    extra missing, means nothing can be checked -- and refusing the request
    would then break OMR for every signed-in reader the moment the app started
    sending tokens, before the env var reached the service. Which is exactly
    what would have happened: the app sends a bearer token as soon as somebody
    signs in, and the deploy that teaches the service which project to trust is
    a separate step.

    So this falls back to the shared API key and labels the job
    `unattributed`. That is NOT the silent downgrade `actor_for` refuses: a
    client cannot cause this state, cannot detect it, and gains nothing from
    it -- the key is still required. What it costs is attribution, which is
    already absent for every signed-out job, and the boot log and every
    refusal say so loudly.
    """


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
        raise CannotVerify("FIREBASE_PROJECT_ID is not set, so no token can be "
                           "checked against a project")
    try:
        import jwt
        from jwt import PyJWKClient  # noqa: F401  (import proves the extra is installed)
    except ImportError as e:
        raise CannotVerify(f"token verification needs PyJWT[crypto]: {e}") from e

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


def actor_for(bearer: str | None, api_key_ok: bool) -> tuple[str, str]:
    """Who to bill this job to: `(actor, trust)`.

    THE EMAIL ADDRESS IS DELIBERATELY NOT RETURNED. It used to be, as a third
    element, and server.py wrote it into every usage line -- so a Cloud
    Logging bucket with no configured retention held the address of every
    signed-in user who ever scanned a page, and `deleteAccount` could not
    reach it. The uid is the whole of what the cost report needs, and it was
    the only thing anything read. Returning the address again would put it
    back in the log, so it stops here rather than being filtered downstream.
    Asserted by engine/scripts/check_omr_attribution.py.

    - `("uid:<sub>", "verified")` -- a checked Firebase ID token. The only
      attribution that is a fact.
    - `("anonymous", "unattributed")` -- a valid shared API key and no
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
        try:
            claims = verify_id_token(bearer)
            return f"uid:{claims['sub']}", "verified"
        except CannotVerify as e:
            # The server's fault, not the caller's. Do not punish a signed-in
            # reader for a missing env var -- take the job on the shared key
            # and say, every time, that it went unattributed and why.
            if not api_key_ok:
                raise
            print(f"omr-service: CANNOT VERIFY TOKENS ({e}) -- job accepted "
                  f"UNATTRIBUTED on the shared key. Set FIREBASE_PROJECT_ID.",
                  flush=True)
            return "anonymous", "unattributed"
    if api_key_ok:
        return "anonymous", "unattributed"
    raise Unverified("no bearer token and no valid API key")


def usage_line(job_id: str, actor: str, trust: str, pages: int,
               seconds: float, outcome: str) -> str:
    """One structured line per finished job: the per-user cost record.

    JSON on stdout rather than a database, because on Cloud Run stdout IS the
    durable store -- Cloud Logging ingests it and can aggregate by any field,
    and it survives the instance dying, which an in-process counter does not.
    This service keeps its jobs in process memory (see server.py's note on
    max-instances=1) precisely because nothing in it is meant to be durable.

    `omr_usage` is the field to filter on.

    NO PERSONAL DATA IN THIS LINE. It carried `"email"` until 0.12.0 -- the
    signed-in user's address, on every conversion, on all four exit paths.
    Cloud Logging is durable by design and the account-deletion Function makes
    no Logging call, so that address outlived the account it belonged to. The
    `actor` field carries `uid:<sub>`, which is what the per-user cost report
    multiplies against `pages`, and the address was read by nothing else.
    Removing it removes the problem rather than managing it.
    """
    return json.dumps({
        "omr_usage": True,
        "job": job_id,
        "actor": actor,
        "trust": trust,
        "pages": pages,
        "seconds": round(seconds, 1),
        "outcome": outcome,
        "at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    }, sort_keys=True)
