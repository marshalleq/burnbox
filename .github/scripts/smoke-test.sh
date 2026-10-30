#!/usr/bin/env bash
# Start Burnbox and check that it serves its pages. Fails loudly on any problem.
set -euo pipefail

PORT=3999
DATA_DIR="$(mktemp -d)"
LOG="$(mktemp)"

BURNBOX_PORT="$PORT" BURNBOX_UPLOAD_DIR="$DATA_DIR" node app.js >"$LOG" 2>&1 &
PID=$!
trap 'kill "$PID" 2>/dev/null || true' EXIT

for _ in $(seq 1 30); do
  if curl -fsS "http://127.0.0.1:$PORT/robots.txt" >/dev/null 2>&1; then break; fi
  if ! kill -0 "$PID" 2>/dev/null; then
    echo "Burnbox exited during start-up:" >&2
    cat "$LOG" >&2
    exit 1
  fi
  sleep 1
done

for path in / /config.json /lang.json /robots.txt; do
  code="$(curl -sS -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT$path")"
  if [ "$code" != "200" ]; then
    echo "GET $path returned $code, expected 200" >&2
    cat "$LOG" >&2
    exit 1
  fi
  echo "GET $path -> 200"
done

# Upload a small file over tus, then download it again and compare.
BASE="http://127.0.0.1:$PORT"
PAYLOAD="burnbox smoke test"
LEN="${#PAYLOAD}"
b64() { printf '%s' "$1" | base64 | tr -d '\n'; }

LOCATION="$(curl -fsS -D - -o /dev/null -X POST "$BASE/files" \
  -H "Tus-Resumable: 1.0.0" -H "Upload-Length: $LEN" \
  -H "Upload-Metadata: name $(b64 smoke.txt),sid $(b64 smokesid),retention $(b64 3600)" \
  | tr -d '\r' | awk 'tolower($1)=="location:" {print $2}')"
if [ -z "$LOCATION" ]; then
  echo "Upload did not return a Location header" >&2
  cat "$LOG" >&2
  exit 1
fi

code="$(printf '%s' "$PAYLOAD" | curl -sS -o /dev/null -w '%{http_code}' -X PATCH "$BASE$LOCATION" \
  -H "Tus-Resumable: 1.0.0" -H "Content-Type: application/offset+octet-stream" \
  -H "Upload-Offset: 0" -H "Content-Length: $LEN" --data-binary @-)"
if [ "$code" != "204" ]; then
  echo "Upload PATCH returned $code, expected 204" >&2
  cat "$LOG" >&2
  exit 1
fi

downloaded="$(curl -fsS "$BASE$LOCATION")"
if [ "$downloaded" != "$PAYLOAD" ]; then
  echo "Downloaded content did not match what was uploaded" >&2
  exit 1
fi
echo "tus upload and download round trip -> OK"
