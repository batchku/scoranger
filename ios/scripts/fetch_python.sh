#!/bin/bash
# Downloads the BeeWare CPython iOS distribution into ios/Vendor/.
# Vendor/ is gitignored (large binaries); run this once per clone.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="3.14-b10"
URL="https://github.com/beeware/Python-Apple-support/releases/download/${VERSION}/Python-${VERSION%-*}-iOS-support.${VERSION#*-}.tar.gz"

if [ -d Vendor/Python.xcframework ]; then
  echo "Vendor/Python.xcframework already present; delete it to re-fetch."
  exit 0
fi
mkdir -p Vendor
echo "Fetching $URL"
curl -L --fail "$URL" | tar -xz -C Vendor
echo "done: $(du -sh Vendor/Python.xcframework | cut -f1)"
