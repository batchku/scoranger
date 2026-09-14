#!/bin/zsh
# Renders the navigation-redesign screens to PNG.
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="file://$HERE/scoranger-navigation.html"
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
T=( n1 01-home            n2 02-library-pieces   n3 03-library-setlists
    n4 04-arrangement-picker n5 05-score-reading  n6 06-score-title-dropdown
    n7 07-score-more-menu  n8 08-more-menu-subscreen n9 09-score-edit-mode
    n10 10-score-performance-mode n11 11-score-ask-chat n12 12-iphone
    n13 13-components-and-gestures )
for k in ${=ONLY:-${(ok)T}}; do shot "screen=$k" "nav-${T[$k]}.png" 1180 886 2; done
rm -rf "$TMP"
echo "done -> $OUT"
