. "$PSScriptRoot/smoke-goal-to-workunit-common.ps1"
$pack = Invoke-GoalToWorkunitJson "candidate-pack" "secrets"
if ($pack.blocked_count -lt 1) { throw "Expected secret goal blocked." }
if (-not (@($pack.risk_gates).blocked_terms -match "secret rotation|private key|token file")) { throw "Expected secret blocked term." }
Write-SmokeResult "goal-to-workunit-risk-gate-blocks-secrets"
