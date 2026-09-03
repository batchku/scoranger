#!/usr/bin/env bash
# The gate: everything that can FAIL, and nothing that cannot.
#
# The sweeps (VisualSweep, DesignerSweep, RowShot, InkShot, InkZoomShot) carry
# no assertions about the product -- they photograph the app for a human to
# look at. Measured across twelve gate logs they were 43.6 of the gate's 76
# minutes, and nine of its ten most expensive tests. A screenshot cannot fail a build, so paying for it on every
# run buys nothing.
#
# They are NOT deleted and NOT unrunnable. To take a set of sweeps:
#   xcodebuild test -project Scoranger.xcodeproj -scheme Scoranger \
#     -destination "$DEST" -only-testing:ScorangerUITests/VisualSweep
#
# Usage: scripts/gate.sh [destination-id]
set -euo pipefail
cd "$(dirname "$0")/.."
DEVICE="${1:-}"
DEST="platform=iOS Simulator,${DEVICE:+id=$DEVICE}"
[[ -n "$DEVICE" ]] || DEST="platform=iOS Simulator,name=iPad Pro 11-inch (M5)"

exec xcodebuild test \
  -project Scoranger.xcodeproj -scheme Scoranger -destination "$DEST" \
  -skip-testing:ScorangerUITests/VisualSweep \
  -skip-testing:ScorangerUITests/DesignerSweep \
  -skip-testing:ScorangerUITests/RowShot \
  -skip-testing:ScorangerUITests/InkShot \
  -skip-testing:ScorangerUITests/InkZoomShot \
  "${@:2}"
