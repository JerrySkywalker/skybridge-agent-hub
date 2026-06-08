param([switch]$Json)
& "$PSScriptRoot\smoke-queue-control-contract.ps1" -Scenario emergency-stop -Json:$Json
