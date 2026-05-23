[CmdletBinding()]
param(
  [switch]$DryRun,
  [switch]$Json,
  [switch]$EnableAutoMerge,
  [switch]$Send,
  [string]$PolicyFile
)

$ErrorActionPreference = "Stop"

$hermesEnvLoader = Join-Path $PSScriptRoot "load-hermes-env.ps1"
if (Test-Path -LiteralPath $hermesEnvLoader -PathType Leaf) {
  . $hermesEnvLoader
}

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

  return @{
    label = $Label
    exit_code = $exitCode
    json = $parsed
    raw_output_included = $false
  }
}

$supervisorArgs = @(
  "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass",
  "-File", ".\scripts\powershell\skybridge-hermes-supervisor.ps1",
  "-Mode", "Status",
  "-UseHermesApi",
  "-Json"
)
if ($DryRun) { $supervisorArgs += "-DryRun" }

$sweepArgs = @(
  "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass",
  "-File", ".\scripts\powershell\skybridge-auto-merge-sweep.ps1",
  "-Json",
  "-SuppressBlockedNotifications"
)
if (-not [string]::IsNullOrWhiteSpace($PolicyFile)) {
  $sweepArgs += @("-PolicyFile", $PolicyFile)
}
if ($EnableAutoMerge) {
  $sweepArgs += "-EnableAutoMerge"
}

$notifyArgs = @(
  "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass",
  "-File", ".\scripts\powershell\notify-bootstrap.ps1",
  "-Title", "SkyBridge Hermes supervised sweep",
  "-Message", "Hermes supervised auto-merge sweep smoke completed.",
  "-Severity", "info",
  "-Json"
)
if ($Send) {
  $notifyArgs += "-Send"
} else {
  $notifyArgs += "-DryRun"
}

$supervisor = Invoke-JsonCommand -Label "hermes_supervisor_status" -Arguments $supervisorArgs
$sweep = Invoke-JsonCommand -Label "auto_merge_sweep" -Arguments $sweepArgs
$notification = Invoke-JsonCommand -Label "bootstrap_notification" -Arguments $notifyArgs

$summary = @{
  ok = ($supervisor.exit_code -eq 0 -and $sweep.exit_code -eq 0 -and $notification.exit_code -eq 0)
  dry_run = [bool]$DryRun
  enable_auto_merge_requested = [bool]$EnableAutoMerge
  send_requested = [bool]$Send
  hermes_env_loaded = -not [string]::IsNullOrWhiteSpace($env:HERMES_API_BASE)
  hermes_api_key_present = -not [string]::IsNullOrWhiteSpace($env:HERMES_API_KEY)
  hermes_api_key_value_included = $false
  supervisor = $supervisor
  auto_merge_sweep = $sweep
  bootstrap_notification = $notification
  safety = @{
    auto_merge_enabled_by_default = $false
    auto_merge_requires_enable_flag = $true
    notification_send_requires_send_flag = $true
    raw_output_included = $false
  }
}

if ($Json) {
  $summary | ConvertTo-Json -Depth 24
} else {
  Write-Host "[hermes-supervised-sweep] ok=$($summary.ok) auto_merge_requested=$($summary.enable_auto_merge_requested) send_requested=$($summary.send_requested)"
}

if (-not $summary.ok) {
  exit 1
}
