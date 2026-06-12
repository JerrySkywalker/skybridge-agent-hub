. "$PSScriptRoot/smoke-managed-mode-v0-common.ps1"
$readiness = Invoke-ManagedModeV0Json "release-readiness"
if ($readiness.release_ready -ne $true) { throw "Release readiness should pass." }
if ($readiness.active_tasks -ne 0 -or $readiness.stale_leases -ne 0 -or $readiness.runner_lock -ne "none") { throw "Expected no active/stale/lock." }
if ($readiness.open_managed_mode_pr_count -ne 0) { throw "Expected no open managed-mode PRs." }
if ($readiness.general_bounded_queue_apply_enabled -ne $false -or $readiness.multi_workunit_queue_enabled -ne $false) { throw "Queue apply must remain disabled." }
Assert-ManagedModeV0SafeJson $readiness
Write-ManagedModeV0SmokeResult "managed-mode-v0-release-readiness"
