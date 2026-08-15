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
  --timeout 600 --concurrency 1 --max-instances 3 \
  --allow-unauthenticated \
  --set-env-vars OMR_API_KEY=<random-secret>
```

Notes:
- `--allow-unauthenticated` + the `OMR_API_KEY` header keeps the client simple
  (no Google auth on-device) while still gating access.
- `--concurrency 1` because each conversion runs a JVM at full tilt.
- First deploy compiles Audiveris from source in Cloud Build (~10 min).

## Local smoke test (needs Docker)

```sh
docker build -t scoranger-omr omr-service
docker run -p 8080:8080 -e OMR_API_KEY=dev scoranger-omr
curl -X POST --data-binary @score.pdf -H "X-API-Key: dev" \
     http://localhost:8080/omr -o score.mxl
```
