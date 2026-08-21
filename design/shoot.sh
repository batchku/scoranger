#!/bin/zsh
# Render every option of the deck to PNG. Chrome headless writes the file and
# then refuses to exit on this machine, so each run is backgrounded, polled for
# its output file, and killed — only PIDs we spawned are ever killed.
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
HERE="$(cd "$(dirname "$0")" && pwd)"
HTML="file://$HERE/scoranger-design-options.html"
SYS="file://$HERE/scoranger-system.html"
OUT="$HERE/png"; mkdir -p "$OUT"
TMP=$(mktemp -d)

shot () {  # url_query  outfile  width  height  scale  [base_url]
  local q="$1" out="$OUT/$2" w="$3" h="$4" sc="$5" base="${6:-$HTML}"
  rm -f "$out"
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --no-first-run \
    --force-device-scale-factor="$sc" --user-data-dir="$TMP/u$RANDOM" \
    --virtual-time-budget=4000 --window-size="$w,$h" \
    --screenshot="$out" "$base?$q" >/dev/null 2>&1 &
  local pid=$!
  local i=0
  while (( i < 60 )); do
    if [[ -s "$out" ]]; then sleep 0.6; break; fi
    sleep 0.5; (( i++ ))
  done
  kill $pid 2>/dev/null
  pkill -P $pid 2>/dev/null
  [[ -s "$out" ]] && echo "  ok   $2" || echo "  FAIL $2"
}

typeset -A NAME
NAME=(
  1A q1-palette-A-paper-clay      1B q1-palette-B-blueprint        1C q1-palette-C-acid-lab
  2A q2-type-A-inter-tight        2B q2-type-B-space-grotesk       2C q2-type-C-archivo-expanded
  3A q3-scale-A-compressed        3B q3-scale-B-extreme-contrast   3C q3-scale-C-mono-forward
  4A q4-mood-A-gallery            4B q4-mood-B-instrument-panel    4C q4-mood-C-zine
  5A q5-layout-A-flush-columns    5B q5-layout-B-floating-panes    5C q5-layout-C-score-first
  6A q6-signature-A-numbers       6B q6-signature-B-ledger         6C q6-signature-C-tape
  7A q7-theme-A-light             7B q7-theme-B-true-dark          7C q7-theme-C-stage-mode
)
for code in ${ONLY:-${(ok)NAME}}; do shot "shot=$code" "${NAME[$code]}.png" 1180 740 2; done
for q in ${SHEETS:-1 2 3 4 5 6 7};  do shot "sheet=$q" "sheet-q$q.png" 1200 2760 1; done
[[ -n "$SKIPSPEC" ]] || shot "spec=1" "q2-typeface-specimens.png" 1000 620 2
rm -rf "$TMP"
echo "done -> $OUT"
