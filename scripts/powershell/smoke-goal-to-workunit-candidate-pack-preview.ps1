. "$PSScriptRoot/smoke-goal-to-workunit-common.ps1"
$pack = Invoke-GoalToWorkunitJson "candidate-pack"
if ($pack.schema -ne "skybridge.workunit_candidate_pack.v1") { throw "Unexpected candidate pack schema." }
if ($pack.bounded_queue_preview_only -ne $true -or $pack.apply_available -ne $false) { throw "Candidate pack must be preview-only with apply disabled." }
Write-SmokeResult "goal-to-workunit-candidate-pack-preview"
