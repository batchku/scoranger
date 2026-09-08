#!/usr/bin/env python3
"""The promise that no login gates the app, asserted rather than intended.

The first of the owner's six principles for the 0.7 line (design/FIREBASE.md
§0, quoted there verbatim):

    LOCAL-FIRST; cloud OPTIONAL; no login should ever gate using the app.
    Everything works offline/signed-out; cloud is additive.

§9.1 already recommended the strong form of this -- no anonymous auth, and the
Firebase SDK not configured until someone signs in -- and §0.2 promoted it from
a recommendation to an invariant, because a property that holds only because
nobody has had a reason to break it is not an invariant, it is luck.

It is the promise a later refactor breaks QUIETLY. Turn journaling on by
default, or move `FirebaseApp.configure()` up into launch for convenience, and
nothing fails, nothing is visibly slower, and the promise is gone. Nobody finds
out until a user with no account watches the app reach for the network.

What this gate holds, and each of these was confirmed by breaking it:

  1. Signed out there is no journal: no file, no table, no `rev` on any
     document. A signed-out library is byte-for-byte what it always was.
  2. The default repository is the plain one. `repository_factory` is an
     injection point, and its DEFAULT is what a signed-out device gets.
  3. The library's own identity costs nothing. It is assigned before any
     account exists (§9.2), so it must not drag sync in behind it.
  4. Every op works with no account, because there is no account in the engine
     at all -- the engine has no Firebase dependency and cannot acquire one
     (§2: the engine runs on-device and a shipped client cannot hold
     service-account credentials).
  5. No shipped app source configures Firebase outside the one place allowed
     to, and today there is no such call anywhere. This is the static half of
     "signed out, the app makes no Firebase contact of any kind"; the runtime
     half is a UI test that walks every screen with no account.

Run: engine/.venv/bin/python engine/scripts/check_signed_out.py
"""
import json
import os
import re
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(ROOT / "engine"))

FAILURES: list[str] = []

# The ONE place that may bring Firebase up, when it exists. Until 0.7.2 there is
# no such file, and the gate asserts the stronger thing: nowhere at all.
SIGN_IN_SITE = "ios/Scoranger/Account/SignIn.swift"


def strip_comments(source: str) -> str:
    """Swift source with its comments removed.

    Crude on purpose -- it does not understand strings containing "//" -- and
    that is the right trade here: the only question asked of the result is
    whether a symbol appears in CODE, and a comment mentioning the symbol is
    exactly the false positive this exists to remove.
    """
    source = re.sub(r"/\*.*?\*/", "", source, flags=re.S)
    return re.sub(r"//[^\n]*", "", source)


def check(condition, message):
    print(f"    {'ok  ' if condition else 'FAIL'} {message}")
    if not condition:
        FAILURES.append(message)
    return condition


def fresh_workspace() -> Path:
    """A workspace of its own, on WHATEVER the module's default repository is.

    Deliberately does not set `repository_factory`. Pinning it to
    `SqliteRepository` here would make every assertion below pass by
    construction, and the refactor this gate exists to catch -- turning
    journaling on by default -- would sail through it. The default is the thing
    under test, so the default is what runs.
    """
    from scoranger_engine import workspace

    root = Path(tempfile.mkdtemp())
    os.environ["SCORANGER_WORKSPACE"] = str(root)
    workspace.WORKSPACE = root
    workspace._reset_repo_for_testing()
    return root


def a_library(root: Path):
    """A signed-out session that does real work: import, rename, delete."""
    from music21 import converter

    from scoranger_engine import ops, workspace

    import fixtures

    slug, _ = workspace.create_score("Morrison's Jig", fixtures.jig(bars=4))
    score = converter.parse(str(workspace.resolve_notation_path(slug)))
    ops.transpose(score, "M2")
    workspace.add_version(slug, score, "transpose", {"interval": "M2"})
    workspace.rename_score(slug, "Morrison's")
    second, _ = workspace.create_score("Banish Misfortune", fixtures.jig(bars=4))
    workspace.delete_score(second)
    workspace.rebuild_manifest()
    return slug


# -- 1, 2, 3. the engine, signed out ---------------------------------------

