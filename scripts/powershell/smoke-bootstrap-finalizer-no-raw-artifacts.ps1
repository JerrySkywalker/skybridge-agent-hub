param([switch]$Json)
& "$PSScriptRoot\smoke-bootstrap-finalizer-common.ps1" -Scenario no-raw-artifacts -Json:$Json
