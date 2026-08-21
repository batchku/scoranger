#!/usr/bin/env bash
# One-time signing setup for headless TestFlight deploys.
#
# Creates a *local* iOS distribution identity: a private key that lives on this
# machine, a certificate issued for it by Apple through the App Store Connect
# API, and an App Store provisioning profile bound to both. After this runs,
# `deploy_testflight.sh` can sign and upload with no Apple ID session, no Xcode
# account and no cloud-signing permission.
#
# This is deliberately separate from the deploy script: it mutates the Apple
# developer account (distribution certificates are a limited, shared resource
# -- an account gets very few, and revoking one invalidates everything signed
# with it). Run it once, on purpose.
#
#   ios/scripts/bootstrap_signing.sh          # create what is missing
#   ios/scripts/bootstrap_signing.sh --force  # replace the profile
#
set -euo pipefail
cd "$(dirname "$0")/.."

# shellcheck source=./lib/deploy_common.sh
source "scripts/lib/deploy_common.sh"

FORCE=""
[[ "${1:-}" == "--force" ]] && FORCE="--force"

require_tools openssl security
load_deploy_env
PY=$(python_with_cryptography)

mkdir -p "$SIGNING_DIR"
chmod 700 "$SIGNING_DIR"

# -- 1. private key + CSR ---------------------------------------------------
# The private key never leaves this machine; Apple only ever sees the CSR.
if [[ -f "$SIGNING_KEY" ]]; then
  say "reusing existing private key $SIGNING_KEY"
else
  say "generating a 2048-bit RSA private key"
  openssl genrsa -out "$SIGNING_KEY" 2048 2>/dev/null
  chmod 600 "$SIGNING_KEY"
fi
say "building certificate signing request"
openssl req -new -key "$SIGNING_KEY" -out "$SIGNING_CSR" \
  -subj "/CN=Scoranger headless distribution/O=$TEAM_ID/C=US"

# -- 2. certificate from Apple ---------------------------------------------
if [[ -f "$SIGNING_CERT" && -f "$SIGNING_CERT_ID" && -z "$FORCE" ]]; then
  say "reusing certificate id $(cat "$SIGNING_CERT_ID")"
else
  say "asking App Store Connect for an iOS distribution certificate"
  "$PY" scripts/lib/asc.py create-cert \
    --csr "$SIGNING_CSR" --out "$SIGNING_CERT" --id-file "$SIGNING_CERT_ID"
fi
CERT_ID=$(cat "$SIGNING_CERT_ID")

# -- 3. keychain ------------------------------------------------------------
# A dedicated keychain, not the login one: signing must work while the Mac is
# locked, and we must not need the user's login password to authorise codesign.
if [[ ! -f "$KEYCHAIN_PATH" ]]; then
  say "creating signing keychain $KEYCHAIN_PATH"
  security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
fi
security set-keychain-settings "$KEYCHAIN_PATH"          # no auto-lock timeout
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"

say "importing certificate and private key"
# -A would allow any binary to use the key; we scope it to the signing tools
security import "$SIGNING_CERT" -k "$KEYCHAIN_PATH" -T /usr/bin/codesign \
  -T /usr/bin/security -T /usr/bin/productsign >/dev/null 2>&1 || true
security import "$SIGNING_KEY" -k "$KEYCHAIN_PATH" -T /usr/bin/codesign \
  -T /usr/bin/security -T /usr/bin/productsign >/dev/null 2>&1 || true

# Without this, codesign blocks on a GUI prompt the first time it touches the
# key -- the single most common cause of a "headless" build hanging forever.
security set-key-partition-list -S apple-tool:,apple:,codesign: \
  -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH" >/dev/null 2>&1 || true

ensure_wwdr_in_keychain
add_keychain_to_search_list

IDENTITY=$(distribution_identity)
[[ -n "$IDENTITY" ]] || die "the distribution identity did not import; \
check that $SIGNING_KEY matches the certificate Apple issued"
say "signing identity ready: $IDENTITY"

# -- 4. provisioning profile ------------------------------------------------
say "resolving bundle id $BUNDLE_ID"
BUNDLE_INTERNAL_ID=$("$PY" scripts/lib/asc.py bundle-id "$BUNDLE_ID")
say "ensuring App Store profile \"$PROFILE_NAME\""
"$PY" scripts/lib/asc.py ensure-profile \
  --name "$PROFILE_NAME" \
  --bundle-id "$BUNDLE_INTERNAL_ID" \
  --cert-id "$CERT_ID" \
  --out "$SIGNING_PROFILE" $FORCE

say ""
say "signing bootstrap complete. Deploy with:"
say "    ios/scripts/deploy_testflight.sh"
