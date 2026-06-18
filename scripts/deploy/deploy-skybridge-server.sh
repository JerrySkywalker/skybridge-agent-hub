#!/usr/bin/env bash
set -euo pipefail

IMAGE_REF=""
COMMIT_SHA=""
EXPECTED_TAG=""
COMPOSE_SOURCE=""
DRY_RUN="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --image-ref)
      IMAGE_REF="${2:-}"
      shift 2
      ;;
    --commit-sha)
      COMMIT_SHA="${2:-}"
      shift 2
      ;;
    --expected-tag)
      EXPECTED_TAG="${2:-}"
      shift 2
      ;;
    --compose-source)
      COMPOSE_SOURCE="${2:-}"
      shift 2
      ;;
    --dry-run)
      DRY_RUN="true"
      shift
      ;;
    *)
      echo "[deploy] unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

DEPLOY_PATH="${SKYBRIDGE_DEPLOY_PATH:-/opt/skybridge-agent-hub}"
COMPOSE_FILE="${SKYBRIDGE_DEPLOY_COMPOSE_FILE:-compose.yaml}"
SERVICE="${SKYBRIDGE_DEPLOY_SERVICE:-skybridge-server}"
HEALTH_URL="${SKYBRIDGE_DEPLOY_HEALTH_URL:-http://127.0.0.1:8787/v1/health}"
PUBLIC_API_BASE="${SKYBRIDGE_PUBLIC_API_BASE:-https://skybridge.example.com}"
REPORT_DIR="${SKYBRIDGE_DEPLOY_REPORT_DIR:-$DEPLOY_PATH/.agent/tmp/deploy}"
PLAN_JSON="$REPORT_DIR/cloud-deploy-plan.json"
REPORT_JSON="$REPORT_DIR/cloud-deploy-report.json"
REPORT_MD="$REPORT_DIR/cloud-deploy-report.md"
COMPOSE_TARGET=""
COMPOSE_BACKUP_PATH=""
COMPOSE_INSTALL_STATUS="not_requested"
COMPOSE_RESTORE_STATUS="not_needed"

mkdir -p "$REPORT_DIR"

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

write_plan() {
  cat > "$PLAN_JSON" <<JSON
{
  "schema": "skybridge.cloud_deploy_plan.v1",
  "deploy_scope": "skybridge-server-only",
  "deploy_path": "$(json_escape "$DEPLOY_PATH")",
  "compose_file": "$(json_escape "$COMPOSE_FILE")",
  "compose_source_provided": $([[ -n "$COMPOSE_SOURCE" ]] && echo true || echo false),
  "compose_target": "$(json_escape "$COMPOSE_TARGET")",
  "compose_backup_path": "$(json_escape "$COMPOSE_BACKUP_PATH")",
  "service": "$(json_escape "$SERVICE")",
  "image_ref": "$(json_escape "$IMAGE_REF")",
  "commit_sha": "$(json_escape "$COMMIT_SHA")",
  "expected_tag": "$(json_escape "$EXPECTED_TAG")",
  "runtime_metadata": {
    "commit_sha": "$(json_escape "$COMMIT_SHA")",
    "image_tag": "$(json_escape "$EXPECTED_TAG")",
    "image_ref": "$(json_escape "$IMAGE_REF")"
  },
  "health_url": "$(json_escape "$HEALTH_URL")",
  "public_api_base": "$(json_escape "$PUBLIC_API_BASE")",
  "dry_run": $DRY_RUN,
  "allowed_mutation": "docker compose up -d $(json_escape "$SERVICE")",
  "forbidden_mutations": ["hermes", "openresty", "authelia", "dns", "tls", "firewall", "host-packages"],
  "secrets_included": false,
  "token_printed": false
}
JSON
}

