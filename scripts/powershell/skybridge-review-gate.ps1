[CmdletBinding()]
param(
  [switch]$Json,
  [string]$ApiBase,
  [string]$TokenFile,
  [string]$ProjectId = "skybridge-agent-hub",
  [string]$Mode = "current-state",
  [int]$TimeoutSeconds = 30,
  [string]$FixtureReadinessFile,
  [string]$FixtureNotificationFile,
  [string]$FixtureBoundedRunFile,
  [string]$FixtureCampaignReportFile,
  [string]$FixtureOperatorReportFile,
  [switch]$FixtureUnboundedEnabled,
  [switch]$FixtureDaemonEnabled
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
Set-Location $RepoRoot
Import-Module (Join-Path $PSScriptRoot "lib\Skybridge.OperatorSanitizer.psm1") -Force

function Invoke-OptionalJson {
  param([string[]]$Arguments)
  try { Invoke-SkybridgeOperatorChildJson -Arguments $Arguments -AllowNonZero } catch { $null }
}

$readiness = if ($FixtureReadinessFile) {
  Read-SkybridgeOperatorJsonFile -Path $FixtureReadinessFile
} else {
  $args = @("-File", (Join-Path $PSScriptRoot "skybridge-self-bootstrap-readiness.ps1"), "-ProjectId", $ProjectId, "-TimeoutSeconds", [string]$TimeoutSeconds, "-Json")
  if ($ApiBase) { $args += @("-ApiBase", $ApiBase) }
  if ($TokenFile) { $args += @("-TokenFile", $TokenFile) }
  Invoke-OptionalJson -Arguments $args
}

$notification = if ($FixtureNotificationFile) {
  Read-SkybridgeOperatorJsonFile -Path $FixtureNotificationFile
} else {
  $args = @("-File", (Join-Path $PSScriptRoot "skybridge-operator-notification-readiness.ps1"), "-ProjectId", $ProjectId, "-TimeoutSeconds", [string]$TimeoutSeconds, "-DryRun", "-Json")
  if ($ApiBase) { $args += @("-ApiBase", $ApiBase) }
  if ($TokenFile) { $args += @("-TokenFile", $TokenFile) }
  Invoke-OptionalJson -Arguments $args
}

$bounded = if ($FixtureBoundedRunFile) {
  Read-SkybridgeOperatorJsonFile -Path $FixtureBoundedRunFile
} else {
  $args = @("-File", (Join-Path $PSScriptRoot "skybridge-run-until-hold-bounded.ps1"), "-ProjectId", $ProjectId, "-TimeoutSeconds", [string]$TimeoutSeconds, "-Preview", "-Json")
  if ($ApiBase) { $args += @("-ApiBase", $ApiBase) }
  if ($TokenFile) { $args += @("-TokenFile", $TokenFile) }
  Invoke-OptionalJson -Arguments $args
}

$campaign = if ($FixtureCampaignReportFile) {
  Read-SkybridgeOperatorJsonFile -Path $FixtureCampaignReportFile
} else {
  $args = @("-File", (Join-Path $PSScriptRoot "skybridge-campaign-policy-report.ps1"), "-ProjectId", $ProjectId, "-TimeoutSeconds", [string]$TimeoutSeconds, "-Json")
  if ($ApiBase) { $args += @("-ApiBase", $ApiBase) }
  if ($TokenFile) { $args += @("-TokenFile", $TokenFile) }
  Invoke-OptionalJson -Arguments $args
}

$operatorReportAvailable = if ($FixtureOperatorReportFile) {
  $op = Read-SkybridgeOperatorJsonFile -Path $FixtureOperatorReportFile
  [bool](Get-SkybridgeOperatorBool -Object $op -Name "ok" -Default $true)
} else {
  Test-Path -LiteralPath (Join-Path $PSScriptRoot "skybridge-operator-report.ps1") -PathType Leaf
}

$control = Get-SkybridgeOperatorProp -Object (Get-SkybridgeOperatorProp -Object $readiness -Name "control_plane") -Name "project_control"
$projectControlState = [string](Get-SkybridgeOperatorProp -Object $control -Name "state" -Default (Get-SkybridgeOperatorProp -Object $readiness -Name "project_control_state" -Default "paused"))
$projectControlPaused = ($projectControlState -eq "paused")
$notificationAvailable = [bool](Get-SkybridgeOperatorBool -Object $notification -Name "report_delivery_supported" -Default $false)
$oldResidueExcluded = [bool](Get-SkybridgeOperatorBool -Object (Get-SkybridgeOperatorProp -Object $bounded -Name "old_residue_exclusion") -Name "no_old_residue_eligible" -Default (Get-SkybridgeOperatorBool -Object $campaign -Name "old_residue_excluded" -Default $true))
$evidenceAvailable = [bool](Get-SkybridgeOperatorBool -Object (Get-SkybridgeOperatorProp -Object $bounded -Name "evidence_summary") -Name "evidence_present" -Default (Get-SkybridgeOperatorBool -Object (Get-SkybridgeOperatorProp -Object $campaign -Name "evidence_state") -Name "evidence_present" -Default $true))
$forbidden = Get-SkybridgeOperatorProp -Object $bounded -Name "forbidden_actions"
$boundedConstraints = (-not (Get-SkybridgeOperatorBool -Object $forbidden -Name "recursive_run_until_hold") -and -not (Get-SkybridgeOperatorBool -Object $forbidden -Name "daemon_implemented"))
$unsafeActive = @((Get-SkybridgeOperatorProp -Object $readiness -Name "blockers" -Default @()) | Where-Object { [string]$_ -eq "active_tasks_present" }).Count -gt 0
$allowedUnbounded = [bool]$FixtureUnboundedEnabled
$allowedDaemon = [bool]$FixtureDaemonEnabled

$blockers = @()
$warnings = @()
if (-not $projectControlPaused) { $blockers += "project_control_not_paused" }
if (-not $oldResidueExcluded) { $blockers += "old_residue_not_excluded" }
if (-not $evidenceAvailable) { $blockers += "evidence_semantics_unavailable" }
if (-not $operatorReportAvailable) { $blockers += "operator_report_unavailable" }
if (-not $notificationAvailable) { $blockers += "notification_report_delivery_unavailable" }
if (-not $boundedConstraints) { $blockers += "bounded_loop_constraints_not_enforced" }
if ($unsafeActive) { $blockers += "unsafe_active_task_present" }
if ($allowedUnbounded) { $blockers += "unbounded_run_enabled" }
if ($allowedDaemon) { $blockers += "daemon_enabled" }
foreach ($warning in @((Get-SkybridgeOperatorProp -Object $readiness -Name "warnings" -Default @()) | ForEach-Object { [string]$_ })) { if ($warning) { $warnings += $warning } }

$allowedPreview = ($projectControlPaused -and $operatorReportAvailable -and $notificationAvailable -and -not $allowedUnbounded -and -not $allowedDaemon)
$allowedBounded = ($allowedPreview -and $oldResidueExcluded -and $evidenceAvailable -and $boundedConstraints -and -not $unsafeActive -and $blockers.Count -eq 0)
$needsReview = (-not $allowedBounded -and $allowedPreview)
$gateStatus = if ($allowedUnbounded -or $allowedDaemon) {
  "failed_closed"
} elseif ($blockers.Count -gt 0 -and -not $allowedPreview) {
  "blocked"
} elseif ($needsReview) {
  "needs_operator_review"
} elseif ($allowedBounded -and [string](Get-SkybridgeOperatorProp -Object $bounded -Name "stop_reason" -Default "") -eq "preview_ready") {
  "safe_to_continue_bounded"
} else {
  "safe_to_continue_preview_only"
}

$report = [pscustomobject]@{
  schema = "skybridge.review_gate.v1"
  ok = ($gateStatus -ne "failed_closed" -and $gateStatus -ne "blocked")
  gate_status = $gateStatus
  mode = $Mode
  allowed_preview = $allowedPreview
  allowed_bounded_run = $allowedBounded
  allowed_unbounded_run = $false
  allowed_daemon = $false
  needs_operator_review = ($needsReview -or $gateStatus -eq "needs_operator_review")
  blockers = @($blockers)
  warnings = @($warnings)
  evidence_required = $true
  notification_required = $true
  notification_available = $notificationAvailable
  last_campaign_status = [string](Get-SkybridgeOperatorProp -Object $campaign -Name "campaign_status" -Default "not_reported")
  last_bounded_run_status = [string](Get-SkybridgeOperatorProp -Object $bounded -Name "stop_reason" -Default "not_reported")
  old_residue_excluded = $oldResidueExcluded
  project_control_paused = $projectControlPaused
  bounded_loop_constraints_enforced = $boundedConstraints
  operator_report_available = $operatorReportAvailable
  recommended_next_safe_action = if ($gateStatus -eq "safe_to_continue_bounded") { "A bounded preview/apply may proceed only under the existing max task constraints and explicit confirmation." } elseif ($gateStatus -eq "safe_to_continue_preview_only") { "Continue with preview-only report and gate checks; do not run apply unless a later goal authorizes it." } elseif ($gateStatus -eq "needs_operator_review") { "Hold for operator review before any bounded apply." } else { "Failed closed; do not run task execution paths." }
  token_printed = $false
}

if ($Json) {
  ConvertTo-SkybridgeOperatorSafeJson -Value $report -Depth 20
} else {
  "Schema:       $($report.schema)"
  "Gate:         $($report.gate_status)"
  "Preview:      $($report.allowed_preview)"
  "Bounded:      $($report.allowed_bounded_run)"
  "TokenPrinted: false"
}
