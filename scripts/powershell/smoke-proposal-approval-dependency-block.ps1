[CmdletBinding()]
param([switch]$Json)
& "$PSScriptRoot\smoke-proposal-review-fixture.ps1" -Scenario "approval-dependency-block" -Json:$Json
exit $LASTEXITCODE
