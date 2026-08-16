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

# job API flow: submit -> poll states -> fetch result (uses the 1-page PDF)
job=$(curl -s -X POST --data-binary @testdata/pdfs/test-1page.pdf -H "X-API-Key: $KEY" \
      "$URL/jobs" --max-time 60 | /usr/bin/python3 -c "import json,sys; print(json.load(sys.stdin).get('job',''))")
if [ -n "$job" ]; then
  jobstate=""
  for i in $(seq 1 60); do
    jobstate=$(curl -s -H "X-API-Key: $KEY" "$URL/jobs/$job" --max-time 15 \
      | /usr/bin/python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('state','?'), d.get('page',0), d.get('pages',0))")
    case "$jobstate" in done*|failed*) break ;; esac
    sleep 3
  done
  size=$(curl -s -H "X-API-Key: $KEY" "$URL/jobs/$job/result" --max-time 60 -o /tmp/omr-test-results/job.mxl -w "%{size_download}")
  if [[ "$jobstate" == done* ]] && [ "$size" -gt 1000 ]; then
    pass=$((pass+1)); printf "PASS job-api: %s, result %s bytes\n" "$jobstate" "$size"
  else
    fail=$((fail+1)); printf "FAIL job-api: state='%s' result=%s bytes\n" "$jobstate" "$size"
  fi
else
  fail=$((fail+1)); echo "FAIL job-api: no job id returned"
fi

for pdf in testdata/pdfs/*.pdf; do
  name=$(basename "$pdf")
  out="/tmp/omr-test-results/${name%.pdf}.mxl"
  result=$(curl -s -X POST --data-binary @"$pdf" -H "X-API-Key: $KEY" \
       "$URL/omr" -o "$out" -w "%{http_code} %{time_total}" --max-time 600)
  code=${result% *}; secs=${result#* }
  if [ "$code" = "429" ]; then  # single-instance capacity blip: retry once
    sleep 20
    result=$(curl -s -X POST --data-binary @"$pdf" -H "X-API-Key: $KEY" \
         "$URL/omr" -o "$out" -w "%{http_code} %{time_total}" --max-time 600)
    code=${result% *}; secs=${result#* }
  fi
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
