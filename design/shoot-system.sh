#!/bin/zsh
# Renders the combined-system screens (scoranger-system.html) to PNG.
# Same trick as shoot.sh: Chrome writes the file and then will not exit, so each
# run is backgrounded, polled for its output, and killed.
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
HERE="$(cd "$(dirname "$0")" && pwd)"
SYS="file://$HERE/scoranger-system.html"
OUT="$HERE/png"; mkdir -p "$OUT"
TMP=$(mktemp -d)

shot () {  # url_query  outfile  width  height  scale
  local q="$1" out="$OUT/$2" w="$3" h="$4" sc="$5"
  rm -f "$out"
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --no-first-run \
    --force-device-scale-factor="$sc" --user-data-dir="$TMP/u$RANDOM" \
    --virtual-time-budget=4000 --window-size="$w,$h" \
    --screenshot="$out" "$SYS?$q" >/dev/null 2>&1 &
  local pid=$! i=0
  while (( i < 60 )); do
    if [[ -s "$out" ]]; then sleep 0.6; break; fi
    sleep 0.5; (( i++ ))
  done
  kill $pid 2>/dev/null; pkill -P $pid 2>/dev/null
  [[ -s "$out" ]] && echo "  ok   $2" || echo "  FAIL $2"
}

typeset -A T
T=( s1 01-resting-score-first  s2 02-library-overlay     s3 03-chat-overlay
    s4 04-working-both-panels  s5 05-pencil-markup       s6 06-highlight-passage
    s7 07-arrangement-details  s8 08-settings            s9 09-alerts
    s10 10-states              s11 11-iphone-compact     s12 12-tokens-and-controls )
for k in ${ONLY:-${(ok)T}}; do shot "screen=$k" "system-${T[$k]}.png" 1180 886 2; done
rm -rf "$TMP"
echo "done -> $OUT"
