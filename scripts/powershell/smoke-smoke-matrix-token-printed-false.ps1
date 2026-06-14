$ErrorActionPreference = "Stop"
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
& powershell -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-smoke-matrix.ps1" -Command report -Json | Out-Null
$report = Join-Path $root ".agent/tmp/smoke-matrix/smoke-matrix-report.json"
if (-not (Test-Path -LiteralPath $report)) { throw "Missing smoke matrix report." }
$json = Get-Content -LiteralPath $report -Raw | ConvertFrom-Json
if ($json.token_printed -ne $false) { throw "Token invariant failed." }
[pscustomobject]@{ ok = $true; smoke = "smoke-matrix-token-printed-false"; token_printed = $false } | ConvertTo-Json
