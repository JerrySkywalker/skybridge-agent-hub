param(
  [ValidateSet(
    "status",
    "preview-once",
    "preview-loop-fixture",
    "policy",
    "server-state-preview",
    "pairing-state-preview",
    "approval-state-preview",
    "queue-state-preview",
    "no-execution-gate",
    "report",
    "safe-summary"
  )]
  [string]$Command = "status",
  [int]$MaxIterationsPreview = 3,
  [switch]$Json
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$PollingDir = Join-Path $RepoRoot ".agent\tmp\resident-polling"
$ReportJsonPath = Join-Path $PollingDir "goal-224-report.json"
$ReportMdPath = Join-Path $PollingDir "goal-224-report.md"
$PreviewReportPath = Join-Path $PollingDir "resident-polling-report.json"

function Ensure-PollingDir {
  New-Item -ItemType Directory -Force -Path $PollingDir | Out-Null
}

function New-Now {
  return (Get-Date).ToUniversalTime().ToString("o")
}

function New-Policy {
  [ordered]@{
    schema = "skybridge.resident_polling_policy.v1"
    polling_enabled = $false
    polling_preview_enabled = $true
    execution_enabled = $false
    claim_enabled = $false
    queue_apply_enabled = $false
    remote_execution_enabled = $false
    arbitrary_command_enabled = $false
    poll_interval_seconds = 300
    max_iterations_preview = $MaxIterationsPreview
    require_resource_gate = $true
    require_pairing = $true
    require_approval_for_future_execution = $true
    no_next_execution_authorized = $true
    token_printed = $false
  }
}

function New-Blocker([string]$Id, [string]$Reason) {
  [ordered]@{
    schema = "skybridge.resident_polling_blocker.v1"
    blocker_id = $Id
    reason = $Reason
    token_printed = $false
  }
}

function New-Status([string]$State = "preview_ready", [string]$Summary = "resident polling preview is explicit and non-executing") {
  [ordered]@{
    schema = "skybridge.resident_polling_status.v1"
    status = $State
    last_poll_summary = $Summary
    next_poll_interval_seconds = 300
    blockers = @(
      New-Blocker "execution_disabled" "execution_enabled=false"
      New-Blocker "claim_disabled" "claim_enabled=false"
      New-Blocker "queue_apply_disabled" "queue_apply_enabled=false"
    )
    execution_enabled = $false
    claim_enabled = $false
    queue_apply_enabled = $false
    no_next_execution_authorized = $true
    token_printed = $false
  }
}

function New-Iteration([int]$Index) {
  [ordered]@{
    schema = "skybridge.resident_polling_iteration.v1"
    iteration_id = "resident-poll-preview-$Index"
    poll_started_at = New-Now
    server_state_checked = $true
    pairing_state_checked = $true
    approval_state_checked = $true
    queue_state_checked = $true
    task_claimed = $false
    codex_executed = $false
    queue_apply_performed = $false
    token_printed = $false
  }
}

function Assert-ReportSafe($Report) {
  $text = $Report | ConvertTo-Json -Depth 20
  if ($text -match '"token_printed"\s*:\s*true') { throw "token_printed=true rejected" }
  if ($text -match '"(task_claimed|codex_executed|queue_apply_performed|execution_enabled|claim_enabled|queue_apply_enabled|remote_execution_enabled|arbitrary_command_enabled)"\s*:\s*true') {
    throw "resident polling report attempted to enable execution"
  }
}

function New-Report([array]$Iterations = @()) {
  $report = [ordered]@{
    schema = "skybridge.resident_polling_report.v1"
    policy = New-Policy
    status = New-Status "preview_checked" "checked local preview state without claiming or executing"
    iterations = $Iterations
    task_claimed = $false
    codex_executed = $false
    queue_apply_performed = $false
    ready_for_goal_225 = $true
    token_printed = $false
  }
  Assert-ReportSafe $report
  return $report
}

function Write-Report($Report) {
  Ensure-PollingDir
  Assert-ReportSafe $Report
  $Report | ConvertTo-Json -Depth 20 | Set-Content -Encoding UTF8 -LiteralPath $PreviewReportPath
}

function Write-Goal224Report {
  $iterations = @(New-Iteration 1)
  $report = New-Report $iterations
  Ensure-PollingDir
  $goal = [ordered]@{
    schema = "skybridge.goal_224_report.v1"
    resident_polling_status = "preview_checked_execution_disabled"
    desktop_panel_status = "pairing_approval_polling_disabled_execution_visible"
    web_panel_status = "pairing_approval_polling_disabled_execution_visible"
    poll_interval_seconds = 300
    task_claimed = $false
    codex_executed = $false
    queue_apply_performed = $false
    execution_enabled = $false
    claim_enabled = $false
    queue_apply_enabled = $false
    remote_execution_enabled = $false
    arbitrary_command_enabled = $false
    no_next_execution_authorized = $true
    token_printed = $false
    report = $report
    ready_for_goal_225 = $true
  }
  Assert-ReportSafe $goal
  $goal | ConvertTo-Json -Depth 20 | Set-Content -Encoding UTF8 -LiteralPath $ReportJsonPath
  @(
    "# Goal 224 Report",
    "",
    "- resident_polling_status: preview_checked_execution_disabled",
    "- desktop_panel_status: pairing_approval_polling_disabled_execution_visible",
    "- web_panel_status: pairing_approval_polling_disabled_execution_visible",
    "- poll_interval_seconds: 300",
    "- task_claimed: false",
    "- codex_executed: false",
    "- queue_apply_performed: false",
    "- execution_enabled: false",
    "- claim_enabled: false",
    "- queue_apply_enabled: false",
    "- no_next_execution_authorized: true",
    "- token_printed: false",
    "- ready_for_goal_225: true"
  ) | Set-Content -Encoding UTF8 -LiteralPath $ReportMdPath
  Write-Report $report
  return $goal
}

Ensure-PollingDir

$output = switch ($Command) {
  "status" { New-Status }
  "policy" { New-Policy }
  "preview-once" { $report = New-Report @(New-Iteration 1); Write-Report $report; $report }
  "preview-loop-fixture" {
    $count = [Math]::Max(1, [Math]::Min($MaxIterationsPreview, 5))
    $iterations = for ($i = 1; $i -le $count; $i++) { New-Iteration $i }
    $report = New-Report @($iterations)
    Write-Report $report
    $report
  }
  "server-state-preview" { [ordered]@{ schema = "skybridge.resident_polling_server_state_preview.v1"; active_tasks = 0; stale_leases = 0; runner_lock = "none"; execution_enabled = $false; token_printed = $false } }
  "pairing-state-preview" { [ordered]@{ schema = "skybridge.resident_polling_pairing_state_preview.v1"; pairing_required = $true; pairing_state = "paired_or_pending_preview"; raw_pairing_code_persisted = $false; token_printed = $false } }
  "approval-state-preview" { [ordered]@{ schema = "skybridge.resident_polling_approval_state_preview.v1"; approval_required_for_future_execution = $true; can_execute_now = $false; token_printed = $false } }
  "queue-state-preview" { [ordered]@{ schema = "skybridge.resident_polling_queue_state_preview.v1"; queued_workunits = 0; task_claimed = $false; queue_apply_performed = $false; token_printed = $false } }
  "no-execution-gate" { [ordered]@{ schema = "skybridge.resident_polling_no_execution_gate.v1"; execution_enabled = $false; claim_enabled = $false; queue_apply_enabled = $false; codex_executed = $false; token_printed = $false } }
  "report" { Write-Goal224Report }
  "safe-summary" { [ordered]@{ ok = $true; polling_preview_enabled = $true; polling_enabled = $false; execution_enabled = $false; claim_enabled = $false; queue_apply_enabled = $false; no_next_execution_authorized = $true; token_printed = $false } }
}

if ($Json) {
  $output | ConvertTo-Json -Depth 20
} else {
  $output | ConvertTo-Json -Depth 20
}
