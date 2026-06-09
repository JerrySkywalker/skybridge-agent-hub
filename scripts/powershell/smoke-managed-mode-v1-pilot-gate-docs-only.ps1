. "$PSScriptRoot\smoke-managed-mode-v1-common.ps1"
$gate = Invoke-ManagedModePilotJson "apply-gate"
if (-not $gate.can_run_pilot) { throw "Low-risk docs/local-smoke pilot should pass strict gate: $($gate.blockers -join ',')" }
if ([int]$gate.selected_workunit_count -ne 1 -or [int]$gate.selected_worker_count -ne 1) { throw "Expected exactly one workunit and worker." }
Write-ManagedModeSmokeResult "managed-mode-v1-pilot-gate-docs-only"
