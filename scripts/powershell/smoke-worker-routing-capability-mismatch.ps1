& "$PSScriptRoot\smoke-worker-routing-common.ps1" -Scenario capability-mismatch -ExpectedReasons @("capability_mismatch_rust-build") -ExpectNoSelected @args
