. "$PSScriptRoot/smoke-goal-to-workunit-common.ps1"
$pack = Invoke-GoalToWorkunitJson "candidate-pack" "production"
if ($pack.blocked_count -lt 1) { throw "Expected production goal blocked." }
if (-not (@($pack.risk_gates).blocked_terms -match "production deploy|server-root config")) { throw "Expected production blocked term." }
Write-SmokeResult "goal-to-workunit-risk-gate-blocks-production"
