[CmdletBinding()]
param([switch]$Json)
& "$PSScriptRoot\smoke-proposal-review-fixture.ps1" -Scenario "convert-approved-only" -Json:$Json
exit $LASTEXITCODE
