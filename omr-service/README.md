# Scoranger OMR service

[Audiveris](https://github.com/audiveris/audiveris) batch mode behind a
one-endpoint HTTP service, for Cloud Run. The iPad app POSTs a PDF and gets
back compressed MusicXML — the same pipeline that runs on the Mac, relocated.

```
POST /omr      raw PDF body + X-API-Key header  ->  .mxl bytes
GET  /healthz                                   ->  {"ok": true}
```

## Deploy (Cloud Run)

```sh
gcloud run deploy scoranger-omr \
  --source omr-service \
  --region us-central1 \
  --memory 4Gi --cpu 2 \
  --timeout 600 --concurrency 8 --max-instances 1 \
  --no-cpu-throttling \
  --allow-unauthenticated \
  --set-env-vars OMR_API_KEY=<random-secret>
```

Notes:
- `--allow-unauthenticated` + the `OMR_API_KEY` header keeps the client simple
  (no Google auth on-device) while still gating access.
- `--concurrency 8` so progress polls can land while a conversion runs; an
  internal lock still serializes Audiveris itself.
- `--max-instances 1` because job state lives in process memory (polls must
  reach the instance that owns the job).
- `--no-cpu-throttling` is REQUIRED: jobs run in a background thread between
  polls, and Cloud Run's default throttling freezes background work when no
  request is in flight (a 40s conversion becomes 3.5 minutes).
- First deploy compiles Audiveris from source in Cloud Build (~10 min).

## Text on the page: OCR and processing switches

Lyrics, chord symbols, titles and part names all reach the export through
Audiveris's TEXTS step, which is Tesseract. Audiveris 5.11 asks Tesseract for
its **legacy** recogniser, and the Debian/Ubuntu `tesseract-ocr-*` packages
are built from tessdata_fast, which holds the LSTM model and none of the
legacy components. With those files Audiveris logs `Could not initialize
TessBaseAPI languages: eng in legacy mode` and reads no text at all for the
rest of the run — which is what "the scan lost the lyrics" looked like.

So the image takes `eng` and `fra` from the tessdata repository, pinned by tag
and checked by digest, and `verify_tessdata.py` fails the build if what landed
cannot drive the legacy recogniser. Measured on a 32-bar lead sheet: 0 chord
symbols and 0 lyrics with the apt files, 28 and 124 with these. It is not
slower — a 12-page quartet took 157s with working OCR against 186s without,
because misreading text as symbols costs more than reading it.

`server.PROCESSING_SWITCHES` states the Audiveris switches the service depends
on (`lyrics`, `chordNames`) on the command line rather than inheriting their
defaults; `engine/scripts/check_omr_switches.py` asserts they are still there.

## Local smoke test (needs Docker)

```sh
docker build -t scoranger-omr omr-service
docker run -p 8080:8080 -e OMR_API_KEY=dev scoranger-omr
curl -X POST --data-binary @score.pdf -H "X-API-Key: dev" \
     http://localhost:8080/omr -o score.mxl
```
