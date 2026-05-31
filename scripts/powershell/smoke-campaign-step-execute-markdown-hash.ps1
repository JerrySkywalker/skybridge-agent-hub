param([switch]$Json)
& "$PSScriptRoot\smoke-campaign-fixture.ps1" -Scenario "step-execute-markdown-hash" -Json:$Json
