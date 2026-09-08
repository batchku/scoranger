#!/usr/bin/env bash
# Deploy the OMR service to Cloud Run, refusing while a transcription is running.
#
# The service keeps job state IN PROCESS MEMORY and runs with max-instances=1,
# so a deploy is a cutover that kills whatever is converting: the reader's
# progress bar stops moving and their PDF never becomes a score. There is no
# graceful hand-off to build -- the old instance drains on SIGTERM and the job
# dies with it -- so the protection is to not deploy at that moment, which is
# what the check below is for.
#
# THE ENV VARS ARE NOT PASSED. `--set-env-vars` REPLACES the whole set, so
# passing OMR_API_KEY would be required to avoid wiping it -- and that would
# put the key on a command line, in shell history and in this repo's logs.
# Omitted entirely, Cloud Run keeps the container's existing environment, so
# the key stays where it is and is never printed. Every other flag is passed
# explicitly and matches what the service already runs (4Gi / 2 cpu / 600s /
# concurrency 8 / max-instances 1 / no CPU throttling), so a deploy cannot
# quietly change the shape of the service:
#
#   --no-cpu-throttling is REQUIRED. Jobs run in a background thread between
#   polls and Cloud Run's default throttling freezes background work when no
#   request is in flight, which turns a 40s conversion into 3.5 minutes.
#
# ONE-TIME, BEFORE THE FIRST DEPLOY THAT CARRIES PER-USER ATTRIBUTION: the
# service needs to know which Firebase project's tokens to trust. Use
# --update-env-vars, which MERGES, and never --set-env-vars, which would
# replace the whole set and wipe OMR_API_KEY:
#
#   gcloud run services update scoranger-omr --region us-central1 \
#     --update-env-vars FIREBASE_PROJECT_ID=scoranger
#
# A project id is not a secret, so it is safe on a command line; the API key is
# not and stays where it is. Without it every signed-in request 401s while
# signed-out ones keep working, which reads as "sharing broke for people with
# accounts" -- the service says so in its boot log for exactly that reason.
#
# Usage:
#   omr-service/deploy.sh              # check, then deploy
#   omr-service/deploy.sh --check      # only say whether it is safe
#   omr-service/deploy.sh --force      # deploy anyway (say why in the commit)
set -uo pipefail
cd "$(dirname "$0")/.."

SERVICE=scoranger-omr
REGION=us-central1
QUIET_MINUTES=15

say()  { printf '\033[1m==>\033[0m %s\n' "$*"; }
die()  { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

MODE="${1:-deploy}"

say "current revision"
gcloud run services describe "$SERVICE" --region "$REGION" \
  --format="value(status.latestReadyRevisionName,status.conditions[0].lastTransitionTime)" \
  || die "cannot read the service; is gcloud pointed at the right project?"

# IS ANYTHING CONVERTING? There is no list-jobs endpoint -- job state is per
# instance and private -- so this reads the service's own log for the lines a
# conversion actually produces. A POST that started a job, or Audiveris's own
# per-sheet output, inside the quiet window means somebody is waiting.
say "looking for a transcription in flight (last ${QUIET_MINUTES}m)"
BUSY=$(gcloud logging read \
  "resource.type=cloud_run_revision AND resource.labels.service_name=${SERVICE} AND (textPayload:\"omr request /jobs\" OR textPayload:\"StepMonitoring\" OR textPayload:\"converting\")" \
  --freshness="${QUIET_MINUTES}m" --limit 5 --format="value(timestamp,textPayload)" 2>/dev/null)

if [[ -n "$BUSY" ]]; then
  echo "$BUSY" | sed 's/^/    /'
  if [[ "$MODE" != "--force" ]]; then
    die "a transcription looks to be in flight. Deploying now would kill it.
     Wait for it to finish (a page takes ~10s, a book a few minutes) and run
     this again, or pass --force if you know the job is abandoned."
  fi
  say "FORCED past a job that looks live -- somebody's conversion is dying for this"
else
  say "nothing converting in the last ${QUIET_MINUTES} minutes"
fi

[[ "$MODE" == "--check" ]] && { say "check only; not deploying"; exit 0; }

say "deploying (rebuilds Audiveris from source in Cloud Build -- around 10 minutes)"
gcloud run deploy "$SERVICE" \
  --source omr-service \
  --region "$REGION" \
  --memory 4Gi --cpu 2 \
  --timeout 600 --concurrency 8 --max-instances 1 \
  --no-cpu-throttling \
  --allow-unauthenticated \
  --quiet \
  || die "deploy failed; the previous revision is still serving"

say "new revision"
gcloud run services describe "$SERVICE" --region "$REGION" \
  --format="value(status.latestReadyRevisionName,status.conditions[0].lastTransitionTime)"
say "now verify the progress reads honestly: omr-service/verify_progress.sh"
