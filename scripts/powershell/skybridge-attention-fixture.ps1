param(
  [ValidateSet("list", "routing-matrix", "safe-summary", "dispatch-fixture")]
  [string]$Command = "list",
  [string]$CampaignId = "dev-queue-189-200",
  [string]$CurrentStepId = "dev-queue-189-200:super-193-notification-attention-loop",
  [string]$GoalId = "super-193-notification-attention-loop",
  [switch]$Json
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$ledgerDir = Join-Path $repoRoot ".agent\tmp\notifications"
$createdAt = "2026-06-08T00:00:00.000Z"

function New-AttentionEvent {
  param(
    [string]$EventType,
    [string]$Level,
    [string]$Source,
    [string]$Message,
    [string]$RecommendedAction
  )
  [pscustomobject]@{
    schema = "skybridge.attention_event.v1"
    attention_event = $true
    attention_event_id = "attention_${CampaignId}_${GoalId}_${EventType}".Replace("-", "_").Replace(":", "_")
    attention_level = $Level
    source = $Source
    campaign_id = $CampaignId
    current_step_id = $CurrentStepId
    goal_id = $GoalId
    event_type = $EventType
    message = $Message
    recommended_action = $RecommendedAction
    created_at = $createdAt
    acknowledged_at = $null
    token_printed = $false
  }
}

function Get-AttentionEvents {
  @(
    New-AttentionEvent `
      -EventType "worker_offline" `
      -Level "action_required" `
      -Source "worker" `
      -Message "Worker is offline; queue execution remains disabled." `
      -RecommendedAction "Verify or register an online worker before any start-one or start-queue action."
    New-AttentionEvent `
      -EventType "queue_blocked" `
      -Level "blocker" `
      -Source "queue_control" `
      -Message "Queue blocked by worker_offline." `
      -RecommendedAction "Keep execution disabled and inspect worker readiness."
    New-AttentionEvent `
      -EventType "human_approval_required" `
      -Level "action_required" `
      -Source "campaign" `
      -Message "Human action required: verify_worker_online_before_execution." `
      -RecommendedAction "Review attention blockers before approving any later execution goal."
    New-AttentionEvent `
      -EventType "goal_ready" `
      -Level "info" `
      -Source "campaign" `
      -Message "$GoalId is ready but execution is not enabled." `
      -RecommendedAction "Review attention state and keep queue execution disabled."
    New-AttentionEvent `
      -EventType "goal_completed" `
      -Level "info" `
      -Source "campaign" `
      -Message "super-192-dashboard-safe-actions is completed." `
      -RecommendedAction "Review safe action audit and PR evidence."
    New-AttentionEvent `
      -EventType "pr_created" `
      -Level "info" `
      -Source "pr" `
      -Message "PR evidence is present for super-192-dashboard-safe-actions." `
      -RecommendedAction "Review PR and CI evidence before later execution enablement."
  )
}

function Get-RoutingMatrix {
  @(
    [pscustomobject]@{
      route = "desktop_only"
      status = "enabled"
      levels = @("info", "warning", "blocker", "action_required", "critical")
      event_types = @("worker_offline", "queue_blocked", "human_approval_required", "goal_ready", "goal_completed", "pr_created", "ci_failed", "stale_lease", "safe_action_applied", "emergency_stop_requested", "notification_delivery_skipped", "notification_delivery_fixture")
      real_external_send = $false
      token_printed = $false
    }
    [pscustomobject]@{
      route = "web_banner"
      status = "enabled"
      levels = @("warning", "blocker", "action_required", "critical")
      event_types = @("worker_offline", "queue_blocked", "human_approval_required", "ci_failed", "stale_lease", "emergency_stop_requested")
      real_external_send = $false
      token_printed = $false
    }
    [pscustomobject]@{
      route = "local_fixture_notification"
      status = "fixture_only"
      levels = @("blocker", "action_required", "critical")
      event_types = @("worker_offline", "queue_blocked", "human_approval_required", "ci_failed", "stale_lease", "emergency_stop_requested")
      real_external_send = $false
      fixture_ledger_dir = ".agent/tmp/notifications"
      token_printed = $false
    }
    [pscustomobject]@{
      route = "ntfy_placeholder"
      status = "not_configured"
      levels = @("critical")
      event_types = @("ci_failed", "emergency_stop_requested")
      real_external_send = $false
      token_printed = $false
    }
    [pscustomobject]@{
      route = "disabled"
      status = "disabled"
      levels = @("info")
      event_types = @("goal_ready", "goal_completed", "pr_created", "safe_action_applied", "notification_delivery_skipped", "notification_delivery_fixture")
      real_external_send = $false
      token_printed = $false
    }
  )
}

function Assert-NoSecretText {
  param([string]$Text)
  if ($Text -match '(?i)authorization\s*[:=]\s*bearer|bearer\s+[A-Za-z0-9_.-]{12,}|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|raw_stdout|raw_stderr|raw_prompt|raw_worker_log') {
    throw "Secret-looking or raw-log field detected."
  }
}

$events = @(Get-AttentionEvents)
$matrix = @(Get-RoutingMatrix)
$result = $null

switch ($Command) {
  "list" {
    $result = [pscustomobject]@{
      ok = $true
      schema = "skybridge.attention_model.v1"
      campaign_id = $CampaignId
      current_step_id = $CurrentStepId
      goal_id = $GoalId
      attention_events = $events
      top_blocker = @($events | Where-Object { $_.attention_level -in @("critical", "blocker") } | Select-Object -First 1)[0]
      recommended_next_action = "Verify or register an online worker before any start-one or start-queue action."
      token_printed = $false
    }
  }
  "routing-matrix" {
    $result = [pscustomobject]@{
      ok = $true
      schema = "skybridge.notification_routing_matrix.v1"
      routing_matrix = $matrix
      external_notification_sent = $false
      token_printed = $false
    }
  }
  "safe-summary" {
    $top = @($events | Where-Object { $_.attention_level -in @("critical", "blocker") } | Select-Object -First 1)[0]
    $result = [pscustomobject]@{
      ok = $true
      schema = "skybridge.campaign_safe_summary.v1"
      campaign_id = $CampaignId
      current_step = $CurrentStepId
      current_goal_id = $GoalId
      current_goal_status = "ready"
      attention_count = $events.Count
      top_blocker = if ($top) { $top.message } else { $null }
      recommended_next_action = if ($top) { $top.recommended_action } else { "Review attention state." }
      token_printed = $false
    }
  }
  "dispatch-fixture" {
    New-Item -ItemType Directory -Path $ledgerDir -Force | Out-Null
    $event = @($events | Where-Object { $_.event_type -eq "worker_offline" } | Select-Object -First 1)[0]
    $ledgerEntry = [pscustomobject]@{
      schema = "skybridge.notification_fixture_ledger.v1"
      notification_event_type = "notification_delivery_fixture"
      route = "local_fixture_notification"
      status = "fixture_written"
      attention_event = $event
      external_notification_sent = $false
      ledger_path = ".agent/tmp/notifications/attention-fixture.jsonl"
      created_at = $createdAt
      token_printed = $false
    }
    $line = $ledgerEntry | ConvertTo-Json -Depth 30 -Compress
    Assert-NoSecretText $line
    Add-Content -LiteralPath (Join-Path $ledgerDir "attention-fixture.jsonl") -Value $line -Encoding UTF8
    $result = [pscustomobject]@{
      ok = $true
      schema = "skybridge.notification_fixture_dispatch.v1"
      fixture_ledger_dir = ".agent/tmp/notifications"
      fixture_ledger_file = ".agent/tmp/notifications/attention-fixture.jsonl"
      external_notification_sent = $false
      notification_event_type = "notification_delivery_fixture"
      token_printed = $false
    }
  }
}

$text = $result | ConvertTo-Json -Depth 40 -Compress
Assert-NoSecretText $text
if ($Json) {
  $text
} else {
  $result
}
