#!/bin/bash
# Fire every PDF in testdata/pdfs at the OMR service and report per-file results.
# Usage: omr-service/test_service.sh [service-url]
set -uo pipefail
cd "$(dirname "$0")/.."

URL="${1:-https://scoranger-omr-37kxlg2dpa-uc.a.run.app}"
KEY=$(cat .omr-api-key)
mkdir -p /tmp/omr-test-results

pass=0; fail=0

# misconfiguration matrix: every auth failure must surface as a clean 401 —
# never a 502 (the server must drain large bodies before answering)
BIGPDF=$(ls testdata/pdfs/*.pdf | head -1)
for label in "wrong-key" "empty-key"; do
  k=""; [ "$label" = "wrong-key" ] && k="not-the-key"
  code=$(curl -s -X POST --data-binary @"$BIGPDF" -H "X-API-Key: $k" \
       "$URL/omr" -o /dev/null -w "%{http_code}" --max-time 60)
  if [ "$code" = "401" ]; then
    pass=$((pass+1)); printf "PASS auth: %-12s -> clean 401\n" "$label"
  else
    fail=$((fail+1)); printf "FAIL auth: %-12s -> HTTP %s (expected 401)\n" "$label" "$code"
  fi
done

for pdf in testdata/pdfs/*.pdf; do
  name=$(basename "$pdf")
  out="/tmp/omr-test-results/${name%.pdf}.mxl"
  result=$(curl -s -X POST --data-binary @"$pdf" -H "X-API-Key: $KEY" \
       "$URL/omr" -o "$out" -w "%{http_code} %{time_total}" --max-time 600)
  code=${result% *}; secs=${result#* }
  size=$(stat -f%z "$out" 2>/dev/null || echo 0)
  # files named *-invalid-* or test-truncated* are corrupt on purpose:
  # a clean 4xx rejection is the correct outcome
  expect4xx=false
  case "$name" in test-truncated*|*-invalid-*) expect4xx=true ;; esac
  if [ "$code" = "200" ] && ! $expect4xx; then
    pass=$((pass+1)); status="PASS"
  elif $expect4xx && [ "${code:0:1}" = "4" ]; then
    pass=$((pass+1)); status="PASS"
  else
    fail=$((fail+1)); status="FAIL"
    # keep the error body readable
    mv "$out" "${out%.mxl}.error.json" 2>/dev/null
  fi
  printf "%-4s %-70s HTTP %-4s %6.1fs %8s bytes\n" "$status" "$name" "$code" "$secs" "$size"
done
echo "----"
echo "$pass passed, $fail failed"
exit $fail
