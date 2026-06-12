$ErrorActionPreference = "Stop"
Import-Module (Join-Path $PSScriptRoot "lib/Skybridge.WorkunitRegistry.psm1") -Force
$summary = Get-SkybridgeRunRegistrySummary
if ($summary.completed_run_count -ne 4) { throw "expected four completed runs" }
if (@($summary.completed_runs | Where-Object { $_.state -ne "completed" }).Count -gt 0) { throw "completed run evidence missing" }
[pscustomobject]@{ ok = $true; scenario = "core-engine-registry-reads-completed-runs"; completed_run_count = $summary.completed_run_count; token_printed = $false } | ConvertTo-Json -Compress
