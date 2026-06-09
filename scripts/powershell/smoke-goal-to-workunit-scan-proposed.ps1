. "$PSScriptRoot/smoke-goal-to-workunit-common.ps1"
$scan = Invoke-GoalToWorkunitJson "scan"
if ($scan.proposed_goal_count -lt 1) { throw "Expected proposed goal scan candidates." }
if (-not (@($scan.candidates).source_proposed_goal_id -contains "proposed-goal-201-local-readme-refresh")) { throw "Expected local README proposed goal." }
Write-SmokeResult "goal-to-workunit-scan-proposed"
