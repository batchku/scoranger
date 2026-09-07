#!/usr/bin/env bash
# Put a privacy manifest inside every embedded Python framework that needs one.
#
# Apple rejected external TestFlight distribution of 0.6.15 with two
# ITMS-91061 warnings: "Missing privacy manifest" for
# Frameworks/_hashlib.framework/_hashlib and Frameworks/_ssl.framework/_ssl,
# each naming OpenSSL/BoringSSL. Those two CPython extension modules link
# OpenSSL, which is on Apple's list of commonly used third-party SDKs, and
# every SDK on that list must carry a PrivacyInfo.xcprivacy at its bundle
# root. Warnings do not block internal testing; they DO block an external
# group, because external testing goes through beta App Review. That is what
# Ali was blocked on.
#
# WHY SEEDING THE PAYLOAD RATHER THAN WRITING THE FRAMEWORKS DIRECTLY.
# BeeWare's utils.sh already has the hook: as it turns each .so into a
# framework it looks for `<module>.xcprivacy` beside the .so, moves it in as
# PrivacyInfo.xcprivacy, and then code-signs the framework -- in that order,
# which is what makes the manifest part of the signed bundle. Writing the
# frameworks ourselves afterwards would mean re-implementing that signing.
# So this drops the files where install_stdlib's rsync will carry them into
# the bundle, and the existing hook does the rest.
#
# The manifests are CHECKED IN (ios/PrivacyManifests/) and the payload is not:
# Vendor/ is gitignored and re-fetched, so anything written into it is
# temporary by design. This runs on every build, so a re-fetched payload is
# re-seeded without anybody remembering to.
#
# The declaration itself: no tracking, no tracking domains, no collected data
# -- OpenSSL collects nothing -- and one required-reason API. Both binaries
# import `stat` and `fstat`, which is Apple's FileTimestamp category, declared
# C617.1: "the timestamps, size, or other metadata of files inside the app
# container". OpenSSL stats certificate and key files the app hands it, and
# C617.1's own wording covers metadata other than timestamps, so it is the
# accurate code rather than the nearest one. Neither binary imports statfs,
# getattrlist, sysctl or mach_absolute_time, so disk space and system boot
# time are not declared -- an unused declaration is an inaccurate one.
#
# Verified by engine/scripts/check_privacy_manifests.py, and by the deploy,
# which will not upload an archive whose frameworks are missing theirs.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
IOS_DIR="$(dirname "$HERE")"
MANIFESTS="$IOS_DIR/PrivacyManifests"
PAYLOAD="${1:-$IOS_DIR/Vendor/Python.xcframework}"

[[ -d "$MANIFESTS" ]] || { echo "seed-privacy: no $MANIFESTS" >&2; exit 1; }
[[ -d "$PAYLOAD" ]] || { echo "seed-privacy: no Python payload at $PAYLOAD" >&2; exit 1; }

shopt -s nullglob
found=0
seeded=0
for manifest in "$MANIFESTS"/*.xcprivacy; do
  module="$(basename "$manifest" .xcprivacy)"
  found=$((found + 1))
  placed=0
  # Every slice and every architecture: the device build reads ios-arm64 and
  # the simulator build reads the simulator slice's own arch folder, so a file
  # in only one of them is a manifest that appears in only one kind of build.
  for dynload in "$PAYLOAD"/*/lib-*/python3.*/lib-dynload; do
    [[ -d "$dynload" ]] || continue
    # Only where the module actually is. A manifest beside a .so that does not
    # exist would be moved into no framework and silently do nothing.
    if compgen -G "$dynload/$module.*.so" > /dev/null; then
      cp "$manifest" "$dynload/$module.xcprivacy"
      placed=$((placed + 1))
    fi
  done
  if (( placed == 0 )); then
    echo "seed-privacy: $module has a manifest but no .so in the payload." >&2
    echo "              Either the module is gone or its name changed; a" >&2
    echo "              manifest that lands nowhere is worse than none." >&2
    exit 1
  fi
  seeded=$((seeded + placed))
  echo "seed-privacy: $module -> $placed slice(s)"
done

(( found > 0 )) || { echo "seed-privacy: no manifests in $MANIFESTS" >&2; exit 1; }
echo "seed-privacy: $found manifest(s), $seeded copies placed"
