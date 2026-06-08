& "$PSScriptRoot\smoke-worker-routing-common.ps1" -Scenario offline-stale -ExpectedReasons @("worker_offline", "worker_stale") @args
