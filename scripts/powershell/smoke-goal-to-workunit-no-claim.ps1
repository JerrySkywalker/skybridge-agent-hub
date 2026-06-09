. "$PSScriptRoot/smoke-goal-to-workunit-common.ps1"
$summary = Invoke-GoalToWorkunitJson "safe-summary"
if ($summary.task_claimed -ne $false) { throw "Candidate conversion must not claim tasks." }
Write-SmokeResult "goal-to-workunit-no-claim"
