#!/usr/bin/env bash
set -euo pipefail

URL="${SKYBRIDGE_HEALTH_URL:-http://127.0.0.1:8787/health}"

for i in {1..30}; do
  if curl -fsS "$URL" >/dev/null; then
    echo "[healthcheck] ok"
    exit 0
  fi
  sleep 2
done

echo "[healthcheck] failed"
exit 1
