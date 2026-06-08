param([switch]$Json)
& "$PSScriptRoot\smoke-queue-control-contract.ps1" -Scenario audit -Json:$Json
