#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${APP_DIR:-/opt/skybridge}"
cd "$APP_DIR"

if [[ ! -f previous-version ]]; then
  echo "[rollback] no previous-version file"
  exit 1
fi

export SKYBRIDGE_VERSION="$(cat previous-version)"
echo "[rollback] rolling back to $SKYBRIDGE_VERSION"
docker compose -f docker-compose.prod.yml pull
docker compose -f docker-compose.prod.yml up -d
./scripts/healthcheck.sh
echo "$SKYBRIDGE_VERSION" > current-version
