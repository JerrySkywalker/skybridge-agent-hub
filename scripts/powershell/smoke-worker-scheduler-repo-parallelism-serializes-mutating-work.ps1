. "$PSScriptRoot/smoke-worker-scheduler-common.ps1"
$plan = Invoke-WorkerSchedulerJson "route-plan" "repo-parallelism"
if (-not (@($plan.policy_blockers) -contains "repo_parallelism_blocks_concurrent_work")) { throw "Expected repo parallelism blocker." }
if (-not (@($plan.selected_routes) | Where-Object { $_.serialized_by_repo_policy -eq $true })) { throw "Expected mutating work serialization." }
Write-SmokeResult "worker-scheduler-repo-parallelism-serializes-mutating-work"
