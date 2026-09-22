"""The app declares the required-reason APIs it uses, and so does every
embedded framework that links OpenSSL.

TWO SUBJECTS, TWO REJECTION CODES, and they are often confused:

  ITMS-91061 "Missing privacy manifest" is about SDKs on Apple's list of
  commonly used third-party SDKs. It is a WARNING that becomes a rejection at
  beta App Review. That is sections 1-3 below, and it is what blocked external
  TestFlight on 0.6.15.

  ITMS-91053 "Missing API declaration" is about REQUIRED-REASON APIs, applies
  to the app's own binary, and is an AUTOMATIC UPLOAD REJECTION. That is
  section 0, added for 0.12.0: the app target shipped no PrivacyInfo.xcprivacy
  at all through 0.11.0 while nine of its files use UserDefaults
  (design/APP_STORE_PRIVACY.md section 7).


Apple refused external TestFlight distribution of 0.6.15 with two ITMS-91061
warnings -- "Missing privacy manifest" for _hashlib.framework and
_ssl.framework, each naming OpenSSL/BoringSSL. OpenSSL is on Apple's list of
commonly used third-party SDKs, every SDK on that list must carry a
PrivacyInfo.xcprivacy at its bundle root, and external testing goes through
beta App Review, where a warning becomes a rejection. Internal testing never
noticed.

This checks the three things that can be checked without Apple:

  1. The manifests themselves say what they should. All four top-level keys
     present and explicit -- empty-versus-omitted is not documented as safe,
     and an invalid manifest is its own rejection (ITMS-91056). No tracking, no
     domains, no collected data, and exactly ONE required-reason declaration:
     FileTimestamp / C617.1.

     C617.1 rather than any of its three siblings: it is the one that covers
     "the timestamps, size, or other metadata of files inside the app
     container", which is what OpenSSL does when it stats a certificate or key
     file the app hands it. DDA9.1 is for showing a timestamp to the reader,
     3B52.1 for document-picker URLs, 0A2A.1 for SDKs forwarding on behalf of
     an app. And nothing else is declared, because a declared reason the code
     does not use is an inaccurate declaration.

  2. Every module that NEEDS one HAS one. The need is read from the binaries
     rather than from a list kept in a head: any framework in a built app
     whose binary carries OpenSSL symbols must have the file. That is the
     assertion that survives a payload upgrade adding a third such module.

  3. The build is wired to put them there -- the seed script exists, and the
     step that runs it comes BEFORE install_python, which is the only ordering
     that works: utils.sh moves the manifest into the framework and then signs
     it, so a manifest arriving later is a manifest outside the signature.

Run: engine/.venv/bin/python engine/scripts/check_privacy_manifests.py
"""

import plistlib
import re
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MANIFESTS = ROOT / "ios" / "PrivacyManifests"
PROJECT = ROOT / "ios" / "project.yml"
SEED = ROOT / "ios" / "scripts" / "seed_privacy_manifests.sh"

# What Apple's static check keys on. Only OpenSSL and BoringSSL/openssl_grpc
# from that list are in this app; libffi, mpdecimal, XZ, Zstandard and BZip2
# ship in the same payload and are NOT on it. Re-read the list each release.
CRYPTO = re.compile(rb"BORINGSSL|openssl_grpc|OPENSSL_|EVP_[A-Za-z]")

APP_MANIFEST = ROOT / "ios" / "Scoranger" / "PrivacyInfo.xcprivacy"

