param([switch]$Json)
& "$PSScriptRoot\smoke-queue-control-contract.ps1" -Scenario no-secrets -Json:$Json
