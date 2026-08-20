#!/usr/bin/env bash
# Increment the app's build number (CURRENT_PROJECT_VERSION in project.yml) and
# regenerate the Xcode project. That value is the single source of truth: it
# ships as CFBundleVersion, App Store Connect records it verbatim (ExportOptions
# has manageAppVersionAndBuildNumber=false), and the app's footer reads it back
# out of Info.plist at runtime.
set -euo pipefail
cd "$(dirname "$0")/.."

current=$(awk '/^ *CURRENT_PROJECT_VERSION:/ {print $2; exit}' project.yml)
[[ "$current" =~ ^[0-9]+$ ]] || { echo "could not read CURRENT_PROJECT_VERSION from project.yml" >&2; exit 1; }
next=$((current + 1))

# the leading spaces keep it inside the settings block, not any other key
sed -i '' "s/^\( *CURRENT_PROJECT_VERSION: \)$current\$/\1$next/" project.yml
xcodegen generate >/dev/null
echo "build number $current -> $next"
