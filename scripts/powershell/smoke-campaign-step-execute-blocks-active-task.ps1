param([switch]$Json)
& "$PSScriptRoot\smoke-campaign-fixture.ps1" -Scenario "step-execute-blocks-active-task" -Json:$Json
