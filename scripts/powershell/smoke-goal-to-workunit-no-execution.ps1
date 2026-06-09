. "$PSScriptRoot/smoke-goal-to-workunit-common.ps1"
$summary = Invoke-GoalToWorkunitJson "safe-summary"
if ($summary.task_executed -ne $false -or $summary.apply_available -ne $false) { throw "Candidate conversion must not execute or enable apply." }
Write-SmokeResult "goal-to-workunit-no-execution"
