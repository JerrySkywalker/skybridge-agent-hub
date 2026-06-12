. "$PSScriptRoot/smoke-local-resource-enforcement-common.ps1"
$gate = Invoke-LocalResourceJson "fixture-ac-ok"
if ($gate.can_run_one_at_a_time -ne $true) { throw "AC fixture should pass." }
if (@($gate.blockers).Count -ne 0) { throw "AC fixture should have no blockers." }
Assert-LocalResourceSafeJson $gate
Write-LocalResourceSmokeResult "local-resource-enforcement-ac-ok"
