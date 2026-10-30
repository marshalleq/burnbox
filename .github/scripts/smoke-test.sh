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

# A placeholder password must stop start-up, not be accepted quietly.
if out="$(BURNBOX_PORT=3998 BURNBOX_UPLOAD_DIR="$DATA_DIR" BURNBOX_ADMIN_PASS=secret node app.js 2>&1)"; then
  echo "Burnbox started with the placeholder admin password 'secret'; it should refuse" >&2
  exit 1
fi
if ! grep -q "Refusing to start" <<<"$out"; then
  echo "Placeholder password failed, but not with the expected message:" >&2
  echo "$out" >&2
  exit 1
fi
echo "placeholder password refused -> OK"

# With a real admin password: wrong guess is forbidden, right one works.
ADMIN_PASS="$(openssl rand -hex 16)"
BURNBOX_PORT=3997 BURNBOX_UPLOAD_DIR="$DATA_DIR" BURNBOX_ADMIN_PASS="$ADMIN_PASS" node app.js >"$LOG.admin" 2>&1 &
ADMIN_PID=$!
trap 'kill "$PID" "$ADMIN_PID" 2>/dev/null || true' EXIT
for _ in $(seq 1 30); do
  curl -fsS "http://127.0.0.1:3997/robots.txt" >/dev/null 2>&1 && break
  kill -0 "$ADMIN_PID" 2>/dev/null || { cat "$LOG.admin" >&2; exit 1; }
  sleep 1
done
wrong="$(curl -sS -o /dev/null -w '%{http_code}' -H 'x-passwd: not-the-password' http://127.0.0.1:3997/admin/data.json)"
right="$(curl -sS -o /dev/null -w '%{http_code}' -H "x-passwd: $ADMIN_PASS" http://127.0.0.1:3997/admin/data.json)"
if [ "$wrong" != "403" ] || [ "$right" != "200" ]; then
  echo "Admin password check: wrong=$wrong (want 403), right=$right (want 200)" >&2
  exit 1
fi
echo "admin password check -> OK"

# tus preflight (OPTIONS) must still be answered by the wildcard route.
pre="$(curl -sS -D - -o /dev/null -X OPTIONS "$BASE/files" -H "Tus-Resumable: 1.0.0" -H "Origin: https://evil.example" | tr -d '\r')"
if ! grep -qi '^HTTP/[0-9.]* 2' <<<"$pre" || ! grep -qi '^tus-extension:' <<<"$pre"; then
  echo "tus OPTIONS preflight did not return a 2xx with Tus-Extension:" >&2
  echo "$pre" >&2
  exit 1
fi
if grep -qi '^access-control-allow-origin:' <<<"$pre"; then
  echo "CORS headers were sent although CORS is off by default:" >&2
  echo "$pre" >&2
  exit 1
fi
echo "tus preflight, no CORS by default -> OK"

# Upload two files into one bucket, then download them as a ZIP and check the contents.
upload() { # sid name content
  local len="${#3}" loc
  loc="$(curl -fsS -D - -o /dev/null -X POST "$BASE/files" \
    -H "Tus-Resumable: 1.0.0" -H "Upload-Length: $len" \
    -H "Upload-Metadata: name $(b64 "$2"),sid $(b64 "$1"),retention $(b64 3600)" \
    | tr -d '\r' | awk 'tolower($1)=="location:" {print $2}')"
  printf '%s' "$3" | curl -fsS -o /dev/null -X PATCH "$BASE$loc" \
    -H "Tus-Resumable: 1.0.0" -H "Content-Type: application/offset+octet-stream" \
    -H "Upload-Offset: 0" -H "Content-Length: $len" --data-binary @-
}
upload zipsid a.txt "alpha file"
upload zipsid b.txt "bravo file"
TOKEN="$(curl -fsS "$BASE/zipsid.json" | python3 -c 'import json,sys; print(json.load(sys.stdin)["archiveToken"])')"
ZIPFILE="$(mktemp)"
curl -fsS -o "$ZIPFILE" "$BASE/files/zipsid++$TOKEN.zip"
python3 - "$ZIPFILE" <<'PY'
import sys, zipfile
z = zipfile.ZipFile(sys.argv[1])
bad = z.testzip()
got = {n: z.read(n).decode() for n in z.namelist()}
want = {"a.txt": "alpha file", "b.txt": "bravo file"}
if bad or got != want:
    sys.exit(f"ZIP check failed: corrupt={bad} contents={got}")