write_report() {
  local status="$1"
  local reason="$2"
  local previous_image="${3:-unknown}"
  local rollback_status="${4:-not_used}"
  cat > "$REPORT_JSON" <<JSON
{
  "schema": "skybridge.cloud_deploy_report.v1",
  "status": "$(json_escape "$status")",
  "reason": "$(json_escape "$reason")",
  "deploy_scope": "skybridge-server-only",
  "service": "$(json_escape "$SERVICE")",
  "compose_source_provided": $([[ -n "$COMPOSE_SOURCE" ]] && echo true || echo false),
  "compose_target": "$(json_escape "$COMPOSE_TARGET")",
  "compose_backup_path": "$(json_escape "$COMPOSE_BACKUP_PATH")",
  "compose_install_status": "$(json_escape "$COMPOSE_INSTALL_STATUS")",
  "compose_restore_status": "$(json_escape "$COMPOSE_RESTORE_STATUS")",
  "image_ref": "$(json_escape "$IMAGE_REF")",
  "commit_sha": "$(json_escape "$COMMIT_SHA")",
  "expected_tag": "$(json_escape "$EXPECTED_TAG")",
  "runtime_metadata": {
    "commit_sha": "$(json_escape "$COMMIT_SHA")",
    "image_tag": "$(json_escape "$EXPECTED_TAG")",
    "image_ref": "$(json_escape "$IMAGE_REF")"
  },
  "previous_image_ref": "$(json_escape "$previous_image")",
  "rollback_status": "$(json_escape "$rollback_status")",
  "health_url": "$(json_escape "$HEALTH_URL")",
  "public_api_base": "$(json_escape "$PUBLIC_API_BASE")",
  "secrets_included": false,
  "raw_logs_included": false,
  "token_printed": false
}
JSON
  cat > "$REPORT_MD" <<MD
# SkyBridge Cloud Deploy Report

- status: $status
- reason: $reason
- deploy_scope: skybridge-server-only
- service: $SERVICE
- compose_source_provided: $([[ -n "$COMPOSE_SOURCE" ]] && echo true || echo false)
- compose_install_status: $COMPOSE_INSTALL_STATUS
- compose_restore_status: $COMPOSE_RESTORE_STATUS
- image_ref: $IMAGE_REF
- commit_sha: $COMMIT_SHA
- expected_tag: $EXPECTED_TAG
- rollback_status: $rollback_status
- token_printed: false
MD
}

fail_report() {
  local reason="$1"
  local previous_image="${2:-unknown}"
  local rollback_status="${3:-not_used}"
  write_report "failed" "$reason" "$previous_image" "$rollback_status"
  echo "[deploy] failed: $reason" >&2
  exit 1
}

require_image_evidence() {
  if [[ -z "$IMAGE_REF" ]]; then
    fail_report "missing_image_ref"
  fi
  if [[ -z "$COMMIT_SHA" ]]; then
    fail_report "missing_commit_sha"
  fi
  if [[ "$IMAGE_REF" == *"@sha256:"* ]]; then
    return 0
  fi
  if [[ -n "$EXPECTED_TAG" && "$IMAGE_REF" == *":$EXPECTED_TAG" ]]; then
    return 0
  fi
  if [[ "$IMAGE_REF" == *":sha-$COMMIT_SHA"* || "$IMAGE_REF" == *":sha-${COMMIT_SHA:0:12}"* || "$IMAGE_REF" == *":$COMMIT_SHA"* ]]; then
    return 0
  fi
  fail_report "image_ref_requires_commit_tag_or_digest"
}

compose_cmd() {
  docker compose -f "$COMPOSE_FILE" "$@"
}