# Apple's required-reason API categories, and the SYMBOLS that put each one in
# a binary. Read off the binary rather than kept as a list of filenames,
# because the app's own code is not the only thing in the app's binary: SPM
# packages that build as STATIC libraries are linked INTO it, and Verovio --
# a local package with no manifest of its own -- is why FileTimestamp is
# declared. Grepping Swift would have missed it entirely.
#
# CACurrentMediaTime is counted under SystemBootTime although Apple's list
# names only `systemUptime` and `mach_absolute_time`. It is mach_absolute_time
# scaled to seconds and it reads the same boot-relative clock, and the brief's
# instruction was to err towards over-declaring. PerfMetrics and the page
# view's frame loop both call it.
REQUIRED_REASON_SYMBOLS = {
    "NSPrivacyAccessedAPICategoryUserDefaults": [
        "_OBJC_CLASS_$_NSUserDefaults"],
    "NSPrivacyAccessedAPICategoryFileTimestamp": [
        "_stat", "_fstat", "_lstat", "_fstatat", "_getattrlist",
        "_getattrlistbulk", "_fgetattrlist"],
    "NSPrivacyAccessedAPICategoryDiskSpace": [
        "_statfs", "_statvfs", "_fstatfs", "_fstatvfs"],
    "NSPrivacyAccessedAPICategorySystemBootTime": [
        "_mach_absolute_time", "_mach_continuous_time", "_CACurrentMediaTime"],
    # activeInputModes is an ObjC selector, not a linked symbol, so it is
    # looked for in the binary's strings rather than its symbol table.
    "NSPrivacyAccessedAPICategoryActiveKeyboards": [],
}

FAILURES: list[str] = []


def note(label: str, ok: bool) -> None:
    print(("  ok   " if ok else "  FAIL ") + label)
    if not ok:
        FAILURES.append(label)


# ------------------------------------------- 0. the app's own, for ITMS-91053
print("the app target's own privacy manifest")
note(f"{APP_MANIFEST.relative_to(ROOT)} exists", APP_MANIFEST.is_file())
app_plist: dict = {}
if APP_MANIFEST.is_file():
    with APP_MANIFEST.open("rb") as handle:
        try:
            app_plist = plistlib.load(handle)
        except Exception as error:
            note(f"the app manifest is a readable plist -- {error}", False)
    note("all four top-level keys are present and explicit",
         set(app_plist) == {"NSPrivacyTracking", "NSPrivacyTrackingDomains",
                            "NSPrivacyCollectedDataTypes",
                            "NSPrivacyAccessedAPITypes"})
    note("it declares no tracking and no tracking domains",
         app_plist.get("NSPrivacyTracking") is False
         and app_plist.get("NSPrivacyTrackingDomains") == [])
    declared = {a.get("NSPrivacyAccessedAPIType"): a.get("NSPrivacyAccessedAPITypeReasons")
                for a in app_plist.get("NSPrivacyAccessedAPITypes") or []}
    note(f"it declares at least one required-reason API -- an empty "
         f"declaration is ITMS-91053 with extra steps; got {sorted(declared)}",
         bool(declared))
    # UserDefaults is the one that is certain from the source, so it is
    # asserted from the source as well as from the binary below: a tree with
    # no build still has to fail if somebody deletes it.
    users = [p.relative_to(ROOT) for p in (ROOT / "ios/Scoranger").rglob("*.swift")
             if "UserDefaults" in p.read_text() or "@AppStorage" in p.read_text()]
    note(f"the app really does use UserDefaults, in {len(users)} files, so the "
         f"declaration is not speculative", len(users) >= 1)
    note("and UserDefaults is declared with CA92.1 -- app-private defaults, "
         "no suite name and no app group anywhere in the target",
         declared.get("NSPrivacyAccessedAPICategoryUserDefaults") == ["CA92.1"])
    note("every declaration carries at least one reason code",
         all(reasons for reasons in declared.values()))
    # Collected data types: the manifest and the questionnaire have to agree,
    # and the questionnaire is filled in from design/APP_STORE_PRIVACY.md.
    collected = {c.get("NSPrivacyCollectedDataType")
                 for c in app_plist.get("NSPrivacyCollectedDataTypes") or []}
    note("no collected data type is marked as used for tracking",
         all(c.get("NSPrivacyCollectedDataTypeTracking") is False
             for c in app_plist.get("NSPrivacyCollectedDataTypes") or []))
    note("Audio Data is NOT declared: dictation is on-device only "
         "(check_dictation.py), so no recording is collected at all",
         "NSPrivacyCollectedDataTypeAudioData" not in collected)
    note(f"it declares the seven data types section 5 of "
         f"design/APP_STORE_PRIVACY.md answers Yes to; got {len(collected)}",
         collected == {
             "NSPrivacyCollectedDataTypeEmailAddress",
             "NSPrivacyCollectedDataTypeName",
             "NSPrivacyCollectedDataTypePhotosorVideos",
             "NSPrivacyCollectedDataTypeOtherUserContent",
             "NSPrivacyCollectedDataTypeUserID",
             "NSPrivacyCollectedDataTypeProductInteraction",
             "NSPrivacyCollectedDataTypeOtherDiagnosticData"})
