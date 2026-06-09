. "$PSScriptRoot/smoke-boinc-manager-common.ps1"
$summary = Invoke-BoincManagerJson "safe-summary"
if ($summary.schema -ne "skybridge.boinc_manager_safe_summary.v1") { throw "Unexpected safe summary schema." }
if ($summary.bounded_queue_apply_available -ne $false -or $summary.can_start_bounded_queue -ne $false) { throw "Bounded queue apply must remain disabled." }
if ($summary.task_created -or $summary.task_claimed -or $summary.task_executed -or $summary.pr_created) { throw "Safe summary must not create work." }
Write-SmokeResult "boinc-manager-safe-summary"
