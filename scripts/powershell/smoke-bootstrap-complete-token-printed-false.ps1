$ErrorActionPreference = "Stop"
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
& powershell -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-bootstrap-complete.ps1" -Command report -Json | Out-Null
$files = @(
  ".agent/tmp/bootstrap-complete/bootstrap-complete-gate.json",
  ".agent/tmp/bootstrap-complete/completed-run-registry.json",
  ".agent/tmp/bootstrap-complete/self-bootstrap-release-report.json",
  ".agent/tmp/bootstrap-complete/post-bootstrap-readiness-report.json"
)
foreach ($file in $files) {
  $full = Join-Path $root $file
  if (-not (Test-Path -LiteralPath $full)) { throw "Missing report $file." }
  $json = Get-Content -LiteralPath $full -Raw | ConvertFrom-Json
  if ($json.token_printed -ne $false) { throw "Token invariant failed in $file." }
}
[pscustomobject]@{ ok = $true; smoke = "bootstrap-complete-token-printed-false"; token_printed = $false } | ConvertTo-Json
