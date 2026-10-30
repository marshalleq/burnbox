#!/usr/bin/env bash
# Run Burnbox behind docs/nginx-ssl-example.conf and exercise it: logins only on /up/, a large
# upload in pieces that is interrupted and resumed, a byte-identical download, range requests,
# and proof that the 413 problem the example's client_max_body_size line avoids is real.
# Usage: nginx-example-test.sh [repo-dir]   (needs Docker, curl, python3, openssl)
set -euo pipefail
REPO="${1:-$(pwd)}"
W="$(mktemp -d)"
cleanup() {
  docker rm -f bb-app bb-nginx bb-nginx-broken >/dev/null 2>&1 || true
  docker network rm bbnet >/dev/null 2>&1 || true
  rm -rf "$W"
}
trap cleanup EXIT

cleanup_first() { docker rm -f bb-app bb-nginx bb-nginx-broken >/dev/null 2>&1 || true; docker network rm bbnet >/dev/null 2>&1 || true; }
cleanup_first
docker network create bbnet >/dev/null

echo "== build image"
docker build -q -t burnbox-nginx "$REPO" >/dev/null

ADMIN="$(openssl rand -hex 12)"
USERPW="$(openssl rand -hex 12)"
docker run -d --name bb-app --network bbnet \
  -e BURNBOX_UPLOAD_APP_PATH=/up/ -e BURNBOX_TRUST_PROXY=1 -e BURNBOX_ADMIN_PASS="$ADMIN" \
  burnbox-nginx >/dev/null

# htpasswd entry (bcrypt) for user "alice"
docker run --rm httpd:alpine htpasswd -nbB alice "$USERPW" > "$W/htpasswd" 2>/dev/null

# Turn the example into a plain-HTTP test config that proxies to the Burnbox container.
python3 - "$REPO/docs/nginx-ssl-example.conf" "$W" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
w = sys.argv[2]
# keep only the second server block and the top-level server_tokens line
blocks = src.split("server {")
body = "server {" + blocks[2]
body = re.sub(r"\n\s*listen 443 ssl;", "\n  listen 8080;", body)
body = re.sub(r"\n\s*http2 on;", "", body)
body = re.sub(r"\n\s*ssl_[a-z_]+ [^\n]*;", "", body)
body = re.sub(r"\n\s*(error_log|access_log)[^\n]*;", "", body)
body = body.replace("http://127.0.0.1:3000", "http://bb-app:3000")
open(w + "/good.conf", "w").write("server_tokens off;\n" + body)
broken = body.replace("client_max_body_size 0;", "")
open(w + "/broken.conf", "w").write("server_tokens off;\n" + broken)
PY

run_nginx() { # name port conf
  docker run -d --name "$1" --network bbnet -p "$2":8080 \
    -v "$W/$3":/etc/nginx/conf.d/default.conf:ro -v "$W/htpasswd":/etc/nginx/burnbox.htpasswd:ro \
    nginx:stable-alpine >/dev/null
}
run_nginx bb-nginx 8085 good.conf
run_nginx bb-nginx-broken 8086 broken.conf
sleep 5
B=http://127.0.0.1:8085
b64() { printf '%s' "$1" | base64 | tr -d '\n'; }
code() { curl -s -o /dev/null -w '%{http_code}' "$@"; }
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1" >&2; docker logs bb-nginx 2>&1 | tail -5 >&2; exit 1; }

echo "== login only on /up/"
[ "$(code $B/up/)" = "401" ] && pass "/up/ without login -> 401" || fail "/up/ without login"
[ "$(code -u "alice:$USERPW" $B/up/)" = "200" ] && pass "/up/ with login -> 200" || fail "/up/ with login"
[ "$(code -u "alice:wrong" $B/up/)" = "401" ] && pass "/up/ wrong password -> 401" || fail "/up/ wrong password"
[ "$(code -X POST $B/up/files -H 'Tus-Resumable: 1.0.0' -H 'Upload-Length: 1')" = "401" ] && pass "upload API without login -> 401" || fail "upload API without login"

