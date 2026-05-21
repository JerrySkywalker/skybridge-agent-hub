#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${APP_DIR:-$(pwd)}"
COMPOSE_FILE="${COMPOSE_FILE:-deploy/docker-compose.prod.yml}"
ENV_FILE="${SKYBRIDGE_ENV_FILE:-.env}"
IMAGE_TAG="${SKYBRIDGE_IMAGE_TAG:-${1:-}}"
HEALTH_URL="${SKYBRIDGE_HEALTH_URL:-http://127.0.0.1:8787/health}"

log() {
  printf '[staging-dry-run] %s\n' "$*"
}

fail() {
  printf '[staging-dry-run] ERROR: %s\n' "$*" >&2
  exit 1
}

cd "$APP_DIR"

[[ -n "$IMAGE_TAG" ]] || fail "Set SKYBRIDGE_IMAGE_TAG or pass an image tag argument."
[[ "$IMAGE_TAG" =~ ^[A-Za-z0-9._-]+$ ]] || fail "Image tag contains unsupported characters."
[[ -f "$COMPOSE_FILE" ]] || fail "Compose file not found: $COMPOSE_FILE"

if [[ -f "$ENV_FILE" ]]; then
  log "env file present: $ENV_FILE (values not printed)"
else
  log "env file missing: $ENV_FILE (expected before a real deploy)"
fi

export SKYBRIDGE_IMAGE_TAG="$IMAGE_TAG"
export SKYBRIDGE_ENV_FILE="$ENV_FILE"

log "rendering compose config for tag $SKYBRIDGE_IMAGE_TAG"
docker compose -f "$COMPOSE_FILE" config >/tmp/skybridge-compose-rendered.yml
log "compose config rendered successfully"

log "checking health target syntax: $HEALTH_URL"
case "$HEALTH_URL" in
  http://127.0.0.1:*|http://localhost:*)
    log "local health target accepted for optional operator checks"
    ;;
  *)
    log "non-local health target not contacted during dry-run"
    ;;
esac

log "dry-run complete; no containers were started or changed"
