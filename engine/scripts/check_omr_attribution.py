#!/usr/bin/env python3
"""Every OMR job is attributable, and an unverified token never spends.

The owner's requirement: *"I want PER-USER tracking of OMR costs"* -- no cap,
each job attributable to a user identity the service logs against it
(design/FIREBASE.md §0.12).

The two things worth proving are not "does a good token work". They are:

  1. **A token that is OFFERED and does not verify is REFUSED**, not quietly
     downgraded to anonymous. A silent downgrade means anyone can spend under
     a clean label by sending rubbish in the Authorization header, which
     destroys the report the whole feature exists to produce.
  2. **`aud` is checked against this project.** A Firebase ID token from ANY
     other Firebase project is also validly signed by Google, so without the
     audience check "verified" means "signed by Google for somebody".

Run against the real module, with no network: token verification is exercised
through its failure paths, which is where the logic is.
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "omr-service"))

FAILURES: list[str] = []


def check(ok: bool, label: str) -> None:
    print(f"    {'ok  ' if ok else 'FAIL'} {label}")
    if not ok:
        FAILURES.append(label)


def a_signed_in_job_is_billed_to_a_uid() -> None:
    print("\na verified token attributes the job to its user")
    import identity

    real = identity.verify_id_token
    identity.verify_id_token = lambda token: {"sub": "u-ali", "email": "a@b.c"}
    try:
        actor, trust, email = identity.actor_for("a.token.here", api_key_ok=False)
    finally:
        identity.verify_id_token = real
    check(actor == "uid:u-ali", f"actor is the uid; got {actor!r}")
    check(trust == "verified", f"trust is 'verified'; got {trust!r}")
    check(email == "a@b.c", "the email rides along for a readable report")
    # A verified token needs no API key at all -- that IS the migration, and it
    # is proven by the call above passing api_key_ok=False rather than by a
    # sentence. (A `check(True, ...)` stood here and asserted nothing, which is
    # the self-disabling check this repo keeps finding.)


def a_bad_token_is_refused_and_never_downgraded() -> None:
    print("\nan unverified token is refused, not downgraded to anonymous")
    import identity

    real = identity.verify_id_token

    def explode(token):
        raise identity.Unverified("signature does not check out")

    identity.verify_id_token = explode
    try:
        # The dangerous case: a bad token AND a valid API key. The tempting
        # implementation falls back to anonymous, and then a spoofed token
        # spends under a label nobody can trace.
        try:
            got = identity.actor_for("rubbish", api_key_ok=True)
            check(False, f"a bad token with a good API key returned {got!r} "
                         "instead of refusing")
        except identity.Unverified:
            check(True, "a bad token with a VALID API key is still refused")
        try:
            identity.actor_for("rubbish", api_key_ok=False)
            check(False, "a bad token with no API key was accepted")
        except identity.Unverified:
            check(True, "a bad token with no API key is refused")
    finally:
        identity.verify_id_token = real


def a_signed_out_job_is_labelled_unattributed() -> None:
    print("\nno account means unattributed, which is not the same as broken")
    import identity

    actor, trust, email = identity.actor_for(None, api_key_ok=True)
    # Importing a scan is a signed-out feature (principle 1), so there is
    # genuinely no user. The report must SAY that rather than imply the
    # attribution failed.
    check(actor == "anonymous", f"actor is 'anonymous'; got {actor!r}")
    check(trust == "unattributed", f"trust is 'unattributed'; got {trust!r}")
    check(email is None, "no email is invented for a job with no user")

    try:
        identity.actor_for(None, api_key_ok=False)
        check(False, "no token and no key was accepted")
    except identity.Unverified:
        check(True, "no token and no valid key is refused")


def the_audience_and_issuer_are_checked() -> None:
    print("\nthe token must be for THIS project")
    import identity

    source = (ROOT / "omr-service" / "identity.py").read_text()
    # Read out of the source because these two are the checks a library will
    # happily skip by default, and their absence is invisible at runtime until
    # somebody else's token is accepted.
    check("audience=PROJECT_ID" in source,
          "jwt.decode passes audience=PROJECT_ID, so a token minted by another "
          "Firebase project is rejected")
    check("issuer=ISSUER_PREFIX + PROJECT_ID" in source,
          "jwt.decode passes the project's own securetoken issuer")
    check('algorithms=["RS256"]' in source,
          'algorithms is pinned to RS256 -- an unpinned decode accepts "alg": '
          '"none"')
    # And no credentials anywhere: the whole point of verifying against public
    # certs is that this service holds nothing worth stealing.
    for forbidden in ("service_account", "GOOGLE_APPLICATION_CREDENTIALS",
                      "firebase_admin", "private_key"):
        check(forbidden not in source,
              f"identity.py does not reference {forbidden}: verification is "
              "public-key only and this service holds no credentials")

    identity.PROJECT_ID = ""
    try:
        identity.verify_id_token("x.y.z")
        check(False, "a missing FIREBASE_PROJECT_ID still verified a token")
    except identity.Unverified:
        check(True, "with no FIREBASE_PROJECT_ID set, nothing verifies -- it "
                    "cannot silently accept everything")


def every_finished_job_emits_one_usage_record() -> None:
    print("\nthe cost record is a line a log query can add up")
    import identity

    line = identity.usage_line("j1", "uid:u-ali", "verified", 9, 12.34, "done",
                              "a@b.c")
    row = json.loads(line)
    check(row["omr_usage"] is True, "carries the omr_usage flag to filter on")
    for field in ("job", "actor", "trust", "pages", "seconds", "outcome", "at"):
        check(field in row, f"carries {field}")
    check(row["pages"] == 9 and row["actor"] == "uid:u-ali",
          "pages and actor are the two the cost report multiplies")

    # EVERY exit path bills, including the failures: a PDF Audiveris cannot
    # read is exactly the one it grinds on for eight minutes, and counting only
    # successes under-reports the expensive cases.
    server = (ROOT / "omr-service" / "server.py").read_text()
    for outcome in ('bill("done")', 'bill("unreadable")', 'bill("timeout")',
                    'bill("error")'):
        check(outcome in server, f"run_job emits {outcome}")


def polling_is_not_billed() -> None:
    print("\nprogress polls are not attributed and not charged")
    server = (ROOT / "omr-service" / "server.py").read_text()
    # The app polls job status about once a second while the bar moves. If
    # do_GET verified a token per poll, one RSA check per job would become
    # hundreds, and a token expiring mid-conversion would break the progress
    # bar of a job that is running fine.
    get_body = server[server.index("def do_GET"):server.index("def do_POST")]
    check("_actor()" not in get_body,
          "do_GET does not resolve an actor: polls cost nothing and happen "
          "every second")
    check("_authed()" in get_body,
          "do_GET still requires the API key, so job state is not world-readable")


def main() -> int:
    a_signed_in_job_is_billed_to_a_uid()
    a_bad_token_is_refused_and_never_downgraded()
    a_signed_out_job_is_labelled_unattributed()
    the_audience_and_issuer_are_checked()
    every_finished_job_emits_one_usage_record()
    polling_is_not_billed()
    print()
    if FAILURES:
        print(f"{len(FAILURES)} FAILED")
        for f in FAILURES:
            print(f"  - {f}")
        return 1
    print("OK: every job says who it was for, and a bad token spends nothing")
    return 0


if __name__ == "__main__":
    sys.exit(main())