print()


# ------------------------------------------------------- 1. what they declare
manifests = sorted(MANIFESTS.glob("*.xcprivacy")) if MANIFESTS.is_dir() else []
note(f"there are manifests to ship: {[m.stem for m in manifests]}", bool(manifests))

for path in manifests:
    with path.open("rb") as handle:
        try:
            plist = plistlib.load(handle)
        except Exception as error:
            note(f"{path.name} is a readable plist -- {error}", False)
            continue
    note(f"{path.name}: all four keys are present and explicit",
         set(plist) == {"NSPrivacyTracking", "NSPrivacyTrackingDomains",
                        "NSPrivacyCollectedDataTypes", "NSPrivacyAccessedAPITypes"})
    note(f"{path.name}: declares no tracking and collects nothing",
         plist.get("NSPrivacyTracking") is False
         and plist.get("NSPrivacyTrackingDomains") == []
         and plist.get("NSPrivacyCollectedDataTypes") == [])
    accessed = plist.get("NSPrivacyAccessedAPITypes") or []
    note(f"{path.name}: one required-reason declaration, and it is "
         f"FileTimestamp / C617.1",
         len(accessed) == 1
         and accessed[0].get("NSPrivacyAccessedAPIType")
             == "NSPrivacyAccessedAPICategoryFileTimestamp"
         and accessed[0].get("NSPrivacyAccessedAPITypeReasons") == ["C617.1"])


# ---------------------------------------------- 2. every module that needs one
def frameworks_needing_a_manifest(app: Path) -> list[Path]:
    """Frameworks whose binary carries OpenSSL symbols."""
    needing = []
    for framework in sorted((app / "Frameworks").glob("*.framework")):
        binary = framework / framework.name.removesuffix(".framework")
        if not binary.is_file():
            continue
        try:
            symbols = subprocess.run(["nm", "-a", str(binary)],
                                     capture_output=True, timeout=120).stdout
        except Exception:
            continue
        if CRYPTO.search(symbols):
            needing.append(framework)
    return needing


# The NEWEST build, and its age printed. Sorted by path this picked whichever
# app sorted last, which in a worktree that has built before is a fossil from
# an earlier version -- and a fossil answers this question wrongly in both
# directions: a stale app without the manifests reports a failure already
# fixed, and a stale app WITH them would report a pass the current tree has
# not earned.
apps = sorted((ROOT.glob("ios/DerivedData*/Build/Products/*/Scoranger.app")),
              key=lambda p: p.stat().st_mtime)
# How new a build has to be to be evidence: newer than the things that decide
# what it should contain. A build made BEFORE the manifests existed cannot be
# expected to carry them, and failing on it says nothing except that a build
# cache is old -- noise that teaches people to ignore this check. A build made
# AFTER them and missing one is the actual failure.
SOURCES_OF_TRUTH = [*manifests, SEED, PROJECT, APP_MANIFEST]
CHANGED_AT = max((p.stat().st_mtime for p in SOURCES_OF_TRUTH if p.exists()),
                 default=0.0)

evidence = None
if not apps:
    print("\n  --   no built app anywhere under ios/DerivedData*.")
