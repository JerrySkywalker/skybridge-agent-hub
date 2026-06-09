param([switch]$Json)
& "$PSScriptRoot\smoke-bootstrap-finalizer-common.ps1" -Scenario evidence-safe -Json:$Json
