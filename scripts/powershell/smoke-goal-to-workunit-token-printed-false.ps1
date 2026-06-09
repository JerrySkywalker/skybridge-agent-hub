. "$PSScriptRoot/smoke-goal-to-workunit-common.ps1"
foreach ($command in @("schema", "scan", "preview", "risk-gate", "candidate-pack", "safe-summary", "fixture-convert", "manifest-validate")) {
  $null = Invoke-GoalToWorkunitJson $command
}
Write-SmokeResult "goal-to-workunit-token-printed-false"
