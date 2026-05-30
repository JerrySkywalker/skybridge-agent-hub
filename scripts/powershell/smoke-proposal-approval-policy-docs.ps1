[CmdletBinding()]
param([switch]$Json)
& "$PSScriptRoot\smoke-proposal-review-fixture.ps1" -Scenario "approval-policy-docs" -Json:$Json
exit $LASTEXITCODE
