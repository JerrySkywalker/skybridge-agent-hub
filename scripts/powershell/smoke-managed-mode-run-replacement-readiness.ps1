. "$PSScriptRoot/smoke-managed-mode-run-common.ps1"

$ready = Invoke-ManagedModeRunJson "run-replacement-readiness"
if ($ready.can_run_replacement -ne $true) { throw "Expected replacement readiness true: $($ready.blockers -join ',')" }
if ($ready.replacement_attempt_count -ne 0 -or $ready.max_replacement_attempts -ne 1) { throw "Unexpected replacement attempt budget." }
if ($ready.selected_invocation_profile -ne "profile_workspace_write_workdir") { throw "Expected workspace-write profile." }
if ($ready.target_path -ne "docs/managed-mode-repeatability-orientation.md") { throw "Unexpected target path." }
Assert-ManagedModeRunSafeJson $ready
Write-ManagedModeRunSmokeResult "managed-mode-run-replacement-readiness"
