. "$PSScriptRoot/smoke-managed-mode-run-common.ps1"
$registry = Invoke-ManagedModeRunJson "registry"
if ($registry.schema -ne "skybridge.managed_mode_run_registry.v1") { throw "Unexpected registry schema." }
if ($registry.sequence_policy.schema -ne "skybridge.managed_mode_sequence_policy.v1") { throw "Missing sequence policy." }
if ($registry.sequence_policy.max_open_runs -ne 1 -or $registry.sequence_policy.max_workunits_per_run -ne 1 -or $registry.sequence_policy.max_tasks_per_run -ne 1) { throw "Sequence policy must be one-at-a-time." }
if ($registry.general_bounded_queue_apply_enabled -ne $false -or $registry.max_workunits -ne 1) { throw "General bounded queue apply must remain disabled with max_workunits=1." }
Assert-ManagedModeRunSafeJson $registry
Write-ManagedModeRunSmokeResult "managed-mode-run-registry-contract"
