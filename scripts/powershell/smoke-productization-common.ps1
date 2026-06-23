$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path

function Invoke-JsonScript([string]$Script, [string[]]$ScriptArgs) {
  $path = Join-Path $PSScriptRoot $Script
  $raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File $path @ScriptArgs -Json
  if ($LASTEXITCODE -ne 0) { throw "$Script failed." }
  (($raw | Out-String).Trim() | ConvertFrom-Json)
}

function Assert-False($Value, [string]$Name) {
  if ($Value -ne $false) { throw "$Name must be false." }
}

function Assert-True($Value, [string]$Name) {
  if ($Value -ne $true) { throw "$Name must be true." }
}

function Assert-FileExists([string]$RelativePath) {
  $path = Join-Path $RepoRoot $RelativePath
  if (-not (Test-Path -LiteralPath $path)) { throw "Missing file: $RelativePath" }
}

function Assert-NoUnsafeText([string]$Text) {
  $tokenTrue = 'token_printed"\s*:\s*tr' + 'ue'
  if ($Text -match "(?i)authorization\s*[:=]\s*bearer|bearer\s+[A-Za-z0-9_.-]{12,}|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|raw_stdout|raw_stderr|raw_prompt(?!_persisted)|raw_worker_log|raw_codex_transcript|raw_ci_log|environment dump|env_dump|cookie\s*[:=]|$tokenTrue") {
    throw "Unsafe text detected."
  }
}

function Assert-TokenPrintedFalse($Value) {
  Assert-False $Value.token_printed "token_printed"
}

function Complete-Smoke([string]$Name) {
  Write-Host "[productization-smoke] ok $Name token_printed=false"
}
