#!/usr/bin/env bash
# Shared configuration and helpers for the signing/deploy scripts.
# Sourced from ios/ as the working directory.

TEAM_ID="V9DBGV72NL"
BUNDLE_ID="com.irllabs.scoranger"
SCHEME="Scoranger"
PROJECT="Scoranger.xcodeproj"
PROFILE_NAME="Scoranger App Store (headless)"

# Signing material. Gitignored: a private key and a certificate belong on the
# machine, never in the repository.
SIGNING_DIR="$HOME/.scoranger-signing"
SIGNING_KEY="$SIGNING_DIR/distribution.key"
SIGNING_CSR="$SIGNING_DIR/distribution.csr"
SIGNING_CERT="$SIGNING_DIR/distribution.cer"
SIGNING_CERT_ID="$SIGNING_DIR/distribution.cert-id"
SIGNING_PROFILE="$SIGNING_DIR/appstore.mobileprovision"
KEYCHAIN_PATH="$HOME/Library/Keychains/scoranger-signing.keychain-db"

ARCHIVE_PATH="build/Scoranger.xcarchive"
EXPORT_DIR="build/export"

say()  { printf '\033[1m==>\033[0m %s\n' "$*"; }
die()  { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

require_tools() {
  for t in "$@"; do
    command -v "$t" >/dev/null 2>&1 || die "'$t' is not on PATH"
  done
}

# Credentials live in ios/.deploy.env (gitignored) or the environment.
# Values are never echoed.
load_deploy_env() {
  if [[ -f ".deploy.env" ]]; then
    set -a
    # shellcheck disable=SC1091
    source ".deploy.env"
    set +a
  fi
  [[ -n "${ASC_KEY_ID:-}" ]] || die "ASC_KEY_ID is not set (see ios/.deploy.env.example)"
  [[ -n "${ASC_ISSUER_ID:-}" ]] || die "ASC_ISSUER_ID is not set (see ios/.deploy.env.example)"
  KEYCHAIN_PASSWORD="${SIGNING_KEYCHAIN_PASSWORD:-}"
  [[ -n "$KEYCHAIN_PASSWORD" ]] || die "SIGNING_KEYCHAIN_PASSWORD is not set (see ios/.deploy.env.example)"
  ASC_KEY_FILE="${ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_$ASC_KEY_ID.p8}"
  [[ -f "$ASC_KEY_FILE" ]] || die "App Store Connect key not found at $ASC_KEY_FILE"
}

# The engine venv is the only interpreter here with `cryptography`, which the
# JWT signing needs.
python_with_cryptography() {
  for p in "../engine/.venv/bin/python" "$(command -v python3 || true)"; do
    [[ -n "$p" && -x "$p" ]] || continue
    if "$p" -c "import cryptography" >/dev/null 2>&1; then echo "$p"; return 0; fi
  done
  die "no python with the 'cryptography' module found (expected engine/.venv)"
}

# An Apple leaf certificate only forms a *valid* signing identity if the Apple
# WWDR intermediate is reachable. It lives in the login/System keychain here,
# but trust evaluation scoped to our dedicated keychain cannot be relied on to
# find it, so put a copy alongside the leaf.
ensure_wwdr_in_keychain() {
  if security find-certificate -c "Apple Worldwide Developer Relations" \
       "$KEYCHAIN_PATH" >/dev/null 2>&1; then
    return 0
  fi
  local tmp; tmp=$(mktemp -d)
  local pem="$tmp/wwdr.pem"
  local found=0
  for kc in "$HOME/Library/Keychains/login.keychain-db" /Library/Keychains/System.keychain; do
    if security find-certificate -c "Apple Worldwide Developer Relations" -p "$kc" \
         > "$pem" 2>/dev/null && [[ -s "$pem" ]]; then
      found=1; break
    fi
  done
  if [[ $found -eq 0 ]]; then
    # fall back to Apple's published intermediate (a public CA certificate)
    say "fetching the Apple WWDR intermediate"
    curl -fsSL "https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer" \
      -o "$tmp/wwdr.cer" || { rm -rf "$tmp"; die "could not obtain the Apple WWDR intermediate"; }
    openssl x509 -inform DER -in "$tmp/wwdr.cer" -out "$pem"
  fi
  security import "$pem" -k "$KEYCHAIN_PATH" -T /usr/bin/codesign >/dev/null 2>&1 || true
  rm -rf "$tmp"
  say "Apple WWDR intermediate present in the signing keychain"
}

# Apple names IOS_DISTRIBUTION certificates "iPhone Distribution: ..." and the
# newer universal DISTRIBUTION type "Apple Distribution: ...". Both sign an App
# Store build, so match either rather than one spelling.
distribution_identity() {
  security find-identity -v -p codesigning "$KEYCHAIN_PATH" 2>/dev/null \
    | grep -E '"(iPhone|Apple) Distribution' | head -1 | sed -E 's/.*"(.*)"/\1/'
}

add_keychain_to_search_list() {
  local current
  current=$(security list-keychains -d user | sed -E 's/^ *"(.*)"$/\1/')
  if ! grep -qF "$KEYCHAIN_PATH" <<<"$current"; then
    # shellcheck disable=SC2086
    security list-keychains -d user -s $(printf '"%s" ' $current) "$KEYCHAIN_PATH" >/dev/null
    say "added signing keychain to the search list"
  fi
}
