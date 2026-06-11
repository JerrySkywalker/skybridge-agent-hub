. "$PSScriptRoot/smoke-managed-mode-run-common.ps1"
$gate = Invoke-ManagedModeRunJson "next-run-gate" -Extra @("-ActiveTasks", "1")
if ($gate.can_run_one_at_a_time) { throw "Active tasks must block next run." }
if ($gate.blockers -notcontains "active_tasks_present") { throw "Missing active task blocker." }
Write-ManagedModeRunSmokeResult "managed-mode-run-prevents-when-active-task"
