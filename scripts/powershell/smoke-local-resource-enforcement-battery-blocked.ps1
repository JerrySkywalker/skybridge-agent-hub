. "$PSScriptRoot/smoke-local-resource-enforcement-common.ps1"
$gate = Invoke-LocalResourceJson "fixture-battery-blocked"
if ($gate.can_run_one_at_a_time -ne $false) { throw "Battery fixture should block." }
$ids = @($gate.blockers | ForEach-Object { $_.blocker_id })
if ($ids -notcontains "on_battery") { throw "Expected on_battery blocker." }
Assert-LocalResourceSafeJson $gate
Write-LocalResourceSmokeResult "local-resource-enforcement-battery-blocked"
