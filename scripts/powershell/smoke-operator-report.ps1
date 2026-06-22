[CmdletBinding()]
param([switch]$Json)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"
Import-Module (Join-Path $PSScriptRoot "lib\Skybridge.OperatorSanitizer.psm1") -Force

$tmpRoot = Join-Path $RepoRoot ".agent\tmp\operator-report-smoke"
New-Item -ItemType Directory -Force -Path $tmpRoot | Out-Null

function Write-Fixture {
  param([string]$Name, $Value)
  $path = Join-Path $tmpRoot $Name
  $Value | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $path -Encoding UTF8
  $path
}

foreach ($case in @(
  "Authorization: Bearer abcdefghijklmnopqrstuvwxyz",
  "sk-proj-abcdefghijklmnopqrstuvwxyz123456",
  "ghp_abcdefghijklmnopqrstuvwxyz1234567890",
  "cookie=sessionid=secret password=hunter2 api_key=abc123456789",
  "https://user:pass@example.invalid/hook",
  ("raw log " + ("x" * 900))
)) {
  $safe = ConvertTo-SkybridgeOperatorSafeText -Text $case -MaxLength 160
  Assert-NoUnsafeText $safe
  if ($safe.Length -gt 175) { throw "Sanitizer did not truncate long text." }
}

$convergencePath = Write-Fixture "convergence.json" ([pscustomobject]@{
  schema = "skybridge.self_bootstrap_convergence.v1"
  ok = $true
  local = [pscustomobject]@{ clean = $true; head_commit = "abc123"; token_printed = $false }
  cloud = [pscustomobject]@{ commit_aligned = $true; deploy_evidence_ok = $true; commit_sha = "abc123"; token_printed = $false }
  readiness = [pscustomobject]@{ status = "partial"; project_control_state = "paused"; can_start_one = $false; can_run_until_hold = $false; workers_online = 1; online_worker_ids = @("jerry-win-local-01"); warnings = @("blocked_tasks_present"); token_printed = $false }
  token_printed = $false
})

$campaignPath = Write-Fixture "campaign.json" ([pscustomobject]@{
  schema = "skybridge.campaign_policy_report.v1"
  ok = $true
  campaign_id = "campaign-policy-compiler-pilot-001"
  campaign_status = "completed"
  generated_task_count = 2
  completed_task_count = 2
  rejected_task_count = 1
  evidence_state = [pscustomobject]@{ evidence_present = $true; token_printed = $false }
  old_residue_excluded = $true
  token_printed = $false
})

$boundedPath = Write-Fixture "bounded-report.json" ([pscustomobject]@{
  schema = "skybridge.run_until_hold_report.v1"
  ok = $true
  latest_bounded_run_status = "completed_max_tasks"
  stop_reason = "completed_max_tasks"
  hold_reason = $null
  executed_tasks = @([pscustomobject]@{ task_id = "campaign-policy-compiler-pilot-docs-001"; evidence_written = $true; token_printed = $false })
  evidence_summary = [pscustomobject]@{ evidence_present = $true; attempted_task_count = 1; token_printed = $false }
  project_control_stayed_paused = $true
  run_until_hold_stayed_bounded = $true
  token_printed = $false
})

$holdPath = Write-Fixture "hold.json" ([pscustomobject]@{
  schema = "skybridge.start_one_hold_report.v1"
  ok = $true
  terminal_state = "already_completed_noop"
  hold_reason = "pilot_task_already_completed"
  evidence_present = $true
  manual_operator_review_needed = $false
  token_printed = $false
})

$notificationPath = Write-Fixture "notification.json" ([pscustomobject]@{
  schema = "skybridge.operator_notification_readiness.v1"
  ok = $true
  status = "bootstrap_dry_run_only"
  dry_run = $true
  report_delivery_supported = $true
  review_gate_supported = $true
  bootstrap_dry_run_available = $true
  real_send_performed = $false
  raw_notification_payload_included = $false
  credential_values_exposed = $false
  token_printed = $false
})

$gatePath = Write-Fixture "gate.json" ([pscustomobject]@{
  schema = "skybridge.review_gate.v1"
  ok = $true
  gate_status = "safe_to_continue_preview_only"
  allowed_preview = $true
  allowed_bounded_run = $false
  allowed_unbounded_run = $false
  allowed_daemon = $false
  old_residue_excluded = $true
  project_control_paused = $true
  recommended_next_safe_action = "Continue with preview-only report and gate checks."
  token_printed = $false
})

$raw = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-operator-report.ps1 `
  -FixtureConvergenceFile $convergencePath `
  -FixtureCampaignPolicyReportFile $campaignPath `
  -FixtureBoundedRunReportFile $boundedPath `
  -FixtureHoldReportFile $holdPath `
  -FixtureNotificationReadinessFile $notificationPath `
  -FixtureReviewGateFile $gatePath `
  -IncludeCampaign -IncludeBoundedRun -IncludeHold -Json
if ($LASTEXITCODE -ne 0) { throw "operator report failed." }
$text = (($raw | Out-String).Trim())
Assert-NoUnsafeText $text
$report = $text | ConvertFrom-Json
if ($report.schema -ne "skybridge.operator_report.v1") { throw "Unexpected operator report schema." }
Assert-True $report.ok "operator report ok"
Assert-True $report.campaign_summary.included "campaign included"
Assert-True $report.bounded_run_summary.included "bounded included"
Assert-True $report.hold_summary.included "hold included"
Assert-True $report.evidence_summary.evidence_present "evidence present"
Assert-False $report.old_residue_summary.old_residue_selected "old residue selected"
Assert-False $report.safety_summary.project_control_unpaused "project_control_unpaused"
Assert-False $report.safety_summary.run_until_hold_recursive "run_until_hold_recursive"
Assert-False $report.token_printed "token_printed"

$summary = [pscustomobject]@{
  ok = $true
  smoke = "operator-report"
  scenarios = @("current_state", "campaign_summary", "bounded_run_summary", "hold_failure_summary", "sanitizer_redaction", "token_printed_false")
  token_printed = $false
}
if ($Json) { $summary | ConvertTo-Json -Depth 8 -Compress } else { Complete-Smoke "operator-report" }