if apps:
    newest = apps[-1]
    age_hours = (time.time() - newest.stat().st_mtime) / 3600
    if newest.stat().st_mtime >= CHANGED_AT:
        evidence = newest
    else:
        print(f"\n  --   the newest build ({newest.relative_to(ROOT)}, "
              f"{age_hours:.1f}h old) predates the\n       manifests, so it is "
              f"not evidence either way. Rebuild, or rely on the deploy,\n"
              f"       which reads the archive it is about to upload.")

def app_code_binary(app: Path) -> Path | None:
    """Where the app's own compiled code is.

    In a Release build it is `Scoranger`. A DEBUG build puts it in
    `Scoranger.debug.dylib` and leaves a 58 KB launcher stub behind -- and the
    stub references none of these APIs, so reading it would report a clean
    binary for an app that uses three categories. The gate builds Debug.
    """
    for name in (f"{app.stem}.debug.dylib", app.stem):
        candidate = app / name
        if candidate.is_file() and candidate.stat().st_size > 1_000_000:
            return candidate
    return None


def categories_in(binary: Path) -> set[str]:
    """Which required-reason categories this binary actually reaches for."""
    symbols = subprocess.run(["nm", "-u", str(binary)],
                             capture_output=True, text=True, timeout=300).stdout
    present = set(symbols.split())
    found = {cat for cat, syms in REQUIRED_REASON_SYMBOLS.items()
             if present & set(syms)}
    # The one that is a selector rather than a link-time symbol.
    strings = subprocess.run(["strings", "-a", str(binary)],
                             capture_output=True, text=True, timeout=300).stdout
    if "activeInputModes" in strings.split():
        found.add("NSPrivacyAccessedAPICategoryActiveKeyboards")
    return found


if evidence is not None:
    app = evidence
    age_seconds = time.time() - app.stat().st_mtime

    # -- 0b. the app manifest, in the bundle Apple would receive -------------
    installed = app / "PrivacyInfo.xcprivacy"
    note("the built app carries PrivacyInfo.xcprivacy AT ITS BUNDLE ROOT -- "
         "anywhere else and Apple does not read it",
         installed.is_file())
    if installed.is_file() and APP_MANIFEST.is_file():
        note("and it is byte-for-byte the one in the repo",
             installed.read_bytes() == APP_MANIFEST.read_bytes())

    binary = app_code_binary(app)
    note("the app's compiled code was found to read symbols from",
         binary is not None)
    if binary is not None and app_plist:
        used = categories_in(binary)
        declared_set = {a.get("NSPrivacyAccessedAPIType")
                        for a in app_plist.get("NSPrivacyAccessedAPITypes") or []}
        # UNDER-declaring is the rejection. Read from the binary so that a
        # statically linked package -- Verovio is one, and has no manifest of
        # its own -- cannot add a category nobody notices.
        missing = used - declared_set
        note(f"every category the binary reaches for is declared; the binary "
             f"uses {sorted(c.replace('NSPrivacyAccessedAPICategory', '') for c in used)}"
             + (f" -- UNDECLARED: {sorted(missing)}" if missing else ""),
             not missing)
        # Over-declaring is safe with Apple and unsafe as documentation, so it
        # is REPORTED and not failed: the reader is told which declaration no
        # symbol backs, and can decide.
        for extra in sorted(declared_set - used):
            print(f"  --   {extra.replace('NSPrivacyAccessedAPICategory', '')} "
                  f"is declared and no symbol in this binary backs it. Safe "
                  f"with Apple,\n       inaccurate as documentation -- check "
                  f"it is still true.")

    needing = frameworks_needing_a_manifest(app)
    print(f"\n  built app: {app.relative_to(ROOT)} "
          f"(built {age_seconds / 3600:.1f}h ago)")
    note(f"the frameworks linking OpenSSL are the ones we know about: "
         f"{[f.stem for f in needing]}",
         {f.stem for f in needing} == {m.stem for m in manifests})
    missing = [f.stem for f in needing if not (f / "PrivacyInfo.xcprivacy").is_file()]
    note(f"each of them carries PrivacyInfo.xcprivacy"
         + (f" -- MISSING from {missing}" if missing else ""),
         not missing)
    for framework in needing:
        installed = framework / "PrivacyInfo.xcprivacy"
        if not installed.is_file():
            continue
        with installed.open("rb") as handle:
            try:
                shipped = plistlib.load(handle)
            except Exception as error:
                note(f"{framework.stem}'s installed manifest is readable -- {error}", False)
                continue
        source = MANIFESTS / f"{framework.stem}.xcprivacy"
        with source.open("rb") as handle:
            note(f"{framework.stem}'s installed manifest is the one in the repo",
                 shipped == plistlib.load(handle))
