[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

function Invoke-BootstrapDryRun {
  param([string]$Severity)
  $output = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File ".\scripts\powershell\notify-bootstrap.ps1" `
    -Title "SkyBridge bootstrap smoke" `
    -Message "Dry-run bootstrap notification smoke for $Severity." `
    -Severity $Severity `
    -DryRun `
    -Json

  if ($LASTEXITCODE -ne 0) {
    throw "notify-bootstrap.ps1 dry-run failed for $Severity"
  }

  $parsed = $output | ConvertFrom-Json
  if ($parsed.skybridge_server_required -ne $false) {
    throw "bootstrap notifier must not require the SkyBridge server"
  }
  if ($parsed.severity -ne $Severity) {
    throw "unexpected severity in dry-run response"
  }
  return $parsed
}

$info = Invoke-BootstrapDryRun -Severity "info"
$warning = Invoke-BootstrapDryRun -Severity "warning"
$urgent = Invoke-BootstrapDryRun -Severity "urgent"

Write-Host "[bootstrap-notify-smoke] info=$($info.ok) warning=$($warning.ok) urgent=$($urgent.ok)"
Write-Host "[bootstrap-notify-smoke] complete"