echo "== 60 MB upload in 5 MB chunks, interrupted and resumed"
SIZE=60000000
head -c $SIZE /dev/urandom > "$W/big.bin"
SID="nginx$RANDOM$RANDOM"
LOC="$(curl -sS -D - -o /dev/null -u "alice:$USERPW" -X POST $B/up/files \
  -H 'Tus-Resumable: 1.0.0' -H "Upload-Length: $SIZE" \
  -H "Upload-Metadata: name $(b64 big.bin),sid $(b64 $SID),retention $(b64 3600)" \
  | tr -d '\r' | awk 'tolower($1)=="location:" {print $2}')"
[ -n "$LOC" ] || fail "no Location from upload create"
CHUNK=5000000
send_chunk() { # index
  local off=$(( $1 * CHUNK ))
  dd if="$W/big.bin" bs=$CHUNK skip="$1" count=1 2>/dev/null | curl -s -o /dev/null -w '%{http_code}' -u "alice:$USERPW" -X PATCH "$B$LOC" \
    -H 'Tus-Resumable: 1.0.0' -H 'Content-Type: application/offset+octet-stream' -H "Upload-Offset: $off" --data-binary @-
}
for i in 0 1 2; do [ "$(send_chunk $i)" = "204" ] && pass "chunk $i accepted through nginx" || fail "chunk $i (nginx 413 means client_max_body_size)"; done
OFFSET="$(curl -sS -I -u "alice:$USERPW" "$B$LOC" -H 'Tus-Resumable: 1.0.0' | tr -d '\r' | awk 'tolower($1)=="upload-offset:" {print $2}')"
[ "$OFFSET" = "15000000" ] && pass "after the interruption the server says it has 15000000 bytes" || fail "resume offset was '$OFFSET'"
for i in 3 4 5 6 7 8 9 10 11; do [ "$(send_chunk $i)" = "204" ] || fail "chunk $i"; done
pass "resumed from the saved offset and finished the upload"

echo "== download without any login"
[ "$(code $B/$SID.json)" = "200" ] && pass "download page data is public" || fail "download page data"
FID="$SID++$(curl -s $B/$SID.json | python3 -c 'import json,sys; print(json.load(sys.stdin)["items"][0]["key"])')"
curl -s -o "$W/down.bin" "$B/files/$FID"
[ "$(shasum -a 256 < "$W/big.bin" | cut -d' ' -f1)" = "$(shasum -a 256 < "$W/down.bin" | cut -d' ' -f1)" ] && pass "downloaded file is byte-identical (SHA-256)" || fail "checksum mismatch"
[ "$(code -H 'Range: bytes=0-9' $B/files/$FID)" = "206" ] && pass "Range request -> 206 (resumable download)" || fail "range request"

echo "== the old config (no client_max_body_size) really does fail"
BB=http://127.0.0.1:8086
LOC2="$(curl -sS -D - -o /dev/null -u "alice:$USERPW" -X POST $BB/up/files -H 'Tus-Resumable: 1.0.0' -H "Upload-Length: $SIZE" \
  -H "Upload-Metadata: name $(b64 big.bin),sid $(b64 broken$RANDOM),retention $(b64 3600)" | tr -d '\r' | awk 'tolower($1)=="location:" {print $2}')"
C="$(dd if="$W/big.bin" bs=$CHUNK count=1 2>/dev/null | curl -s -o /dev/null -w '%{http_code}' -u "alice:$USERPW" -X PATCH "$BB$LOC2" \
  -H 'Tus-Resumable: 1.0.0' -H 'Content-Type: application/offset+octet-stream' -H 'Upload-Offset: 0' --data-binary @-)"
echo "      without the setting, a 5 MB chunk gets HTTP $C (413 = Request Entity Too Large)"

# The broken config must really fail, otherwise the example's setting proves nothing.
[ "$C" = "413" ] || fail "expected 413 without client_max_body_size, got $C"
echo "ALL NGINX CHECKS PASSED"
