. "$PSScriptRoot/smoke-goal-to-workunit-common.ps1"
$pack = Invoke-GoalToWorkunitJson "candidate-pack" "low-docs"
if ($pack.candidate_ready_count -lt 1) { throw "Expected low docs candidate_ready." }
if (-not (@($pack.risk_gates).decision -contains "allow_candidate_ready")) { throw "Expected allow_candidate_ready gate." }
Write-SmokeResult "goal-to-workunit-risk-gate-low-docs"
