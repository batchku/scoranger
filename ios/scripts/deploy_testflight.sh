#!/usr/bin/env bash
# Build, sign and upload a TestFlight build with no interaction.
#
#   ios/scripts/deploy_testflight.sh                # bump, archive, upload, wait
#   ios/scripts/deploy_testflight.sh --preflight    # check readiness, change nothing
#   ios/scripts/deploy_testflight.sh --no-bump      # reuse the current build number
#   ios/scripts/deploy_testflight.sh --no-wait      # don't block on processing
#
# Signing is manual and local: the identity and profile that bootstrap_signing.sh
# created. Nothing here needs an Apple ID session, an Xcode account or Apple's
# cloud-signing service -- the whole path is driven by the App Store Connect API
# key, which is what makes it runnable from a phone.
set -euo pipefail
cd "$(dirname "$0")/.."

# shellcheck source=./lib/deploy_common.sh
source "scripts/lib/deploy_common.sh"

PREFLIGHT_ONLY=0
BUMP=1
WAIT=1
for arg in "$@"; do
  case "$arg" in
    --preflight) PREFLIGHT_ONLY=1 ;;
    --no-bump)   BUMP=0 ;;
    --no-wait)   WAIT=0 ;;
    -h|--help)   sed -n '2,10p' "$0"; exit 0 ;;
    *)           die "unknown argument: $arg" ;;
  esac
done

# ---------------------------------------------------------------- preflight
say "preflight"
require_tools xcodebuild xcodegen security openssl
load_deploy_env
PY=$(python_with_cryptography)

# gitignored build inputs that a fresh clone will not have
[[ -d "Vendor/Python.xcframework" ]] || die "Vendor/Python.xcframework missing -- run scripts/fetch_python.sh"
[[ -d "PythonApp/app_packages" ]]    || die "PythonApp/app_packages missing -- run scripts/vendor_engine.sh"

[[ -f "$SIGNING_PROFILE" ]] || die "no provisioning profile at $SIGNING_PROFILE -- run scripts/bootstrap_signing.sh"
[[ -f "$KEYCHAIN_PATH" ]]   || die "no signing keychain at $KEYCHAIN_PATH -- run scripts/bootstrap_signing.sh"

security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
add_keychain_to_search_list
IDENTITY=$(security find-identity -v -p codesigning "$KEYCHAIN_PATH" \
  | grep "Apple Distribution" | head -1 | sed -E 's/.*"(.*)"/\1/' || true)
[[ -n "$IDENTITY" ]] || die "no Apple Distribution identity in $KEYCHAIN_PATH -- run scripts/bootstrap_signing.sh"

# a profile that expired mid-cycle produces a baffling codesign failure later
EXPIRY=$(security cms -D -i "$SIGNING_PROFILE" 2>/dev/null \
  | plutil -extract ExpirationDate raw - 2>/dev/null || echo "")
say "identity: $IDENTITY"
say "profile:  $PROFILE_NAME (expires ${EXPIRY:0:10})"

"$PY" scripts/lib/asc.py check >/dev/null \
  || die "the App Store Connect key cannot see its signing assets -- run scripts/lib/asc.py check"
say "App Store Connect key authenticates"

if [[ $PREFLIGHT_ONLY -eq 1 ]]; then
  say "preflight only: everything needed for a headless deploy is in place"
  exit 0
fi

# ------------------------------------------------------------- build number
if [[ $BUMP -eq 1 ]]; then
  say "bumping build number"
  scripts/bump_build.sh
else
  say "reusing the current build number"
  xcodegen generate >/dev/null
fi
BUILD_NUMBER=$(awk '/^ *CURRENT_PROJECT_VERSION:/ {print $2; exit}' project.yml)
[[ "$BUILD_NUMBER" =~ ^[0-9]+$ ]] || die "could not read the build number from project.yml"
say "building version $(awk '/^ *MARKETING_VERSION:/ {print $2; exit}' project.yml) build $BUILD_NUMBER"

# ------------------------------------------------------------------ archive
# Manual signing is forced here rather than in project.yml so that opening the
# project in Xcode still uses automatic development signing.
say "archiving (this takes a few minutes)"
rm -rf "$ARCHIVE_PATH"
xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE_PATH" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$IDENTITY" \
  PROVISIONING_PROFILE_SPECIFIER="$PROFILE_NAME" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  OTHER_CODE_SIGN_FLAGS="--keychain $KEYCHAIN_PATH" \
  | grep -E "error:|warning: (Provisioning|Signing)|ARCHIVE (SUCCEEDED|FAILED)" || true

[[ -d "$ARCHIVE_PATH" ]] || die "archive failed"
ARCHIVED_BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" \
  "$ARCHIVE_PATH/Products/Applications/$SCHEME.app/Info.plist")
[[ "$ARCHIVED_BUILD" == "$BUILD_NUMBER" ]] \
  || die "archive says build $ARCHIVED_BUILD but project.yml says $BUILD_NUMBER"
say "archived build $ARCHIVED_BUILD"

# ------------------------------------------------------- export and upload
say "exporting and uploading to TestFlight"
rm -rf "$EXPORT_DIR"
set +e
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportOptionsPlist ExportOptions.plist \
  -exportPath "$EXPORT_DIR" \
  -authenticationKeyPath "$ASC_KEY_FILE" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID" \
  > "build/export.log" 2>&1
EXPORT_STATUS=$?
set -e
if [[ $EXPORT_STATUS -ne 0 ]]; then
  grep -E "^error:" "build/export.log" | head -10 >&2 || true
  die "export/upload failed (exit $EXPORT_STATUS); full log at ios/build/export.log"
fi
say "upload accepted by App Store Connect"

# -------------------------------------------------------------------- wait
if [[ $WAIT -eq 1 ]]; then
  say "waiting for build $BUILD_NUMBER to finish processing"
  "$PY" scripts/lib/asc.py wait-build --version "$BUILD_NUMBER" \
    --bundle-identifier "$BUNDLE_ID" || \
    say "note: not VALID yet -- Apple's processing sometimes lags well past the upload"
fi

say "done: build $BUILD_NUMBER is on TestFlight"
