#!/bin/bash
# Vendors the pure-Python engine into the iOS app tree.
#   PythonApp/app/           bridge.py + scoranger_engine (copied from ../engine)
#   PythonApp/app_packages/  music21 + pure-Python deps
# Re-run after changing engine code. Requires python3.14 on PATH (bytecode
# magic must match the embedded 3.14 runtime).
set -euo pipefail
cd "$(dirname "$0")/.."

PY=../engine/.venv/bin/python
APP=PythonApp/app
PKGS=PythonApp/app_packages

rm -rf "$PKGS" "$APP/scoranger_engine"
mkdir -p "$APP" "$PKGS"

# engine sources (server/render/chat/cli are host-only; the bridge replaces them)
mkdir -p "$APP/scoranger_engine"
for f in __init__.py ops.py workspace.py db.py; do
  cp "../engine/scoranger_engine/$f" "$APP/scoranger_engine/"
done

"$PY" -m pip install --quiet --no-deps --target "$PKGS" \
  music21 chardet joblib jsonpickle more-itertools webcolors \
  requests certifi urllib3 idna charset_normalizer

# strip what the app never uses. music21/__init__ imports both `corpus` and
# `test`, so keep all .py code and delete only the bundled score data.
find "$PKGS/music21/corpus" -type f ! -name "*.py" -delete
find "$PKGS/music21/corpus" -type d -empty -delete
rm -rf "$PKGS"/*.dist-info "$PKGS/bin"

# drop compiled speedups (mypyc darwin .so in chardet/charset_normalizer wheels)
# — wrong platform for iOS and App Store validation rejects them; the pure
# Python fallbacks remain importable.
find "$PKGS" -name "*.so" -delete
find "$PKGS" -name "*.fwork" -delete

# precompile (write_bytecode=0 at runtime, so ship .pyc)
"$PY" -m compileall -q "$APP" "$PKGS"

echo "vendored: $(du -sh $PKGS | cut -f1) packages, $(du -sh $APP | cut -f1) app"
