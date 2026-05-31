param([switch]$Json)
& "$PSScriptRoot\smoke-campaign-fixture.ps1" -Scenario "step-execute-preview" -Json:$Json
