[CmdletBinding()]
param(
  [switch]$DryRun
)

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

$savedEnv = @{
  SKYBRIDGE_BOOTSTRAP_NTFY_URL = $env:SKYBRIDGE_BOOTSTRAP_NTFY_URL
  SKYBRIDGE_BOOTSTRAP_NTFY_TOPIC = $env:SKYBRIDGE_BOOTSTRAP_NTFY_TOPIC
  SKYBRIDGE_BOOTSTRAP_NTFY_URGENT_TOPIC = $env:SKYBRIDGE_BOOTSTRAP_NTFY_URGENT_TOPIC
  SKYBRIDGE_BOOTSTRAP_NTFY_USER = $env:SKYBRIDGE_BOOTSTRAP_NTFY_USER
  SKYBRIDGE_BOOTSTRAP_NTFY_PASS = $env:SKYBRIDGE_BOOTSTRAP_NTFY_PASS
  SKYBRIDGE_BOOTSTRAP_NTFY_TOKEN = $env:SKYBRIDGE_BOOTSTRAP_NTFY_TOKEN
  SKYBRIDGE_BOOTSTRAP_WECOM_WEBHOOK = $env:SKYBRIDGE_BOOTSTRAP_WECOM_WEBHOOK
  NTFY_TOPIC_URL = $env:NTFY_TOPIC_URL
  NTFY_URL = $env:NTFY_URL
  NTFY_TOPIC = $env:NTFY_TOPIC
  NTFY_TOKEN = $env:NTFY_TOKEN
  NTFY_USER = $env:NTFY_USER
  NTFY_PASSWORD = $env:NTFY_PASSWORD
  WECOM_WEBHOOK_URL = $env:WECOM_WEBHOOK_URL
}

try {
  foreach ($key in $savedEnv.Keys) {
    Remove-Item -Path "Env:$key" -ErrorAction SilentlyContinue
  }

  $missing = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File ".\scripts\powershell\notify-bootstrap.ps1" `
    -Title "SkyBridge bootstrap smoke" `
    -Message "Missing config smoke." `
    -Severity "info" `
    -Json
  $missingParsed = $missing | ConvertFrom-Json
  if (($missingParsed.results | Where-Object { $_.provider -eq "ntfy" }).status -ne "skipped") {
    throw "missing ntfy config should produce skipped status"
  }

  $env:SKYBRIDGE_BOOTSTRAP_NTFY_URL = "https://ntfy.example.invalid"
  $env:SKYBRIDGE_BOOTSTRAP_NTFY_TOPIC = "example-topic"
  $configuredNoSend = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File ".\scripts\powershell\notify-bootstrap.ps1" `
    -Title "SkyBridge bootstrap smoke" `
    -Message "Configured but no send flag." `
    -Severity "warning" `
    -Json
  $configuredParsed = $configuredNoSend | ConvertFrom-Json
  $ntfy = $configuredParsed.results | Where-Object { $_.provider -eq "ntfy" }
  if ($ntfy.status -ne "configured" -or $ntfy.reason -ne "send_flag_required") {
    throw "configured ntfy without -Send should not attempt real delivery"
  }

  $info = Invoke-BootstrapDryRun -Severity "info"
  $warning = Invoke-BootstrapDryRun -Severity "warning"
  $urgent = Invoke-BootstrapDryRun -Severity "urgent"
} finally {
  foreach ($entry in $savedEnv.GetEnumerator()) {
    if ($null -eq $entry.Value) {
      Remove-Item -Path "Env:$($entry.Key)" -ErrorAction SilentlyContinue
    } else {
      Set-Item -Path "Env:$($entry.Key)" -Value $entry.Value
    }
  }
}

Write-Host "[bootstrap-notify-smoke] info=$($info.ok) warning=$($warning.ok) urgent=$($urgent.ok)"
Write-Host "[bootstrap-notify-smoke] complete"
