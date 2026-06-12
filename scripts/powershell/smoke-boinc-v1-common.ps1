$ErrorActionPreference = "Stop"

function Invoke-BoincV1PreviewJson {
  param(
    [Parameter(Mandatory = $true)][string]$Command,
    [switch]$SimulateOpenReview,
    [switch]$SimulateResourceGateFail
  )

  $scriptPath = Join-Path $PSScriptRoot "skybridge-boinc-v1-preview.ps1"
  $args = @("-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $scriptPath, "-Command", $Command, "-Json")
  if ($SimulateOpenReview) { $args += "-SimulateOpenReview" }
  if ($SimulateResourceGateFail) { $args += "-SimulateResourceGateFail" }
  $raw = & pwsh @args
  if ($LASTEXITCODE -ne 0) { throw "BOINC v1 preview command failed: $Command" }
  if ($raw -notmatch '"token_printed":false') { throw "Expected token_printed=false in $Command output." }
  if ($raw -match '(?i)authorization\s*[:=]\s*bearer|bearer\s+[A-Za-z0-9_.-]{12,}|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|raw_stdout|raw_stderr|raw_prompt|raw_worker_log|raw_codex_transcript|raw_ci_log|github_log|token_printed"\s*:\s*true') {
    throw "Secret-looking or raw output field detected in $Command output."
  }
  $raw | ConvertFrom-Json
}

function Assert-Equal {
  param([object]$Actual, [object]$Expected, [string]$Message)
  if ($Actual -ne $Expected) { throw "$Message Expected '$Expected', got '$Actual'." }
}

function Assert-True {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw $Message }
}

function Assert-False {
  param([bool]$Condition, [string]$Message)
  if ($Condition) { throw $Message }
}

function Write-SmokeResult {
  param([string]$Scenario)
  [pscustomobject]@{ ok = $true; scenario = $Scenario; token_printed = $false } | ConvertTo-Json -Compress
}
