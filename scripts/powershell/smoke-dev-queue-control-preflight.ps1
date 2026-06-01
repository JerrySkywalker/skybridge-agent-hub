$ErrorActionPreference = "Stop"
$json = & pwsh -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-dev-queue-control.ps1" -Command preflight -Json | ConvertFrom-Json
if ($json.active_tasks -ne 0) { throw "Expected no active tasks." }
if ($json.stale_leases -ne 0) { throw "Expected no stale leases." }
if ($json.token_printed -ne $false) { throw "Expected token_printed=false." }
[pscustomobject]@{ ok = $true; scenario = "dev-queue-control-preflight"; token_printed = $false } | ConvertTo-Json -Compress
