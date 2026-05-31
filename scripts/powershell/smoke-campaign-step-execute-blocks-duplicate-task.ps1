param([switch]$Json)
& "$PSScriptRoot\smoke-campaign-fixture.ps1" -Scenario "step-execute-blocks-duplicate-task" -Json:$Json
