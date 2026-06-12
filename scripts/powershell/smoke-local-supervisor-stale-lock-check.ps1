$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "local-supervisor-smoke-common.ps1")
$lock = Invoke-LocalSupervisorSmokeCommand -Command "stale-lock-check"
if ($lock.stale_leases -ne 0 -or $lock.runner_lock -ne "none") { throw "Unexpected stale lock check" }
[pscustomobject]@{ ok = $true; scenario = "local-supervisor-stale-lock-check"; token_printed = $false } | ConvertTo-Json -Compress
