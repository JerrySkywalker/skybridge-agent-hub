[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$secretValues = @(
  "skybridge-dev-secret-topic",
  "skybridge-urgent-secret-topic",
  "secret-user",
  "secret-pass",
  "secret-token",
  "secret-webhook-key"
)

$tempDir = Join-Path ([IO.Path]::GetTempPath()) ("skybridge-bootstrap-env-smoke-" + [guid]::NewGuid().ToString("N"))
$tempFile = Join-Path $tempDir "bootstrap-notify.env.ps1"
$savedEnv = @{
  SKYBRIDGE_BOOTSTRAP_ENV_FILE = $env:SKYBRIDGE_BOOTSTRAP_ENV_FILE
  SKYBRIDGE_BOOTSTRAP_NTFY_URL = $env:SKYBRIDGE_BOOTSTRAP_NTFY_URL
  SKYBRIDGE_BOOTSTRAP_NTFY_TOPIC = $env:SKYBRIDGE_BOOTSTRAP_NTFY_TOPIC
  SKYBRIDGE_BOOTSTRAP_NTFY_URGENT_TOPIC = $env:SKYBRIDGE_BOOTSTRAP_NTFY_URGENT_TOPIC
  SKYBRIDGE_BOOTSTRAP_NTFY_USER = $env:SKYBRIDGE_BOOTSTRAP_NTFY_USER
  SKYBRIDGE_BOOTSTRAP_NTFY_PASS = $env:SKYBRIDGE_BOOTSTRAP_NTFY_PASS
  SKYBRIDGE_BOOTSTRAP_NTFY_TOKEN = $env:SKYBRIDGE_BOOTSTRAP_NTFY_TOKEN
  SKYBRIDGE_BOOTSTRAP_WECOM_WEBHOOK = $env:SKYBRIDGE_BOOTSTRAP_WECOM_WEBHOOK
}

try {
  New-Item -ItemType Directory -Force -Path $tempDir | Out-Null
  @'
$env:SKYBRIDGE_BOOTSTRAP_NTFY_URL = "https://ntfy.example.invalid"
$env:SKYBRIDGE_BOOTSTRAP_NTFY_TOPIC = "skybridge-dev-secret-topic"
$env:SKYBRIDGE_BOOTSTRAP_NTFY_URGENT_TOPIC = "skybridge-urgent-secret-topic"
$env:SKYBRIDGE_BOOTSTRAP_NTFY_USER = "secret-user"
$env:SKYBRIDGE_BOOTSTRAP_NTFY_PASS = "secret-pass"
$env:SKYBRIDGE_BOOTSTRAP_NTFY_TOKEN = "secret-token"
$env:SKYBRIDGE_BOOTSTRAP_WECOM_WEBHOOK = "https://wecom.example.invalid/secret-webhook-key"
'@ | Set-Content -LiteralPath $tempFile -Encoding UTF8

  foreach ($key in $savedEnv.Keys) {
    Remove-Item -Path "Env:$key" -ErrorAction SilentlyContinue
  }
  $env:SKYBRIDGE_BOOTSTRAP_ENV_FILE = $tempFile

  $json = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File ".\scripts\powershell\load-bootstrap-env.ps1" -Json
  if ($LASTEXITCODE -ne 0) {
    throw "load-bootstrap-env.ps1 -Json failed"
  }
  $jsonText = $json -join "`n"
  foreach ($secret in $secretValues) {
    if ($jsonText.Contains($secret)) {
      throw "loader JSON exposed a secret value"
    }
  }
  $parsed = $jsonText | ConvertFrom-Json
  if ($parsed.loaded -ne $true -or $parsed.file_exists -ne $true) {
    throw "loader did not report the temp env file as loaded"
  }

  . ".\scripts\powershell\load-bootstrap-env.ps1"
  if ($env:SKYBRIDGE_BOOTSTRAP_NTFY_TOPIC -ne "skybridge-dev-secret-topic") {
    throw "dot-sourced loader did not populate process environment"
  }

  $notifyJson = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File ".\scripts\powershell\notify-bootstrap.ps1" `
    -Title "SkyBridge bootstrap env smoke" `
    -Message "Dry-run only." `
    -Severity "warning" `
    -DryRun `
    -Json
  if ($LASTEXITCODE -ne 0) {
    throw "notify-bootstrap.ps1 -DryRun -Json failed"
  }
  $notifyText = $notifyJson -join "`n"
  foreach ($secret in $secretValues) {
    if ($notifyText.Contains($secret)) {
      throw "notify-bootstrap JSON exposed a secret value"
    }
  }
  $notifyParsed = $notifyText | ConvertFrom-Json
  $ntfy = $notifyParsed.results | Where-Object { $_.provider -eq "ntfy" }
  if ($ntfy.status -ne "configured" -or $ntfy.reason -ne "dry_run") {
    throw "notify-bootstrap did not see loaded dry-run ntfy config"
  }
} finally {
  foreach ($entry in $savedEnv.GetEnumerator()) {
    if ($null -eq $entry.Value) {
      Remove-Item -Path "Env:$($entry.Key)" -ErrorAction SilentlyContinue
    } else {
      Set-Item -Path "Env:$($entry.Key)" -Value $entry.Value
    }
  }
  Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "[bootstrap-env-smoke] complete"
