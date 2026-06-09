function Invoke-ManagedModePilotJson {
  param(
    [Parameter(Mandatory = $true)][string]$Command,
    [string]$Scenario = "low-docs",
    [string[]]$Extra = @()
  )
  $script = Join-Path $PSScriptRoot "skybridge-managed-mode-pilot.ps1"
  $raw = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File $script -Command $Command -Scenario $Scenario -Json @Extra
  if ($LASTEXITCODE -ne 0) { throw "skybridge-managed-mode-pilot $Command failed." }
  if ($raw -match '"token_printed"\s*:\s*true') { throw "token_printed=true found." }
  if ($raw -match '(?i)authorization\s*[:=]\s*bearer|bearer\s+[A-Za-z0-9_.-]{12,}|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|raw_stdout|raw_stderr|raw_prompt|raw_worker_log|raw_codex_transcript') {
    throw "Secret-looking or raw artifact field found."
  }
  $raw | ConvertFrom-Json
}

function Write-ManagedModeSmokeResult {
  param([string]$Scenario)
  [pscustomobject]@{ ok = $true; scenario = $Scenario; token_printed = $false } | ConvertTo-Json -Compress
}
