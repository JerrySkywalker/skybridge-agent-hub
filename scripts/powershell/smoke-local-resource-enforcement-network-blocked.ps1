. "$PSScriptRoot/smoke-local-resource-enforcement-common.ps1"
$gate = Invoke-LocalResourceJson "fixture-network-blocked"
if ($gate.can_run_one_at_a_time -ne $false) { throw "Network fixture should block." }
$ids = @($gate.blockers | ForEach-Object { $_.blocker_id })
if ($ids -notcontains "network_unavailable") { throw "Expected network blocker." }
Write-LocalResourceSmokeResult "local-resource-enforcement-network-blocked"
