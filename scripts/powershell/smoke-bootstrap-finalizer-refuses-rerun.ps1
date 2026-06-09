param([switch]$Json)
& "$PSScriptRoot\smoke-bootstrap-finalizer-common.ps1" -Scenario refuses-rerun -Json:$Json
