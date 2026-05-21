#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${APP_DIR:-/opt/skybridge}"
BACKUP_DIR="${BACKUP_DIR:-$APP_DIR/backups}"
TS="$(date +%Y%m%d-%H%M%S)"

mkdir -p "$BACKUP_DIR"
echo "[backup] placeholder backup at $BACKUP_DIR/$TS"
tar -czf "$BACKUP_DIR/skybridge-config-$TS.tgz" -C "$APP_DIR" docker-compose.prod.yml .env 2>/dev/null || true
