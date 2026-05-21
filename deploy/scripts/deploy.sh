#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${APP_DIR:-/opt/skybridge}"
VERSION="${1:-latest}"

cd "$APP_DIR"

echo "[deploy] backing up"
./scripts/backup.sh || true

echo "[deploy] deploying version: $VERSION"
echo "$VERSION" > previous-version.tmp
if [[ -f current-version ]]; then cp current-version previous-version; fi

export SKYBRIDGE_VERSION="$VERSION"
docker compose -f docker-compose.prod.yml pull
docker compose -f docker-compose.prod.yml up -d

./scripts/healthcheck.sh

echo "$VERSION" > current-version
echo "[deploy] done"
