#!/usr/bin/env bash
# Check that every tag of the published image is still complete: for each tag, every piece
# it is made of (one image per architecture, plus the attestations) must still exist in the
# registry. Run after the cleanup job has deleted old versions; fails loudly if one is gone.
#
# Usage: verify-image.sh ghcr.io/owner/name
# Optional env: GITHUB_ACTOR and GITHUB_TOKEN to read a private package (a public one needs none).
set -euo pipefail

IMAGE="${1:?usage: verify-image.sh ghcr.io/owner/name}"
# the registry only accepts lowercase names
IMAGE="$(printf '%s' "$IMAGE" | tr 'A-Z' 'a-z')"
REPO="${IMAGE#ghcr.io/}"

if [ -n "${GITHUB_TOKEN:-}" ]; then
  auth=(-u "${GITHUB_ACTOR:-token}:$GITHUB_TOKEN")
else
  auth=()
fi
token="$(curl -fsS "${auth[@]}" "https://ghcr.io/token?scope=repository:${REPO}:pull&service=ghcr.io" \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["token"])')"
tags="$(curl -fsS -H "Authorization: Bearer $token" "https://ghcr.io/v2/${REPO}/tags/list" \
  | python3 -c 'import json,sys; print("\n".join(json.load(sys.stdin)["tags"] or []))')"

if [ -z "$tags" ]; then
  echo "No tags found for $IMAGE: nothing to verify, which is not expected." >&2
  exit 1
fi

for tag in $tags; do
  index="$(docker buildx imagetools inspect --raw "$IMAGE:$tag")"
  pieces="$(python3 -c '
import json, sys
doc = json.load(sys.stdin)
manifests = doc.get("manifests")
if not manifests:
    sys.exit("not a multi-architecture index")
print("\n".join(m["digest"] for m in manifests))
' <<<"$index")" || { echo "$IMAGE:$tag is not a multi-architecture image index" >&2; exit 1; }

  count=0
  for digest in $pieces; do
    if ! docker buildx imagetools inspect --raw "$IMAGE@$digest" >/dev/null 2>&1; then
      echo "BROKEN: $IMAGE:$tag refers to $digest, which is missing from the registry" >&2
      exit 1
    fi
    count=$((count + 1))
  done
  echo "OK  :$tag - all $count pieces present"
done