else:
    # No app to look at. This is NOT counted as a pass and NOT counted as a
    # failure, and the difference matters.
    #
    # A check that quietly skips its own subject is worse than no check, so
    # the temptation is to fail here. But this runs in run_checks.sh, which
    # runs on a clean checkout where nobody has built anything, and a check
    # that fails for a reason nobody can act on is a check that gets worked
    # around.
    #
    # So the enforcement lives where a build ALWAYS exists -- the deploy, which
    # reads the archive it is about to upload and refuses on a missing
    # manifest. What is asserted here instead is that the enforcement is still
    # there, which is the part that could quietly disappear.
    print("       The bundle itself was therefore not checked here. The archive "
          "IS checked by\n       the deploy, unconditionally; that it does so "
          "is asserted below.")

DEPLOY = ROOT / "ios" / "scripts" / "deploy_testflight.sh"
deploy = DEPLOY.read_text() if DEPLOY.is_file() else ""
note("the deploy refuses to upload an archive missing a manifest",
     "PrivacyInfo.xcprivacy" in deploy and "MISSING_MANIFESTS" in deploy)
note("and it decides which frameworks need one by reading their binaries",
     "BORINGSSL|openssl_grpc" in deploy)
# The app's own manifest has no seed script and no build phase to assert: it
# is an ordinary resource. The archive check IS the enforcement, so that the
# enforcement exists is the thing to hold down.
note("the deploy also refuses an archive whose APP carries no manifest, "
     "which is ITMS-91053 and an outright upload rejection",
     "ARCHIVED_APP/PrivacyInfo.xcprivacy" in deploy
     and "ITMS-91053" in deploy)
note("and it checks that manifest DECLARES something rather than merely "
     "existing",
     "NSPrivacyAccessedAPITypes:0:NSPrivacyAccessedAPIType" in deploy)


# ------------------------------------------------------------ 3. the wiring
note("the seed script is there and executable",
     SEED.is_file() and SEED.stat().st_mode & 0o111)
# COMMANDS, not prose. The first version of this compared positions in the
# whole file and failed on the word `install_python` inside the comment that
# explains the ordering -- a check reading the documentation of the thing it is
# checking. Comment lines are dropped, and each step is matched as the command
# it actually is.
def command_lines(text: str) -> list[str]:
    lines = []
    for raw in text.splitlines():
        stripped = raw.strip()
        if not stripped or stripped.startswith("#"):
            continue
        lines.append(stripped)
    return lines


def first_line_matching(lines: list[str], needle: str) -> int | None:
    for index, line in enumerate(lines):
        if needle in line:
            return index
    return None


project = PROJECT.read_text() if PROJECT.is_file() else ""
steps = command_lines(project)
seed_at = first_line_matching(steps, "seed_privacy_manifests.sh")
install_at = first_line_matching(steps, "install_python Vendor/")
note("the build runs it", seed_at is not None)
note("and runs it BEFORE install_python, which is what puts the manifest "
     "inside the signature",
     seed_at is not None and install_at is not None and seed_at < install_at)

if FAILURES:
    print(f"\nFAIL: {len(FAILURES)} privacy-manifest problem(s)")
    for line in FAILURES:
        print("   ", line)
    sys.exit(1)
print("\nOK: the app declares the required-reason APIs it uses, and every "
      "framework\n    that links OpenSSL carries an accurate privacy manifest")
