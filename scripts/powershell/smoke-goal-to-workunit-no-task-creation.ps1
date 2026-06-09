. "$PSScriptRoot/smoke-goal-to-workunit-common.ps1"
$summary = Invoke-GoalToWorkunitJson "safe-summary"
if ($summary.task_created -ne $false -or $summary.pr_created -ne $false) { throw "Candidate conversion must not create tasks or PRs." }
Write-SmokeResult "goal-to-workunit-no-task-creation"
