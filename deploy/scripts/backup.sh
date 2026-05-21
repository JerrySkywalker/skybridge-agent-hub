#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${APP_DIR:-/opt/skybridge}"
BACKUP_DIR="${BACKUP_DIR:-$APP_DIR/backups}"
DATA_DIR="${SKYBRIDGE_DATA_DIR:-$APP_DIR/data}"
TS="$(date +%Y%m%d-%H%M%S)"
BACKUP_FILE="$BACKUP_DIR/skybridge-backup-$TS.tgz"

mkdir -p "$BACKUP_DIR"
echo "[backup] writing timestamped backup: $BACKUP_FILE"

items=()
[[ -f "$APP_DIR/docker-compose.prod.yml" ]] && items+=("docker-compose.prod.yml")
[[ -f "$APP_DIR/current-version" ]] && items+=("current-version")
[[ -f "$APP_DIR/previous-version" ]] && items+=("previous-version")
[[ -d "$DATA_DIR" ]] && items+=("${DATA_DIR#$APP_DIR/}")

if [[ ${#items[@]} -eq 0 ]]; then
  echo "[backup] nothing to archive; leaving existing backups untouched"
  exit 0
fi

tar -czf "$BACKUP_FILE" -C "$APP_DIR" "${items[@]}"
echo "[backup] complete: $BACKUP_FILE"
