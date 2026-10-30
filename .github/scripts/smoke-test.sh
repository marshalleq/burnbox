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
