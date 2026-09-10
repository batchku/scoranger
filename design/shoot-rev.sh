#!/bin/zsh
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="file://$HERE/scoranger-nav-revision.html"
OUT="$HERE/png"; mkdir -p "$OUT"
TMP=$(mktemp -d)
shot () {
  local q="$1" out="$OUT/$2" w="$3" h="$4" sc="$5"
  rm -f "$out"
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --no-first-run \
    --force-device-scale-factor="$sc" --user-data-dir="$TMP/u$RANDOM" \
    --virtual-time-budget=4000 --window-size="$w,$h" \
    --screenshot="$out" "$SRC?$q" >/dev/null 2>&1 &
  local pid=$! i=0
  while (( i < 60 )); do
    if [[ -s "$out" ]]; then sleep 0.6; break; fi
    sleep 0.5; (( i++ ))
  done
  kill $pid 2>/dev/null; pkill -P $pid 2>/dev/null
  [[ -s "$out" ]] && echo "  ok   $2" || echo "  FAIL $2"
}
typeset -A T
T=( r1 1-library-browse-clean  r2 2-library-edit-mode  r3 3-move-to-piece
    r4 4-arrangement-sheet-actions  r5 5-plus-menu  r6 6-paged-one-page
    r7 7-paged-spread-pan )
for k in ${=ONLY:-${(ok)T}}; do shot "screen=$k" "rev-${T[$k]}.png" 1180 886 2; done
rm -rf "$TMP"
echo "done -> $OUT"