print("zip download of two files -> OK")
PY

# CORS is opt-in: only the listed origin is allowed.
start_instance() { # port, then VAR=value pairs; sets LAST_PID
  local port="$1"; shift
  env "$@" BURNBOX_PORT="$port" BURNBOX_UPLOAD_DIR="$DATA_DIR" node app.js >"$LOG.$port" 2>&1 &
  LAST_PID=$!
  EXTRA_PIDS+=("$LAST_PID")
  for _ in $(seq 1 30); do
    curl -fsS "http://127.0.0.1:$port/robots.txt" >/dev/null 2>&1 && return 0
    kill -0 "$LAST_PID" 2>/dev/null || { cat "$LOG.$port" >&2; exit 1; }
    sleep 1
  done
  echo "instance on port $port did not start" >&2; exit 1
}
EXTRA_PIDS=()
trap 'kill "$PID" "$ADMIN_PID" "${EXTRA_PIDS[@]}" 2>/dev/null || true' EXIT

start_instance 3995 BURNBOX_CORS_ORIGIN=https://good.example
good="$(curl -sS -D - -o /dev/null -X OPTIONS http://127.0.0.1:3995/files -H "Tus-Resumable: 1.0.0" -H "Origin: https://good.example" | tr -d '\r')"
bad="$(curl -sS -D - -o /dev/null -X OPTIONS http://127.0.0.1:3995/files -H "Tus-Resumable: 1.0.0" -H "Origin: https://evil.example" | tr -d '\r')"
if ! grep -qi '^access-control-allow-origin: https://good.example' <<<"$good" || grep -qi '^access-control-allow-origin: https://evil.example' <<<"$bad"; then
  echo "CORS allow-list is wrong. good:" >&2; echo "$good" >&2; echo "evil:" >&2; echo "$bad" >&2
  exit 1
fi
echo "CORS opt-in allows only the listed origin -> OK"

# Wrong passwords are limited per IP; requests with no password are not counted.
LIMIT_PASS="$(openssl rand -hex 16)"
start_instance 3994 BURNBOX_ADMIN_PASS="$LIMIT_PASS" BURNBOX_AUTH_FAILURE_LIMIT=3
LB=http://127.0.0.1:3994
for _ in 1 2 3 4 5 6; do curl -sS -o /dev/null "$LB/admin/data.json"; done   # no password: not counted
for i in 1 2 3; do
  c="$(curl -sS -o /dev/null -w '%{http_code}' -H 'x-passwd: wrong' "$LB/admin/data.json")"
  [ "$c" = "403" ] || { echo "wrong guess $i returned $c, expected 403" >&2; exit 1; }
done
c="$(curl -sS -o /dev/null -w '%{http_code}' -H 'x-passwd: wrong' "$LB/admin/data.json")"
[ "$c" = "429" ] || { echo "4th wrong guess returned $c, expected 429" >&2; exit 1; }
echo "wrong-password limit (403 x3, then 429) -> OK"

# A correct password that meets other errors must never count towards the limit.
UP_PASS="$(openssl rand -hex 16)"
start_instance 3993 BURNBOX_UPLOAD_PASS="$UP_PASS" BURNBOX_AUTH_FAILURE_LIMIT=3
for _ in 1 2 3 4 5 6; do
  # valid password, but no upload metadata, so the server answers 400
  curl -sS -o /dev/null -X POST http://127.0.0.1:3993/files -H "x-passwd: $UP_PASS" -H "Tus-Resumable: 1.0.0" -H "Upload-Length: 1"
done
c="$(curl -sS -o /dev/null -w '%{http_code}' -H "x-passwd: $UP_PASS" http://127.0.0.1:3993/config.json)"
[ "$c" = "200" ] || { echo "correct password was locked out after harmless 4xx errors (got $c)" >&2; exit 1; }
echo "correct password is not locked out by other 4xx errors -> OK"

