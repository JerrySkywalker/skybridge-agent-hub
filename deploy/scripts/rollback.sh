#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${APP_DIR:-/opt/skybridge}"
cd "$APP_DIR"
trap './scripts/notify-deploy.sh rollback-failed "${SKYBRIDGE_IMAGE_TAG:-unknown}" || true' ERR

if [[ ! -f previous-version ]]; then
  echo "[rollback] no previous-version file"
  exit 1
fi

export SKYBRIDGE_IMAGE_TAG="$(cat previous-version)"
./scripts/notify-deploy.sh rollback-started "$SKYBRIDGE_IMAGE_TAG" || true
echo "[rollback] rolling back to $SKYBRIDGE_IMAGE_TAG"
docker compose -f docker-compose.prod.yml pull
docker compose -f docker-compose.prod.yml up -d
./scripts/healthcheck.sh
echo "$SKYBRIDGE_IMAGE_TAG" > current-version
trap - ERR
./scripts/notify-deploy.sh rollback-succeeded "$SKYBRIDGE_IMAGE_TAG" || true
