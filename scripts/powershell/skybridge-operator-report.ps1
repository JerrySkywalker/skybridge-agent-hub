[CmdletBinding()]
param(
  [switch]$Json,
  [string]$ApiBase,
  [string]$TokenFile,
  [string]$ProjectId = "skybridge-agent-hub",
  [string]$ReportKind = "current-state",
  [switch]$IncludeCampaign,
  [switch]$IncludeBoundedRun,
  [switch]$IncludeHold,
  [int]$TimeoutSeconds = 30,
  [string]$FixtureConvergenceFile,
  [string]$FixtureCampaignPolicyReportFile,
  [string]$FixtureBoundedRunReportFile,
  [string]$FixtureHoldReportFile,
  [string]$FixtureNotificationReadinessFile,
  [string]$FixtureReviewGateFile
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
Set-Location $RepoRoot
Import-Module (Join-Path $PSScriptRoot "lib\Skybridge.OperatorSanitizer.psm1") -Force

function Invoke-OptionalJson {
  param([string[]]$Arguments)
  try { Invoke-SkybridgeOperatorChildJson -Arguments $Arguments -AllowNonZero } catch {
    [pscustomobject]@{ ok = $false; error_summary = ConvertTo-SkybridgeOperatorSafeText -Text $_.Exception.Message; token_printed = $false }
  }
}

function Get-Convergence {
  if ($FixtureConvergenceFile) { return Read-SkybridgeOperatorJsonFile -Path $FixtureConvergenceFile }
  $branch = ""
  $clean = $false
  $head = ""
  try { $branch = ((& git branch --show-current 2>$null | Out-String).Trim()) } catch {}
  try { $head = ((& git rev-parse HEAD 2>$null | Out-String).Trim()) } catch {}
  try { $clean = [string]::IsNullOrWhiteSpace(((& git status --short 2>$null | Out-String).Trim())) } catch {}
  $version = $null
  if ($ApiBase) {
    try { $version = Invoke-RestMethod -Method GET -Uri "$($ApiBase.TrimEnd('/'))/v1/version" -TimeoutSec $TimeoutSeconds } catch {}
  }
  $readinessArgs = @("-File", (Join-Path $PSScriptRoot "skybridge-self-bootstrap-readiness.ps1"), "-ProjectId", $ProjectId, "-TimeoutSeconds", [string]$TimeoutSeconds, "-Json")
  if ($ApiBase) { $readinessArgs += @("-ApiBase", $ApiBase) }
  if ($TokenFile) { $readinessArgs += @("-TokenFile", $TokenFile) }
  $readinessProbe = Invoke-OptionalJson -Arguments $readinessArgs
  $cloudCommit = [string](Get-SkybridgeOperatorProp -Object $version -Name "commit_sha" -Default "")
  [pscustomobject]@{
    ok = $true
    local = [pscustomobject]@{
      branch = $branch
      clean = $clean
      head_commit = $head
      token_printed = $false
    }
    cloud = [pscustomobject]@{
      commit_sha = $cloudCommit
      commit_aligned = (-not [string]::IsNullOrWhiteSpace($cloudCommit) -and $cloudCommit -eq $head)
      deploy_evidence_ok = $false
      token_printed = $false
    }
    readiness = if ($readinessProbe) { Get-SkybridgeOperatorProp -Object $readinessProbe -Name "readiness" -Default $readinessProbe } else { $null }
    token_printed = $false
  }
}

function Get-Campaign {
  if ($FixtureCampaignPolicyReportFile) { return Read-SkybridgeOperatorJsonFile -Path $FixtureCampaignPolicyReportFile }
  $args = @("-File", (Join-Path $PSScriptRoot "skybridge-campaign-policy-report.ps1"), "-ProjectId", $ProjectId, "-TimeoutSeconds", [string]$TimeoutSeconds, "-Json")
  if ($ApiBase) { $args += @("-ApiBase", $ApiBase) }
  if ($TokenFile) { $args += @("-TokenFile", $TokenFile) }
  Invoke-OptionalJson -Arguments $args
}

function Get-Bounded {
  if ($FixtureBoundedRunReportFile) { return Read-SkybridgeOperatorJsonFile -Path $FixtureBoundedRunReportFile }
  $args = @("-File", (Join-Path $PSScriptRoot "skybridge-run-until-hold-report.ps1"), "-ProjectId", $ProjectId, "-TimeoutSeconds", [string]$TimeoutSeconds, "-Json")
  if ($ApiBase) { $args += @("-ApiBase", $ApiBase) }
  if ($TokenFile) { $args += @("-TokenFile", $TokenFile) }
  Invoke-OptionalJson -Arguments $args
}

function Get-Hold {
  if ($FixtureHoldReportFile) { return Read-SkybridgeOperatorJsonFile -Path $FixtureHoldReportFile }
  $args = @("-File", (Join-Path $PSScriptRoot "skybridge-start-one-hold-report.ps1"), "-ProjectId", $ProjectId, "-TimeoutSeconds", [string]$TimeoutSeconds, "-Json")
  if ($ApiBase) { $args += @("-ApiBase", $ApiBase) }
  if ($TokenFile) { $args += @("-TokenFile", $TokenFile) }
  Invoke-OptionalJson -Arguments $args
}

function Get-Notification {
  if ($FixtureNotificationReadinessFile) { return Read-SkybridgeOperatorJsonFile -Path $FixtureNotificationReadinessFile }
  $args = @("-File", (Join-Path $PSScriptRoot "skybridge-operator-notification-readiness.ps1"), "-ProjectId", $ProjectId, "-TimeoutSeconds", [string]$TimeoutSeconds, "-DryRun", "-Json")
  if ($ApiBase) { $args += @("-ApiBase", $ApiBase) }
  if ($TokenFile) { $args += @("-TokenFile", $TokenFile) }
  Invoke-OptionalJson -Arguments $args
}

function Get-ReviewGate {
  if ($FixtureReviewGateFile) { return Read-SkybridgeOperatorJsonFile -Path $FixtureReviewGateFile }
  $args = @("-File", (Join-Path $PSScriptRoot "skybridge-review-gate.ps1"), "-ProjectId", $ProjectId, "-TimeoutSeconds", [string]$TimeoutSeconds, "-Json")
  if ($ApiBase) { $args += @("-ApiBase", $ApiBase) }
  if ($TokenFile) { $args += @("-TokenFile", $TokenFile) }
  Invoke-OptionalJson -Arguments $args
}

$convergence = Get-Convergence
$campaign = if ($IncludeCampaign -or -not $PSBoundParameters.ContainsKey("IncludeCampaign")) { Get-Campaign } else { $null }
$bounded = if ($IncludeBoundedRun -or -not $PSBoundParameters.ContainsKey("IncludeBoundedRun")) { Get-Bounded } else { $null }
$hold = if ($IncludeHold -or -not $PSBoundParameters.ContainsKey("IncludeHold")) { Get-Hold } else { $null }
$notification = Get-Notification
$gate = Get-ReviewGate

$cloud = Get-SkybridgeOperatorProp -Object $convergence -Name "cloud"
$readiness = Get-SkybridgeOperatorProp -Object $convergence -Name "readiness"
$workerIds = @((Get-SkybridgeOperatorProp -Object $readiness -Name "online_worker_ids" -Default @()) | ForEach-Object { [string]$_ })
$campaignEvidence = Get-SkybridgeOperatorProp -Object $campaign -Name "evidence_state"
$boundedEvidence = Get-SkybridgeOperatorProp -Object $bounded -Name "evidence_summary"
$holdEvidence = Get-SkybridgeOperatorProp -Object $hold -Name "evidence_summary"

$report = [pscustomobject]@{
  schema = "skybridge.operator_report.v1"
  ok = $true
  generated_at = (Get-Date).ToUniversalTime().ToString("o")
  project_id = $ProjectId
  report_kind = $ReportKind
  local_cloud_summary = [pscustomobject]@{
    local_clean = Get-SkybridgeOperatorBool -Object (Get-SkybridgeOperatorProp -Object $convergence -Name "local") -Name "clean"
    cloud_commit_aligned = Get-SkybridgeOperatorBool -Object $cloud -Name "commit_aligned"
    cloud_deploy_evidence_ok = Get-SkybridgeOperatorBool -Object $cloud -Name "deploy_evidence_ok"
    cloud_commit_sha = [string](Get-SkybridgeOperatorProp -Object $cloud -Name "commit_sha" -Default "")
    token_printed = $false
  }
  readiness_summary = [pscustomobject]@{
    status = [string](Get-SkybridgeOperatorProp -Object $readiness -Name "status" -Default "unknown")
    project_control_state = [string](Get-SkybridgeOperatorProp -Object $readiness -Name "project_control_state" -Default "unknown")
    can_start_one = Get-SkybridgeOperatorBool -Object $readiness -Name "can_start_one"
    can_run_until_hold = Get-SkybridgeOperatorBool -Object $readiness -Name "can_run_until_hold"
    warnings = @((Get-SkybridgeOperatorProp -Object $readiness -Name "warnings" -Default @()) | ForEach-Object { ConvertTo-SkybridgeOperatorSafeText -Text ([string]$_) -MaxLength 120 })
    token_printed = $false
  }
  worker_summary = [pscustomobject]@{
    workers_online = Get-SkybridgeOperatorInt -Object $readiness -Name "workers_online"
    online_worker_ids = @($workerIds)
    heartbeat_required_for_execution = $true
    token_printed = $false
  }
  notification_summary = [pscustomobject]@{
    status = [string](Get-SkybridgeOperatorProp -Object $notification -Name "status" -Default "unknown")
    dry_run = Get-SkybridgeOperatorBool -Object $notification -Name "dry_run" -Default $true
    report_delivery_supported = Get-SkybridgeOperatorBool -Object $notification -Name "report_delivery_supported"
    review_gate_supported = Get-SkybridgeOperatorBool -Object $notification -Name "review_gate_supported"
    bootstrap_dry_run_available = Get-SkybridgeOperatorBool -Object $notification -Name "bootstrap_dry_run_available"
    real_send_performed = Get-SkybridgeOperatorBool -Object $notification -Name "real_send_performed"
    raw_notification_payload_included = $false
    credential_values_exposed = $false
    token_printed = $false
  }
  campaign_summary = [pscustomobject]@{
    included = ($null -ne $campaign)
    latest_campaign_id = [string](Get-SkybridgeOperatorProp -Object $campaign -Name "campaign_id" -Default "")
    generated_task_count = Get-SkybridgeOperatorInt -Object $campaign -Name "generated_task_count"
    completed_task_count = Get-SkybridgeOperatorInt -Object $campaign -Name "completed_task_count"
    rejected_unsafe_count = Get-SkybridgeOperatorInt -Object $campaign -Name "rejected_task_count"
    campaign_status = [string](Get-SkybridgeOperatorProp -Object $campaign -Name "campaign_status" -Default "not_reported")
    token_printed = $false
  }
  bounded_run_summary = [pscustomobject]@{
    included = ($null -ne $bounded)
    selected_count = @((Get-SkybridgeOperatorProp -Object $bounded -Name "selected_candidates" -Default @())).Count
    executed_count = @((Get-SkybridgeOperatorProp -Object $bounded -Name "executed_tasks" -Default @())).Count
    stop_reason = [string](Get-SkybridgeOperatorProp -Object $bounded -Name "stop_reason" -Default (Get-SkybridgeOperatorProp -Object $bounded -Name "latest_bounded_run_status" -Default "not_reported"))
    hold_reason = [string](Get-SkybridgeOperatorProp -Object $bounded -Name "hold_reason" -Default "")
    project_control_unpaused = (-not (Get-SkybridgeOperatorBool -Object $bounded -Name "project_control_stayed_paused" -Default $true))
    run_until_hold_recursive = (-not (Get-SkybridgeOperatorBool -Object $bounded -Name "run_until_hold_stayed_bounded" -Default $true))
    token_printed = $false
  }
  hold_summary = [pscustomobject]@{
    included = ($null -ne $hold)
    terminal_state = [string](Get-SkybridgeOperatorProp -Object $hold -Name "terminal_state" -Default "not_reported")
    hold_reason = [string](Get-SkybridgeOperatorProp -Object $hold -Name "hold_reason" -Default "")
    evidence_present = Get-SkybridgeOperatorBool -Object $hold -Name "evidence_present"
    manual_operator_review_needed = Get-SkybridgeOperatorBool -Object $hold -Name "manual_operator_review_needed"
    token_printed = $false
  }
  evidence_summary = [pscustomobject]@{
    evidence_present = ((Get-SkybridgeOperatorBool -Object $campaignEvidence -Name "evidence_present" -Default $true) -and (Get-SkybridgeOperatorBool -Object $boundedEvidence -Name "evidence_present" -Default $true) -and (Get-SkybridgeOperatorBool -Object $hold -Name "evidence_present" -Default $true))
    campaign_evidence_present = Get-SkybridgeOperatorBool -Object $campaignEvidence -Name "evidence_present" -Default $true
    bounded_evidence_present = Get-SkybridgeOperatorBool -Object $boundedEvidence -Name "evidence_present" -Default $true
    hold_evidence_present = Get-SkybridgeOperatorBool -Object $hold -Name "evidence_present" -Default $true
    prompt_content_included = $false
    log_content_included = $false
    credential_values_included = $false
    token_printed = $false
  }
  old_residue_summary = [pscustomobject]@{
    old_residue_selected = $false
    old_residue_excluded = (Get-SkybridgeOperatorBool -Object $campaign -Name "old_residue_excluded" -Default $true)
    old_task_claimed = $false
    old_task_requeued = $false
    token_printed = $false
  }
  safety_summary = [pscustomobject]@{
    project_control_unpaused = $false
    run_until_hold_recursive = $false
    unbounded_run_enabled = $false
    daemon_enabled = $false
    prompt_content_included = $false
    log_content_included = $false
    secret_or_token_included = $false
    token_printed = $false
  }
  review_gate = $gate
  recommended_next_safe_action = [string](Get-SkybridgeOperatorProp -Object $gate -Name "recommended_next_safe_action" -Default "Continue with sanitized operator reporting and dry-run notification readiness.")
  token_printed = $false
}

$report.ok = (
  -not [bool]$report.notification_summary.real_send_performed -and
  -not [bool]$report.notification_summary.raw_notification_payload_included -and
  -not [bool]$report.notification_summary.credential_values_exposed -and
  -not [bool]$report.safety_summary.project_control_unpaused -and
  -not [bool]$report.safety_summary.run_until_hold_recursive -and
  -not [bool]$report.safety_summary.secret_or_token_included
)

if ($Json) {
  ConvertTo-SkybridgeOperatorSafeJson -Value $report -Depth 30
} else {
  "Schema:       $($report.schema)"
  "OK:           $($report.ok)"
  "ReportKind:   $($report.report_kind)"
  "Gate:         $($report.review_gate.gate_status)"
  "Next:         $($report.recommended_next_safe_action)"
  "TokenPrinted: false"
}
