& "$PSScriptRoot\smoke-worker-routing-common.ps1" -Scenario repo-lock -ExpectedReasons @("active_repo_lock_blocks_routing_preview") -ExpectRepoBlocked -ExpectNoSelected @args
