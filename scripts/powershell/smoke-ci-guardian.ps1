[CmdletBinding()]
param(
  [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$output = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File ".\scripts\powershell\skybridge-ci-guardian.ps1" `
  -PR 999999 `
  -DryRun `
  -MaxRepairAttempts 2 `
  -SkyBridgeApiBase "http://127.0.0.1:1"

if ($LASTEXITCODE -ne 0) {
  throw "skybridge-ci-guardian.ps1 dry-run failed"
}

$jsonStartIndex = [Array]::FindIndex([string[]]$output, [Predicate[string]]{ param($line) $line -match "^\s*\{" })
if ($jsonStartIndex -lt 0) {
  throw "guardian dry-run output did not include JSON"
}

$parsed = (($output | Select-Object -Skip $jsonStartIndex) -join "`n") | ConvertFrom-Json
if ($parsed.dry_run -ne $true -or $parsed.auto_merge -ne $false) {
  throw "guardian dry-run did not preserve safe defaults"
}
if ($parsed.max_transient_retry_count -ne 1 -or $parsed.pending_check_timeout_seconds -lt 1) {
  throw "guardian dry-run did not report bounded retry and pending timeout defaults"
}

Write-Host "[ci-guardian-smoke] dry-run pr=$($parsed.pr_number) maxRepair=$($parsed.max_repair_attempts)"
