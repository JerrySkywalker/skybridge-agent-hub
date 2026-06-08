[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$json = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot "scripts\powershell\skybridge-worker-service.ps1") -Command status -Json
$patterns = @(
  "Authorization\s*[:=]\s*Bearer",
  "Bearer\s+[A-Za-z0-9_.-]{12,}",
  "sk-[A-Za-z0-9_-]{20,}",
  "gh[pousr]_[A-Za-z0-9_]{20,}",
  "-----BEGIN [A-Z ]*PRIVATE KEY-----",
  "\\secrets\\",
  "/secrets/"
)
foreach ($pattern in $patterns) {
  if ($json -match $pattern) { throw "Worker service output contains secret-looking text for pattern $pattern" }
}
$result = $json | ConvertFrom-Json
if ([bool]$result.token_printed) { throw "token_printed=true" }

[pscustomobject]@{
  ok = $true
  smoke = "worker-service-no-secrets"
  checked_patterns = $patterns.Count
  token_printed = $false
} | ConvertTo-Json -Depth 10 -Compress
