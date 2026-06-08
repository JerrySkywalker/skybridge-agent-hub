param([switch]$Json)
& "$PSScriptRoot\smoke-queue-control-contract.ps1" -Scenario start-apply-forbidden -Json:$Json
