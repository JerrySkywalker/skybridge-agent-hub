. "$PSScriptRoot/smoke-goal-to-workunit-common.ps1"
$pack = Invoke-GoalToWorkunitJson "candidate-pack" "self-approval"
if (-not (@($pack.risk_gates).reasons -match "generated_goal_must_not_approve_itself")) { throw "Expected self-approval blocker/review reason." }
if (@($pack.risk_gates).generated_goal_self_approved -contains $true) { throw "Generated goals must not self-approve." }
Write-SmokeResult "goal-to-workunit-no-auto-approval"
