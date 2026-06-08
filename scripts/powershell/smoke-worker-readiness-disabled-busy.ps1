& "$PSScriptRoot\smoke-worker-routing-common.ps1" -Scenario disabled-busy -ExpectedReasons @("worker_disabled", "worker_busy_current_task") @args
