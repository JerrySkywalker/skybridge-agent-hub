#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${APP_DIR:-/opt/skybridge}"
VERSION="${1:-${SKYBRIDGE_IMAGE_TAG:-latest}}"
DRY_RUN="${DRY_RUN:-false}"

cd "$APP_DIR"
trap './scripts/notify-deploy.sh deploy-failed "$VERSION" || true' ERR

if [[ "$DRY_RUN" == "true" ]]; then
  export SKYBRIDGE_IMAGE_TAG="$VERSION"
  ./scripts/staging-dry-run.sh "$VERSION"
  exit 0
fi

echo "[deploy] backing up"
./scripts/backup.sh || true

echo "[deploy] deploying version: $VERSION"
echo "$VERSION" > previous-version.tmp
if [[ -f current-version ]]; then cp current-version previous-version; fi

export SKYBRIDGE_IMAGE_TAG="$VERSION"
./scripts/notify-deploy.sh deploy-started "$VERSION" || true
docker compose -f docker-compose.prod.yml pull
docker compose -f docker-compose.prod.yml up -d

./scripts/healthcheck.sh

echo "$VERSION" > current-version
trap - ERR
./scripts/notify-deploy.sh deploy-succeeded "$VERSION" || true
echo "[deploy] done"
