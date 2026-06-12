$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "local-supervisor-smoke-common.ps1")
$lock = Invoke-LocalSupervisorSmokeCommand -Command "lock-status"
if ($lock.active_tasks -ne 0 -or $lock.stale_leases -ne 0 -or $lock.runner_lock -ne "none") { throw "Unexpected lock status" }
[pscustomobject]@{ ok = $true; scenario = "local-supervisor-lock-status"; token_printed = $false } | ConvertTo-Json -Compress