# Trusting every proxy hop must be loud; an explicit hop count must not be overridden by forceHttps.
for combo in "BURNBOX_FORCE_HTTPS=true" "BURNBOX_FORCE_HTTPS=true BURNBOX_TRUST_PROXY=1"; do
  wlog="$(mktemp)"
  # shellcheck disable=SC2086
  env $combo BURNBOX_PORT=3992 BURNBOX_UPLOAD_DIR="$DATA_DIR" node app.js >"$wlog" 2>&1 &
  wpid=$!
  for _ in $(seq 1 20); do grep -q "listening" "$wlog" && break; sleep 1; done
  kill "$wpid" 2>/dev/null || true; wait "$wpid" 2>/dev/null || true
  warned="$(grep -c 'trusts every X-Forwarded-For hop' "$wlog" || true)"
  case "$combo" in
    *TRUST_PROXY=1*) [ "$warned" = "0" ] || { echo "warned although BURNBOX_TRUST_PROXY=1 was set" >&2; exit 1; } ;;
    *) [ "$warned" = "1" ] || { echo "no warning although every proxy hop is trusted" >&2; cat "$wlog" >&2; exit 1; } ;;
  esac
done
echo "trust-proxy warning and forceHttps handling -> OK"

# Settings given as environment variables are read by type, and bad values stop start-up.
refuses() { # expected-message-fragment VAR=value...
  local expect="$1" out; shift
  if out="$(env "$@" BURNBOX_UPLOAD_DIR="$DATA_DIR" timeout 15 node app.js 2>&1)"; then
    echo "Burnbox started although it should have refused: $*" >&2; exit 1
  fi
  grep -q "$expect" <<<"$out" || { echo "Refused, but without '$expect' for: $*" >&2; echo "$out" >&2; exit 1; }
}
refuses "BURNBOX_PORT must be a whole number" BURNBOX_PORT=abc
refuses "BURNBOX_MAX_FILE_SIZE must be a whole number of bytes" BURNBOX_MAX_FILE_SIZE=2GB
refuses "BURNBOX_DISABLE_QR_CODE must be true or false" BURNBOX_DISABLE_QR_CODE=maybe
refuses "BURNBOX_RETENTIONS must be valid JSON" BURNBOX_RETENTIONS='{bad'
refuses "defaultRetention" BURNBOX_DEFAULT_RETENTION=12345
echo "bad environment values refused -> OK"

start_instance 3991 \
  BURNBOX_DISABLE_QR_CODE=false BURNBOX_REQUIRE_BUCKET_PASSWORD=true \
  BURNBOX_MAX_FILE_SIZE=1000 BURNBOX_MAX_BUCKET_SIZE=5000 \
  BURNBOX_RETENTIONS='{"one-time":"once","3600":"1h"}' BURNBOX_DEFAULT_RETENTION=3600 \
  BURNBOX_FILE_UPLOADED_WEBHOOK=http://127.0.0.1:9/hook BURNBOX_ACCESS_LOG=false
curl -fsS http://127.0.0.1:3991/config.json | python3 -c '
import json, sys
c = json.load(sys.stdin)
want = {"disableQrCode": False, "requireBucketPassword": True, "maxFileSize": 1000,
        "maxBucketSize": 5000, "defaultRetention": "3600",
        "retentions": {"one-time": "once", "3600": "1h"}}
bad = {k: c.get(k) for k, v in want.items() if c.get(k) != v}
sys.exit(f"config.json does not match the environment: {bad}") if bad else print("environment settings read by type -> OK")
'
curl -fsS -o /dev/null http://127.0.0.1:3991/robots.txt
if grep -q 'GET /robots.txt' "$LOG.3991"; then
  echo "BURNBOX_ACCESS_LOG=false still wrote an access log line" >&2; exit 1
fi
echo "access log switched off by BURNBOX_ACCESS_LOG=false -> OK"

# requireBucketPassword is enforced by the server, not only by the upload page.
create() { # extra-metadata (may be empty)
  curl -sS -o /dev/null -w '%{http_code}' -X POST http://127.0.0.1:3991/files \
    -H "Tus-Resumable: 1.0.0" -H "Upload-Length: 1" \
    -H "Upload-Metadata: name $(b64 r.txt),sid $(b64 reqpw$RANDOM),retention $(b64 3600)$1"
}
nopw="$(create "")"
withpw="$(create ",password $(b64 some-bucket-password)")"
if [ "$nopw" != "400" ] || [ "$withpw" != "201" ]; then
  echo "requireBucketPassword: without password got $nopw (want 400), with password got $withpw (want 201)" >&2
  exit 1
fi
echo "requireBucketPassword enforced by the server -> OK"
