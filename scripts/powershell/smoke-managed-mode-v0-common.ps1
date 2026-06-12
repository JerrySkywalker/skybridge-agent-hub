$ErrorActionPreference = "Stop"

function Invoke-ManagedModeV0Json {
  param([Parameter(Mandatory = $true)][string]$Command)
  $text = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "skybridge-managed-mode-v0.ps1") -Command $Command -Json
  if ($LASTEXITCODE -ne 0) { throw "skybridge-managed-mode-v0.ps1 failed for $Command" }
  $text | ConvertFrom-Json
}

function Assert-ManagedModeV0SafeJson {
  param([Parameter(Mandatory = $true)]$Value)
  $json = $Value | ConvertTo-Json -Depth 100 -Compress
  if ($json -match '(?i)authorization\s*[:=]\s*bearer|bearer\s+[A-Za-z0-9_.-]{12,}|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|raw_stdout(?!s?_persisted)|raw_stderr(?!s?_persisted)|raw_prompt(?!s?_persisted)|raw_worker_log(?!s?_persisted)|raw_codex_transcript(?!s?_persisted)|raw_ci_log(?!s?_persisted)|token_printed"\s*:\s*true') {
    throw "Managed Mode v0 JSON contains unsafe text."
  }
}

function Write-ManagedModeV0SmokeResult {
  param([Parameter(Mandatory = $true)][string]$Scenario)
  [pscustomobject]@{ ok = $true; scenario = $Scenario; token_printed = $false } | ConvertTo-Json -Compress
}
