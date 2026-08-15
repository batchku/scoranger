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

# Verovio as a local SPM package (its Package.swift uses unsafeFlags, which
# SPM rejects in version-pinned remote dependencies)
if [ ! -d Vendor/verovio ]; then
  git clone --depth 1 --branch version-6.2.1 https://github.com/rism-digital/verovio Vendor/verovio
  # drop the test target — its default path overlaps VerovioCore's sources
  /usr/bin/python3 -c "
p = 'Vendor/verovio/Package.swift'
src = open(p).read()
open(p, 'w').write(src.replace(''',
        .testTarget(
            name: \"VerovioToolkitTests\",
            dependencies: [\"VerovioToolkit\"]
        )''', ''))
"
fi
