$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$client = Get-Content -Raw -LiteralPath (Join-Path $repoRoot "packages\client\src\index.ts")
foreach ($required in @("deriveAttentionEvents", "notificationRoutingMatrix", "real_external_send: false", "token_printed: false")) {
  if ($client -notmatch [regex]::Escape($required)) { throw "Attention code missing safety marker: $required" }
}
$secretPattern = '(?i)authorization\s*[:=]\s*bearer|bearer\s+[A-Za-z0-9_.-]{12,}|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|"raw_stdout"\s*:|"raw_stderr"\s*:|"raw_prompt"\s*:|"raw_worker_log"\s*:'
$json = & pwsh -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-attention-fixture.ps1" -Command list -Json
if ($json -match $secretPattern) { throw "Attention fixture output contains secret-looking text." }
if ($json -notmatch '"token_printed":false') { throw "Expected token_printed=false in output." }

[pscustomobject]@{
  ok = $true
  scenario = "attention-no-secrets"
  token_printed = $false
} | ConvertTo-Json -Compress
