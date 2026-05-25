[CmdletBinding()]
param(
  [switch]$Send,
  [switch]$Json,
  [switch]$UseHermesApi,
  [switch]$EnableAutoMerge,
  [string]$SkyBridgeApiBase = "http://127.0.0.1:8787",
  [string]$PolicyFile,
  [string]$LogRoot = ".\.agent\nightly"
)

$ErrorActionPreference = "Stop"

$bootstrapEnvLoader = Join-Path $PSScriptRoot "load-bootstrap-env.ps1"
if (Test-Path -LiteralPath $bootstrapEnvLoader -PathType Leaf) {
  . $bootstrapEnvLoader
}

$hermesEnvLoader = Join-Path $PSScriptRoot "load-hermes-env.ps1"
if (Test-Path -LiteralPath $hermesEnvLoader -PathType Leaf) {
  . $hermesEnvLoader
}

function Invoke-JsonCommand {
  param([string]$Label, [string[]]$Arguments, [string]$LogFile)

  $startedAt = Get-Date
  try {
    $output = & pwsh @Arguments
    $exitCode = $LASTEXITCODE
    $parsed = $null
    try {
      $parsed = (($output) -join "`n") | ConvertFrom-Json
    } catch {
      $parsed = $null
    }
    $result = [ordered]@{
      label = $Label
      ok = ($exitCode -eq 0)
      exit_code = $exitCode
      started_at = $startedAt.ToUniversalTime().ToString("o")
      finished_at = (Get-Date).ToUniversalTime().ToString("o")
      json = $parsed
      raw_output_included = $false
    }
  } catch {
    $result = [ordered]@{
      label = $Label
      ok = $false
      exit_code = 1
      started_at = $startedAt.ToUniversalTime().ToString("o")
      finished_at = (Get-Date).ToUniversalTime().ToString("o")
      error = $_.Exception.Message
      raw_output_included = $false
    }
  }

  if (-not [string]::IsNullOrWhiteSpace($LogFile)) {
    $result | ConvertTo-Json -Depth 24 | Set-Content -LiteralPath $LogFile -Encoding UTF8
  }
  return $result
}

function Send-PilotSummary {
  param([object]$Run)

  $healthStatus = if ($Run.health.json) { $Run.health.json.status } else { "unknown" }
  $reportPrs = if ($Run.nightly_report.json) { $Run.nightly_report.json.github.open_prs.open_count } else { "unknown" }
  $sweepCounts = if ($Run.nightly_sweep.json -and $Run.nightly_sweep.json.actions) {
    (@($Run.nightly_sweep.json.actions | Where-Object { $_.label -eq "nightly_sweep" } | Select-Object -First 1).json.policy_counts)
  } else {
    $null
  }
  $eligible = if ($sweepCounts) { $sweepCounts.eligible } else { "unknown" }
  $blocked = if ($sweepCounts) { $sweepCounts.blocked } else { "unknown" }

  $message = "Nightly pilot: tunnel=$($Run.tunnel.json.listening), hermes=$healthStatus, open_prs=$reportPrs, sweep_eligible=$eligible, blocked=$blocked, auto_merge=$($Run.enable_auto_merge_requested)."
  $args = @(
    "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass",
    "-File", ".\scripts\powershell\notify-bootstrap.ps1",
    "-Title", "SkyBridge nightly pilot",
    "-Message", $message,
    "-Severity", "info",
    "-Json"
  )
  if ($Send) {
    $args += "-Send"
  } else {
    $args += "-DryRun"
  }

  return Invoke-JsonCommand -Label "pilot_summary_notification" -Arguments $args -LogFile (Join-Path $script:runDir "notification.json")
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$runDir = Join-Path $LogRoot $timestamp
$script:runDir = $runDir
New-Item -ItemType Directory -Force -Path $runDir | Out-Null

$tunnelArgs = @(
  "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass",
  "-File", ".\scripts\powershell\start-hermes-tunnel.ps1",
  "-Start",
  "-Json"
)
$healthArgs = @(
  "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass",
  "-File", ".\scripts\powershell\watch-hermes-health.ps1",
  "-Once",
  "-Json"
)
$reportArgs = @(
  "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass",
  "-File", ".\scripts\powershell\skybridge-nightly-supervisor-report.ps1",
  "-DryRun",
  "-SkyBridgeApiBase", $SkyBridgeApiBase,
  "-Json"
)
if ($UseHermesApi) { $reportArgs += "-UseHermesApi" }
if (-not [string]::IsNullOrWhiteSpace($PolicyFile)) { $reportArgs += @("-PolicyFile", $PolicyFile) }

$sweepArgs = @(
  "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass",
  "-File", ".\scripts\powershell\skybridge-hermes-supervisor.ps1",
  "-Mode", "NightlySweep",
  "-UseHermesApi",
  "-DryRun",
  "-SkyBridgeApiBase", $SkyBridgeApiBase,
  "-Json"
)
if ($EnableAutoMerge) {
  $sweepArgs = @($sweepArgs | Where-Object { $_ -ne "-DryRun" })
  $sweepArgs += "-EnableAutoMerge"
}
if (-not [string]::IsNullOrWhiteSpace($PolicyFile)) { $sweepArgs += @("-PolicyFile", $PolicyFile) }

$run = [ordered]@{
  ok = $true
  generated_at = (Get-Date).ToUniversalTime().ToString("o")
  log_dir = (Resolve-Path -LiteralPath $runDir).Path
  send_requested = [bool]$Send
  use_hermes_api = [bool]$UseHermesApi
  enable_auto_merge_requested = [bool]$EnableAutoMerge
  urgent_notification = $false
  tunnel = Invoke-JsonCommand -Label "tunnel" -Arguments $tunnelArgs -LogFile (Join-Path $runDir "tunnel.json")
  health = $null
  nightly_report = $null
  nightly_sweep = $null
  notification = $null
  safety = [ordered]@{
    production_deploy = $false
    secrets_printed = $false
    hermes_api_key_value_included = $false
    auto_merge_enabled_by_default = $false
    auto_merge_requires_enable_flag = $true
    phone_notification_requires_send_flag = $true
    urgent_notification = $false
  }
}

$run.health = Invoke-JsonCommand -Label "health" -Arguments $healthArgs -LogFile (Join-Path $runDir "health.json")
$run.nightly_report = Invoke-JsonCommand -Label "nightly_report" -Arguments $reportArgs -LogFile (Join-Path $runDir "nightly-report.json")
$run.nightly_sweep = Invoke-JsonCommand -Label "nightly_sweep" -Arguments $sweepArgs -LogFile (Join-Path $runDir "nightly-sweep.json")
$run.notification = Send-PilotSummary -Run $run
$run.ok = [bool]($run.tunnel.ok -and $run.health.ok -and $run.nightly_report.ok -and $run.nightly_sweep.ok -and $run.notification.ok)

$summaryPath = Join-Path $runDir "summary.json"
$run | ConvertTo-Json -Depth 28 | Set-Content -LiteralPath $summaryPath -Encoding UTF8

if ($Json) {
  $run | ConvertTo-Json -Depth 28
} else {
  Write-Host "[hermes-nightly-pilot] ok=$($run.ok) log_dir=$($run.log_dir) send=$Send auto_merge=$EnableAutoMerge"
}

if (-not $run.ok) {
  exit 1
}
