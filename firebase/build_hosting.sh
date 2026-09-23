#!/usr/bin/env bash
# Build the static site served at https://scoranger.web.app from the repo.
#
#   firebase/build_hosting.sh           # render, then refuse on any problem
#   (then)  cd firebase && firebase deploy --only hosting --project scoranger
#
# WHY THIS EXISTS. The live site was deployed once, by hand, from a directory
# that was never committed: one file, the apple-app-site-association that makes
# an invitation link open the app instead of Safari. A Firebase Hosting deploy
# REPLACES THE WHOLE SITE, so deploying anything else from this repo -- a
# privacy page, say -- would have deleted that file and broken every set-list
# invitation already sent. The AASA is now tracked at
# firebase/hosting/.well-known/, fetched byte-for-byte from the live release
# (2026-09-22), and every deploy carries it.
#
# The privacy policy is rendered from design/privacy-policy.md, which is the
# one copy of the text. It REFUSES while any "*[...]*" editorial placeholder
# remains: an App Review reviewer, or a reader, would otherwise be handed a page
# that says "Do not publish it as written".
set -euo pipefail
cd "$(dirname "$0")"

say() { printf '\033[1m==>\033[0m %s\n' "$*"; }
die() { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

command -v pandoc >/dev/null || die "pandoc is needed to render the policy (brew install pandoc)"

SRC=../design/privacy-policy.md
OUT=hosting/privacy/index.html
AASA=hosting/.well-known/apple-app-site-association

say "the invitation association is present and well formed"
[[ -s "$AASA" ]] || die "$AASA is missing -- a deploy without it breaks every invitation link"
python3 - "$AASA" <<'PY' || die "$AASA is not a valid association for this app"
import json, sys
d = json.load(open(sys.argv[1]))
details = d["applinks"]["details"]
ids = [i for x in details for i in (x.get("appIDs") or [x.get("appID")])]
assert "V9DBGV72NL.com.irllabs.scoranger" in ids, ids
paths = [c.get("/") for x in details for c in x.get("components", [])]
assert "/invite/*" in paths, paths
PY

say "the policy has no editorial placeholder left"
if grep -n '\*\[' "$SRC"; then
  die "design/privacy-policy.md still carries the placeholder(s) above; resolve them first"
fi

say "rendering $OUT"
mkdir -p "$(dirname "$OUT")"
# The source's opening note (italic, then a rule) is for whoever edits the
# file, not for the reader, so the page starts at the title and the date.
python3 - "$SRC" <<'PY' > /tmp/scoranger-policy.$$.md
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
text = re.sub(r"\A(# [^\n]+\n)\s*\*[^*]+?\*\s*\n---\s*\n", r"\1\n", text, flags=re.S)
sys.stdout.write(text)
PY
pandoc /tmp/scoranger-policy.$$.md --from gfm --to html5 --standalone \
  --metadata title="Scoranger privacy policy" \
  --variable pagetitle="Scoranger privacy policy" \
  --css=/privacy/style.css -o "$OUT"
rm -f /tmp/scoranger-policy.$$.md
cat > hosting/privacy/style.css <<'CSS'
:root { color-scheme: light dark; }
body { max-width: 42rem; margin: 2.5rem auto; padding: 0 1rem;
       font: 17px/1.55 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
h1 { font-size: 1.8rem; line-height: 1.2; }
h2 { margin-top: 2.2rem; font-size: 1.25rem; }
table { border-collapse: collapse; width: 100%; }
th, td { text-align: left; vertical-align: top; padding: .45rem .6rem;
         border-bottom: 1px solid color-mix(in srgb, currentColor 18%, transparent); }
header#title-block-header { display: none; }
CSS
say "built: $(wc -c < "$OUT" | tr -d ' ') bytes, plus the association"
