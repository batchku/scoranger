#!/bin/zsh
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="file://$HERE/scoranger-modal-free.html"
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
T=( v0 00-library-merged  v1 01-library-row-hamburger  v2 02-piece-screen  v3 03-arrangement-screen
    v4 04-move-to-piece-screen   v5 05-setlists-screen  v6 06-setlist-inline-reveal
    v7 07-inline-patterns        v8 08-score-options-screens  v9 09-title-switcher-band
    v10 10-settings-screens )
for k in ${=ONLY:-${(ok)T}}; do shot "screen=$k" "mf-${T[$k]}.png" 1180 886 2; done
rm -rf "$TMP"
echo "done -> $OUT"
