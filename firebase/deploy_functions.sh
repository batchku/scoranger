#!/usr/bin/env bash
# Deploy the callables in functions/index.js to the live project, all five,
# from one tree.
#
# This script exists because there was no script. The functions were deployed
# by hand with gcloud on the 8th and three of them again on the 9th, and the
# two that were not -- claimInvite and removeMember -- shipped in build 187 a
# day behind their source. The recipient tapped "Add to my set lists" and the
# old claimInvite, which knew nothing of open links, said the invitation was
# sent to a different address (design/FIREBASE.md §10.1.2).
#
# All five, always, so there is one tree deployed and not a mixture. gcloud
# rather than firebase-tools, because firebase-tools wants an interactive
# login this machine does not have; gcloud is signed in. Settings match what
# is deployed today: gen2, nodejs22, us-west1, 256M, 60s.
#
# Run: firebase/deploy_functions.sh            (asks first)
#      firebase/deploy_functions.sh --yes      (does not)
#
# This changes live infrastructure. Do not run it without the owner's word.
set -euo pipefail
cd "$(dirname "$0")"

PROJECT=scoranger
REGION=us-west1
FUNCTIONS=(shareSetlist createInvite claimInvite revokeInvite removeMember)

if [[ "${1:-}" != "--yes" ]]; then
  echo "About to deploy ${#FUNCTIONS[@]} callables to $PROJECT/$REGION from:"
  echo "  $(git log -1 --format='%h %s' -- functions/index.js)"
  read -r -p "Deploy? [y/N] " answer
  [[ "$answer" == [yY] ]] || { echo "not deployed"; exit 1; }
fi

# The suite first. A deploy of functions that fail their own tests is worse
# than no deploy, and this is the only place the two are forced together.
if [[ -z "${SKIP_TESTS:-}" ]]; then
  echo "==> functions.test.mjs against the emulator"
  JAVA_HOME="${JAVA_HOME:-/opt/homebrew/opt/openjdk}" \
    PATH="${JAVA_HOME:-/opt/homebrew/opt/openjdk}/bin:$PWD/node_modules/.bin:$PATH" \
    npm run --silent test:functions 2>&1 | grep -E "^[0-9]+/[0-9]+ passed|^  FAIL" \
    || { echo "the suite did not pass; not deploying"; exit 1; }
fi

for fn in "${FUNCTIONS[@]}"; do
  echo "==> $fn"
  gcloud functions deploy "$fn" --gen2 --runtime nodejs22 --region "$REGION" \
    --project "$PROJECT" --source functions --entry-point "$fn" \
    --trigger-http --memory 256M --timeout 60s --quiet \
    --format='value(name,updateTime,state)'
done

echo "==> deployed; every callable now dates from this tree:"
for fn in "${FUNCTIONS[@]}"; do
  printf '    %-14s %s\n' "$fn" \
    "$(gcloud functions describe "$fn" --gen2 --region "$REGION" --project "$PROJECT" \
         --format='value(updateTime,state)')"
done
