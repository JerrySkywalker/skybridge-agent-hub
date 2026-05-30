[CmdletBinding()]
param([switch]$Json)
& "$PSScriptRoot\smoke-proposal-review-fixture.ps1" -Scenario "approve" -Json:$Json
exit $LASTEXITCODE
