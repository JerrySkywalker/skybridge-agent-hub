. "$PSScriptRoot/smoke-managed-mode-v0-common.ps1"
$readiness = Invoke-ManagedModeV0Json "release-readiness"
if ($readiness.resource_gate_required_for_next_run -ne $true) { throw "Managed Mode next run must require resource gate." }
if ($readiness.no_next_execution_authorized -ne $true) { throw "Next execution must still require future authorization." }
Write-ManagedModeV0SmokeResult "managed-mode-next-run-requires-resource-gate"
