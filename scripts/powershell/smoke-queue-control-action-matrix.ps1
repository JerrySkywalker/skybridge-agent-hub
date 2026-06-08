param([switch]$Json)
& "$PSScriptRoot\smoke-queue-control-contract.ps1" -Scenario action-matrix -Json:$Json
