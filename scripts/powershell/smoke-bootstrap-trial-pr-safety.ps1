param([switch]$Json)
& "$PSScriptRoot\smoke-bootstrap-trial-goal201-common.ps1" -Scenario pr-safety -Json:$Json
