[CmdletBinding()]
param(
  [switch]$Json
)

$ErrorActionPreference = "Stop"

function Invoke-JsonCommand {
  param([string]$Label, [string[]]$Arguments)

  $output = & pwsh @Arguments
  $exitCode = $LASTEXITCODE
  $parsed = $null
  try {
    $parsed = (($output) -join "`n") | ConvertFrom-Json
  } catch {
    $parsed = $null
  }

  return [ordered]@{
    label = $Label
    ok = ($exitCode -eq 0 -and $null -ne $parsed)
    exit_code = $exitCode
    json = $parsed
    raw_output_included = $false
  }
}

$hermesUnavailable = Invoke-JsonCommand -Label "hermes_unavailable" -Arguments @(
  "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass",
  "-File", ".\scripts\powershell\watch-hermes-health.ps1",
  "-Once",
  "-HermesApiBase", "http://127.0.0.1:9",
  "-HermesApiKey", "placeholder-not-secret",
  "-Json"
)

$noEligible = Invoke-JsonCommand -Label "no_eligible_prs" -Arguments @(
  "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass",
  "-File", ".\scripts\powershell\skybridge-auto-merge-sweep.ps1",
  "-Fixture",
  "-FixtureScenario", "NoEligible",
  "-SuppressBlockedNotifications",
  "-Json"
)

$blockedHighRisk = Invoke-JsonCommand -Label "blocked_high_risk_pr" -Arguments @(
  "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass",
  "-File", ".\scripts\powershell\skybridge-auto-merge-sweep.ps1",
  "-Fixture",
  "-FixtureScenario", "BlockedHighRisk",
  "-SuppressBlockedNotifications",
  "-Json"
)

$phoneWouldSend = Invoke-JsonCommand -Label "phone_would_send" -Arguments @(
  "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass",
  "-File", ".\scripts\powershell\notify-bootstrap.ps1",
  "-Title", "SkyBridge failure drill",
  "-Message", "Dry-run failure drill notification preview.",
  "-Severity", "warning",
  "-DryRun",
  "-Json"
)

$checks = [ordered]@{
  hermes_unavailable_simulated = ($hermesUnavailable.json.status -in @("tunnel_down", "api_degraded", "missing_base", "missing_key"))
  no_eligible_prs_simulated = ($noEligible.json.eligible_count -eq 0 -and $noEligible.json.total_open_prs -gt 0)
  blocked_high_risk_simulated = ($blockedHighRisk.json.policy_counts.blocked -gt 0 -and $blockedHighRisk.json.policy_counts.high_risk_files -gt 0)
  phone_notification_dry_run = ($phoneWouldSend.json.dry_run -eq $true -and $phoneWouldSend.json.send_requested -eq $false)
}

$summary = [ordered]@{
  ok = -not (@($checks.GetEnumerator() | Where-Object { -not $_.Value }).Count -gt 0)
  checks = $checks
  hermes_unavailable = $hermesUnavailable
  no_eligible_prs = $noEligible
  blocked_high_risk_pr = $blockedHighRisk
  phone_would_send = $phoneWouldSend
  safety = [ordered]@{
    dry_run_only = $true
    github_mutated = $false
    auto_merge_enabled = $false
    notification_sent = $false
    hermes_api_key_value_included = $false
  }
}

if ($Json) {
  $summary | ConvertTo-Json -Depth 20
} else {
  Write-Host "[hermes-failure-drill] ok=$($summary.ok) hermes_unavailable=$($checks.hermes_unavailable_simulated) no_eligible=$($checks.no_eligible_prs_simulated) blocked_high_risk=$($checks.blocked_high_risk_simulated) phone_dry_run=$($checks.phone_notification_dry_run)"
}

if (-not $summary.ok) {
  exit 1
}
