& "$PSScriptRoot\smoke-worker-routing-common.ps1" -Scenario os-tool-mismatch -ExpectedReasons @("os_mismatch", "tool_mismatch_bash", "tool_mismatch_docker") @args
