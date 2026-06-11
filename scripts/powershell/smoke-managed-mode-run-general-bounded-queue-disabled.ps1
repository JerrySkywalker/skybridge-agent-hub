. "$PSScriptRoot/smoke-managed-mode-run-common.ps1"
$summary = Invoke-ManagedModeRunJson "safe-summary"
if ($summary.general_bounded_queue_apply_enabled -ne $false -or $summary.general_bounded_queue -ne "disabled") { throw "General bounded queue must remain disabled." }
if ($summary.one_at_a_time_run_apply_enabled -ne $false) { throw "One-at-a-time apply must be disabled by default." }
Write-ManagedModeRunSmokeResult "managed-mode-run-general-bounded-queue-disabled"
