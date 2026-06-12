$ErrorActionPreference = "Stop"

function Invoke-LocalResourceJson {
  param([Parameter(Mandatory = $true)][string]$Command)
  $text = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "skybridge-local-resource-policy.ps1") -Command $Command -Json
  if ($LASTEXITCODE -ne 0) { throw "skybridge-local-resource-policy.ps1 failed for $Command" }
  $text | ConvertFrom-Json
}

function Assert-LocalResourceSafeJson {
  param([Parameter(Mandatory = $true)]$Value)
  $json = $Value | ConvertTo-Json -Depth 100 -Compress
  if ($json -match '(?i)authorization\s*[:=]\s*bearer|bearer\s+[A-Za-z0-9_.-]{12,}|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|raw_stdout|raw_stderr|raw_prompt|raw_worker_log|raw_codex_transcript|token_printed"\s*:\s*true') {
    throw "Local resource JSON contains unsafe text."
  }
}

function Write-LocalResourceSmokeResult {
  param([Parameter(Mandatory = $true)][string]$Scenario)
  [pscustomobject]@{ ok = $true; scenario = $Scenario; token_printed = $false } | ConvertTo-Json -Compress
}
