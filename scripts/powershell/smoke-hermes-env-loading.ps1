[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$secretValues = @(
  "hermes-secret-key",
  "hermes-secret-model",
  "https://hermes-secret.example.invalid"
)

$tempDir = Join-Path ([IO.Path]::GetTempPath()) ("skybridge-hermes-env-smoke-" + [guid]::NewGuid().ToString("N"))
$tempFile = Join-Path $tempDir "hermes.env.ps1"
$savedEnv = @{
  HERMES_ENV_FILE = $env:HERMES_ENV_FILE
  HERMES_API_BASE = $env:HERMES_API_BASE
  HERMES_API_KEY = $env:HERMES_API_KEY
  HERMES_MODEL = $env:HERMES_MODEL
}

try {
  foreach ($key in $savedEnv.Keys) {
    Remove-Item -Path "Env:$key" -ErrorAction SilentlyContinue
  }

  $missingFile = Join-Path $tempDir "missing.env.ps1"
  New-Item -ItemType Directory -Force -Path $tempDir | Out-Null
  $env:HERMES_ENV_FILE = $missingFile

  $missingJson = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File ".\scripts\powershell\load-hermes-env.ps1" -Json
  if ($LASTEXITCODE -ne 0) {
    throw "load-hermes-env.ps1 -Json failed for missing file"
  }
  $missingParsed = ($missingJson -join "`n") | ConvertFrom-Json
  if ($missingParsed.file_exists -ne $false -or $missingParsed.loaded -ne $false -or $missingParsed.fail_open -ne $true) {
    throw "missing Hermes env file did not fail open"
  }

  @'
$env:HERMES_API_BASE = "https://hermes-secret.example.invalid"
$env:HERMES_API_KEY = "hermes-secret-key"
$env:HERMES_MODEL = "hermes-secret-model"
'@ | Set-Content -LiteralPath $tempFile -Encoding UTF8

  $env:HERMES_ENV_FILE = $tempFile
  $json = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File ".\scripts\powershell\load-hermes-env.ps1" -Json
  if ($LASTEXITCODE -ne 0) {
    throw "load-hermes-env.ps1 -Json failed"
  }
  $jsonText = $json -join "`n"
  foreach ($secret in $secretValues) {
    if ($jsonText.Contains($secret)) {
      throw "Hermes env loader JSON exposed a secret value"
    }
  }

  $parsed = $jsonText | ConvertFrom-Json
  if ($parsed.loaded -ne $true -or $parsed.file_exists -ne $true) {
    throw "Hermes env loader did not report the temp env file as loaded"
  }
  foreach ($variable in $parsed.variables) {
    if ($variable.value_included -ne $false) {
      throw "Hermes env loader reported secret values as included"
    }
  }

  . ".\scripts\powershell\load-hermes-env.ps1"
  if ($env:HERMES_API_KEY -ne "hermes-secret-key") {
    throw "dot-sourced Hermes env loader did not populate process environment"
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

Write-Host "[hermes-env-smoke] complete"
