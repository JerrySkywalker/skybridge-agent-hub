. "$PSScriptRoot/smoke-managed-mode-run-common.ps1"
$gate = Invoke-ManagedModeRunJson "next-run-gate"
if ($gate.schema -ne "skybridge.one_at_a_time_managed_mode_gate.v1") { throw "Unexpected gate schema." }
if ($gate.previous_run_208_completed -ne $true) { throw "208 completion must be visible to the gate." }
if ($gate.run_apply_enabled -ne $false) { throw "209A gate must not enable run apply." }
if ($gate.active_tasks -ne 0 -or $gate.stale_leases -ne 0 -or $gate.runner_lock -ne "none") { throw "Default gate fixture should be clean." }
Write-ManagedModeRunSmokeResult "managed-mode-run-one-at-a-time-gate"
