. "$PSScriptRoot/smoke-goal-to-workunit-common.ps1"
$validation = Invoke-GoalToWorkunitJson "manifest-validate"
if ($validation.valid -ne $true -or $validation.apply_available -ne $false) { throw "Expected valid preview manifest with apply disabled." }
if ($validation.manifest.execution_review_required -ne $true) { throw "Manifest must require execution review." }
Write-SmokeResult "goal-to-workunit-manifest-validate"
