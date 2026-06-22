[CmdletBinding()]
param([switch]$Json)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$tmpRoot = Join-Path $RepoRoot ".agent\tmp\operator-notification-readiness-smoke"
New-Item -ItemType Directory -Force -Path $tmpRoot | Out-Null

function Write-Fixture {
  param([string]$Name, $Value)
  $path = Join-Path $tmpRoot $Name
  $Value | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $path -Encoding UTF8
  $path
}

$bootstrapPath = Write-Fixture "bootstrap.json" ([pscustomobject]@{
  schema = "skybridge.notification_readiness.v1"
  ok = $true
  status = "partial"
  dry_run = $true
  provider_count = 1
  ready_provider_count = 1
  real_provider_count = 0
  real_ready_provider_count = 0
  dry_run_safe_provider_count = 1
  bootstrap_dry_run_available = $true
  report_delivery_supported = $true
  review_gate_supported = $true
  real_send_performed = $false
  raw_notification_payload_included = $false
  credential_values_exposed = $false
  token_printed = $false
})

$realPath = Write-Fixture "real-provider.json" ([pscustomobject]@{
  schema = "skybridge.notification_readiness.v1"
  ok = $true
  status = "ready"
  dry_run = $true
  provider_count = 2
  ready_provider_count = 2
  real_provider_count = 1
  real_ready_provider_count = 1
  dry_run_safe_provider_count = 1
  bootstrap_dry_run_available = $true
  report_delivery_supported = $true
  review_gate_supported = $true
  real_send_performed = $false
  raw_notification_payload_included = $false
  credential_values_exposed = $false
  token_printed = $false
})

$nonePath = Write-Fixture "none.json" ([pscustomobject]@{
  schema = "skybridge.notification_readiness.v1"
  ok = $true
  status = "not_ready"
  dry_run = $true
  provider_count = 0
  ready_provider_count = 0
  real_provider_count = 0
  real_ready_provider_count = 0
  dry_run_safe_provider_count = 0
  bootstrap_dry_run_available = $false
  report_delivery_supported = $false
  review_gate_supported = $true
  real_send_performed = $false
  raw_notification_payload_included = $false
  credential_values_exposed = $false
  token_printed = $false
})

$reportPath = Write-Fixture "operator-report.json" ([pscustomobject]@{
  schema = "skybridge.operator_report.v1"
  ok = $true
  report_kind = "current-state"
  raw_notification_payload_included = $false
  credential_values_exposed = $false
  token_printed = $false
})

foreach ($case in @(
  @{ name = "bootstrap"; path = $bootstrapPath; status = "bootstrap_dry_run_only"; real = $false },
  @{ name = "real"; path = $realPath; status = "real_provider_configured"; real = $true }
)) {
  $raw = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-operator-notification-readiness.ps1 -FixtureNotificationReadinessFile $case.path -FixtureOperatorReportFile $reportPath -DryRun -Json
  if ($LASTEXITCODE -ne 0) { throw "operator notification readiness failed for $($case.name)." }
  $text = (($raw | Out-String).Trim())
  Assert-NoUnsafeText $text
  $result = $text | ConvertFrom-Json
  if ($result.schema -ne "skybridge.operator_notification_readiness.v1") { throw "Unexpected operator notification schema." }
  Assert-True $result.ok "$($case.name) ok"
  if ($result.status -ne $case.status) { throw "Unexpected status for $($case.name): $($result.status)" }
  Assert-True $result.report_delivery_supported "$($case.name) report delivery"
  Assert-True $result.review_gate_supported "$($case.name) review gate"
  Assert-False $result.real_send_performed "$($case.name) real send"
  Assert-False $result.raw_notification_payload_included "$($case.name) raw payload"
  Assert-False $result.credential_values_exposed "$($case.name) credentials"
  Assert-False $result.token_printed "$($case.name) token_printed"
}

$closedRaw = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-operator-notification-readiness.ps1 -FixtureNotificationReadinessFile $nonePath -FixtureOperatorReportFile $reportPath -RealSendTest -Json
if ($LASTEXITCODE -ne 0) { throw "real send fail-closed fixture should return JSON without throwing." }
$closedText = (($closedRaw | Out-String).Trim())
Assert-NoUnsafeText $closedText
$closed = $closedText | ConvertFrom-Json
if ($closed.status -ne "failed_closed") { throw "RealSendTest without provider must fail closed." }
Assert-False $closed.real_send_performed "closed real_send_performed"
Assert-False $closed.token_printed "closed token_printed"

$summary = [pscustomobject]@{
  ok = $true
  smoke = "operator-notification-readiness"
  scenarios = @("bootstrap_dry_run", "no_real_provider", "fixture_real_provider", "real_send_test_fails_closed", "token_printed_false")
  token_printed = $false
}
if ($Json) { $summary | ConvertTo-Json -Depth 8 -Compress } else { Complete-Smoke "operator-notification-readiness" }
