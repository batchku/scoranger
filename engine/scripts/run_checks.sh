#!/usr/bin/env bash
# Every check_*.py, in one run.
#
# They were run by hand before, one name at a time, from a list kept in a head.
# A check nobody remembers to run is a check that is not there -- the same
# failure mode the checks themselves exist to catch.
#
# Usage: engine/scripts/run_checks.sh [name-fragment]
set -uo pipefail
cd "$(dirname "$0")/../.."
PY=engine/.venv/bin/python
ONLY="${1:-}"
pass=0; fail=0; failed=()
for c in engine/scripts/check_*.py; do
  name=$(basename "$c" .py)
  [[ -z "$ONLY" || "$name" == *"$ONLY"* ]] || continue
  if out=$("$PY" "$c" 2>&1); then
    printf '  ok   %s\n' "$name"; pass=$((pass+1))
  else
    printf '  FAIL %s\n' "$name"; echo "$out" | tail -12 | sed 's/^/         /'
    fail=$((fail+1)); failed+=("$name")
  fi
done
echo
echo "checks: $pass passed, $fail failed"
(( fail == 0 )) || { printf 'failed: %s\n' "${failed[*]}"; exit 1; }
