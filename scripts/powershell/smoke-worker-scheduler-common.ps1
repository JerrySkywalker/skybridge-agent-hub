$ErrorActionPreference = "Stop"

function Invoke-WorkerSchedulerJson {
  param(
    [Parameter(Mandatory = $true)][string]$Command,
    [string]$Scenario = "default"
  )
  $scriptPath = Join-Path $PSScriptRoot "skybridge-worker-scheduler.ps1"
  $raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File $scriptPath -Command $Command -Scenario $Scenario -Json
  if ($LASTEXITCODE -ne 0) { throw "Worker scheduler command failed: $Command / $Scenario" }
  if ($raw -notmatch '"token_printed":false') { throw "Expected token_printed=false in $Command output." }
  if ($raw -match '(?i)authorization\s*[:=]\s*bearer|bearer\s+[A-Za-z0-9_.-]{12,}|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|raw_stdout|raw_stderr|raw_prompt|raw_worker_log|raw_codex_transcript|token_printed"\s*:\s*true') {
    throw "Secret-looking or raw output field detected in $Command output."
  }
  $raw | ConvertFrom-Json
}

function Write-SmokeResult {
  param([string]$Scenario)
  [pscustomobject]@{ ok = $true; scenario = $Scenario; token_printed = $false } | ConvertTo-Json -Compress
}
