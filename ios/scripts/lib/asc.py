#!/usr/bin/env python3
"""App Store Connect API client for the headless TestFlight pipeline.

Everything the deploy path needs from Apple that is not `xcodebuild`:
creating the distribution certificate and provisioning profile, and watching
a build land in TestFlight. Authentication is an ES256 JWT signed with the
team's .p8 private key -- no Apple ID, no interactive session, no Xcode
account, which is what makes the pipeline headless.

Credentials come from the environment or from ios/.deploy.env (gitignored):

    ASC_KEY_ID       the key's 10-character id, e.g. MJ85RP93GW
    ASC_ISSUER_ID    the team's issuer UUID
    ASC_KEY_PATH     optional; defaults to the standard search paths below

The .p8 itself is never read into a shell variable or passed on a command
line: only its path travels, and only this process opens it.
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import plistlib
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

API = "https://api.appstoreconnect.apple.com/v1/"
REPO_ROOT = Path(__file__).resolve().parents[3]
IOS_DIR = REPO_ROOT / "ios"

# Apple's documented search paths for App Store Connect private keys.
KEY_SEARCH_DIRS = [
    Path.home() / ".appstoreconnect" / "private_keys",
    Path.home() / "private_keys",
    IOS_DIR / "private_keys",
]


class AscError(RuntimeError):
    """An error from the API or from our own preconditions."""


# --------------------------------------------------------------------------
# credentials


def _load_dotenv() -> None:
    """Fold ios/.deploy.env into the environment without clobbering real vars."""
    path = IOS_DIR / ".deploy.env"
    if not path.is_file():
        return
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        os.environ.setdefault(key, value)


def _key_path(key_id: str) -> Path:
    explicit = os.environ.get("ASC_KEY_PATH")
    if explicit:
        p = Path(explicit).expanduser()
        if not p.is_file():
            raise AscError(f"ASC_KEY_PATH points at a missing file: {p}")
        return p
    for d in KEY_SEARCH_DIRS:
        p = d / f"AuthKey_{key_id}.p8"
        if p.is_file():
            return p
    raise AscError(
        f"No AuthKey_{key_id}.p8 found in: "
        + ", ".join(str(d) for d in KEY_SEARCH_DIRS)
    )


def _b64(data: bytes) -> bytes:
    return base64.urlsafe_b64encode(data).rstrip(b"=")


def token() -> str:
    """A short-lived ES256 JWT for the App Store Connect API."""
    # imported lazily so `--help` and preflight work without cryptography
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import ec, utils

    _load_dotenv()
    key_id = os.environ.get("ASC_KEY_ID")
    issuer = os.environ.get("ASC_ISSUER_ID")
    if not key_id or not issuer:
        raise AscError(
            "ASC_KEY_ID and ASC_ISSUER_ID must be set (environment or "
            f"{IOS_DIR / '.deploy.env'}). See ios/.deploy.env.example."
        )
    private = serialization.load_pem_private_key(
        _key_path(key_id).read_bytes(), password=None
    )
    now = int(time.time())
    header = {"alg": "ES256", "kid": key_id, "typ": "JWT"}
    payload = {"iss": issuer, "iat": now, "exp": now + 600,
               "aud": "appstoreconnect-v1"}
    signing_input = _b64(json.dumps(header).encode()) + b"." + _b64(
        json.dumps(payload).encode())
    der = private.sign(signing_input, ec.ECDSA(hashes.SHA256()))
    r, s = utils.decode_dss_signature(der)
    sig = _b64(r.to_bytes(32, "big") + s.to_bytes(32, "big"))
    return (signing_input + b"." + sig).decode()


# --------------------------------------------------------------------------
# transport


def request(method: str, path: str, body: dict | None = None) -> dict:
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(
        API + path, data=data, method=method,
        headers={"Authorization": f"Bearer {token()}",
                 "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req) as response:
            raw = response.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        detail = e.read().decode()
        try:
            errors = json.loads(detail)["errors"]
            detail = "; ".join(
                f"{x.get('title','')}: {x.get('detail','')}" for x in errors)
        except Exception:
            detail = detail[:400]
        raise AscError(f"HTTP {e.code} on {method} {path} -- {detail}") from None


def get(path: str) -> dict:
    return request("GET", path)


# --------------------------------------------------------------------------
# commands


def cmd_check(args: argparse.Namespace) -> int:
    """Report what the key may do, and whether signing assets are in place."""
    probes = [
        ("apps?limit=1", "read apps"),
        ("builds?limit=1", "read builds"),
        ("certificates?limit=1", "read certificates"),
        ("profiles?limit=1", "read profiles"),
        ("bundleIds?limit=1", "read bundle IDs"),
        ("users?limit=1", "read users (Admin-only)"),
    ]
    print("App Store Connect API key")
    ok = True
    for path, label in probes:
        try:
            get(path)
            print(f"  [ok]   {label}")
        except AscError as e:
            ok = False
            print(f"  [FAIL] {label} -- {e}")
    print()

    certs = get("certificates?limit=200").get("data", [])
    dist = [c for c in certs
            if c["attributes"].get("certificateType") in
            ("IOS_DISTRIBUTION", "DISTRIBUTION")]
    print(f"Certificates visible to the key: {len(certs)}")
    for c in certs:
        a = c["attributes"]
        print(f"  {a.get('certificateType'):<20} {a.get('displayName','')[:36]:<38}"
              f" expires {a.get('expirationDate','')[:10]}  id={c['id']}")
    if not dist:
        print("  -> no API-manageable distribution certificate yet "
              "(run bootstrap_signing.sh)")
        ok = False

    profiles = [p for p in get("profiles?limit=200").get("data", [])
                if p["attributes"].get("profileType") == "IOS_APP_STORE"]
    print(f"\nApp Store profiles visible to the key: {len(profiles)}")
    for p in profiles:
        a = p["attributes"]
        print(f"  {a.get('name','')[:44]:<46} {a.get('profileState')}"
              f"  expires {a.get('expirationDate','')[:10]}")
    if not profiles:
        print("  -> no API-manageable App Store profile yet "
              "(run bootstrap_signing.sh)")
        ok = False
    return 0 if ok else 1


def cmd_create_cert(args: argparse.Namespace) -> int:
    """Create an IOS_DISTRIBUTION certificate from a CSR."""
    csr = Path(args.csr).read_text(encoding="utf-8")
    body = {"data": {"type": "certificates",
                     "attributes": {"certificateType": "IOS_DISTRIBUTION",
                                    "csrContent": csr}}}
    created = request("POST", "certificates", body)["data"]
    content = created["attributes"]["certificateContent"]
    out = Path(args.out)
    out.write_bytes(base64.b64decode(content))
    print(f"certificate id: {created['id']}")
    print(f"name:           {created['attributes'].get('displayName')}")
    print(f"expires:        {created['attributes'].get('expirationDate','')[:10]}")
    print(f"written to:     {out}")
    if args.id_file:
        Path(args.id_file).write_text(created["id"], encoding="utf-8")
    return 0


def cmd_bundle_id(args: argparse.Namespace) -> int:
    """Print the internal id of a bundle identifier."""
    for b in get("bundleIds?limit=200").get("data", []):
        if b["attributes"].get("identifier") == args.identifier:
            print(b["id"])
            return 0
    raise AscError(f"bundle id '{args.identifier}' not registered on the team")


def cmd_ensure_profile(args: argparse.Namespace) -> int:
    """Create (or reuse) an App Store profile and write the .mobileprovision."""
    existing = [p for p in get("profiles?limit=200").get("data", [])
                if p["attributes"].get("name") == args.name]
    profile = None
    if existing:
        p = existing[0]
        if p["attributes"].get("profileState") == "ACTIVE" and not args.force:
            profile = p
            print(f"reusing profile {p['id']} ({args.name})")
        else:
            # an invalid profile cannot be updated, only replaced
            request("DELETE", f"profiles/{p['id']}")
            print(f"deleted stale profile {p['id']}")
    if profile is None:
        body = {"data": {
            "type": "profiles",
            "attributes": {"name": args.name, "profileType": "IOS_APP_STORE"},
            "relationships": {
                "bundleId": {"data": {"id": args.bundle_id, "type": "bundleIds"}},
                "certificates": {"data": [{"id": args.cert_id,
                                           "type": "certificates"}]}}}}
        profile = request("POST", "profiles", body)["data"]
        print(f"created profile {profile['id']} ({args.name})")

    content = profile["attributes"]["profileContent"]
    raw = base64.b64decode(content)
    out = Path(args.out)
    out.write_bytes(raw)

    # Xcode locates profiles by their UUID filename, not by our name
    decoded = subprocess.run(["security", "cms", "-D", "-i", str(out)],
                             capture_output=True, check=True).stdout
    uuid = plistlib.loads(decoded)["UUID"]
    installed = (Path.home() / "Library/Developer/Xcode/UserData/"
                 "Provisioning Profiles" / f"{uuid}.mobileprovision")
    installed.parent.mkdir(parents=True, exist_ok=True)
    installed.write_bytes(raw)
    print(f"uuid:      {uuid}")
    print(f"installed: {installed}")
    return 0


def cmd_wait_build(args: argparse.Namespace) -> int:
    """Block until a build number shows up in App Store Connect."""
    apps = get(f"apps?filter[bundleId]={args.bundle_identifier}").get("data", [])
    if not apps:
        raise AscError(f"no app for bundle id {args.bundle_identifier}")
    app_id = apps[0]["id"]
    deadline = time.time() + args.timeout
    while time.time() < deadline:
        builds = get(f"builds?filter[app]={app_id}"
                     f"&filter[version]={args.version}").get("data", [])
        if builds:
            a = builds[0]["attributes"]
            print(f"build {args.version}: {a.get('processingState')}"
                  f" (uploaded {a.get('uploadedDate')})")
            if a.get("processingState") in ("VALID", "FAILED", "INVALID"):
                return 0 if a.get("processingState") == "VALID" else 1
        time.sleep(args.interval)
    print(f"build {args.version} did not register within {args.timeout}s. "
          "Apple sometimes lags; check App Store Connect directly.")
    return 1


def cmd_latest_builds(args: argparse.Namespace) -> int:
    apps = get(f"apps?filter[bundleId]={args.bundle_identifier}").get("data", [])
    if not apps:
        raise AscError(f"no app for bundle id {args.bundle_identifier}")
    builds = get(f"builds?filter[app]={apps[0]['id']}&limit={args.limit}"
                 "&sort=-uploadedDate").get("data", [])
    for b in builds:
        a = b["attributes"]
        print(f"  build {a['version']:>5}  {a['processingState']:<10}"
              f"  uploaded {a.get('uploadedDate','')}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("check", help="probe key permissions and signing assets"
                   ).set_defaults(func=cmd_check)

    p = sub.add_parser("create-cert", help="create an iOS distribution certificate")
    p.add_argument("--csr", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--id-file")
    p.set_defaults(func=cmd_create_cert)

    p = sub.add_parser("bundle-id", help="resolve a bundle identifier to its id")
    p.add_argument("identifier")
    p.set_defaults(func=cmd_bundle_id)

    p = sub.add_parser("ensure-profile", help="create/reuse an App Store profile")
    p.add_argument("--name", required=True)
    p.add_argument("--bundle-id", required=True)
    p.add_argument("--cert-id", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--force", action="store_true")
    p.set_defaults(func=cmd_ensure_profile)

    p = sub.add_parser("wait-build", help="wait for a build to register")
    p.add_argument("--version", required=True)
    p.add_argument("--bundle-identifier", default="com.irllabs.scoranger")
    p.add_argument("--timeout", type=int, default=1800)
    p.add_argument("--interval", type=int, default=30)
    p.set_defaults(func=cmd_wait_build)

    p = sub.add_parser("builds", help="list recent builds")
    p.add_argument("--bundle-identifier", default="com.irllabs.scoranger")
    p.add_argument("--limit", type=int, default=8)
    p.set_defaults(func=cmd_latest_builds)

    args = parser.parse_args()
    try:
        return args.func(args)
    except AscError as e:
        print(f"error: {e}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
