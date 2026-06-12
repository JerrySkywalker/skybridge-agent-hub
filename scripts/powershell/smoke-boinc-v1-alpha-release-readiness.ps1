$ErrorActionPreference = "Stop"
$report = (& pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "skybridge-boinc-v1-alpha.ps1") -Command v1-alpha-release-report -Json | Out-String).Trim() | ConvertFrom-Json
if ($report.active_tasks -ne 0 -or $report.stale_leases -ne 0 -or $report.runner_lock -ne "none" -or $report.open_task_pr_count -ne 0) { throw "release readiness queue state mismatch" }
if ($report.no_workunit_c -ne $true -or $report.ready_for_goal_217 -ne $true) { throw "release readiness completion mismatch" }
[pscustomobject]@{ ok = $true; scenario = "boinc-v1-alpha-release-readiness"; token_printed = $false } | ConvertTo-Json -Compress