resolve_path_under_deploy_path() {
  local candidate="$1"
  local deploy_root
  local resolved
  deploy_root="$(realpath -m -- "$DEPLOY_PATH")"
  if [[ "$candidate" = /* ]]; then
    resolved="$(realpath -m -- "$candidate")"
  else
    resolved="$(realpath -m -- "$DEPLOY_PATH/$candidate")"
  fi
  case "$resolved" in
    "$deploy_root"/*)
      printf '%s' "$resolved"
      ;;
    *)
      fail_report "compose_target_outside_deploy_path"
      ;;
  esac
}

prepare_compose_sync() {
  COMPOSE_TARGET="$(resolve_path_under_deploy_path "$COMPOSE_FILE")"
  if [[ -z "$COMPOSE_SOURCE" ]]; then
    COMPOSE_INSTALL_STATUS="not_requested"
    return 0
  fi
  if [[ "$DRY_RUN" == "true" ]]; then
    COMPOSE_INSTALL_STATUS="dry_run"
    return 0
  fi
  if [[ ! -f "$COMPOSE_SOURCE" ]]; then
    fail_report "compose_source_not_found"
  fi
  local backup_dir
  backup_dir="$REPORT_DIR/compose-backups"
  mkdir -p "$backup_dir"
  mkdir -p "$(dirname "$COMPOSE_TARGET")"
  if [[ -f "$COMPOSE_TARGET" ]]; then
    COMPOSE_BACKUP_PATH="$backup_dir/$(basename "$COMPOSE_TARGET").$(date -u +%Y%m%dT%H%M%SZ).bak"
    if ! cp "$COMPOSE_TARGET" "$COMPOSE_BACKUP_PATH"; then
      fail_report "compose_backup_failed"
    fi
  else
    COMPOSE_BACKUP_PATH="none"
  fi
  if ! cp "$COMPOSE_SOURCE" "$COMPOSE_TARGET"; then
    fail_report "compose_install_failed"
  fi
  COMPOSE_INSTALL_STATUS="installed"
}

restore_compose_if_needed() {
  if [[ "$COMPOSE_INSTALL_STATUS" != "installed" ]]; then
    COMPOSE_RESTORE_STATUS="not_needed"
    return 0
  fi
  if [[ -n "$COMPOSE_BACKUP_PATH" && "$COMPOSE_BACKUP_PATH" != "none" && -f "$COMPOSE_BACKUP_PATH" ]]; then
    if cp "$COMPOSE_BACKUP_PATH" "$COMPOSE_TARGET"; then
      COMPOSE_RESTORE_STATUS="restored"
    else
      COMPOSE_RESTORE_STATUS="failed"
    fi
    return 0
  fi
  if rm -f "$COMPOSE_TARGET"; then
    COMPOSE_RESTORE_STATUS="removed_installed_file"
  else
    COMPOSE_RESTORE_STATUS="failed"
  fi
}

wait_for_health() {
  for _ in $(seq 1 30); do
    if curl -fsS "$HEALTH_URL" >/dev/null; then
      return 0
    fi
    sleep 2
  done
  return 1
}

run_route_parity() {
  if command -v pwsh >/dev/null 2>&1 && [[ -f "scripts/powershell/skybridge-cloud-parity-check.ps1" ]]; then
    pwsh -NoProfile -ExecutionPolicy Bypass -File "scripts/powershell/skybridge-cloud-parity-check.ps1" -ApiBase "$PUBLIC_API_BASE" -Json >/dev/null
  else
    curl -fsS "$PUBLIC_API_BASE/v1/version" >/dev/null &&
      curl -fsS "$PUBLIC_API_BASE/v1/summary" >/dev/null &&
      curl -fsS "$PUBLIC_API_BASE/v1/manual-tasks/providers" >/dev/null
  fi
}

require_image_evidence
prepare_compose_sync
write_plan

if [[ "$SERVICE" != "skybridge-server" ]]; then
  fail_report "service_scope_not_skybridge_server"
fi

if [[ "$DRY_RUN" == "true" ]]; then
  write_report "skipped" "dry_run" "not_checked" "not_used"
  echo "[deploy] dry-run ok: service=$SERVICE image_ref=$IMAGE_REF"
  exit 0
fi

cd "$DEPLOY_PATH"

if ! compose_cmd config --services | grep -Fx "$SERVICE" >/dev/null; then
  restore_compose_if_needed
  fail_report "compose_service_not_found"
fi

previous_container="$(compose_cmd ps -q "$SERVICE" || true)"
previous_image="unknown"
if [[ -n "$previous_container" ]]; then
  previous_image="$(docker inspect --format '{{.Config.Image}}' "$previous_container" 2>/dev/null || echo unknown)"
fi

if ! docker pull "$IMAGE_REF"; then
  restore_compose_if_needed
  fail_report "docker_pull_failed" "$previous_image"
fi

export SKYBRIDGE_SERVER_IMAGE="$IMAGE_REF"
export SKYBRIDGE_DEPLOY_IMAGE_REF="$IMAGE_REF"
export SKYBRIDGE_DEPLOY_COMMIT_SHA="$COMMIT_SHA"
export SKYBRIDGE_DEPLOY_IMAGE_TAG="$EXPECTED_TAG"

if ! compose_cmd up -d "$SERVICE"; then
  rollback_status="not_used"
  restore_compose_if_needed
  if [[ "$previous_image" != "unknown" ]]; then
    export SKYBRIDGE_SERVER_IMAGE="$previous_image"
    export SKYBRIDGE_DEPLOY_IMAGE_REF="$previous_image"
    if compose_cmd up -d "$SERVICE" && wait_for_health; then
      rollback_status="succeeded"
    else
      rollback_status="failed"
    fi
  fi
  fail_report "compose_up_failed" "$previous_image" "$rollback_status"
fi

if ! wait_for_health; then
  rollback_status="not_used"
  restore_compose_if_needed
  if [[ "$previous_image" != "unknown" ]]; then
    export SKYBRIDGE_SERVER_IMAGE="$previous_image"
    export SKYBRIDGE_DEPLOY_IMAGE_REF="$previous_image"
    if compose_cmd up -d "$SERVICE" && wait_for_health; then
      rollback_status="succeeded"
    else
      rollback_status="failed"
    fi
  fi
  fail_report "health_wait_failed" "$previous_image" "$rollback_status"
fi

if ! run_route_parity; then
  rollback_status="not_used"
  restore_compose_if_needed
  if [[ "$previous_image" != "unknown" ]]; then
    export SKYBRIDGE_SERVER_IMAGE="$previous_image"
    export SKYBRIDGE_DEPLOY_IMAGE_REF="$previous_image"
    if compose_cmd up -d "$SERVICE" && wait_for_health; then
      rollback_status="succeeded"
    else
      rollback_status="failed"
    fi
  fi
  fail_report "route_parity_failed" "$previous_image" "$rollback_status"
fi

write_report "succeeded" "deployed" "$previous_image" "not_used"
echo "[deploy] succeeded: service=$SERVICE image_ref=$IMAGE_REF"
