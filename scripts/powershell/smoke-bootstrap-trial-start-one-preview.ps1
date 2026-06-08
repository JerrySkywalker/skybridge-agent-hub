param([switch]$Json)
& "$PSScriptRoot\smoke-bootstrap-trial-goal201-common.ps1" -Scenario start-one-preview -Json:$Json
