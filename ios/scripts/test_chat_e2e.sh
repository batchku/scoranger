#!/bin/bash
# End-to-end chat test on the simulator: real OpenRouter call, real engine.
# Regression for the "(no reply)" bug: an open-ended arrangement prompt must
# produce a non-empty textual reply (and usually new score versions).
# Usage: ios/scripts/test_chat_e2e.sh [simulator-udid] [prompt]
set -uo pipefail
cd "$(dirname "$0")/.."

UDID="${1:-DC20324D-C7D2-4828-8DAC-0BE2242B8BF2}"
PROMPT="${2:-Add an arrangement starting with this score: make it richer, your choice how.}"
SLUG="test-1page"

xcrun simctl boot "$UDID" 2>/dev/null
xcrun simctl install "$UDID" DerivedData/Build/Products/Debug-iphonesimulator/Scoranger.app || exit 1
C=$(xcrun simctl get_app_container "$UDID" com.irllabs.scoranger data)

# make sure the target score exists (import the 1-page mxl result if needed)
if [ ! -d "$C/Documents/workspace/$SLUG" ]; then
  mkdir -p "$C/Documents/inbox"
  cp /tmp/omr-test-results/test-1page.mxl "$C/Documents/inbox/$SLUG.mxl" 2>/dev/null || {
    echo "NOTE: seeding $SLUG via PDF conversion (slower)"; cp ../testdata/pdfs/test-1page.pdf "$C/Documents/inbox/"; }
fi

rm -f "$C/Documents/outbox-chat/e2e.result.json"
mkdir -p "$C/Documents/inbox-chat"
/usr/bin/python3 -c "
import json, sys
print(json.dumps({'score': '$SLUG', 'message': '''$PROMPT''', 'model': 'gemini-flash'}))
" > "$C/Documents/inbox-chat/e2e.json.tmp"

xcrun simctl terminate "$UDID" com.irllabs.scoranger 2>/dev/null
xcrun simctl launch "$UDID" com.irllabs.scoranger > /dev/null

# wait for the score to exist (in case it was just seeded), then submit
for i in $(seq 1 60); do
  [ -d "$C/Documents/workspace/$SLUG" ] && break
  sleep 5
done
mv "$C/Documents/inbox-chat/e2e.json.tmp" "$C/Documents/inbox-chat/e2e.json"

for i in $(seq 1 90); do
  if [ -f "$C/Documents/outbox-chat/e2e.result.json" ]; then break; fi
  sleep 4
done

RESULT="$C/Documents/outbox-chat/e2e.result.json"
if [ ! -f "$RESULT" ]; then echo "FAIL: no chat result after 6 min"; exit 1; fi
/usr/bin/python3 - "$RESULT" << 'EOF'
import json, sys
d = json.load(open(sys.argv[1]))
reply = (d.get("reply") or "").strip()
if not d.get("ok"):
    print(f"FAIL: chat errored: {d.get('error')}"); sys.exit(1)
if not reply or reply == "(no reply)":
    print(f"FAIL: empty reply: {d!r}"); sys.exit(1)
print("PASS: reply =", reply[:400])
EOF
