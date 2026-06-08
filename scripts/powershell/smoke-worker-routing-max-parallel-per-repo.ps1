& "$PSScriptRoot\smoke-worker-routing-common.ps1" -Scenario max-parallel -ExpectedReasons @("max_parallel_per_repo_exceeded") -ExpectRepoBlocked -ExpectNoSelected @args
