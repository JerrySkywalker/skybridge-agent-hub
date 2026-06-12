$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "local-supervisor-smoke-common.ps1")
$status = Invoke-LocalSupervisorSmokeCommand -Command "status"
if ($status.schema -ne "skybridge.local_supervisor_status.v1") { throw "Unexpected status schema" }
Assert-FalseProperty $status "execution_enabled"
if ($status.active_tasks -ne 0 -or $status.stale_leases -ne 0 -or $status.runner_lock -ne "none") { throw "Unsafe lock/task state" }
if ($status.branch -eq "unknown" -or $status.commit -eq "unknown") { throw "Git branch/commit metadata must be present" }
[pscustomobject]@{ ok = $true; scenario = "local-supervisor-status"; token_printed = $false } | ConvertTo-Json -Compress