def a_signed_out_library_pays_nothing() -> None:
    print("\nsigned out, the library costs what it always did")
    root = fresh_workspace()
    a_library(root)

    from scoranger_engine import workspace

    check(not (root / "sync.db").exists(),
          "no journal file, after a whole import-arrange-rename-delete session")

    repo = workspace._repo()
    docs = [json.loads(json.dumps(d)) for d in repo.list_scores(include_deleted=True)]
    check(docs and all("rev" not in d for d in docs),
          "no score carries a rev")
    versions = [v for d in docs for v in repo.list_versions(d["slug"])]
    check(versions and all("rev" not in v for v in versions),
          "no version carries a rev")
    check(all("rev" not in (repo.get_library() or {}) for _ in [0]),
          "the library document carries no rev")

    tables = {r[0] for r in repo._conn.execute(
        "SELECT name FROM sqlite_master WHERE type = 'table'")}
    check("changes" not in tables and "journal" not in tables,
          f"the database has no journal table: {sorted(tables)}")


def the_default_repository_is_the_plain_one() -> None:
    print("\nthe injection point defaults to no sync")
    import importlib

    from scoranger_engine import db
    workspace = importlib.reload(importlib.import_module("scoranger_engine.workspace"))

    check(workspace.repository_factory is db.SqliteRepository,
          "workspace.repository_factory is SqliteRepository on a fresh import")

    source = (ROOT / "engine/scoranger_engine/workspace.py").read_text()
    check("import sync" not in source and "from . import sync" not in source
          and "from .sync" not in source,
          "workspace.py does not import the sync module at all")


def the_library_identity_drags_nothing_in() -> None:
    print("\nthe library has an identity and it is free")
    root = fresh_workspace()
    a_library(root)

    from scoranger_engine import ids, workspace

    library = workspace._repo().get_library()
    check(library is not None and ids.is_id(library.get("uid", "")),
          f"the library was given an id with no account in sight: {library}")
    check(not (root / "sync.db").exists(),
          "and assigning it started no journal")

    # assigned once: a second open finds it and leaves it alone
    was = library["uid"]
    workspace._reset_repo_for_testing()
    check(workspace._repo().get_library()["uid"] == was,
          "the id is assigned once and never rewritten")

    manifest = json.loads((root / "manifest.json").read_text())
    check((manifest.get("library") or {}).get("uid") == was,
          "and the app can read it out of the manifest")


# -- 4, 5. no Firebase anywhere it could reach a signed-out user ------------

def the_engine_cannot_acquire_a_cloud_dependency() -> None:
    print("\nthe engine has no way to phone anywhere")
    deps = (ROOT / "engine/pyproject.toml").read_text()
    for forbidden in ("firebase", "google-cloud", "google-auth", "requests", "httpx"):
        check(forbidden not in deps.lower(),
              f"engine/pyproject.toml does not depend on {forbidden}")

    # An IMPORT, not the word: several modules point at design/FIREBASE.md for
    # their rationale, which is the documentation working rather than a leak.
    reaching_out = re.compile(
        r"^\s*(?:import|from)\s+(firebase\w*|google\.\w+|google_\w+|requests|httpx|urllib\b|http\.client)",
        re.M)
    # Scanned over the engine AS SHIPPED, which is the vendored copy the app
    # embeds -- a stronger claim than scanning the repo, and the honest one.
    # `server.py` is `scor serve`, the desktop API behind the developer viewer;
    # it uses urllib and it is deliberately not vendored into the app.
    shipped = sorted((ROOT / "ios/PythonApp/app/scoranger_engine").glob("*.py"))
    check(bool(shipped), "the vendored engine is present to scan "
                         "(run ios/scripts/vendor_engine.sh)")
    check(not (ROOT / "ios/PythonApp/app/scoranger_engine/server.py").exists(),
          "scor serve is not vendored into the app")
    offenders = sorted(
        f"{p.name}: {m.group(1)}"
        for p in shipped for m in reaching_out.finditer(p.read_text()))
    check(not offenders,
          f"no module the app ships imports a network client: {offenders}")


