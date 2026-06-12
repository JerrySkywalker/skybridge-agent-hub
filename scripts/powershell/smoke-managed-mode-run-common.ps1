function Invoke-ManagedModeRunJson {
  param(
    [Parameter(Mandatory = $true)][string]$Command,
    [string[]]$Extra = @()
  )
  $script = Join-Path $PSScriptRoot "skybridge-managed-mode-run.ps1"
  $raw = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File $script -Command $Command -Json @Extra
  if ($LASTEXITCODE -ne 0) { throw "skybridge-managed-mode-run $Command failed." }
  if ($raw -match '"token_printed"\s*:\s*true') { throw "token_printed=true found." }
  if ($raw -match '(?i)authorization\s*[:=]\s*bearer|bearer\s+[A-Za-z0-9_.-]{12,}|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|raw_stdout(?!s?_persisted)|raw_stderr(?!s?_persisted)|raw_prompt(?!s?_persisted)|raw_worker_log(?!s?_persisted)|raw_codex_transcript(?!s?_persisted)|raw_ci_log(?!s?_persisted)') {
    throw "Secret-looking or raw artifact field found."
  }
  $raw | ConvertFrom-Json
}

function Assert-ManagedModeRunSafeJson {
  param($Object)
  $raw = $Object | ConvertTo-Json -Depth 100 -Compress
  if ($raw -notmatch '"token_printed"\s*:\s*false') { throw "Expected token_printed=false." }
  if ($raw -match '(?i)authorization\s*[:=]\s*bearer|bearer\s+[A-Za-z0-9_.-]{12,}|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|raw_stdout(?!s?_persisted)|raw_stderr(?!s?_persisted)|raw_prompt(?!s?_persisted)|raw_worker_log(?!s?_persisted)|raw_codex_transcript(?!s?_persisted)|raw_ci_log(?!s?_persisted)|token_printed"\s*:\s*true') {
    throw "Secret-looking or raw artifact field found."
  }
}

function Write-ManagedModeRunSmokeResult {
  param([string]$Scenario)
  [pscustomobject]@{ ok = $true; scenario = $Scenario; token_printed = $false } | ConvertTo-Json -Compress
}
