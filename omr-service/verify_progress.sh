#!/usr/bin/env bash
# Does the transcription's progress read honestly?
#
# Ali's report: the bar reads a full "reading page 8 of 8" from the first
# second of a conversion to the last. The cause is in this service --
# SHEET_MARK also matched the sheet LIST Audiveris prints in its first second
# ("Book reaching PAGE on sheets:[#1#2#3#4#5#6#7#8]"), whose last number is
# the page TOTAL, so `page` jumped to `pages` before a sheet had been read.
# Fixed in the source on 2026-09-04 by anchoring the pattern to the logger
# prefix; the running revision predates that by three weeks.
#
# So this measures the thing the reader sees. It runs a REAL multi-page
# conversion against the deployed service and records every (page, pages) the
# job API reports. The bug's signature is unmistakable and needs no judgement:
# page == pages on every single poll.
#
# The key is read from the repo's gitignored .omr-api-key and passed as a
# HEADER from a variable -- never on a command line, where it would land in
# shell history and in logs.
#
# Usage: omr-service/verify_progress.sh [pdf]
set -uo pipefail
cd "$(dirname "$0")/.."

PDF="${1:-testdata/pdfs/test-scan.pdf}"
URL="${OMR_URL:-https://scoranger-omr-37kxlg2dpa-uc.a.run.app}"
KEYFILE=".omr-api-key"

say() { printf '\033[1m==>\033[0m %s\n' "$*"; }
die() { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

[[ -f "$PDF" ]] || die "no PDF at $PDF"
[[ -f "$KEYFILE" ]] || die "no $KEYFILE (gitignored; copy it from the main checkout)"
KEY="$(tr -d '\r\n' < "$KEYFILE")"
[[ -n "$KEY" ]] || die "$KEYFILE is empty"

say "revision under test"
gcloud run services describe scoranger-omr --region us-central1 \
  --format="value(status.latestReadyRevisionName)" 2>/dev/null || echo "  (gcloud unavailable)"

say "starting a job: $(basename "$PDF")"
START=$(curl -s -m 120 -X POST -H "X-API-Key: $KEY" \
  --data-binary "@$PDF" "$URL/jobs") || die "could not reach the service"
JOB=$(printf '%s' "$START" | sed -n 's/.*"job"[: ]*"\([^"]*\)".*/\1/p')
PAGES=$(printf '%s' "$START" | sed -n 's/.*"pages"[: ]*\([0-9]*\).*/\1/p')
[[ -n "$JOB" ]] || die "no job id in: ${START:0:200}"
say "job $JOB, $PAGES pages"

PINNED=0
POLLS=0
SEEN=""
FIRST_PAGE=""
for _ in $(seq 1 120); do
  BODY=$(curl -s -m 30 -H "X-API-Key: $KEY" "$URL/jobs/$JOB")
  STATE=$(printf '%s' "$BODY" | sed -n 's/.*"state"[: ]*"\([^"]*\)".*/\1/p')
  PAGE=$(printf '%s' "$BODY" | sed -n 's/.*"page"[: ]*\([0-9]*\).*/\1/p')
  if [[ "$STATE" == "converting" && -n "$PAGE" ]]; then
    POLLS=$((POLLS + 1))
    [[ -z "$FIRST_PAGE" ]] && FIRST_PAGE="$PAGE"
    [[ "$PAGE" == "$PAGES" ]] && PINNED=$((PINNED + 1))
    case " $SEEN " in *" $PAGE "*) ;; *) SEEN="$SEEN $PAGE" ;; esac
    printf '    page %s of %s\n' "$PAGE" "$PAGES"
  fi
  [[ "$STATE" == "done" || "$STATE" == "failed" ]] && break
  sleep 2
done

say "state: ${STATE:-unknown}"
say "polls while converting: $POLLS; distinct pages reported:${SEEN:- none}"
[[ "$STATE" == "done" ]] || die "the conversion did not finish (state=${STATE:-unknown})"
(( POLLS > 0 )) || die "never observed the converting state; nothing to judge"

# THE BUG, stated as the thing the reader sees: the counter goes straight to
# the last page and stays there.
#
# The first version of this test asked for "two distinct values" and "not
# every poll pinned", and the broken service PASSED it -- it reports 0 before
# Audiveris has printed anything, then 4, then 4 forever, which is two
# distinct values and three unpinned polls. It would have rubber-stamped the
# deploy it exists to check.
#
# Climbing means an INTERMEDIATE page: a number that is neither "nothing yet"
# nor the total. On a 4-page score that is a 2 or a 3, and the fixed service
# reports them because it is reading the per-sheet lines rather than the sheet
# list. Zero and the total prove nothing.
DISTINCT=$(printf '%s' "$SEEN" | wc -w | tr -d ' ')
MIDDLE=0
for value in $SEEN; do
  if (( value > 0 && value < PAGES )); then MIDDLE=$((MIDDLE + 1)); fi
done

if (( PAGES < 3 )); then
  say "NOTE: a $PAGES-page score has no intermediate page to report; "\
"use a longer one to judge this (testdata/pdfs/test-scan.pdf is 4)."
  exit 0
fi

if (( MIDDLE == 0 )); then
  die "progress never reports an intermediate page. It went $SEEN on a
     $PAGES-page score -- $PINNED of $POLLS polls at the last page -- which is
     a full bar reading \"page $PAGES of $PAGES\" for the whole conversion.
     This is the SHEET_MARK bug: the pattern is matching the sheet LIST
     Audiveris prints in its first second, whose last number is the TOTAL.
     Fixed in omr-service/server.py on 2026-09-04; deploy it with
     omr-service/deploy.sh."
fi
say "OK: progress climbs -- pages reported:$SEEN of $PAGES "\
"($MIDDLE intermediate, $PINNED of $POLLS polls at the last page)"
