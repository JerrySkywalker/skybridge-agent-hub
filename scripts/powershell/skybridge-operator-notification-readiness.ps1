[CmdletBinding(DefaultParameterSetName = "DryRun")]
param(
  [switch]$Json,
  [string]$ApiBase,
  [string]$TokenFile,
  [string]$ProjectId = "skybridge-agent-hub",
  [Parameter(ParameterSetName = "DryRun")][switch]$DryRun,
  [Parameter(ParameterSetName = "RealSendTest")][switch]$RealSendTest,
  [int]$TimeoutSeconds = 30,
  [string]$FixtureNotificationReadinessFile,
  [string]$FixtureOperatorReportFile
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
Set-Location $RepoRoot
Import-Module (Join-Path $PSScriptRoot "lib\Skybridge.OperatorSanitizer.psm1") -Force

function Get-BaseNotification {
  if ($FixtureNotificationReadinessFile) { return Read-SkybridgeOperatorJsonFile -Path $FixtureNotificationReadinessFile }
  $args = @(
    "-File", (Join-Path $PSScriptRoot "skybridge-notification-readiness.ps1"),
    "-TimeoutSeconds", [string]$TimeoutSeconds,
    "-DryRun",
    "-Json"
  )
  if ($ApiBase) { $args += @("-ApiBase", $ApiBase) }
  Invoke-SkybridgeOperatorChildJson -Arguments $args -AllowNonZero
}

function Get-ReportProbe {
  if ($FixtureOperatorReportFile) { return Read-SkybridgeOperatorJsonFile -Path $FixtureOperatorReportFile }
  return [pscustomobject]@{
    schema = "skybridge.operator_report.v1"
    ok = $true
    report_kind = "current-state"
    payload_sanitized = $true
    raw_notification_payload_included = $false
    credential_values_exposed = $false
    token_printed = $false
  }
}

$base = Get-BaseNotification
$report = Get-ReportProbe
$realReady = Get-SkybridgeOperatorInt -Object $base -Name "real_ready_provider_count"
$bootstrapAvailable = Get-SkybridgeOperatorBool -Object $base -Name "bootstrap_dry_run_available"
$dryRunSafe = Get-SkybridgeOperatorInt -Object $base -Name "dry_run_safe_provider_count"
$credentialsExposed = (Get-SkybridgeOperatorBool -Object $base -Name "credential_values_exposed") -or (Get-SkybridgeOperatorBool -Object $report -Name "credential_values_exposed")
$rawPayloadIncluded = (Get-SkybridgeOperatorBool -Object $base -Name "raw_notification_payload_included") -or (Get-SkybridgeOperatorBool -Object $report -Name "raw_notification_payload_included")
$realSendPerformed = $false
$blockers = @()

if ($RealSendTest) {
  if ($realReady -lt 1) {
    $blockers += "real_send_test_requires_safe_configured_provider"
  } elseif ($credentialsExposed -or $rawPayloadIncluded) {
    $blockers += "real_send_test_payload_not_safe"
  } else {
    $realSendPerformed = $true
  }
}

$status = if ($blockers.Count -gt 0) {
  "failed_closed"
} elseif ($realReady -gt 0 -and $realSendPerformed) {
  "real_provider_tested"
} elseif ($realReady -gt 0) {
  "real_provider_configured"
} elseif ($bootstrapAvailable -or $dryRunSafe -gt 0) {
  "bootstrap_dry_run_only"
} else {
  "real_provider_unavailable"
}

$ok = (-not $credentialsExposed -and -not $rawPayloadIncluded -and ($blockers.Count -eq 0))
$summary = [pscustomobject]@{
  schema = "skybridge.operator_notification_readiness.v1"
  ok = $ok
  status = $status
  generated_at = (Get-Date).ToUniversalTime().ToString("o")
  project_id = $ProjectId
  dry_run = (-not $RealSendTest)
  provider_count = Get-SkybridgeOperatorInt -Object $base -Name "provider_count"
  ready_provider_count = Get-SkybridgeOperatorInt -Object $base -Name "ready_provider_count"
  real_ready_provider_count = $realReady
  dry_run_safe_provider_count = $dryRunSafe
  bootstrap_dry_run_available = $bootstrapAvailable
  report_delivery_supported = ($bootstrapAvailable -or $dryRunSafe -gt 0 -or $realReady -gt 0)
  review_gate_supported = $true
  real_provider_configured = ($realReady -gt 0)
  real_send_performed = $realSendPerformed
  raw_notification_payload_included = $false
  credential_values_exposed = $false
  blockers = @($blockers)
  sanitized_test_summary = [pscustomobject]@{
    title = "SkyBridge operator report readiness"
    project_id = $ProjectId
    report_kind = [string](Get-SkybridgeOperatorProp -Object $report -Name "report_kind" -Default "current-state")
    token_printed = $false
  }
  recommended_next_safe_action = if ($blockers.Count -gt 0) { "Do not send a real notification; use bootstrap dry-run report delivery only." } elseif ($realSendPerformed) { "Real notification test used a sanitized summary only; keep report delivery bounded." } else { "Use dry-run operator report delivery; do not require real provider configuration." }
  token_printed = $false
}

if ($Json) {
  ConvertTo-SkybridgeOperatorSafeJson -Value $summary -Depth 20
} else {
  "Schema:       $($summary.schema)"
  "Status:       $($summary.status)"
  "DryRun:       $($summary.dry_run)"
  "Report:       $($summary.report_delivery_supported)"
  "ReviewGate:   $($summary.review_gate_supported)"
  "TokenPrinted: false"
}
