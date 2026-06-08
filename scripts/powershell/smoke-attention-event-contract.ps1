$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$client = Get-Content -Raw -LiteralPath (Join-Path $repoRoot "packages\client\src\index.ts")

foreach ($required in @(
  "AttentionEvent",
  "AttentionLevel",
  "AttentionSource",
  "AttentionEventType",
  "attention_event",
  "attention_level",
  "recommended_action",
  "acknowledged_at",
  "token_printed: false",
  "worker_offline",
  "queue_blocked",
  "human_approval_required",
  "goal_ready",
  "goal_completed",
  "pr_created",
  "ci_failed",
  "stale_lease",
  "safe_action_applied",
  "emergency_stop_requested",
  "notification_delivery_skipped",
  "notification_delivery_fixture"
)) {
  if ($client -notmatch [regex]::Escape($required)) {
    throw "Attention contract missing: $required"
  }
}

[pscustomobject]@{
  ok = $true
  scenario = "attention-event-contract"
  token_printed = $false
} | ConvertTo-Json -Compress
