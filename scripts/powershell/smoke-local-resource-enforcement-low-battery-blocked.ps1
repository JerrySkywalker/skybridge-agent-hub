. "$PSScriptRoot/smoke-local-resource-enforcement-common.ps1"
$gate = Invoke-LocalResourceJson "fixture-battery-blocked"
$ids = @($gate.blockers | ForEach-Object { $_.blocker_id })
if ($ids -notcontains "ac_power_required") { throw "Expected AC power blocker for battery fixture." }
Write-LocalResourceSmokeResult "local-resource-enforcement-low-battery-blocked"
