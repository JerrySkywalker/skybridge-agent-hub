$ErrorActionPreference = "Stop"
$result = & powershell -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-smoke-matrix.ps1" -Command run-fast -Json | ConvertFrom-Json
if ($result.schema -ne "skybridge.smoke_matrix_run.v1") { throw "Unexpected smoke matrix run schema." }
if ($result.group -ne "fast" -or $result.passed -ne $true) { throw "Fast smoke matrix did not pass." }
if ($result.token_printed -ne $false) { throw "Token invariant failed." }
[pscustomobject]@{ ok = $true; smoke = "smoke-matrix-fast"; token_printed = $false } | ConvertTo-Json
