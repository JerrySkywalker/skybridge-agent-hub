. "$PSScriptRoot/smoke-local-resource-enforcement-common.ps1"
$gate = Invoke-LocalResourceJson "fixture-memory-blocked"
if ($gate.can_run_one_at_a_time -ne $false) { throw "Memory fixture should block." }
$ids = @($gate.blockers | ForEach-Object { $_.blocker_id })
if ($ids -notcontains "memory_above_threshold") { throw "Expected memory blocker." }
Write-LocalResourceSmokeResult "local-resource-enforcement-memory-blocked"
