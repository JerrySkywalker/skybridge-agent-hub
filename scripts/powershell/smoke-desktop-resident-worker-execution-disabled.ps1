$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "local-supervisor-smoke-common.ps1")
$status = Invoke-LocalSupervisorSmokeCommand -Command "status"
Assert-FalseProperty $status "execution_enabled"
Assert-FalseProperty $status "poll_enabled"
if ($status.no_next_execution_authorized -ne $true) { throw "no_next_execution_authorized must be true" }
[pscustomobject]@{ ok = $true; scenario = "desktop-resident-worker-execution-disabled"; token_printed = $false } | ConvertTo-Json -Compress