def nothing_configures_firebase_at_launch() -> None:
    print("\nnothing brings Firebase up before someone asks for it")
    swift = sorted((ROOT / "ios/Scoranger").rglob("*.swift"))
    check(bool(swift), "there are Swift sources to scan")

    configure = re.compile(r"FirebaseApp\s*\.\s*configure")
    offenders = [str(p.relative_to(ROOT)) for p in swift
                 if configure.search(p.read_text())
                 and str(p.relative_to(ROOT)) != SIGN_IN_SITE]
    check(not offenders,
          f"only {SIGN_IN_SITE} may configure Firebase; found: {offenders}")

    # The Firebase SDK IS linked as of 0.7.2, and that is not the promise.
    # LINKING is not CONFIGURING: the framework can sit in the binary all day
    # without a signed-out launch touching the network. The assertion that
    # survived the change is the one above -- exactly one file may call
    # `configure()` -- plus these two, which say the call is reached by a
    # deliberate act and not by a view appearing.
    sign_in = ROOT / SIGN_IN_SITE
    check(sign_in.exists(),
          f"{SIGN_IN_SITE} exists, and is the one place allowed to configure Firebase")
    if sign_in.exists():
        source = sign_in.read_text()
        check("guard FirebaseApp.app() == nil else { return }" in source,
              "the configure call is guarded: FirebaseApp.configure() traps on a "
              "second call, and a second sign-in in one session would make one")
        # Reached from a sign-in method, never from a lifecycle hook. `.task`,
        # `onAppear` and `init` all fire without anybody asking to sign in.
        for hook in ("func body", ".task {", ".onAppear"):
            check(hook not in source,
                  f"{SIGN_IN_SITE} contains no {hook!r}: configuring Firebase must "
                  "be reached by pressing a button, not by a view appearing")

    # CODE, not prose. A comment in ScorangerApp.swift explaining that it does
    # NOT configure Firebase used to fail this, which is the check being wrong
    # about its own subject: what matters is whether launch REACHES Firebase.
    app_entry = strip_comments(
        (ROOT / "ios/Scoranger/ScorangerApp.swift").read_text())
    check("Firebase" not in app_entry,
          "ScorangerApp.swift does not USE Firebase: launch is the one path "
          "every signed-out reader takes")


def firebase_clients_stay_in_one_folder() -> None:
    """Nothing outside `Account/` may reach for a Firebase client.

    Not tidiness. `Auth.auth()`, `Firestore.firestore()`, `Storage.storage()`
    and `Functions.functions()` all TRAP when no `FirebaseApp` has been
    configured -- they do not return nil and they do not throw -- and in this
    app nothing configures Firebase until somebody presses a sign-in button.

    So every one of those calls is a crash on a signed-out launch unless it is
    guarded, and keeping them in one folder is what makes "is it guarded?" a
    question with a readable answer. Spread through the views it becomes a
    property of the order SwiftUI happens to render in, which is not a property
    anybody can check.

    Found by reading the code rather than by a crash: `SharedSetlists.uid` was
    `Auth.auth().currentUser?.uid` with no guard, reachable only because the
    band that renders it happens to test for an account first.
    """
    print("\nno view can trap by asking Firebase a question")
    clients = re.compile(r"\b(Auth\s*\.\s*auth|Firestore\s*\.\s*firestore"
                         r"|Storage\s*\.\s*storage|Functions\s*\.\s*functions)\b")
    swift = sorted((ROOT / "ios/Scoranger").rglob("*.swift"))
    offenders = sorted(
        str(p.relative_to(ROOT)) for p in swift
        if clients.search(strip_comments(p.read_text()))
        and "/Account/" not in str(p))
    check(not offenders,
          "only ios/Scoranger/Account/ may reach for a Firebase client "
          f"(they trap when Firebase is not up); found: {offenders}")

    # And inside Account/, the ONE accessor that asks who is signed in is
    # guarded. Every other path in that folder reads through it.
    store = ROOT / "ios/Scoranger/Account/SharedSetlists.swift"
    check(store.exists(), "the shared setlist store exists to scan")
    if store.exists():
        source = store.read_text()
        check("guard FirebaseApp.app() != nil else { return nil }" in source,
              "SharedSetlists.currentUid guards on FirebaseApp before calling "
              "Auth.auth(), which traps when nothing has configured Firebase")
        body = strip_comments(source)
        # Two: the guarded accessor, and the sign-out/listener plumbing that
        # runs only behind it. A third is a path that skipped the accessor.
        uses = len(re.findall(r"Auth\s*\.\s*auth", body))
        check(uses <= 2,
              f"Auth.auth() appears {uses} times in SharedSetlists.swift; "
              "every path should read through the guarded `currentUid`")


