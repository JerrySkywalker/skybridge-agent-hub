param([switch]$Json)
& "$PSScriptRoot\smoke-bootstrap-finalizer-common.ps1" -Scenario report-state -Json:$Json
