#!/usr/bin/env bash
set -euo pipefail

EVENT="${1:-deploy-event}"
IMAGE_TAG="${2:-${SKYBRIDGE_IMAGE_TAG:-unknown}}"
TOPIC_URL="${NTFY_TOPIC_URL:-}"
TOKEN="${NTFY_TOKEN:-}"

log() {
  printf '[notify-deploy] %s\n' "$*"
}

if [[ -z "$TOPIC_URL" ]]; then
  log "NTFY_TOPIC_URL not configured; skipped $EVENT for tag $IMAGE_TAG"
  exit 0
fi

TITLE="SkyBridge ${EVENT}"
BODY="event=${EVENT}
image_tag=${IMAGE_TAG}
host=$(hostname 2>/dev/null || echo unknown)"

args=(-fsS -X POST "$TOPIC_URL" -H "Title: $TITLE" -H "Priority: default" --data-binary "$BODY")
if [[ -n "$TOKEN" ]]; then
  args=(-H "Authorization: Bearer $TOKEN" "${args[@]}")
fi

curl "${args[@]}" >/dev/null
log "sent $EVENT notification for tag $IMAGE_TAG"