def google_sign_in_cannot_be_called_without_its_configuration() -> None:
    """The 0.7.0 build 183 crash, as a check.

    `GIDSignIn.sharedInstance.signIn(withPresenting:)` raises an OBJECTIVE-C
    NSException when no configuration has been set -- "No active
    configuration" -- and the process aborts. Ali tapped Sign in with Google
    and the app died.

    **The reason this is a source check and not a test is the important part.**
    An NSException is not a Swift `Error`. The `do/catch` wrapped around that
    call could never have caught it, no error handling added afterwards can,
    and there is no runtime seam to assert on. The only defence is that the
    precondition is satisfied before the call, so that is what is checked.
    """
    print("\nGoogle sign-in has its client id before it is asked to sign in")
    site = ROOT / SIGN_IN_SITE
    check(site.exists(), f"{SIGN_IN_SITE} exists")
    if not site.exists():
        return
    source = strip_comments(site.read_text())

    calls = re.search(r"GIDSignIn\s*\.\s*sharedInstance\s*\.\s*signIn", source)
    check(calls is not None, "the Google sign-in call is in this file")
    check("GIDConfiguration(clientID:" in source,
          "a GIDConfiguration is built -- without one, signIn raises an "
          "NSException that no Swift catch can contain")
    check("GIDSignIn.sharedInstance.configuration =" in source,
          "and it is assigned to GIDSignIn.sharedInstance.configuration")

    # ORDER, not just presence: configured before called, in the same function.
    if calls is not None:
        configure_at = source.find("GIDSignIn.sharedInstance.configuration =")
        # The call site is reached via configureGoogleIfNeeded(); assert the
        # helper is invoked before the signIn call rather than merely existing.
        guarded = re.search(
            r"configureGoogleIfNeeded\(\)[\s\S]{0,400}?"
            r"GIDSignIn\s*\.\s*sharedInstance\s*\.\s*signIn", source)
        check(guarded is not None,
              "configureGoogleIfNeeded() is called BEFORE signIn, not merely "
              "defined -- a helper nobody calls is how this shipped")
        check(configure_at != -1, "the assignment is present")

    # The client id comes from Firebase's parse of GoogleService-Info.plist,
    # not from a second copy that could disagree with it.
    check("options.clientID" in source,
          "the client id is read from FirebaseApp options, so there is one "
          "source of truth for which project this build talks to")


def apple_sign_in_never_swallows_its_errors() -> None:
    """A tap that does nothing and says nothing is the worst outcome.

    The Apple button's `onCompletion` failure branch was written to ignore
    cancellation and, in doing so, ignored every error including the one that
    was really happening: the `com.apple.developer.applesignin` entitlement is
    absent, so `ASAuthorizationController` fails at once. Ali tapped it and got
    silence.
    """
    print("\nApple sign-in reports what went wrong")
    site = ROOT / SIGN_IN_SITE
    source = strip_comments(site.read_text()) if site.exists() else ""
    check("ASAuthorizationError" in source and ".canceled" in source,
          "cancellation is identified BY ITS CODE, so it is the only silence "
          "and every other failure reaches the reader")
    check("appleIsAvailable" in source,
          "availability is a property, so the button can be disabled with a "
          "reason rather than looking live and doing nothing")
    # Both halves of the filename, because the code names them separately as
    # `forResource:` and `withExtension:` -- the contiguous string
    # "embedded.mobileprovision" never appears, which is how the first version
    # of this assertion failed against correct code.
    check('"embedded"' in source and '"mobileprovision"' in source
          and "com.apple.developer.applesignin" in source,
          "availability is read from the app's OWN embedded.mobileprovision, "
          "so the button starts working when the capability is enabled with no "
          "code change to remember")


def main() -> int:
    a_signed_out_library_pays_nothing()
    the_default_repository_is_the_plain_one()
    the_library_identity_drags_nothing_in()
    the_engine_cannot_acquire_a_cloud_dependency()
    nothing_configures_firebase_at_launch()
    firebase_clients_stay_in_one_folder()
    google_sign_in_cannot_be_called_without_its_configuration()
    apple_sign_in_never_swallows_its_errors()

    print()
    if FAILURES:
        print(f"{len(FAILURES)} FAILED")
        for f in FAILURES:
            print(f"  - {f}")
        return 1
    print("OK: signed out, the app is what it always was, and nothing reaches out")
    return 0


if __name__ == "__main__":
    sys.exit(main())
