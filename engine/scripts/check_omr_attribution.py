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
  3. **NO EMAIL ADDRESS REACHES THE LOG.** Until 0.12.0 `usage_line` carried
     the signed-in user's address on every conversion, on all four exit
     paths, into a Cloud Logging bucket with no configured retention that
     `deleteAccount` makes no call against -- so the address outlived the
     account. The uid in `actor` is the whole of what the cost report needs
     and was the only field anything read. This asserts the address is gone
     from BOTH ends: `actor_for` does not hand it out, and `usage_line`
     cannot be made to write it. Verified against a token whose claims DO
     carry an address, because a check fed no address proves nothing.

Run against the real module, with no network: token verification is exercised
through its failure paths, which is where the logic is.
"""
import inspect
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
        who = identity.actor_for("a.token.here", api_key_ok=False)
    finally:
        identity.verify_id_token = real
    check(len(who) == 2, f"actor_for answers (actor, trust) and nothing else; "
                         f"got {len(who)} values: {who!r}")
    actor, trust = who[0], who[1]
    check(actor == "uid:u-ali", f"actor is the uid; got {actor!r}")
    check(trust == "verified", f"trust is 'verified'; got {trust!r}")
    # The token's claims DID carry a@b.c. Nothing in the answer may.
    check(not any("a@b.c" in str(v) for v in who),
          f"the address in the token's claims is not handed back; got {who!r}")
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


def a_misconfigured_server_does_not_break_signed_in_readers() -> None:
    """The regression this separation exists to prevent.

    The app sends a bearer token the moment somebody signs in. The deploy that
    tells the service which Firebase project to trust is a SEPARATE step. In
    between -- and that window is real, not hypothetical -- every signed-in
    reader's PDF import would have answered 401 while signed-out imports kept
    working, because the code treated "I cannot verify anything" the same as
    "your token is forged".

    They are different failures with different remedies and only one of them is
    the caller's fault.
    """
    print("\na server that cannot verify still takes the job, unattributed")
    import identity

    saved = identity.PROJECT_ID
    identity.PROJECT_ID = ""            # the un-deployed env var
    try:
        actor, trust = identity.actor_for("a.real.token", api_key_ok=True)
        check(actor == "anonymous" and trust == "unattributed",
              f"a signed-in job is accepted unattributed; got {actor!r}/{trust!r}")

        # But it is NOT a way in: no key, no job, token or not.
        try:
            identity.actor_for("a.real.token", api_key_ok=False)
            check(False, "a token was accepted with no API key while the "
                         "server could not verify anything")
        except identity.CannotVerify:
            check(True, "with no API key it still refuses -- the fallback is "
                        "to the key, not to nothing")
    finally:
        identity.PROJECT_ID = saved

    # And the two failures are genuinely distinct types, so no future edit can
    # collapse them back together by accident.
    check(not issubclass(identity.CannotVerify, identity.Unverified)
          and not issubclass(identity.Unverified, identity.CannotVerify),
          "CannotVerify and Unverified are unrelated types: a server problem "
          "must not be catchable as a client problem")


def a_signed_out_job_is_labelled_unattributed() -> None:
    print("\nno account means unattributed, which is not the same as broken")
    import identity

    actor, trust = identity.actor_for(None, api_key_ok=True)
    # Importing a scan is a signed-out feature (principle 1), so there is
    # genuinely no user. The report must SAY that rather than imply the
    # attribution failed.
    check(actor == "anonymous", f"actor is 'anonymous'; got {actor!r}")
    check(trust == "unattributed", f"trust is 'unattributed'; got {trust!r}")

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
        check(False, "a missing FIREBASE_PROID still verified a token")
    except identity.CannotVerify:
        check(True, "with no FIREBASE_PROJECT_ID set, nothing verifies -- it "
                    "cannot silently accept everything")


def every_finished_job_emits_one_usage_record() -> None:
    print("\nthe cost record is a line a log query can add up")
    import identity

    line = identity.usage_line("j1", "uid:u-ali", "verified", 9, 12.34, "done")
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


def no_address_reaches_the_log() -> None:
    """The fix for the sharpest edge in design/APP_STORE_PRIVACY.md, held down.

    Three independent assertions, because each catches a different way of
    putting it back: the LINE, driven end to end from a token whose claims
    carry an address; the SIGNATURE, so no caller can pass one; and the JOB
    RECORD in server.py, which is where the address was parked between
    acceptance and billing.
    """
    print("\nno user's email address reaches Cloud Logging")
    import identity

    real = identity.verify_id_token
    identity.verify_id_token = lambda token: {
        "sub": "u-ali", "email": "ali@example.com",
        "name": "Ali Momeni", "email_verified": True}
    try:
        who = identity.actor_for("a.token.here", api_key_ok=False)
    finally:
        identity.verify_id_token = real

    # End to end: whatever actor_for answers is exactly what bill() spreads
    # into usage_line, so this is the line Cloud Logging would ingest.
    line = identity.usage_line("j1", who[0], who[1], 9, 12.3, "done")
    for leak in ("ali@example.com", "example.com", "Ali Momeni", "@"):
        check(leak not in line,
              f"the usage line contains no {leak!r}; got {line}")
    check("email" not in json.loads(line),
          f"the usage line has no email field at all; got {sorted(json.loads(line))}")

    # The signature, so the field cannot be reintroduced by a caller passing
    # one positionally into a parameter that still exists.
    params = list(inspect.signature(identity.usage_line).parameters)
    check(params == ["job_id", "actor", "trust", "pages", "seconds", "outcome"],
          f"usage_line takes no free-text detail parameter; got {params}")
    check(list(inspect.signature(identity.actor_for).parameters)
          == ["bearer", "api_key_ok"]
          and inspect.signature(identity.actor_for).return_annotation
              in ("tuple[str, str]", tuple[str, str]),
          "actor_for is annotated to return (actor, trust) only; got "
          f"{inspect.signature(identity.actor_for).return_annotation!r}")

    # And the job record, read from the source: the dict server.py keeps per
    # job is what bill() reads eight minutes later, and an address stored
    # there is an address one line away from the log again.
    server = (ROOT / "omr-service" / "server.py").read_text()
    code = "\n".join(l for l in server.splitlines()
                     if not l.lstrip().startswith("#"))
    check('"email"' not in code and "'email'" not in code,
          "server.py keeps no email key on the job record")
    check("claims.get(\"email\")" not in (ROOT / "omr-service" / "identity.py").read_text(),
          "identity.py never reads the email claim out of a verified token")


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
    a_misconfigured_server_does_not_break_signed_in_readers()
    a_signed_out_job_is_labelled_unattributed()
    the_audience_and_issuer_are_checked()
    every_finished_job_emits_one_usage_record()
    no_address_reaches_the_log()
    polling_is_not_billed()
    print()
    if FAILURES:
        print(f"{len(FAILURES)} FAILED")
        for f in FAILURES:
            print(f"  - {f}")
        return 1
    print("OK: every job says who it was for by uid, a bad token spends "
          "nothing,\n    and no address reaches the log")
    return 0


if __name__ == "__main__":
    sys.exit(main())
