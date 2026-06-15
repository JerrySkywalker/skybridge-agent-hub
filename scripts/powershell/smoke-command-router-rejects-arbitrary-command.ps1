$ErrorActionPreference = "Stop"
$raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "skybridge-session-supervisor.ps1") -Command route -Target "local-session status; git status" -Json 2>&1
if ($LASTEXITCODE -eq 0) { throw "Arbitrary command route was accepted." }
$text = ($raw | Out-String)
if ($text -match '"token_printed"\s*:\s*true|authorization\s*[:=]\s*bearer|bearer\s+[A-Za-z0-9_.-]{12,}|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----') {
  throw "Unsafe text in rejection output."
}
[pscustomobject]@{ ok = $true; scenario = "command-router-rejects-arbitrary-command"; token_printed = $false } | ConvertTo-Json -Compress
