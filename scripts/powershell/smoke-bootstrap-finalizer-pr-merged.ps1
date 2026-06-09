param([switch]$Json)
& "$PSScriptRoot\smoke-bootstrap-finalizer-common.ps1" -Scenario pr-merged -Json:$Json
