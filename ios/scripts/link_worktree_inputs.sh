#!/bin/bash
# Link a git worktree's gitignored build inputs to the main checkout.
#
# WHY THIS EXISTS. A `git worktree` gets the tracked files and nothing else,
# and this build needs six things that are deliberately untracked: two large
# vendored trees, a Python venv, the UI tests' sample scores, and two API keys
# baked into the bundle at build time. Miss one and the build still succeeds --
# it just produces an app that is quietly missing a piece, and the failure
# surfaces twenty minutes later inside the gate looking like a code defect:
#
#   testdata      -> "the seeded library never appeared", and every UI test
#                    that opens a score fails
#   .env          -> "the key fields do not say which key is in use"
#   .omr-api-key  -> the same
#   Vendor        -> no Python framework, no Verovio: the build fails outright,
#                    which is the honest one of the six
#
# That cost the 0.6.10 release three void gate runs, found one failure at a
# time, because each missing input was fixed as it appeared instead of the set
# being enumerated once. The paths below are the whole set: everything
# .gitignore excludes that project.yml's build phases or the engine actually
# read. Adding a new one means adding it here.
#
# Symlinks, not copies: Vendor alone is over a gigabyte, and a copied venv
# would resolve `scoranger_engine` to the wrong checkout -- see the note in
# CLAUDE.md about the engine a worktree's `scor` actually runs.
#
# Usage, from anywhere inside the worktree:
#   ios/scripts/link_worktree_inputs.sh [path-to-main-checkout]
set -euo pipefail
cd "$(dirname "$0")/../.."

MAIN="${1:-$(git worktree list --porcelain | awk '/^worktree /{print $2; exit}')}"
HERE="$(pwd -P)"
[[ -d "$MAIN" ]] || { echo "no main checkout at $MAIN" >&2; exit 1; }
if [[ "$(cd "$MAIN" && pwd -P)" == "$HERE" ]]; then
  echo "this IS the main checkout -- nothing to link."
  exit 0
fi

INPUTS=(
  ios/Vendor                # Python.xcframework + verovio + the sound bank
  engine/.venv              # the only interpreter with music21 and cryptography
  testdata                  # the UI tests' seeded library
  .env                      # OpenRouter key, baked into the bundle
  .omr-api-key              # OMR key, baked into the bundle
  ios/.deploy.env           # App Store Connect credentials
)

missing=0
for p in "${INPUTS[@]}"; do
  if [[ ! -e "$MAIN/$p" ]]; then
    printf '  %-24s absent from the main checkout too -- skipped\n' "$p"
    missing=1
    continue
  fi
  mkdir -p "$(dirname "$p")"
  ln -sfn "$MAIN/$p" "$p"
  printf '  %-24s linked\n' "$p"
done

# These two are GENERATED rather than linked: vendor_engine.sh writes a
# snapshot of this worktree's own engine, and linking them would make every
# worktree ship whichever engine the main checkout happens to be on.
for p in ios/PythonApp/app_packages ios/PythonApp/app/scoranger_engine; do
  [[ -e "$p" ]] || { echo "  $p missing -- run ios/scripts/vendor_engine.sh"; missing=1; }
done

echo
if (( missing )); then
  echo "some inputs are still missing; the gate will fail in ways that look like code."
  exit 1
fi
echo "every gitignored build input is in place."
